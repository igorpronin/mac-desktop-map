# Changelog

All notable changes to DeskMap are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow [SemVer](https://semver.org).

## [0.1.0] — 2026-07-18

First public release.

### Added
- Floating always-on-top window showing the current desktop (Space) number, on every desktop and over fullscreen apps; draggable, position remembered.
- Click the window to give the desktop a custom name (names are keyed by the Space's stable UUID and survive reordering and restarts).
- Desktop number in the menu bar with the custom name in its tooltip and menu.
- Go to… — jump to any desktop from the menu or by clicking the number in the window; uses Mission Control keyboard shortcuts (per-desktop hotkey when enabled, Ctrl+←/→ otherwise; requires Accessibility).
- Compact mode (`4 | Name`, names clipped to 15 characters), Number only mode, Contrast mode (inverted color scheme), opacity slider with auto-adapting text color, left/right alignment.
- Desktops settings window: edit all names at once, pre-assign names to not-yet-created desktop numbers.
- Fullscreen apps shown as "⛶"; Mission Control-style cross-display numbering.
- Launch at login, 10 UI languages, no network access.

[0.1.0]: https://github.com/igorpronin/mac-desktop-map/releases/tag/v0.1.0
