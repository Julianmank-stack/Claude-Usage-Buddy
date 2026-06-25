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
elif command -v "${CCUSAGE_BIN:-ccusage}" >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  # Derive a 0..1 "remaining" from ccusage's 5-hour billing blocks.
  #
  # ccusage groups Claude Code activity into rolling 5-hour blocks. We read the
  # *active* block's token total and compare it to a limit:
  #   * CCUSAGE_TOKEN_LIMIT, if you set it (your exact per-window token budget), or
  #   * "max" — your heaviest completed block, so the buddy self-calibrates and
  #     drains as this session approaches your typical peak.
  # remaining = 1 - used/limit.
  CCUSAGE_BIN="${CCUSAGE_BIN:-ccusage}"
  json=$("$CCUSAGE_BIN" blocks --json 2>/dev/null || true)
  if [[ -n "$json" ]]; then
    # Tokens used in the current (active) block; 0 if nothing is active.
    used=$(printf '%s' "$json" | jq -r '[.blocks[]? | select(.isActive==true) | .totalTokens] | (.[0] // 0)')

    if [[ -n "${CCUSAGE_TOKEN_LIMIT:-}" ]]; then
      limit="$CCUSAGE_TOKEN_LIMIT"
    else
      # Heaviest completed (non-active, non-gap) block.
      limit=$(printf '%s' "$json" | jq -r '[.blocks[]? | select(.isActive!=true and .isGap!=true) | .totalTokens] | (max // empty)')
    fi

    if [[ -z "${limit:-}" || "$limit" == "0" || "$limit" == "null" ]]; then
      echo "ccusage: no token limit yet (need either a completed block or CCUSAGE_TOKEN_LIMIT)." >&2
      echo "Raw ccusage JSON follows so you can pin a limit:" >&2
      printf '%s\n' "$json" | jq '.blocks[]? | {isActive, isGap, totalTokens}' >&2 || true
    else
      frac=$(awk -v u="$used" -v l="$limit" 'BEGIN { r = 1 - u/l; if (r<0) r=0; if (r>1) r=1; printf "%.4f", r }')
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
