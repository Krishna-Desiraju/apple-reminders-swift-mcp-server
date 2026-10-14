#!/bin/bash
#
# Install, update, or remove the Apple Reminders MCP server as a background
# service (a per-user LaunchAgent) that serves MCP over HTTP on your LAN.
#
#   curl -fsSL https://raw.githubusercontent.com/cmer/apple-reminders-swift-mcp-server/main/scripts/install.sh | bash
#
# After installing, the `reminders-mcp` command runs this script (for example
# `reminders-mcp token` or `reminders-mcp update`). See --help.

set -Eeuo pipefail
# Never exit silently: report where an unexpected failure happened.
trap 'printf "\033[31mError:\033[0m installer stopped unexpectedly (line %s, exit %s)\n" "$LINENO" "$?" >&2' ERR

DEFAULT_REPO="https://github.com/cmer/apple-reminders-swift-mcp-server.git"
DEFAULT_REF="main"
DEFAULT_HOST="0.0.0.0"
DEFAULT_PORT="3847"

ROOT="${REMINDERS_MCP_HOME:-$HOME/Library/Application Support/apple-reminders-mcp}"
LABEL="${REMINDERS_MCP_LABEL:-local.apple-reminders-mcp}"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_FILE="$HOME/Library/Logs/$LABEL.log"
CONFIG_FILE="$ROOT/config.env"
TOKEN_FILE="$ROOT/token"
RELEASES="$ROOT/releases"
CURRENT="$ROOT/current"
DOMAIN="gui/$(id -u)"
CLI_NAME="reminders-mcp"
BIN_DIR="${REMINDERS_MCP_BIN_DIR:-$HOME/.local/bin}"
CLI_LINK="$BIN_DIR/$CLI_NAME"

usage() {
  cat <<EOF
Usage: $CLI_NAME [command] [options]
   or: install.sh [command] [options]

Commands:
  install        Install, or update an existing install to the latest version (default)
  update         Same as install
  token          Print the access token
  status         Show the service state, version, URL, and token
  rotate-token   Generate a new token and restart the service
  uninstall      Stop the service and delete everything it installed

Options (saved for future updates):
  --host ADDR    Address to listen on (default $DEFAULT_HOST, all interfaces)
  --port N       Port to listen on (default $DEFAULT_PORT)
  --ref REF      Git branch or tag to track (default $DEFAULT_REF)
  --repo URL     Git repository to install from (default $DEFAULT_REPO)

Other options:
  --force               Rebuild even if already on the latest commit
  --skip-access-check   Don't trigger the macOS Reminders permission prompt
  -h, --help            Show this help

Files:
  $ROOT
  $PLIST
  $LOG_FILE
  $CLI_LINK
EOF
}

say() { printf '\033[1m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33mWarning:\033[0m %s\n' "$*" >&2; }
die() {
  printf '\033[31mError:\033[0m %s\n' "$*" >&2
  exit 1
}

