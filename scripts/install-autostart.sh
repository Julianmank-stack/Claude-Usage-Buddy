#!/usr/bin/env bash
#
# Install the Claude Usage Buddy as a macOS LaunchAgent so it:
#   * starts automatically every time you log in, and
#   * relaunches itself if it ever quits — so it's *always* in your menu bar.
#
# The app fetches your real plan usage from claude.ai by itself (built-in web
# view — log in once from the buddy's menu). No other agents or dependencies.
#
# Run once:
#   ./scripts/install-autostart.sh
#
# To remove it later:
#   ./scripts/uninstall-autostart.sh
#
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$REPO/.build/release/ClaudeUsageBuddy"
LABEL="com.claudeusagebuddy.agent"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
USAGE_LIMIT="${CLAUDE_USAGE_LIMIT:-session}"

echo "Building the release binary…"
( cd "$REPO" && swift build -c release )

if [[ ! -x "$BIN" ]]; then
  echo "Build did not produce $BIN" >&2
  exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>CLAUDE_USAGE_LIMIT</key>
        <string>$USAGE_LIMIT</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>StandardOutPath</key>
    <string>/tmp/claude-usage-buddy.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/claude-usage-buddy.err</string>
</dict>
</plist>
EOF

# Migration: earlier versions used a separate refresh-timer agent that drove
# usage via Chrome/AppleScript. The app now fetches by itself — remove it.
OLD_REFRESH="$HOME/Library/LaunchAgents/com.claudeusagebuddy.refresh.plist"
if [[ -f "$OLD_REFRESH" ]]; then
  launchctl unload "$OLD_REFRESH" 2>/dev/null || true
  rm -f "$OLD_REFRESH"
  echo "Removed the old Chrome-based refresh agent (no longer needed)."
fi

# (Re)load it. Unload first so re-running this script picks up a new binary.
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo
echo "Installed. The buddy is running now and will start automatically at login."
echo "Look in the top-right of your menu bar."
echo
echo "Live usage is built in: click the buddy -> 'Log in to claude.ai…' and sign"
echo "in once. The buddy then refreshes every 10s on its own — no Chrome needed."
echo "  - Tracking limit: $USAGE_LIMIT (re-run with CLAUDE_USAGE_LIMIT=weekly_all or min to change)."
echo "  - Logs: /tmp/claude-usage-buddy.{log,err}"
echo
echo "Because KeepAlive is on, picking 'Quit' from its menu will relaunch it."
echo "To fully stop and remove auto-start, run: ./scripts/uninstall-autostart.sh"
