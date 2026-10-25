#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
command -v magick >/dev/null || { echo 'Install ImageMagick first: brew install imagemagick' >&2; exit 1; }
./build.sh
'build/Bose Bar.app/Contents/MacOS/BoseBar' --export-demo "$PWD/docs/images/raw"
python3 scripts/make-artwork.py
