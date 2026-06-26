# Claude Usage Buddy 👾

A tiny macOS **menu bar** app that puts a pixel-art "Claude buddy" up in your
upper bar and **slowly fades it as your Claude usage drains**. Full usage = a
solid, bright clay-colored buddy. As usage leaves, the buddy fades toward a
faint, tired ghost — a quick glance tells you how much you've got left.

<!-- The buddy is drawn at runtime, so there's no asset to ship. -->

## What it looks like

- Lives in the macOS menu bar (no Dock icon, no window).
- A little pixel-art Claude buddy — the rounded clay creature with two eyes and
  stubby legs — in Claude's clay color.
- Opacity tracks remaining usage; it also drifts slightly gray as it empties.
- Click it for a menu showing the exact percentage and the data source.

## Requirements

- macOS 12 or later
- Swift toolchain (comes with Xcode or the Xcode Command Line Tools:
  `xcode-select --install`)

## Run it

```bash
swift run
```

That launches the buddy into your menu bar. Out of the box it runs in **Demo
drain** mode — a slow drain-and-refill cycle so you can immediately watch the
fade effect. Toggle it off from the menu once you wire up live data.

To build a release binary:

```bash
swift build -c release
.build/release/ClaudeUsageBuddy
```

## Always on (auto-start at login)

To keep the buddy in your menu bar permanently — starting at login and
relaunching itself if it ever quits:

```bash
./scripts/install-autostart.sh
```

This builds a release binary and installs two `launchd` LaunchAgents:

- `com.claudeusagebuddy.agent` — the buddy itself (`RunAtLoad` + `KeepAlive`).
- `com.claudeusagebuddy.refresh` — re-derives your usage every couple of
  minutes (see below) so the buddy live-updates.

To stop everything and remove auto-start:

```bash
./scripts/uninstall-autostart.sh
```

(Because `KeepAlive` is on, choosing **Quit** from the menu just relaunches it —
use the uninstall script to fully stop it.)

## Feeding it real usage

The app reads a remaining-usage fraction from:

```
~/.claude-usage-buddy/state.json
```

…which is just:

```json
{ "fraction": 0.42 }
```

`fraction` is `0.0` (empty) → `1.0` (full). `{"percent": 42}` works too. While
this file exists and is readable it takes priority over demo mode, and the menu
shows **Source: live**.

You can set it by hand:

```bash
./scripts/update-usage.sh 42%     # set it directly
./scripts/update-usage.sh 0.42    # or as a fraction
```

…but for live updates the buddy reads your **real plan usage from claude.ai**
(see below). Either way, the app re-checks the file every few seconds, so
updates show up almost immediately. `install-autostart.sh` already wires up the
`launchd` timer that refreshes it.

### Live usage from claude.ai (the real plan %)

`scripts/fetch-claude-usage.sh` reads the same data the **Settings → Usage** page
shows, from:

```
GET https://claude.ai/api/organizations/<org>/usage
```

It computes `remaining = 1 − percent/100` and, by default, tracks whichever
limit you're **closest to hitting** (smallest remaining across your 5-hour
**session** and 7-day **weekly** limits) — so the buddy warns you about whichever
wall is nearest. Pin one explicitly with `CLAUDE_USAGE_LIMIT=session` (or
`weekly_all`). Your org id is auto-discovered; override with `CLAUDE_ORG_ID`.

**Auth — one-time setup.** The endpoint needs your logged-in `sessionKey` cookie:

1. In Chrome on **claude.ai**, open DevTools (⌥⌘I) → **Application** tab →
   **Cookies → https://claude.ai** → copy the value of **`sessionKey`**
   (it starts with `sk-ant-sid…`).
2. Save it to a locked-down file:

   ```bash
   mkdir -p ~/.claude-usage-buddy
   printf '%s' 'PASTE_SESSION_KEY_HERE' > ~/.claude-usage-buddy/session-key
   chmod 600 ~/.claude-usage-buddy/session-key
   ```

3. Test it:

   ```bash
   ./scripts/fetch-claude-usage.sh
   ```

The key never touches the repo. It expires every so often (you'll see the
buddy stop updating / the refresh log show an auth error) — just repeat step 1–2
to refresh it. This uses an **undocumented** endpoint, so it may change without
notice.

> Prefer not to deal with a session key? You can instead drive the buddy from
> your local **Claude Code** token usage via
> [`ccusage`](https://github.com/ryoppippi/ccusage) — see this project's git
> history for that variant — but note it measures CLI tokens, not the plan %
> shown on the account page.

## How the fade works

`Buddy.image(fraction:)` redraws the pixel art each refresh:

- **Alpha** = `0.16 + 0.84 × fraction` — never fully invisible, so it stays
  clickable even at empty.
- **Color** drifts from Claude clay toward gray as it drains, so a low buddy
  reads as faded/tired rather than just dim.

Tweak the look in `Sources/ClaudeUsageBuddy/main.swift` — the pixel grid, the
clay color, the floor opacity, and the refresh interval are all right at the
top.
