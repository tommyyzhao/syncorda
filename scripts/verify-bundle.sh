#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
app="${1:-$root/dist/Syncorda.app}"

if [[ ! -d "$app" ]]; then
  print -u2 "App bundle not found: $app"
  exit 66
fi

plutil -lint "$app/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$app"

print "Bundle: $app"
print "Version: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
print "Build: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
print "SyncordaApp architectures: $(lipo -archs "$app/Contents/MacOS/SyncordaApp")"
print "syncordactl architectures: $(lipo -archs "$app/Contents/MacOS/syncordactl")"
