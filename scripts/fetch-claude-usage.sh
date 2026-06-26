#!/usr/bin/env bash
#
# Live usage from claude.ai — without fighting Cloudflare and without storing a
# credential. It asks your already-logged-in Google Chrome to fetch the usage
# JSON from inside an open claude.ai tab (see claude-usage.applescript), so the
# request is authenticated and Cloudflare-cleared by the browser itself.
#
# Requirements (one-time):
#   * Google Chrome running, with a claude.ai tab open and logged in.
#   * Chrome menu: View > Developer > "Allow JavaScript from Apple Events" = ON.
#   * Grant Automation permission when macOS first prompts (lets this control Chrome).
#
# It writes remaining usage (0..1) to ~/.claude-usage-buddy/state.json, tracking
# whichever limit you're closest to hitting. Pin one with
# CLAUDE_USAGE_LIMIT=session (or weekly_all).
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
if ! command -v node >/dev/null 2>&1; then
  echo "Need Node.js to parse the response (node not found on PATH)." >&2
  exit 1
fi

json=$(osascript "$HERE/claude-usage.applescript" 2>"$ERR" || true)

if [[ -z "$json" ]]; then
  echo "Couldn't read usage from Chrome. Check that:" >&2
  echo "  1. Chrome is running with a claude.ai tab open and logged in." >&2
  echo "  2. Chrome > View > Developer > 'Allow JavaScript from Apple Events' is ON." >&2
  echo "  3. You allowed Automation control of Chrome when macOS prompted." >&2
  if [[ -s "$ERR" ]]; then echo "--- osascript said ---" >&2; cat "$ERR" >&2; fi
  exit 1
fi

# Cloudflare challenge leaking through (page not actually logged in / cleared)?
if printf '%s' "$json" | grep -qi "just a moment\|<!doctype html"; then
  echo "Chrome returned an HTML challenge instead of JSON — open claude.ai in a" >&2
  echo "tab, let it finish loading (past any 'Just a moment'), then retry." >&2
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
    if (usedPct === null) {                        // most-drained limit
      const ps = limits.filter(l => num(l.percent)).map(l => l.percent);
      if (ps.length) usedPct = Math.max(...ps);
    }
    if (usedPct === null) {                         // top-level mirrors
      const m = [j.five_hour, j.seven_day].filter(o => o && num(o.utilization)).map(o => o.utilization);
      if (m.length) usedPct = Math.max(...m);
    }
    if (usedPct === null) process.exit(2);

    let r = 1 - usedPct / 100; if (r < 0) r = 0; if (r > 1) r = 1;
    process.stdout.write(r.toFixed(4));
  });') || true

if [[ -z "$frac" ]]; then
  echo "Got a response from claude.ai but couldn't find a usage percent in it." >&2
  echo "First 200 chars: $(printf '%s' "$json" | head -c 200)" >&2
  exit 1
fi

printf '{"fraction": %s}\n' "$frac" > "$STATE_FILE"
echo "Wrote $STATE_FILE -> fraction=$frac (remaining; tracking: $WHICH)"
