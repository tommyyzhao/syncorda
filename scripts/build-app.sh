#!/bin/zsh
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

version="${SYNCORDA_VERSION:-0.1.0-alpha.1}"
build="${SYNCORDA_BUILD:-1}"
architecture="${SYNCORDA_ARCH:-$(uname -m)}"
signing_identity="${DEVELOPER_ID_APPLICATION:--}"
output_root="${SYNCORDA_APP_OUTPUT_DIR:-$root/dist}"

if ! [[ "$build" =~ ^[0-9]+$ ]]; then
  print -u2 "SYNCORDA_BUILD must be a positive integer (received '$build')."
  exit 64
fi

swift build -c release --arch "$architecture"
bin_path="$(swift build -c release --arch "$architecture" --show-bin-path)"
app="$output_root/Syncorda.app"
staging_app="$output_root/.Syncorda.app.staging.$$.app"

if [[ -e "$staging_app" ]]; then
  print -u2 "Staging path already exists: $staging_app"
  exit 65
fi

mkdir -p "$staging_app/Contents/MacOS" "$staging_app/Contents/Resources"
cp "$bin_path/SyncordaApp" "$staging_app/Contents/MacOS/SyncordaApp"
cp "$bin_path/syncordactl" "$staging_app/Contents/MacOS/syncordactl"
cp "$root/Resources/Info.plist" "$staging_app/Contents/Info.plist"
cp "$root/Resources/AppIcon.icns" "$staging_app/Contents/Resources/AppIcon.icns"

plutil -replace CFBundleShortVersionString -string "$version" "$staging_app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$build" "$staging_app/Contents/Info.plist"

if ! lipo -archs "$staging_app/Contents/MacOS/SyncordaApp" | tr ' ' '\n' | grep -qx "$architecture"; then
  print -u2 "SyncordaApp was not built for the requested architecture '$architecture'."
  exit 65
fi

if [[ "$signing_identity" == "-" ]]; then
  signing_args=(--force --sign - --timestamp=none)
else
  signing_args=(--force --sign "$signing_identity" --options runtime --timestamp)
fi

# Sign nested executables explicitly, then seal the app bundle. A Developer ID identity enables
# hardened runtime and timestamping; the default is intentionally ad-hoc for local development.
codesign "${signing_args[@]}" "$staging_app/Contents/MacOS/syncordactl"
codesign "${signing_args[@]}" "$staging_app/Contents/MacOS/SyncordaApp"
codesign "${signing_args[@]}" "$staging_app"

if [[ -e "$app" ]]; then
  previous_app="$output_root/.Syncorda.app.previous.$(date +%Y%m%d%H%M%S).app"
  mv "$app" "$previous_app"
  print "Preserved previous bundle at $previous_app"
fi
mv "$staging_app" "$app"

echo "Built $app (version $version, build $build, $architecture, identity $signing_identity)"
