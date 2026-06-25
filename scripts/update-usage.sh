#!/usr/bin/env bash
#
# Writes the current Claude usage as a fraction (0..1) into the state file the
# menu-bar buddy reads. Run it on a schedule (cron / launchd / a loop) to keep
# the buddy in sync with how much usage you have left.
#
# Usage:
#   ./scripts/update-usage.sh 0.42        # set remaining fraction directly
#   ./scripts/update-usage.sh 42%         # or as a percent
#   ./scripts/update-usage.sh             # try to derive it from `ccusage`
#
set -euo pipefail

STATE_DIR="$HOME/.claude-usage-buddy"
STATE_FILE="$STATE_DIR/state.json"
mkdir -p "$STATE_DIR"

frac=""

if [[ $# -ge 1 ]]; then
  arg="$1"
  if [[ "$arg" == *% ]]; then
    pct="${arg%\%}"
    frac=$(awk -v p="$pct" 'BEGIN { printf "%.4f", p/100 }')
  else
    frac="$arg"
  fi
elif command -v ccusage >/dev/null 2>&1; then
  # Best-effort: derive a 0..1 "remaining" from ccusage's JSON if it exposes a
  # percent-used field. Adjust the jq path to match your ccusage version.
  if command -v jq >/dev/null 2>&1; then
    used_pct=$(ccusage --json 2>/dev/null | jq -r '.percentUsed // empty' || true)
    if [[ -n "$used_pct" ]]; then
      frac=$(awk -v u="$used_pct" 'BEGIN { printf "%.4f", 1 - u/100 }')
    fi
  fi
fi

if [[ -z "$frac" ]]; then
  echo "Could not determine usage. Pass a value, e.g. ./scripts/update-usage.sh 42%" >&2
  exit 1
fi

# Clamp to [0,1].
frac=$(awk -v f="$frac" 'BEGIN { if (f<0) f=0; if (f>1) f=1; printf "%.4f", f }')

printf '{"fraction": %s}\n' "$frac" > "$STATE_FILE"
echo "Wrote $STATE_FILE -> fraction=$frac"
