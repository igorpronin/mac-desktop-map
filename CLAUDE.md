# DeskMap — notes for Claude

macOS menu bar utility (Swift Package, no Xcode project): a small floating window
showing the current desktop (Space) number; click the window to give the desktop
a custom name. UI/architecture reference: /Users/proninigor/Projects/ip-monit-2.

`./build-app.sh` builds the public variant, `./build-app.sh -dev` builds the owner's
local variant (extra About info via `DEV_BUILD` compile flag). The copy installed
in `/Applications` must always be the `-dev` build.

## README files

`README.md` (English) and `README.ru.md` (Russian) are mirrors of each other. Any
change to one MUST be applied to the other in the same commit. Both keep the
language-switcher links (`**English** | [Русский](README.ru.md)` /
`[English](README.md) | **Русский**`) at the top — do not remove them.

## Languages

The app UI has 10 languages (en, ru, es, de, fr, it, pt, zh, ja, ko) in
`Sources/DeskMap/Localization.swift`. Every new UI string MUST be added to ALL
ten language tables at once — `t(_:)` force-unwraps the English table, and a
missing key elsewhere silently falls back to English. The dev-only About suffix
(`devSuffix`) exists in en/ru only; that is intentional.

## Versioning — MANDATORY

The version lives in ONE place: `Sources/DeskMap/Version.swift` (`AppInfo.version`).
`build-app.sh` extracts it into Info.plist; the About dialog shows it.

**Every functional change MUST bump the version** (semver: patch for fixes,
minor for features). Never ship a functional change with an unchanged version.

The first public release (v0.1.0, 2026-07-18) is out — the bumping rule is
ACTIVE. Every version bump MUST, in the same commit, also update:

1. `CHANGELOG.md` — a new entry describing the changes (Keep a Changelog
   format, with the release link at the bottom of the file);
2. the "Current version" line in BOTH `README.md` and `README.ru.md`.

Release procedure: bump + changelog + readme → commit & push → `git tag vX.Y.Z`
→ push the tag → `./build-app.sh` (public) → `ditto -c -k --keepParent
build/DeskMap.app dist/DeskMap.zip` → verify `strings` show no dev/private
data → `gh release create vX.Y.Z dist/DeskMap.zip` → rebuild `-dev` back into
build/ and relaunch (dist/ is gitignored; the zip ships only via Releases).

## Temporary files

Use the project-local `tmp/` folder (gitignored) for any temporary files —
screenshots, scratch scripts, intermediate artifacts. Do NOT use the global
`/tmp` or other locations outside the project.

## Space detection

No public API for Spaces — we use the private SkyLight framework via dlsym
(`SLSMainConnectionID`, `SLSCopyManagedDisplaySpaces`), same as WhichSpace/yabai.
Desktop numbering is cross-display (Mission Control style: only type==0 user
spaces are counted; fullscreen apps are type 4 and shown as "⛶"). Custom names
are stored in UserDefaults keyed by the Space uuid (stable across reordering).
Names pre-assigned in Settings for not-yet-existing desktop numbers are stored
separately keyed by index ("PendingNames") and move onto the desktop's uuid as
soon as a desktop with that number appears.

## Switching desktops (Go to…)

There is no public (or reliably working private) API to switch Spaces, so
SpaceSwitcher posts synthetic Mission Control keyboard shortcuts via CGEvent:
the per-desktop "Switch to Desktop N" hotkey when enabled (read from
com.apple.symbolichotkeys, ids 118+), else stepwise Ctrl+←/→ using positions
among ALL Spaces (fullscreen ones included — arrows walk through them).
Requires the Accessibility permission. NB: dev builds are ad-hoc signed, so the
TCC grant breaks on every rebuild (signature hash changes). Owner's decision:
NO self-signed dev certificate (offered, declined for security caution) — after
a rebuild, refresh the grant with `tccutil reset Accessibility local.deskmap`,
then trigger Go to… once to get a fresh system prompt, grant, and restart the
app. Do not read TCC.db or other system security stores (owner forbade it);
tccutil reset scoped to our own bundle id is allowed.
