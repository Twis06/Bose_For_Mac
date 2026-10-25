# Bose Bar contributor notes

- Read PRODUCT.md, DESIGN.md and docs/DEVELOPMENT.md before changes.
- Keep the app native and dependency-free at runtime. Do not add a web view or package manager requirement for end users.
- Run ./test.sh and ./build.sh for code changes. Use --universal for release builds.
- Tests and documentation previews must never access Bluetooth. Hardware probes are explicitly opt-in.
- Preserve upstream MIT attribution. Sources for EQ recommendations live in docs/eq-presets.md.
- Do not commit private device names, Bluetooth addresses, serials or diagnostic logs.
- Do not claim support or hardware verification without evidence. Never expose a guessed write layout.
- Keep artifacts in build/ and dist/ untracked. Release uploads must have SHA256SUMS.
