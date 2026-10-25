# Development

Requires macOS 13+ and Apple's Command Line Tools (`xcode-select --install`). There are **no third-party runtime dependencies**.

```sh
git clone https://github.com/Twis06/Bose_For_Mac.git
cd Bose_For_Mac
./test.sh
./build.sh
open 'build/Bose Bar.app'
```

Use `./build.sh --universal` for a binary containing both arm64 and x86_64. Normal local builds target the current machine. The app bundle identifier remains `local.bosebar.app` to preserve preferences from the initial local version.

## Source map

- `Sources/App.swift`: AppKit menu and native EQ controls.
- `Sources/StatusIcon.swift`: template headphone icon and bottom-up battery bar.
- `Sources/Model.swift`: connection lifecycle, readback and UI state.
- `Sources/EQPresets.swift`: attributed presets and serial write/verify/restore transaction.
- `Sources/Bluetooth.swift`: IOBluetooth transport, request queue, timeouts and incremental decoding.
- `Sources/BMAP.swift`: protocol frames and validated payload parsers.
- `Sources/DemoRenderer.swift`: development-only preview export path, dormant in normal use.

The main run loop receives Bluetooth callbacks. A dedicated serial GCD queue performs blocking writes. Timed-out requests invalidate the connection so a stale reply cannot acknowledge a later write. Control-channel closure does not deliberately close the audio/baseband connection. macOS sometimes returns duplicate paired devices and inaccurate connection flags; address resolution, saved selection and a bounded SDP fallback handle the observed behavior.

## Testing

`./test.sh` exercises fragmented and concatenated frames, signed EQ, malformed payloads, preset/configured mode flags, preset ranges, multi-band verification, rollback and disconnected failures. It never connects to hardware.

Hardware probe (quit the running app first):

```sh
xcrun swiftc -O Sources/BMAP.swift Sources/EQPresets.swift Sources/Bluetooth.swift Tests/Probe.swift -o /tmp/bosebar-probe
/tmp/bosebar-probe --device AA:BB:CC:DD:EE:FF
```

The probe only reads by default. `--verify` reapplies the existing mode and bass value, then checks readback. It is a manual, opt-in hardware check. Do not commit device addresses or unsanitized diagnostic output.

App diagnostics: `open 'build/Bose Bar.app' --args --diagnose`. Raw local logs append to `/tmp/bosebar-diagnostic.log` and are off in normal launches. `--device ADDRESS` selects a paired device. `--show-menu` opens the menu after startup for inspection.

## Demo artwork

Install [ImageMagick](https://github.com/ImageMagick/ImageMagick) (`brew install imagemagick`), then run:

```sh
./scripts/render-demo.sh
```

The app exports its real NSMenu titles, state and native NSSlider views with seeded demo data, without connecting to headphones. ImageMagick composes them into the README images. They are **rendered previews**, not live desktop screenshots; captions say so. Raw previews and composition sources are checked in. Sage/Midnight styling values are adapted from [Screenshot.rocks](https://github.com/daveearley/screenshot.rocks), with its MIT notice in `docs/licenses/`. The project icon is original vector geometry. No Bose photography or logo is redistributed.

## Release

```sh
./scripts/package-release.sh
# Review version, assets, docs and checksums before publishing:
gh release create v1.1.0 dist/Bose-Bar-macOS.zip dist/Bose-Bar-macOS.dmg dist/SHA256SUMS --title 'Bose Bar 1.1.0' --notes-file docs/releases/1.1.0.md
```

`BOSEBAR_SIGN_IDENTITY` optionally sets a local signing identity; the default is ad-hoc signing. Public builds are currently **not notarized**. A production Developer ID signing/notarization pipeline would require maintainer credentials; do not commit those credentials or suggest disabling Gatekeeper.

The installer verifies the downloaded ZIP against the release's SHA-256 file, validates the bundle and code signature, and installs in `~/Applications`. Checksums detect corruption; they are not an independent trust anchor. An update retains `Bose Bar.previous.app` beside the installed app. Move/delete that backup before the next update. No administrator access is needed.
