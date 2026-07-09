# Claude Usage Buddy 👾

A tiny macOS **menu bar** app that puts a pixel-art "Claude buddy" up in your
upper bar and **slowly fades it as your Claude usage drains**. Full usage = a
solid, bright clay-colored buddy. As usage leaves, the buddy fades toward a
faint, tired ghost — a quick glance tells you how much you've got left.

<!-- The buddy is drawn at runtime, so there's no asset to ship. -->

## What it looks like

- Lives in the macOS menu bar (no Dock icon, no main window).
- A little pixel-art Claude buddy — the rounded clay creature with two eyes and
  stubby legs — in Claude's clay color.
- Opacity tracks remaining usage; it also drifts slightly gray as it empties.
- Click it for a menu showing the exact percentage and the data source.
- **Live usage is built in**: the app itself fetches your real plan usage from
  claude.ai (log in once from the menu). It counts everything that drains your
  plan — web, **Claude Desktop**, mobile — because the limits are account-wide.

## Requirements

- macOS 12 or later
- Swift toolchain (comes with Xcode or the Xcode Command Line Tools:
  `xcode-select --install`)

## Run it

```bash
swift run
```

That launches the buddy into your menu bar. Click it → **"Log in to
claude.ai…"** and sign in once; the buddy then shows your real remaining plan
usage and refreshes every 10 seconds on its own. (There's also a **Demo drain**
toggle in the menu — a drain-and-refill loop for watching the fade effect.)

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

This builds a release binary and installs one `launchd` LaunchAgent
(`com.claudeusagebuddy.agent`, `RunAtLoad` + `KeepAlive`). Live usage needs no
second agent — the app fetches it itself. The agent pins the tracked limit to
the 5-hour **session** window; re-run with `CLAUDE_USAGE_LIMIT=weekly_all` (or
`min` for "whichever limit is closest to its cap") to change that.

To stop everything and remove auto-start:

```bash
./scripts/uninstall-autostart.sh
```

(Because `KeepAlive` is on, choosing **Quit** from the menu just relaunches it —
use the uninstall script to fully stop it.)

## How live usage works (built in)

The app embeds a hidden **WebKit web view** logged into claude.ai. Every 10
seconds it fetches the same data the **Settings → Usage** page shows
(`GET https://claude.ai/api/organizations/<org>/usage`) from *inside* that
page context — so the request is authenticated by the web view's own persistent
cookies and passes Cloudflare like any real browser. No external browser, no
stored session key, no dependencies beyond macOS.

- **Log in once**: click the buddy → **"Log in to claude.ai…"** → sign in →
  close the window. The session persists across restarts. If it ever expires,
  the menu shows **⚠️ Log in to claude.ai…** again.
- **What it counts**: your plan limits are **account-wide**, so usage from the
  website, **Claude Desktop**, mobile, and Claude Code all show up in the same
  number automatically.
- **Which limit**: `remaining = 1 − percent/100`, tracking the 5-hour
  **session** window by default. Set the env var `CLAUDE_USAGE_LIMIT` to
  `weekly_all` (7-day) or `min` (whichever limit is closest to its cap).
- **Staleness is visible**: if a refresh hasn't succeeded for over ~90 seconds,
  the menu source line switches to **STALE — N min old** instead of silently
  freezing.

> This uses an **undocumented** endpoint, so it may change without notice.

### Manual override / other sources

If the built-in fetcher has no reading, the app falls back to a state file:

```
~/.claude-usage-buddy/state.json     # {"fraction": 0.42} or {"percent": 42}
```

Set it by hand with `./scripts/update-usage.sh 42%` (or `0.42`), or write it
from any script of your own. Older Chrome/AppleScript-based fetchers live in
`scripts/legacy/` if you prefer driving the file externally.

## How the fade works

`Buddy.image(fraction:)` redraws the pixel art each refresh:

- **Alpha** = `0.16 + 0.84 × fraction` — never fully invisible, so it stays
  clickable even at empty.
- **Color** drifts from Claude clay toward gray as it drains, so a low buddy
  reads as faded/tired rather than just dim.

Tweak the look in `Sources/ClaudeUsageBuddy/main.swift` — the pixel grid, the
clay color, the floor opacity, and the refresh interval are all right at the
top.
