#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./test.sh
./build.sh --universal
mkdir -p dist
# A stable asset name makes the documented latest-release installer durable.
ditto -c -k --norsrc --noextattr --keepParent 'build/Bose Bar.app' dist/Bose-Bar-macOS.zip
staging="$(mktemp -d "${TMPDIR:-/tmp}/bosebar-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto 'build/Bose Bar.app' "$staging/Bose Bar.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname 'Bose Bar' -srcfolder "$staging" -ov -format UDZO dist/Bose-Bar-macOS.dmg
(cd dist && shasum -a 256 Bose-Bar-macOS.zip Bose-Bar-macOS.dmg > SHA256SUMS)
printf 'Release assets are in dist/\n'
