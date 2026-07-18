# DeskMap

**English** | [Русский](README.ru.md)

Current version: **0.1.0** — see [Releases](../../releases) and the [CHANGELOG](CHANGELOG.md).

<img src="docs/icon.png" width="96" align="right" alt="DeskMap icon">

A tiny macOS utility that always shows **which desktop (Space) you are on** — the desktop number in a small floating window and in the menu bar. Click the window to give the desktop your own name.

Made for one simple purpose: when you juggle many desktops, a permanent, glanceable label of "where am I" — with names that mean something to you ("Mail", "Code", "Music") instead of bare numbers.

## What it looks like

| Normal | Compact | Contrast | Number only |
|:---:|:---:|:---:|:---:|
| <img src="docs/screenshot-normal.png" width="111" alt="Floating window: number badge and desktop name"> | <img src="docs/screenshot-compact.png" width="139" alt="Compact window: number as plain text, long name clipped"> | <img src="docs/screenshot-contrast.png" width="111" alt="Contrast mode: white background, dark text"> | <img src="docs/screenshot-number-only.png" width="82" alt="Number only: just the desktop number"> |

The semi-transparent floating window over a desktop; the same number lives in the menu bar. Screenshots are rendered offscreen with fake data by `scripts/make-screenshots.sh` — no real desktop content involved.

## Features

- **Floating window** — a small semi-transparent pill that stays on top of all windows, on every desktop, even over fullscreen apps. Drag it anywhere; the position is remembered.
- **Click to rename** — click the window, type a name, press Enter (Esc cancels, an empty name removes it). Names are remembered per desktop and survive restarts.
- **Menu bar number** — the current desktop number also lives in the menu bar; the custom name is shown in its tooltip and the dropdown menu.
- **Go to desktop** — the "Go to…" menu lists every desktop by number and name; pick one to switch to it. In the floating window, clicking the number opens the same picker (clicking the name renames, as usual). Switching presses Mission Control keyboard shortcuts for you: the "Switch to Desktop N" shortcut when it is enabled in System Settings, otherwise it walks there with Ctrl+←/→. Requires the Accessibility permission — macOS asks on first use.
- **Fullscreen awareness** — fullscreen apps are separate Spaces without a number; they are shown as "⛶".
- **Cross-display numbering** — desktops are numbered the same way Mission Control numbers them; the window shows the number for the display it is on.
- **Compact mode** — an even smaller window: the number becomes plain text before the name (`4 | Name`), the font is smaller, and long names are clipped to 15 characters.
- **Number only** — hide the name entirely and show just the desktop number.
- **All names in one place** — the Desktops settings window lists every desktop with its number and name; edit any of them at once. The "Add" button appends a row for a desktop that doesn't exist yet — when you later create a desktop with that number, it picks up the prepared name automatically.
- **Opacity slider** — one slider in UI settings drives the window look from fully transparent to solid black; the text color adapts along the way so it always stays readable.
- **Contrast mode** — a toggle in UI settings inverts the color scheme: the background goes from transparent to white instead of black, and the text adapts the opposite way.
- **Left or right alignment** — with right alignment the number moves to the right side of the name, and the window keeps its right edge fixed, growing leftward when the content size changes. Handy when the window sits near the right screen edge.
- **Always on top** is a separate toggle: with it off, the window orders like a regular window and can be covered by others.
- **Everything is remembered** — names, window position, compact/number-only modes, alignment, opacity and visibility all survive app restarts.
- **Launch at login** — toggle in the menu (uses the system `SMAppService`).
- **10 languages** — English (default), Русский, Español, Deutsch, Français, Italiano, Português, 中文, 日本語, 한국어. Switchable from the menu.

## Privacy

DeskMap makes no network requests at all. Desktop names are stored locally in the app's preferences. No accounts, no analytics, nothing leaves your Mac.

## Install (prebuilt)

1. Download `DeskMap.zip` from the [Releases](../../releases) page and unzip it.
2. Move `DeskMap.app` to `/Applications`.
3. First launch: the app is not notarized, so macOS will block a normal double-click. Either **right-click the app → Open → Open**, or remove the quarantine flag in Terminal:

   ```sh
   xattr -dr com.apple.quarantine /Applications/DeskMap.app
   ```

4. Look for the desktop number in your menu bar (if you don't see it, your menu bar may be full — Cmd-drag other icons to make room). The floating window can be toggled from the menu.

Requires macOS 13 Ventura or later.

## Build from source

Requirements: macOS 13+, Xcode Command Line Tools (`xcode-select --install`). No Xcode project needed — it's a plain Swift Package.

```sh
git clone <this repo>
cd mac-desktop-map
./build-app.sh
ditto build/DeskMap.app /Applications/DeskMap.app
```

`build-app.sh` compiles a release binary with SwiftPM, wraps it into an `.app` bundle with the icon (regenerated by `scripts/make-icon.sh` if missing), and ad-hoc signs it. The app version is taken from `Sources/DeskMap/Version.swift` and shown in the About dialog.

Dev variant with extra info in the About dialog: `./build-app.sh -dev`.

## How it works

- macOS has no public API for Spaces, so DeskMap uses the same private SkyLight calls as [WhichSpace](https://github.com/gechr/WhichSpace) and [yabai](https://github.com/koekeishiya/yabai) (`SLSMainConnectionID`, `SLSCopyManagedDisplaySpaces`, loaded via `dlsym`). Only regular user desktops are counted; fullscreen-app Spaces are skipped, matching Mission Control's numbering.
- Updates come from the system "active Space changed" notification, plus a slow poll to catch desktops being reordered in Mission Control (which sends no notification).
- Custom names are keyed by the Space's stable UUID, so they stick to the desktop even when its number changes.
- The window is a borderless, non-activating `NSPanel` at floating level hosting a SwiftUI view — clicking it never steals focus from your current app.