xml_escape() {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# --- Settings -----------------------------------------------------------------

load_config() {
  HOST="$DEFAULT_HOST"
  PORT="$DEFAULT_PORT"
  REF="$DEFAULT_REF"
  REPO="$DEFAULT_REPO"
  if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    . "$CONFIG_FILE"
  fi
}

save_config() {
  mkdir -p "$ROOT"
  {
    printf 'HOST=%q\n' "$HOST"
    printf 'PORT=%q\n' "$PORT"
    printf 'REF=%q\n' "$REF"
    printf 'REPO=%q\n' "$REPO"
  } >"$CONFIG_FILE"
}

# --- Token --------------------------------------------------------------------

generate_token() {
  # 32 random bytes as base64url, same format as `--generate-token`.
  openssl rand -base64 32 | tr '+/' '-_' | tr -d '=\n'
}

ensure_token() {
  if [ -s "$TOKEN_FILE" ]; then
    return
  fi
  say "Generating access token"
  write_token
}

write_token() {
  mkdir -p "$ROOT"
  (
    umask 077
    generate_token >"$TOKEN_FILE.tmp"
  )
  mv "$TOKEN_FILE.tmp" "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
}

# --- Prerequisites ------------------------------------------------------------

check_prerequisites() {
  [ "$(uname -s)" = "Darwin" ] || die "This only runs on macOS."

  local tool
  for tool in git node npm openssl curl; do
    command -v "$tool" >/dev/null 2>&1 || die "$tool is required but was not found in PATH."
  done
  xcrun --find swift >/dev/null 2>&1 ||
    die "Swift is required. Install the Xcode Command Line Tools: xcode-select --install"

  local major
  major="$(node -p 'process.versions.node.split(".")[0]')"
  [ "$major" -ge 18 ] || die "Node.js 18 or newer is required (found $(node -v))."

  # Resolve the real binary so the service keeps working without version
  # manager shims (nvm, mise, asdf) on launchd's minimal PATH.
  NODE_BIN="$(node -p 'process.execPath')"
}

# --- Build --------------------------------------------------------------------

# Identifies the Swift sources a bundle was built from. When it's unchanged we
# reuse the existing RemindersCLI.app: rebuilding changes its ad-hoc code
# signature, and macOS would then ask for Reminders permission again.
swift_build_key() {
  git -C "$1" rev-parse HEAD:swift-cli HEAD:scripts/build-swift-cli.sh | tr '\n' ' '
}

build_release() {
  local dir="$1" key
  say "Installing Node.js dependencies"
  (cd "$dir" && npm ci --no-audit --no-fund --loglevel=error)

  say "Building server"
  (cd "$dir" && npm run --silent build)

  key="$(swift_build_key "$dir")"
  if [ -d "$CURRENT/swift-cli/RemindersCLI.app" ] &&
    [ "$(cat "$CURRENT/.swift-build-key" 2>/dev/null)" = "$key" ]; then
    say "Swift CLI unchanged, reusing existing build"
    cp -R "$CURRENT/swift-cli/RemindersCLI.app" "$dir/swift-cli/"
  else
    say "Building Swift CLI (this takes a minute)"
    if ! (cd "$dir" && ./scripts/build-swift-cli.sh) >"$ROOT/swift-build.log" 2>&1; then
      tail -n 30 "$ROOT/swift-build.log" >&2
      die "Swift build failed. Full output: $ROOT/swift-build.log"
    fi
    SWIFT_REBUILT=1
  fi
  printf '%s' "$key" >"$dir/.swift-build-key"
}

# Fetch the latest commit of $REF and build it into a new release directory.
# Sets RELEASE_DIR, or leaves it empty when already up to date.
fetch_release() {
  local staging sha
  RELEASE_DIR=""
  mkdir -p "$RELEASES"
  staging="$RELEASES/.staging"
  rm -rf "$staging"

  say "Fetching $REF from $REPO"
  git clone --quiet --depth 1 --branch "$REF" "$REPO" "$staging" ||
    die "Could not clone $REPO (ref $REF)."
  sha="$(git -C "$staging" rev-parse --short=12 HEAD)"

  if [ -z "$FORCE" ] && [ "$(current_sha)" = "$sha" ] && [ -f "$CURRENT/dist/index.js" ]; then
    rm -rf "$staging"
    say "Already up to date ($sha)"
    return
  fi

  build_release "$staging"
  rm -rf "${RELEASES:?}/$sha"
  mv "$staging" "$RELEASES/$sha"
  RELEASE_DIR="$RELEASES/$sha"
}

current_sha() {
  if [ -L "$CURRENT" ]; then
    basename "$(readlink "$CURRENT")"
  fi
}

prune_releases() {
  local keep_current keep_previous dir name
  keep_current="$(current_sha)"
  keep_previous="${1:-}"
  for dir in "$RELEASES"/*; do
    [ -d "$dir" ] || continue
    name="$(basename "$dir")"
    if [ "$name" != "$keep_current" ] && [ "$name" != "$keep_previous" ]; then
      rm -rf "$dir"
    fi
  done
}

# --- Service ------------------------------------------------------------------

write_plist() {
  mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG_FILE")"
  cat >"$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$(xml_escape "$LABEL")</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(xml_escape "$NODE_BIN")</string>
    <string>$(xml_escape "$CURRENT/dist/index.js")</string>
    <string>--http</string>
    <string>--host</string>
    <string>$(xml_escape "$HOST")</string>
    <string>--port</string>
    <string>$(xml_escape "$PORT")</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>REMINDERS_MCP_TOKEN_FILE</key>
    <string>$(xml_escape "$TOKEN_FILE")</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ThrottleInterval</key>
  <integer>10</integer>
  <key>StandardOutPath</key>
  <string>$(xml_escape "$LOG_FILE")</string>
  <key>StandardErrorPath</key>
  <string>$(xml_escape "$LOG_FILE")</string>
</dict>
</plist>
EOF
  plutil -lint "$PLIST" >/dev/null || die "Generated an invalid plist at $PLIST"
}

stop_service() {
  launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
  # bootout returns before the job is fully gone; wait so bootstrap doesn't race it.
  local i
  for i in 1 2 3 4 5 6 7 8 9 10; do
    launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1 || return 0
    sleep 0.5
  done
}

start_service() {
  stop_service
  local i
  for i in 1 2 3 4 5; do
    if launchctl bootstrap "$DOMAIN" "$PLIST" 2>/dev/null; then
      # RunAtLoad isn't a guarantee: launchd can defer the first spawn
      # ("speculative") indefinitely, leaving the job loaded but never run.
      launchctl kickstart "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
      return 0
    fi
    sleep 1
  done
  die "launchctl could not load $PLIST"
}

local_url() {
  local host="$HOST"
  case "$host" in
    0.0.0.0 | :: | "") host="127.0.0.1" ;;
  esac
  case "$host" in
    *:*) host="[$host]" ;;
  esac
  printf 'http://%s:%s/mcp' "$host" "$PORT"
}

# Succeeds once the server answers an authenticated tools/list request.
health_check() {
  local token i
  token="$(cat "$TOKEN_FILE")"
  for i in $(seq 1 20); do
    if curl -fsS --max-time 5 -o /dev/null "$(local_url)" \
      -H "Authorization: Bearer $token" \
      -H 'Content-Type: application/json' \
      -H 'Accept: application/json, text/event-stream' \
      -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' 2>/dev/null; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

# Launch the bundle the same way the server does, so the macOS permission
# prompt is attributed to RemindersCLI.app. Returns quickly when access was
# already granted; otherwise waits (up to ACCESS_TIMEOUT) for the user to
# answer the prompt.
ACCESS_TIMEOUT=180

request_access() {
  local out pid waited=0
  out="$(mktemp -d)"
  say "Checking Reminders permission (approve the macOS prompt if one appears)"
  open -W -n -a "$CURRENT/swift-cli/RemindersCLI.app" \
    --stdout "$out/stdout" --stderr "$out/stderr" --args request-access 2>/dev/null &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$ACCESS_TIMEOUT" ]; then
      kill "$pid" 2>/dev/null || true
      break
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$pid" 2>/dev/null || true

  if grep -q '"granted" *: *true' "$out/stdout" 2>/dev/null; then
    say "Reminders access granted"
  else
    warn "Reminders access was not granted. Enable RemindersCLI in System Settings > Privacy & Security > Reminders, then run: $CLI_NAME update"
  fi
  rm -rf "$out"
}

# Link `reminders-mcp` to the installed copy of this script so it can be run
# later without re-downloading it.
install_cli() {
  if [ -e "$CLI_LINK" ] && [ ! -L "$CLI_LINK" ]; then
    warn "$CLI_LINK exists and isn't a link we created; not installing the $CLI_NAME command."
    return
  fi
  mkdir -p "$BIN_DIR"
  ln -sfh "$CURRENT/scripts/install.sh" "$CLI_LINK"
}

cli_on_path() {
  case ":$PATH:" in
    *":$BIN_DIR:"*) return 0 ;;
  esac
  return 1
}

# --- Output -------------------------------------------------------------------

# One URL per line, best first: the Bonjour name, then each interface's IP.
lan_urls() {
  case "$HOST" in
    0.0.0.0 | ::) ;;
    *)
      printf 'http://%s:%s/mcp\n' "$HOST" "$PORT"
      return 0
      ;;
  esac
  local name iface ip
  name="$(scutil --get LocalHostName 2>/dev/null || true)"
  if [ -n "$name" ]; then
    printf 'http://%s.local:%s/mcp\n' "$name" "$PORT"
  fi
  for iface in $(ifconfig -l); do
    ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
    if [ -n "$ip" ]; then
      printf 'http://%s:%s/mcp\n' "$ip" "$PORT"
    fi
  done
  return 0
}

# Copy to the clipboard when running in a terminal, so `status > file` or a
# script calling us doesn't clobber it.
copy_to_clipboard() {
  [ -t 1 ] && command -v pbcopy >/dev/null 2>&1 || return 1
  printf '%s' "$1" | pbcopy
}

print_connection_info() {
  local token urls url others command bold reset
  token="$(cat "$TOKEN_FILE")"
  urls="$(lan_urls)"
  url="${urls%%$'\n'*}"
  others="$(printf '%s\n' "$urls" | sed 1d)"
  command="claude mcp add --transport http --scope user apple-reminders $url --header \"Authorization: Bearer $token\""
  bold=$'\033[1m'
  reset=$'\033[0m'

  cat <<EOF

${bold}Add it to Claude Code${reset}

On any machine on your network, run:

  $command

Then start Claude Code and run /mcp; apple-reminders should show as connected.
EOF
  if copy_to_clipboard "$command"; then
    echo "(The command is on your clipboard.)"
  fi

  cat <<EOF

${bold}Token${reset}       $token
${bold}Server URL${reset}  $url
EOF
  if [ -n "$others" ]; then
    echo
    echo "If $url doesn't resolve from another machine, use one of these instead:"
    printf '%s\n' "$others" | sed 's/^/  /'
  fi

  cat <<EOF

Show the token again any time:  $CLI_NAME token
Logs:                           $LOG_FILE

The first time a client connects, macOS may ask whether node can accept
incoming connections. Click Allow.
EOF
  if ! cli_on_path; then
    cat <<EOF

$BIN_DIR isn't on your PATH. Add it to use the $CLI_NAME command:
  echo 'export PATH="$BIN_DIR:\$PATH"' >> ~/.zshrc
Or run it directly: $CLI_LINK token
EOF
  fi
}

# --- Commands -----------------------------------------------------------------

cmd_install() {
  check_prerequisites
  save_config
  ensure_token

  local previous
  previous="$(current_sha)"
  SWIFT_REBUILT=""
  fetch_release

  if [ -n "$RELEASE_DIR" ]; then
    ln -sfh "$RELEASE_DIR" "$CURRENT"
  fi

  write_plist
  say "Starting service"
  start_service

  if ! health_check; then
    tail -n 20 "$LOG_FILE" >&2 2>/dev/null || true
    if [ -n "$RELEASE_DIR" ] && [ -n "$previous" ] && [ -d "$RELEASES/$previous" ]; then
      warn "$(basename "$RELEASE_DIR") failed to start; rolling back to $previous"
      ln -sfh "$RELEASES/$previous" "$CURRENT"
      rm -rf "$RELEASE_DIR"
      start_service
      if health_check; then
        die "Update failed. Still running the previous version ($previous). See $LOG_FILE"
      fi
    fi
    die "The server did not respond at $(local_url). See $LOG_FILE"
  fi

  prune_releases "$previous"
  install_cli
  say "Running $(current_sha) from $REF"

  if [ -z "$SKIP_ACCESS" ]; then
    request_access
  elif [ -n "$SWIFT_REBUILT" ]; then
    warn "The Swift CLI was rebuilt; macOS may ask for Reminders permission again on first use."
  fi

  print_connection_info
}

cmd_status() {
  [ -f "$PLIST" ] || die "Not installed."
  local state pid
  local info
  info="$(launchctl print "$DOMAIN/$LABEL" 2>/dev/null || true)"
  state="$(awk -F' = ' '/^\tstate/ {print $2; exit}' <<<"$info")"
  pid="$(awk -F' = ' '/^\tpid/ {print $2; exit}' <<<"$info")"

  echo "Service:  ${state:-not loaded}${pid:+ (pid $pid)}"
  echo "Version:  $(current_sha) ($REF from $REPO)"
  if health_check; then
    echo "Health:   responding at $(local_url)"
  else
    echo "Health:   not responding at $(local_url)"
  fi
  print_connection_info
}

cmd_token() {
  [ -s "$TOKEN_FILE" ] || die "Not installed (no token at $TOKEN_FILE)."
  cat "$TOKEN_FILE"
  # Skip the newline when piped so `reminders-mcp token | pbcopy` copies just the token.
  if [ -t 1 ]; then echo; fi
}

cmd_rotate_token() {
  [ -f "$PLIST" ] || die "Not installed."
  say "Generating new token"
  write_token
  say "Restarting service"
  launchctl kickstart -k "$DOMAIN/$LABEL" >/dev/null
  health_check || die "The server did not respond after restarting. See $LOG_FILE"
  print_connection_info
  echo
  warn "The old token no longer works. Update every client with the new one."
}

cmd_uninstall() {
  say "Stopping service"
  stop_service
  rm -f "$PLIST"
  [ -L "$CLI_LINK" ] && rm -f "$CLI_LINK"
  if [ -f "$CONFIG_FILE" ]; then
    say "Removing $ROOT"
    rm -rf "$ROOT"
  elif [ -e "$ROOT" ]; then
    # Guard against a mistyped REMINDERS_MCP_HOME pointing somewhere else.
    warn "$ROOT has no config.env, so it doesn't look like an install directory. Leaving it in place."
  fi
  say "Uninstalled. Logs remain at $LOG_FILE"
}

# --- Main ---------------------------------------------------------------------

main() {
  local command="install"
  FORCE=""
  SKIP_ACCESS=""
  load_config

  while [ $# -gt 0 ]; do
    case "$1" in
      install | update | token | status | rotate-token | uninstall) command="$1" ;;
      --host)
        HOST="${2:?--host requires a value}"
        shift
        ;;
      --port)
        PORT="${2:?--port requires a value}"
        shift
        ;;
      --ref)
        REF="${2:?--ref requires a value}"
        shift
        ;;
      --repo)
        REPO="${2:?--repo requires a value}"
        shift
        ;;
      --force) FORCE=1 ;;
      --skip-access-check) SKIP_ACCESS=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) die "Unknown argument: $1 (see --help)" ;;
    esac
    shift
  done

  case "$PORT" in
    '' | *[!0-9]*) die "Invalid port: $PORT" ;;
  esac

  case "$command" in
    install | update) cmd_install ;;
    token) cmd_token ;;
    status) cmd_status ;;
    rotate-token) cmd_rotate_token ;;
    uninstall) cmd_uninstall ;;
  esac
}

main "$@"
