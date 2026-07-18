#!/bin/bash
# Renders README screenshots (docs/) offscreen with fake data.
set -euo pipefail
cd "$(dirname "$0")/.."

swiftc \
    Sources/DeskMap/Version.swift \
    Sources/DeskMap/SpaceMonitor.swift \
    Sources/DeskMap/SpaceSwitcher.swift \
    Sources/DeskMap/Localization.swift \
    Sources/DeskMap/ContentView.swift \
    Sources/DeskMap/SettingsView.swift \
    Sources/DeskMap/AppDelegate.swift \
    scripts/screenshots/main.swift \
    -o tmp/deskmap-render-screens

tmp/deskmap-render-screens docs

# Иконка для README
sips -z 256 256 -s format png assets/AppIcon.icns --out docs/icon.png >/dev/null
echo "written: docs/icon.png"
