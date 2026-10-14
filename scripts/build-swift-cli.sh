#!/bin/bash
set -e

cd "$(dirname "$0")/../swift-cli"

echo "🔨 Building Swift CLI..."
swift build --configuration release

# Locate the freshly built binary, tolerating a missing `.build/release` symlink
# (some packaging flows strip it).
if [ -x ".build/release/reminders-cli" ]; then
  BINARY=".build/release/reminders-cli"
else
  BINARY="$(ls .build/*-apple-macosx/release/reminders-cli 2>/dev/null | head -1)"
fi

if [ -z "$BINARY" ] || [ ! -x "$BINARY" ]; then
  echo "❌ Could not find built reminders-cli binary"
  exit 1
fi

echo "✅ Swift CLI built: $BINARY"

# Wrap the binary in a minimal .app bundle so macOS attributes TCC (Reminders
# access) to our Info.plist, not to the host process. Without this, hosts that
# lack NSRemindersUsageDescription (e.g. Claude Desktop) silently deny the
# permission prompt and the user has no way to grant access.
APP_BUNDLE="RemindersCLI.app"
echo "📦 Wrapping in $APP_BUNDLE for TCC attribution..."

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/reminders-cli"
chmod +x "$APP_BUNDLE/Contents/MacOS/reminders-cli"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>reminders-cli</string>
    <key>CFBundleIdentifier</key>
    <string>com.krishna-desiraju.reminders-cli</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>RemindersCLI</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSRemindersUsageDescription</key>
    <string>RemindersCLI needs access to your Reminders to let the MCP server read and manage them.</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>RemindersCLI needs full access to your Reminders to let the MCP server read and manage them.</string>
</dict>
</plist>
PLIST

# Ad-hoc codesign so macOS gives the bundle a stable TCC identity. No
# Developer ID is needed for local use.
codesign --force --sign - "$APP_BUNDLE" >/dev/null

echo "✅ App bundle ready: swift-cli/$APP_BUNDLE/Contents/MacOS/reminders-cli"
