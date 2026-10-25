#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="$PWD/build/Bose Bar.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
architectures=("$(uname -m)")
if [[ "${1:-}" == "--universal" ]]; then architectures=(arm64 x86_64); fi
for architecture in "${architectures[@]}"; do
  xcrun swiftc -O -whole-module-optimization -target "$architecture-apple-macosx13.0" \
    -module-cache-path "${TMPDIR:-/tmp}/bosebar-module-cache" \
    Sources/*.swift -o "build/BoseBar-$architecture"
done
if [[ ${#architectures[@]} -gt 1 ]]; then
  xcrun lipo -create build/BoseBar-arm64 build/BoseBar-x86_64 -output "$app/Contents/MacOS/BoseBar"
else
  cp "build/BoseBar-${architectures[0]}" "$app/Contents/MacOS/BoseBar"
fi
cp Resources/Info.plist "$app/Contents/Info.plist"
cp LICENSE "$app/Contents/Resources/LICENSE.txt"
cp NOTICE "$app/Contents/Resources/NOTICE.txt"
if [[ -f Resources/AppIcon.icns ]]; then cp Resources/AppIcon.icns "$app/Contents/Resources/"; fi
codesign --force --sign "${BOSEBAR_SIGN_IDENTITY:--}" "$app"
codesign --verify --strict "$app"
printf 'Built %s\n' "$app"
du -sh "$app"
