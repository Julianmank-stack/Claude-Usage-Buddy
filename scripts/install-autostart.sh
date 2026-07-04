#!/usr/bin/env bash
#
# Install the Claude Usage Buddy as a macOS LaunchAgent so it:
#   * starts automatically every time you log in, and
#   * relaunches itself if it ever quits — so it's *always* in your menu bar.
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

# (Re)load it. Unload first so re-running this script picks up a new binary path.
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

# --- Usage refresh timer -----------------------------------------------------
# A second agent pulls your real plan usage from claude.ai every couple of
# minutes and writes it to the state file. The app re-reads that file every ~5s,
# so the buddy live-updates. No local dependencies beyond macOS + Chrome.
REFRESH_LABEL="com.claudeusagebuddy.refresh"
REFRESH_PLIST="$HOME/Library/LaunchAgents/$REFRESH_LABEL.plist"
REFRESH_INTERVAL="${REFRESH_INTERVAL:-10}"
USAGE_LIMIT="${CLAUDE_USAGE_LIMIT:-session}"

cat > "$REFRESH_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$REFRESH_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>-lc</string>
        <string>exec "$REPO/scripts/fetch-claude-usage.sh"</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>CLAUDE_USAGE_LIMIT</key>
        <string>$USAGE_LIMIT</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>$REFRESH_INTERVAL</integer>
    <key>StandardOutPath</key>
    <string>/tmp/claude-usage-buddy-refresh.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/claude-usage-buddy-refresh.err</string>
</dict>
</plist>
EOF

launchctl unload "$REFRESH_PLIST" 2>/dev/null || true
launchctl load "$REFRESH_PLIST"

echo
echo "Installed. The buddy is running now and will start automatically at login."
echo "Look in the top-right of your menu bar."
echo
echo "Usage refresh: every ${REFRESH_INTERVAL}s from claude.ai (your real plan usage),"
echo "read via your logged-in Chrome — no session key stored. Make sure:"
echo "  - Chrome is running with a claude.ai tab open and logged in."
echo "  - Chrome > View > Developer > 'Allow JavaScript from Apple Events' is ON."
echo "  - You allow Automation control of Chrome when macOS prompts."
echo "  - Tracking limit: $USAGE_LIMIT (override with CLAUDE_USAGE_LIMIT, e.g. weekly_all or min)."
echo "  - Logs: /tmp/claude-usage-buddy-refresh.{log,err}"
echo
echo "Because KeepAlive is on, picking 'Quit' from its menu will relaunch it."
echo "To fully stop and remove auto-start, run: ./scripts/uninstall-autostart.sh"
