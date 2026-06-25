#!/usr/bin/env bash
#
# Stop the Claude Usage Buddy and remove its login auto-start.
#
set -euo pipefail

LABEL="com.claudeusagebuddy.agent"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

if [[ -f "$PLIST" ]]; then
  launchctl unload "$PLIST" 2>/dev/null || true
  rm -f "$PLIST"
  echo "Removed auto-start ($PLIST) and stopped the buddy."
else
  echo "No auto-start installed ($PLIST not found)."
fi

# Belt and suspenders: stop any stray running copy.
killall ClaudeUsageBuddy 2>/dev/null || true
