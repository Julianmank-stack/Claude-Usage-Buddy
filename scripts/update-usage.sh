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
else
  # No explicit value given — derive a live "remaining" from ccusage's 5-hour
  # billing blocks (Claude Code activity). remaining = 1 - used/limit, where
  # `used` is the active block's tokens and `limit` is either CCUSAGE_TOKEN_LIMIT
  # or your heaviest completed block (so the buddy self-calibrates).
  #
  # No global install or jq needed: we run ccusage via npx/bunx if it isn't on
  # PATH, and parse the JSON with node (falling back to jq).
  if [[ -n "${CCUSAGE_CMD:-}" ]]; then
    ccusage_cmd="$CCUSAGE_CMD"
  elif command -v ccusage >/dev/null 2>&1; then
    ccusage_cmd="ccusage"
  elif command -v bunx >/dev/null 2>&1; then
    ccusage_cmd="bunx ccusage"
  elif command -v npx >/dev/null 2>&1; then
    ccusage_cmd="npx -y ccusage@latest"
  else
    echo "Need ccusage. Either pass a value (e.g. ./scripts/update-usage.sh 42%)," >&2
    echo "or install Node so 'npx ccusage' works, or set CCUSAGE_CMD." >&2
    exit 1
  fi

  json=$($ccusage_cmd blocks --json 2>/dev/null || true)
  if [[ -z "$json" ]]; then
    echo "ccusage returned no data (no Claude Code usage yet?). Ran: $ccusage_cmd blocks --json" >&2
    exit 1
  fi

  if command -v node >/dev/null 2>&1; then
    frac=$(printf '%s' "$json" | CCUSAGE_TOKEN_LIMIT="${CCUSAGE_TOKEN_LIMIT:-}" node -e '
      let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
        let j; try { j = JSON.parse(s); } catch (e) { process.exit(3); }
        const blocks = j.blocks || [];
        const active = blocks.filter(b => b.isActive).map(b => +b.totalTokens || 0);
        const used = active.length ? active[0] : 0;
        const env = process.env.CCUSAGE_TOKEN_LIMIT;
        const limit = env ? +env
          : Math.max(0, ...blocks.filter(b => !b.isActive && !b.isGap).map(b => +b.totalTokens || 0));
        if (!limit) process.exit(2);
        let r = 1 - used / limit; if (r < 0) r = 0; if (r > 1) r = 1;
        process.stdout.write(r.toFixed(4));
      });') || true
  elif command -v jq >/dev/null 2>&1; then
    used=$(printf '%s' "$json" | jq -r '[.blocks[]? | select(.isActive==true) | .totalTokens] | (.[0] // 0)')
    if [[ -n "${CCUSAGE_TOKEN_LIMIT:-}" ]]; then
      limit="$CCUSAGE_TOKEN_LIMIT"
    else
      limit=$(printf '%s' "$json" | jq -r '[.blocks[]? | select(.isActive!=true and .isGap!=true) | .totalTokens] | (max // empty)')
    fi
    if [[ -n "${limit:-}" && "$limit" != "0" && "$limit" != "null" ]]; then
      frac=$(awk -v u="$used" -v l="$limit" 'BEGIN { r=1-u/l; if(r<0)r=0; if(r>1)r=1; printf "%.4f", r }')
    fi
  else
    echo "Need node or jq to parse ccusage output." >&2
  fi

  if [[ -z "${frac:-}" ]]; then
    echo "Couldn't compute usage from ccusage — likely no completed block yet to" >&2
    echo "calibrate against. Set CCUSAGE_TOKEN_LIMIT to a token budget, e.g.:" >&2
    echo "  CCUSAGE_TOKEN_LIMIT=2000000 ./scripts/update-usage.sh" >&2
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
