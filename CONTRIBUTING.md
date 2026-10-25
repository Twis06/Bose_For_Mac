# Contributing

Keep the app native and small. Start with the [development guide](docs/DEVELOPMENT.md), run `./test.sh` and `./build.sh`, and describe how you verified the change.

For device support, include model, firmware, macOS version, expected behavior and sanitized protocol evidence. Do not infer write layouts from another model or expose unsupported controls. Never include Bluetooth addresses, serial numbers or private device names in public logs.

New EQ suggestions should provide bass/mid/treble values, the intended listening preference, the headphone model and an original source when one exists. Clearly label personal starting points. Avoid “perfect,” “audiophile correction” or measurement claims without evidence.

For UI changes, retain native AppKit conventions, keyboard navigation, appearance adaptation and meaningful accessibility labels. Regenerate demo artwork if visible controls change, and label simulated values honestly.
