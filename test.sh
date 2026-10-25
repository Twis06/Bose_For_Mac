#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
output="$(mktemp -d "${TMPDIR:-/tmp}/bosebar-tests.XXXXXX")"
trap 'rm -rf "$output"' EXIT
xcrun swiftc -O -module-cache-path "${TMPDIR:-/tmp}/bosebar-module-cache" \
  Sources/BMAP.swift Sources/EQPresets.swift Tests/ProtocolTests.swift Tests/PresetTests.swift -o "$output/protocol-tests"
"$output/protocol-tests"
