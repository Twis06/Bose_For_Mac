#!/bin/bash
# Download, verify and install the latest universal macOS release. No sudo.
set -euo pipefail
if [[ "$(uname -s)" != Darwin ]]; then echo 'Bose Bar requires macOS 13 or later.' >&2; exit 1; fi
major="$(sw_vers -productVersion | cut -d. -f1)"
if [[ "$major" -lt 13 ]]; then echo 'Bose Bar requires macOS 13 or later.' >&2; exit 1; fi
case "$(uname -m)" in arm64|x86_64) ;; *) echo 'Unsupported Mac architecture.' >&2; exit 1 ;; esac
release='https://github.com/Twis06/Bose_For_Mac/releases/latest/download'
work="$(mktemp -d "${TMPDIR:-/tmp}/bosebar-install.XXXXXX")"
trap 'rm -rf "$work"' EXIT
printf 'Downloading Bose Bar…\n'
curl --fail --location --retry 3 --proto '=https' --tlsv1.2 "$release/Bose-Bar-macOS.zip" -o "$work/Bose-Bar-macOS.zip"
curl --fail --location --retry 3 --proto '=https' --tlsv1.2 "$release/SHA256SUMS" -o "$work/SHA256SUMS"
expected="$(awk '$2 == "Bose-Bar-macOS.zip" {print $1}' "$work/SHA256SUMS")"
if [[ ! "$expected" =~ ^[0-9a-fA-F]{64}$ ]]; then echo 'Missing or invalid release checksum.' >&2; exit 1; fi
actual="$(shasum -a 256 "$work/Bose-Bar-macOS.zip" | awk '{print $1}')"
if [[ "$expected" != "$actual" ]]; then echo 'Checksum mismatch. Nothing was installed.' >&2; exit 1; fi
# Reject traversal before extracting and validating the known app bundle.
if unzip -Z1 "$work/Bose-Bar-macOS.zip" | awk '/(^\/|(^|\/)\.\.(\/|$))/ {bad=1} END {exit !bad}'; then
  echo 'Invalid archive paths. Nothing was installed.' >&2; exit 1
fi
ditto -x -k "$work/Bose-Bar-macOS.zip" "$work/unpacked"
app="$work/unpacked/Bose Bar.app"
[[ -x "$app/Contents/MacOS/BoseBar" ]] || { echo 'Release is missing the application.' >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" == 'local.bosebar.app' ]] || { echo 'Unexpected application identifier.' >&2; exit 1; }
codesign --verify --deep --strict "$app"
mkdir -p "$HOME/Applications"
target="$HOME/Applications/Bose Bar.app"
backup="$HOME/Applications/Bose Bar.previous.app"
if [[ -e "$backup" ]]; then echo "Move the previous backup aside first: $backup" >&2; exit 1; fi
# Quit only this app, after download and verification succeeded.
pkill -x BoseBar 2>/dev/null || true
if [[ -e "$target" ]]; then mv "$target" "$backup"; fi
if ! ditto "$app" "$target"; then
  echo 'Installation failed. The previous version is in Bose Bar.previous.app.' >&2
  exit 1
fi
printf 'Installed: %s\n' "$target"
if [[ -e "$backup" ]]; then printf 'Previous version retained: %s\n' "$backup"; fi
printf 'This community build is ad-hoc signed, not Apple-notarized.\n'
open "$target"
