# Apple Reminders MCP Server v0.2.0

A comprehensive Model Context Protocol (MCP) server for Apple Reminders on macOS, enabling AI assistants like Claude and Cursor AI to manage reminders using natural language.

## 🎉 What's New in v0.2.0

- ✅ **Full CRUD operations** (create, read, update, delete)
- ✅ **Recurring reminders** (daily, weekly, monthly, yearly patterns)
- ✅ **Location-based reminders** (geofence triggers for arriving/leaving)
- ✅ **Multiple alarms** per reminder (absolute & relative)
- ✅ **Search functionality** (text search in title and notes)
- ✅ **Date-based queries** (today, overdue, completed)
- ✅ **12 MCP tools** (up from 3 in v0.1.0)

## Features

✨ **Comprehensive Integration**

- Full CRUD on reminders (create, read, update, delete, complete)
- Search and filter reminders
- Date-based queries (today, overdue, completed)
- ~70% feature coverage of Apple Reminders

🚀 **Powered by EventKit + Swift**

- Native EventKit integration for best performance
- ✅ **Recurring reminders** (daily, weekly, monthly, custom)
- ✅ **Location-based reminders** (arrive/depart triggers)
- ✅ **Multiple alarms** per reminder
- ✅ **Tag workarounds** (encoded in notes)

🔒 **Privacy First**

- All operations happen locally on your Mac
- No cloud services or external APIs
- Respects macOS permission system
- Optional token-protected HTTP mode for access from other machines on your LAN

## Prerequisites

- **macOS 13.0+** (Ventura or later)
- **Node.js 18+**
- **Swift 5.9+** (Xcode Command Line Tools)

## Quick Start

### 1. Install & Build

```bash
# Clone or download this repository
cd apple-reminders-mcp-server

# Run setup (installs dependencies and builds everything)
npm run setup
```

### 2. Request Permissions

The build produces a small `RemindersCLI.app` wrapper around the Swift binary. Launch the wrapper to trigger the macOS permission prompt and click **Allow**:

```bash
open -W -n -a "$PWD/swift-cli/RemindersCLI.app" --args request-access
```

If you've previously denied access, grant it manually in System Settings > Privacy & Security > Reminders (look for **RemindersCLI**).

> **Why a bundle?** macOS attributes Reminders access to the *responsible* process. When the MCP host (e.g. Claude Desktop) spawns the bare binary directly, the host stays responsible — and if its Info.plist has no `NSRemindersUsageDescription`, macOS silently denies access without ever showing a prompt. The `RemindersCLI.app` bundle has its own usage description, so launching it via `open` makes the bundle the responsible process and the prompt fires correctly. The MCP server uses the same `open` path at runtime to keep TCC attribution consistent.

### 3. Configure Your AI Assistant

#### For Claude Desktop

Edit `~/.config/claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "apple-reminders": {
      "command": "node",
      "args": ["/absolute/path/to/apple-reminders-mcp-server/dist/index.js"]
    }
  }
}
```

#### For Cursor AI

Edit your Cursor MCP settings to add this server with the same configuration.

### 4. Restart Your AI Assistant

Restart Claude Desktop or Cursor to load the MCP server.

## Remote Access over HTTP

