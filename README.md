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
./scripts/update-usage.sh         # best-effort from `ccusage`, if installed
```

Run that on a schedule (cron, `launchd`, or a simple loop) to keep the buddy in
sync with your real usage. The app re-checks the file every few seconds, so
updates show up almost immediately.

## How the fade works

`Buddy.image(fraction:)` redraws the pixel art each refresh:

- **Alpha** = `0.16 + 0.84 × fraction` — never fully invisible, so it stays
  clickable even at empty.
- **Color** drifts from Claude clay toward gray as it drains, so a low buddy
  reads as faded/tired rather than just dim.

Tweak the look in `Sources/ClaudeUsageBuddy/main.swift` — the pixel grid, the
clay color, the floor opacity, and the refresh interval are all right at the
top.
