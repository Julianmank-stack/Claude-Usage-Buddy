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

A helper writes it for you:

```bash
./scripts/update-usage.sh 42%     # set it directly
./scripts/update-usage.sh 0.42    # or as a fraction
./scripts/update-usage.sh         # live: derive it from `ccusage`
```

Run that on a schedule (cron, `launchd`, or a simple loop) to keep the buddy in
sync with your real usage. The app re-checks the file every few seconds, so
updates show up almost immediately. `install-autostart.sh` already sets up the
`launchd` timer for you.

### Live usage via ccusage

With no argument, the helper reads your **Claude Code** activity through
[`ccusage`](https://github.com/ryoppippi/ccusage). No global install is needed —
if `ccusage` isn't on your `PATH` it's run via `npx` (so you just need Node.js),
and the JSON is parsed with `node` (no `jq` required). It looks at ccusage's
rolling 5-hour billing blocks and computes:

```
remaining = 1 − (tokens used in the active block ÷ limit)
```

The limit is your heaviest *completed* block, so the buddy self-calibrates and
fades as the current session approaches your typical peak. To pin an exact
per-window token budget instead, set `CCUSAGE_TOKEN_LIMIT`:

```bash
CCUSAGE_TOKEN_LIMIT=2000000 ./scripts/update-usage.sh
```

Note: this tracks **Claude Code token usage**, which is *not* the same as the
plan-usage percentage shown on claude.ai's account page — there's no public API
for that number. If ccusage lives somewhere unusual, point at it with
`CCUSAGE_BIN`.

## How the fade works

`Buddy.image(fraction:)` redraws the pixel art each refresh:

- **Alpha** = `0.16 + 0.84 × fraction` — never fully invisible, so it stays
  clickable even at empty.
- **Color** drifts from Claude clay toward gray as it drains, so a low buddy
  reads as faded/tired rather than just dim.

Tweak the look in `Sources/ClaudeUsageBuddy/main.swift` — the pixel grid, the
clay color, the floor opacity, and the refresh interval are all right at the
top.
