#!/usr/bin/env bash
#
# Live usage from claude.ai — without fighting Cloudflare and without storing a
# credential. It asks your already-logged-in Google Chrome to fetch the usage
# JSON from inside an open claude.ai tab (see claude-usage.applescript), so the
# request is authenticated and Cloudflare-cleared by the browser itself.
#
# The percent math runs inside the page too, so there are NO local dependencies
# beyond macOS + Chrome (no Node, no jq).
#
# Requirements (one-time):
#   * Google Chrome running, with a claude.ai tab open and logged in.
#   * Chrome menu: View > Developer > "Allow JavaScript from Apple Events" = ON.
#   * Grant Automation permission when macOS first prompts (lets this control Chrome).
#
# Writes remaining usage (0..1) to ~/.claude-usage-buddy/state.json, tracking
# CLAUDE_USAGE_LIMIT: "session" (5-hour), "weekly_all" (7-day), or "min"
# (default: whichever limit you're closest to hitting).
#
set -euo pipefail

STATE_DIR="$HOME/.claude-usage-buddy"
STATE_FILE="$STATE_DIR/state.json"
mkdir -p "$STATE_DIR"
HERE="$(cd "$(dirname "$0")" && pwd)"
ERR=/tmp/claude-usage-buddy-osa.err

if ! command -v osascript >/dev/null 2>&1; then
  echo "This live source needs macOS + Google Chrome (osascript not found)." >&2
  exit 1
fi

WHICH="${CLAUDE_USAGE_LIMIT:-min}"

frac=$(osascript "$HERE/claude-usage.applescript" "$WHICH" 2>"$ERR" || true)

if [[ -z "$frac" ]]; then
  echo "Couldn't reach Chrome. Check that:" >&2
  echo "  1. Chrome is running with a claude.ai tab open and logged in." >&2
  echo "  2. Chrome > View > Developer > 'Allow JavaScript from Apple Events' is ON." >&2
  echo "  3. You allowed Automation control of Chrome when macOS prompted." >&2
  if [[ -s "$ERR" ]]; then echo "--- osascript said ---" >&2; cat "$ERR" >&2; fi
  exit 1
fi

if [[ "$frac" == ERR:* ]]; then
  case "$frac" in
    "ERR:no-claude.ai-tab-found")
      echo "No claude.ai tab found in Chrome — open (and pin) one, logged in." >&2 ;;
    "ERR:HTTP 401"|"ERR:HTTP 403")
      echo "claude.ai said '${frac#ERR:}' — the tab may be logged out. Reload it and log in." >&2 ;;
    *)
      echo "In-page fetch failed: ${frac#ERR:}" >&2 ;;
  esac
  exit 1
fi

# Expect a clean 0..1 fraction like "0.4600".
if ! [[ "$frac" =~ ^(0(\.[0-9]+)?|1(\.0+)?)$ ]]; then
  echo "Unexpected response from Chrome (first 200 chars):" >&2
  printf '%s' "$frac" | head -c 200 >&2; echo >&2
  exit 1
fi

printf '{"fraction": %s}\n' "$frac" > "$STATE_FILE"
echo "Wrote $STATE_FILE -> fraction=$frac (remaining; tracking: $WHICH)"
