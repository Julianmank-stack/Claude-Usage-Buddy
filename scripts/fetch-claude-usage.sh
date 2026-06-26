#!/usr/bin/env bash
#
# Live usage from claude.ai. Reads your plan's remaining usage straight from the
# same endpoint the Settings -> Usage page uses, and writes it to the state file
# the menu-bar buddy reads.
#
#   GET https://claude.ai/api/organizations/<org>/usage
#   -> { "limits": [ { "kind": "session", "percent": <0..100 used>, ... }, ... ] }
#
# remaining = 1 - percent/100. By default we track the limit you're CLOSEST to
# hitting (smallest remaining across all limits), so the buddy warns you about
# whichever wall — 5-hour session or 7-day weekly — is nearest. Override with
# CLAUDE_USAGE_LIMIT=session  (or weekly_all) to pin one.
#
# Auth: your claude.ai sessionKey cookie. Put it in ~/.claude-usage-buddy/session-key
# (chmod 600) or pass it as CLAUDE_SESSION_KEY. It is never written to the repo.
#
set -euo pipefail

STATE_DIR="$HOME/.claude-usage-buddy"
STATE_FILE="$STATE_DIR/state.json"
KEY_FILE="$STATE_DIR/session-key"
mkdir -p "$STATE_DIR"

UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) claude-usage-buddy"

# --- session key -------------------------------------------------------------
SESSION_KEY="${CLAUDE_SESSION_KEY:-}"
if [[ -z "$SESSION_KEY" && -r "$KEY_FILE" ]]; then
  SESSION_KEY="$(tr -d '[:space:]' < "$KEY_FILE")"
fi
if [[ -z "$SESSION_KEY" ]]; then
  echo "No session key found." >&2
  echo "Put your claude.ai sessionKey in $KEY_FILE (then: chmod 600 \"$KEY_FILE\")," >&2
  echo "or run with CLAUDE_SESSION_KEY=... — see the README for how to copy it." >&2
  exit 1
fi

if ! command -v node >/dev/null 2>&1; then
  echo "Need Node.js to parse the response (node not found on PATH)." >&2
  exit 1
fi

claude_get() {
  # $1 = path under https://claude.ai
  curl -fsS "https://claude.ai$1" \
    -H "Cookie: sessionKey=$SESSION_KEY" \
    -H "Accept: application/json" \
    -H "User-Agent: $UA" 2>/dev/null || true
}

# --- org id (auto-discover so we never hardcode a personal id) ---------------
ORG_ID="${CLAUDE_ORG_ID:-}"
if [[ -z "$ORG_ID" ]]; then
  orgs=$(claude_get "/api/organizations")
  ORG_ID=$(printf '%s' "$orgs" | node -e '
    let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
      try { const a=JSON.parse(s); const o=Array.isArray(a)?a[0]:a;
            if (o && o.uuid) { process.stdout.write(o.uuid); return; } } catch(e){}
      process.exit(1);
    });' || true)
fi
if [[ -z "$ORG_ID" ]]; then
  echo "Couldn't determine your organization id (session key expired or blocked?)." >&2
  echo "Set CLAUDE_ORG_ID to skip auto-discovery." >&2
  exit 1
fi

# --- usage -------------------------------------------------------------------
json=$(claude_get "/api/organizations/$ORG_ID/usage")
if [[ -z "$json" ]]; then
  echo "Usage request failed (expired session key, or a Cloudflare/network block)." >&2
  exit 1
fi

WHICH="${CLAUDE_USAGE_LIMIT:-min}"

frac=$(printf '%s' "$json" | CLAUDE_USAGE_LIMIT="$WHICH" node -e '
  let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{
    let j; try { j = JSON.parse(s); } catch (e) { process.exit(3); }
    const which = process.env.CLAUDE_USAGE_LIMIT || "min";
    const num = v => typeof v === "number" && isFinite(v);
    const limits = Array.isArray(j.limits) ? j.limits : [];
    let usedPct = null;

    if (which !== "min") {
      const e = limits.find(l => l.kind === which || l.group === which);
      if (e && num(e.percent)) usedPct = e.percent;
    }
    if (usedPct === null) {                       // most-drained limit
      const ps = limits.filter(l => num(l.percent)).map(l => l.percent);
      if (ps.length) usedPct = Math.max(...ps);
    }
    if (usedPct === null) {                        // top-level mirrors
      const m = [j.five_hour, j.seven_day].filter(o => o && num(o.utilization)).map(o => o.utilization);
      if (m.length) usedPct = Math.max(...m);
    }
    if (usedPct === null) process.exit(2);

    let r = 1 - usedPct / 100; if (r < 0) r = 0; if (r > 1) r = 1;
    process.stdout.write(r.toFixed(4));
  });') || true

if [[ -z "$frac" ]]; then
  echo "Got a response but couldn't find a usage percent in it." >&2
  exit 1
fi

printf '{"fraction": %s}\n' "$frac" > "$STATE_FILE"
echo "Wrote $STATE_FILE -> fraction=$frac (remaining; tracking: $WHICH)"
