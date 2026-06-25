#!/usr/bin/env bash
#
# Stop the Claude Usage Buddy and remove its login auto-start.
#
set -euo pipefail

for LABEL in com.claudeusagebuddy.agent com.claudeusagebuddy.refresh; do
  PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
  if [[ -f "$PLIST" ]]; then
    launchctl unload "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    echo "Removed $PLIST"
  fi
done

# Belt and suspenders: stop any stray running copy.
killall ClaudeUsageBuddy 2>/dev/null || true
echo "Stopped the buddy and removed auto-start + usage refresh."