By default the server speaks MCP over stdio, so only an AI assistant on the same Mac can use it. HTTP mode serves the same tools over [Streamable HTTP](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports#streamable-http) so assistants on other machines on your network can reach your reminders. The server still runs on the Mac that owns the reminders; only the MCP traffic goes over the network.

### Install as a service

The install script sets everything up as a background service that starts at login and restarts if it crashes:

```bash
curl -fsSL https://raw.githubusercontent.com/cmer/apple-reminders-swift-mcp-server/main/scripts/install.sh | bash
```

It checks for Node.js 18+, git and the Xcode Command Line Tools, then:

1. Clones the latest `main` into `~/Library/Application Support/apple-reminders-mcp` and builds it.
2. Generates an access token and saves it to a file only you can read.
3. Registers a LaunchAgent (`~/Library/LaunchAgents/local.apple-reminders-mcp.plist`) that runs the server in HTTP mode.
4. Checks that the server responds, then asks macOS for Reminders access. Approve the prompt if one appears.
5. Installs a `reminders-mcp` command in `~/.local/bin` for managing the service later.
6. Prints the server URLs, the token, and the command to connect Claude Code.

**To update, run `reminders-mcp update`** (or the curl command again). It fetches the latest commit, rebuilds, and restarts the service. If the new version fails to start, it rolls back to the previous one. The token and your settings are kept. The Swift CLI is only rebuilt when its sources change, because each rebuild changes its signature and macOS would ask for Reminders permission again.

Other commands:

```bash
reminders-mcp token              # Print the token (reminders-mcp token | pbcopy to copy it)
reminders-mcp status             # Service state, version, URLs, and token
reminders-mcp rotate-token       # New token; old one stops working immediately
reminders-mcp uninstall          # Stop the service and delete everything it installed
reminders-mcp update --port 4000 # Change settings (saved for future updates)
```

If `~/.local/bin` isn't on your PATH, the installer tells you how to add it. You can also run the script from a checkout as `./scripts/install.sh`; either way it installs from GitHub, not from the checkout.

`--host`, `--port`, `--ref` (branch or tag to track), and `--repo` are remembered between runs. When piping from curl, pass options with `bash -s -- --port 4000`. Logs go to `~/Library/Logs/local.apple-reminders-mcp.log`.

The first time a remote client connects, macOS may ask whether `node` can accept incoming connections. Click Allow.

### Run it manually

Generate a token, then start the server with it:

```bash
node dist/index.js --generate-token
REMINDERS_MCP_TOKEN=<token> node dist/index.js --http
# Apple Reminders MCP Server listening on http://0.0.0.0:3847/mcp
```

| Flag | Environment variable | Default |
|------|----------------------|---------|
| `--http` | `REMINDERS_MCP_TRANSPORT=http` | stdio |
| `--host <addr>` | `REMINDERS_MCP_HOST` | `0.0.0.0` (all interfaces) |
| `--port <n>` | `REMINDERS_MCP_PORT` | `3847` |
| — | `REMINDERS_MCP_TOKEN` or `REMINDERS_MCP_TOKEN_FILE` | required |

The token is only read from the environment or a file so it doesn't appear in `ps` output. It must be at least 32 characters. Pass `--host 127.0.0.1` to restrict the server to the local machine.

Grant Reminders permission on the Mac first (step 2 of Quick Start). If a remote client calls `request_access` instead, the macOS prompt appears on the Mac, not on the client.

### Connect a client

Every request must carry the token as `Authorization: Bearer <token>`.

**Claude Code:**

```bash
claude mcp add --transport http --scope user apple-reminders http://my-mac.local:3847/mcp \
  --header "Authorization: Bearer <token>"
```

**Claude Desktop** (via [`mcp-remote`](https://www.npmjs.com/package/mcp-remote), since its config file only launches local commands):

```json
{
  "mcpServers": {
    "apple-reminders": {
      "command": "npx",
      "args": [
        "mcp-remote", "http://my-mac.local:3847/mcp",
        "--allow-http",
        "--header", "Authorization:${AUTH_HEADER}"
      ],
      "env": { "AUTH_HEADER": "Bearer <token>" }
    }
  }
}
```

### Security

- **Bearer token.** Every request must carry the token. It is compared in constant time.
- **Lockout.** An IP that sends 10 bad tokens within 15 minutes gets `429` responses until the window passes.
- **Request limits.** Only `POST /mcp` is served. Bodies over 1 MB are rejected.
- **Audit log.** Every tool call is logged to stderr with the caller's IP, along with rejected auth attempts.
- **No TLS.** Traffic, including the token, is plain HTTP. That's fine on a trusted home or office LAN, but anyone who can sniff the network can read it. Don't expose the port to the internet; if you need access from outside your LAN, put it behind a VPN such as Tailscale or a TLS-terminating reverse proxy.
- **Full access.** Anyone holding the token can read, create, and delete your reminders. Rotate it with `reminders-mcp rotate-token`, or by generating a new one and restarting the server.

## Available Tools (16 Total)

### Reminder Management (7 tools)

1. **`create_reminder`** - Create reminders with comprehensive attributes
   - Basic: title, notes, due date, priority, tags, URL
   - Advanced: recurring patterns, location triggers, multiple alarms
2. **`update_reminder`** - Update existing reminders
3. **`delete_reminder`** - Permanently delete reminders
4. **`complete_reminder`** - Mark reminder as complete
5. **`uncomplete_reminder`** - Mark reminder as incomplete
6. **`get_reminder`** - Get one reminder by ID with full detail, including its recurrence rule
7. **`get_reminders`** - List all reminders (filter by completion)

### List Management (4 tools)

8. **`get_all_lists`** - Get all reminder lists, with their account and ID
9. **`create_list`** - Create a list, with optional hex color and account (defaults to the account of your default list, usually iCloud)
10. **`update_list`** - Rename or recolor a list
11. **`delete_list`** - Delete a list **and every reminder in it**

`update_list` and `delete_list` take either an `id` or a `name`. If two lists share a name, the call fails and asks for the ID. Read-only lists (e.g. subscribed or shared lists you can't edit) can't be changed.

### Search & Query (4 tools)

12. **`search_reminders`** - Search by text in title/notes
13. **`get_todays_reminders`** - Get reminders due today
14. **`get_overdue_reminders`** - Get past-due reminders
15. **`get_completed_reminders`** - Get completed reminders (optional date range)

### System (1 tool)

16. **`request_access`** - Trigger the macOS Reminders permission prompt. Call once before other tools if access has not yet been granted.

## Usage Examples

### Basic Reminders

```
"Create a reminder to buy milk"
"Show me all my reminders"
"Mark the milk reminder as complete"
"Delete the milk reminder"
```

### Lists

```
"Create a list called Groceries"
"Rename my Groceries list to Shopping and make it green"
"Delete the Old Projects list"
```

### Recurring Reminders

```
"Create a weekly reminder for team meeting every Monday at 10am"
"Set up a daily reminder to take medication at 8am"
"Create a monthly reminder on the 1st to pay rent"
"Remind me on the first Monday of every month to review the budget"
```

### Location-Based Reminders

```
"Remind me to buy groceries when I arrive at the supermarket"
"Create a reminder to call mom when I leave work"
```

### Search & Filters

```
"Search for reminders about meetings"
"Show me today's reminders"
"What reminders are overdue?"
"Show me completed reminders from last week"
```

### Advanced Features

```
""Create an URGENT reminder with priority 1 to call the client"
"Create a high-priority reminder with tags #work #urgent""
"Set up a reminder with multiple alarms - 1 day before and 1 hour before"
"Create a reminder that repeats every other week"
```

## Architecture

```
AI Assistant (Claude/Cursor)
    ↓ MCP Protocol (stdio, or Streamable HTTP with --http)
TypeScript MCP Server (Node.js)
    ↓ open -W -n -a RemindersCLI.app  (LaunchServices, for TCC attribution)
RemindersCLI.app → Swift CLI Binary (EventKit)
    ↓ EventKit Framework
Apple Reminders.app
```

The MCP server invokes the Swift CLI through a small `RemindersCLI.app` bundle so that macOS attributes Reminders permission to the bundle's `Info.plist` instead of the host process. `open` detaches stdio, so the executor redirects stdout/stderr to temp files via `--stdout`/`--stderr` and reads them back. If no bundle is present (e.g. dev builds run from Terminal), the executor falls back to direct exec.

### Why EventKit + Swift?

This project uses Apple's **EventKit framework** via a Swift CLI, rather than the simpler JXA (JavaScript for Automation) approach. Here's why:

**JXA Limitations** (POC tested and documented):

- ❌ No support for **recurring reminders** (daily, weekly, monthly patterns)
- ❌ No support for **location-based reminders** (geofencing)
- ❌ No access to **tags** (would require text workarounds)
- ❌ No support for **subtasks** (not exposed in API)
- ❌ **Multiple alarms** not accessible
- ❌ JXA is essentially abandoned by Apple (no updates since 2014)

**EventKit Advantages**:

- ✅ Full access to **70%+ of Reminders features** via official Apple API
- ✅ Native support for **recurring reminders** with complex rules
- ✅ Native support for **location triggers** (arrive/depart)
- ✅ Native support for **multiple alarms** per reminder
- ✅ **Actively maintained** by Apple with new macOS releases
- ✅ Better **performance** and **reliability**

**Trade-off**: EventKit requires Swift compilation, but the benefits far outweigh the minimal additional setup complexity. The Swift CLI is built once during installation and provides access to nearly all Reminders features that are publicly available.

## Feature Coverage (~70%)

### ✅ Fully Supported

- **Core Operations**: Create, read, update, delete, complete
- **Recurring Reminders**: Daily, weekly, monthly, yearly with custom rules
- **Location Reminders**: Geofence triggers (arriving/leaving)
- **Multiple Alarms**: Absolute (specific time) and relative (before due date)
- **Search**: Text search in title and notes
- **Date Queries**: Today, overdue, completed with date ranges
- **Lists**: Create, rename, recolor, and delete lists; specify list for reminders
- **Priority**: 0=none, 1=urgent (!!!), 5=medium, 9=low
- **Flagged Status**: Mark reminders as important (flag icon)
- **Notes & URLs**: Rich text notes, associated URLs

### ⚠️ Workarounds

- **Tags**: Encoded as `[#tag]` in notes field (searchable)
- **Subtasks**: Use structured notes or linked reminders

### ⚠️ API Limitations (Not Yet Available in EventKit)

- **Urgent Alarms** (macOS 26.2+): The new "Urgent" alarm feature is NOT exposed in EventKit API
  - Workaround: Use `priority: 1` + `flagged: true` + regular alarms
  - See `URGENT_FEATURE_STATUS.md` for details
- Apple has not announced when/if EventKit will support this feature

### ❌ Not Supported (Private Apple APIs)

- Native tags feature
- Subtasks feature
- Smart lists

## Development

### Project Structure

```
apple-reminders-mcp-server/
├── swift-cli/              # Swift CLI (EventKit integration)
│   ├── Sources/
│   │   ├── RemindersKit/   # Core library
│   │   │   ├── Models/     # Swift models
│   │   │   └── *.swift     # Managers
│   │   └── reminders-cli/  # CLI executable
│   ├── RemindersCLI.app/   # Generated by build:swift; ad-hoc signed bundle
│   │                       # used as the TCC subject for Reminders access
│   └── Package.swift
├── src/                    # TypeScript MCP Server
│   ├── index.ts           # Entry point: picks stdio or HTTP transport
│   ├── server.ts          # MCP server and tool routing
│   ├── config.ts          # CLI flags / env parsing
│   ├── http-server.ts     # Token-protected Streamable HTTP transport
│   ├── executor/          # Swift CLI executor (launches via `open` when
│   │                      #   RemindersCLI.app is present)
│   ├── tools/             # 16 MCP tool handlers
│   ├── validation/        # Zod schemas
│   └── types/             # TypeScript types
└── docs/                  # Documentation
```

### Development Commands

```bash
# Build everything
npm run build          # Build TypeScript
npm run build:swift    # Build Swift CLI

# Development mode
npm run dev            # Watch mode for TypeScript

# Testing
npm test               # Run tests
npm run lint           # Lint code
npm run format         # Format code
swift test             # Swift unit tests, run from swift-cli/ (no Reminders access needed)
RUN_LIVE_REMINDERS=1 npm run test:live  # Opt-in live tests against real Reminders; creates and deletes its own throwaway list

# Cleanup
npm run clean          # Remove build artifacts
```

### Building from Source

```bash
# Build Swift CLI (release mode)
cd swift-cli
swift build --configuration release

# Build TypeScript
cd ..
npm run build
```

## Testing

### Test Swift CLI Directly

```bash
# Create an urgent reminder (priority 1 = shows !!! in Reminders.app)
./swift-cli/.build/release/reminders-cli create-reminder '{"title":"URGENT: Fix bug","priority":1}'

# Create recurring reminder
./swift-cli/.build/release/reminders-cli create-reminder '{
  "title":"Weekly Meeting",
  "dueDate":"2026-01-12T10:00:00Z",
  "recurrence":{"frequency":"weekly","daysOfWeek":["monday"]}
}'

# Search reminders
./swift-cli/.build/release/reminders-cli search-reminders '{"searchText":"meeting"}'

# Get today's reminders
./swift-cli/.build/release/reminders-cli get-todays-reminders

# Create, rename, and delete a list
./swift-cli/.build/release/reminders-cli create-list '{"name":"Groceries","color":"#34C759"}'
./swift-cli/.build/release/reminders-cli update-list '{"name":"Groceries","newName":"Shopping"}'
./swift-cli/.build/release/reminders-cli delete-list '{"name":"Shopping"}'
```

### Test with MCP Inspector

```bash
npx @modelcontextprotocol/inspector node dist/index.js
```

## Advanced Features

### Recurring Reminders

Create reminders that repeat on a schedule. A recurring reminder needs a `dueDate`, which is the first occurrence:

```typescript
{
  "title": "Team sync",
  "dueDate": "2026-01-12T10:00:00Z",
  "recurrence": {
    "frequency": "weekly",                        // daily, weekly, monthly, yearly
    "interval": 1,                                // every N weeks
    "daysOfWeek": ["monday", "wednesday"],        // full lowercase weekday names
    "endDate": "2026-12-31"                       // calendar date, last day included
  }
}
```

Monthly on the first Monday, or yearly on Thanksgiving (the fourth Thursday of November):

```typescript
"recurrence": { "frequency": "monthly", "nthWeekday": { "ordinal": 1, "weekday": "monday" } }
"recurrence": { "frequency": "yearly", "monthsOfYear": [11], "nthWeekday": { "ordinal": 4, "weekday": "thursday" } }
```

Fields:

- `interval`: every N days, weeks, months or years (default 1)
- `daysOfWeek` (weekly): e.g. `["monday", "friday"]`
- `daysOfMonth` (monthly): days 1–31, e.g. `[1, 15]`
- `nthWeekday` (monthly or yearly): `ordinal` 1–5, or -1 for the last one. A yearly rule also needs `monthsOfYear`.
- `monthsOfYear` (yearly): months 1–12
- `endDate` (`YYYY-MM-DD`) or `occurrenceCount`: stop after a date, or after N occurrences remaining, including the current one. Use one or the other, not both.

A rule without a `dueDate` is rejected, and so is one that combines `daysOfMonth` with `nthWeekday`.

#### Reading

List tools show a `🔁` summary line under each recurring reminder (e.g. "🔁 Every 2 weeks on Mon, Wed"). `get_reminder` returns the full rule as JSON. A rule this server can't express, such as "last weekday" or a reminder with several rules, reads as `{"supported": false, "rrule": "..."}` and shows "Repeats on a custom schedule this server can't edit". Leave such a reminder alone by omitting `recurrence` on update.

#### Updating

In `update_reminder`, `recurrence` and `dueDate` work the same way: omitted = unchanged, `null` = clear, a value = replace. Clearing the due date of a recurring reminder is rejected unless you also pass `recurrence: null`. To change a rule, read it with `get_reminder` first and send the whole rule back, because it replaces the old one.

`notes` and `url` are still replaced on every update, so omitting them clears them. This is a change for `dueDate`: omitting it used to clear the due date, and now leaves it as it is.

#### Completing

Completing a recurring reminder advances it to its next occurrence. It keeps its ID and stays open, and Reminders leaves a completed copy behind under a new ID. Completing the last occurrence completes the reminder for good.

To stop a reminder repeating, call `update_reminder` with `recurrence: null`, then `complete_reminder`. `uncomplete_reminder` can't undo an advance.

#### Known limitation: Hourly repeats

Reminders.app "Hourly" repeats show through this server as "Every day", because EventKit reports them as daily. Renaming, editing other fields and completing them are safe. Setting `recurrence` on one replaces the hourly repeat.

### Location-Based Reminders

Trigger reminders based on location:

```typescript
{
  "title": "Buy groceries",
  "location": {
    "latitude": 37.7749,
    "longitude": -122.4194,
    "radius": 100,           // meters
    "proximity": "enter",    // or "leave"
    "title": "Whole Foods"
  }
}
```

### Multiple Alarms

Add multiple notifications to a reminder:

```typescript
{
  "title": "Important meeting",
  "dueDate": "2026-01-15T14:00:00Z",
  "alarms": [
    {
      "type": "relative",
      "relativeOffset": -86400  // 1 day before (in seconds)
    },
    {
      "type": "absolute",
      "absoluteDate": "2026-01-15T13:00:00Z"  // 1 hour before
    }
  ]
}
```

## Troubleshooting

### Permission Denied

1. From the repository root, run `open -W -n -a "$PWD/swift-cli/RemindersCLI.app" --args request-access` and click **Allow** on the prompt.
2. If you've previously denied: open System Settings > Privacy & Security > Reminders and enable **RemindersCLI**.
3. Restart your AI assistant.

If the prompt never appears at all, double-check that `swift-cli/RemindersCLI.app` exists. It's produced by `npm run build:swift`; if it's missing, that build step didn't run. Calling the bare `swift-cli/.build/release/reminders-cli` binary directly from an MCP host that lacks `NSRemindersUsageDescription` (Claude Desktop is one) will silently deny without prompting — the bundle is what makes the prompt fire.

To start over with permissions for just this tool: `tccutil reset Reminders com.krishna-desiraju.reminders-cli`.

### Swift CLI Not Found

1. Build the Swift CLI: `npm run build:swift`
2. Verify: `ls swift-cli/.build/release/reminders-cli`

### Tool Not Working

1. Check Swift CLI directly with test JSON
2. Check MCP server logs in your AI assistant
3. Use MCP Inspector for isolated debugging

## Roadmap

### ✅ Completed

- [x] Full CRUD operations
- [x] Search and filters
- [x] Date-based queries
- [x] Recurring reminders
- [x] Location-based reminders
- [x] Multiple alarms
- [x] List management (create, update, delete lists)

### 🔄 Future Enhancements

- [ ] Batch operations
- [ ] Rich error messages with suggestions
- [ ] Performance optimization
- [ ] Pre-compiled binaries for distribution
- [ ] npm package publication

## Contributing

This is a learning project. Contributions, issues, and feature requests are welcome!

## License

MIT

## References

- [MCP Documentation](https://modelcontextprotocol.io/)
- [EventKit Documentation](https://developer.apple.com/documentation/eventkit)
- [FradSer's mcp-server-apple-events](https://github.com/FradSer/mcp-server-apple-events)

---

**Built with ❤️ for the MCP ecosystem**

Version 0.2.0 | Updated January 2026
