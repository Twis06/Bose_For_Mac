# Bose Bar
<!-- impeccable:product-schema 1 -->

## Platform
Native macOS menu bar utility; macOS 13+ on Apple silicon and Intel.

## Purpose
Fast access to Bose QC Ultra battery, listening modes and EQ. The product remains small, local and usable without an account or phone app for routine changes.

## Constraints
Swift, AppKit and IOBluetooth. No browser runtime, Python installation, cloud connection or third-party runtime packages. Discover supported values from hardware. Avoid unverified controls and hide unsupported formats. No Dock icon or main window.

## Supported scope
Original QC Ultra firmware 1.6.7 verified for battery, mode and EQ reads and same-value writes. QC Ultra 2 recognized but not hardware-verified. No claims for other models.

## Product decisions
Optional narrow vertical battery bar, on by default. Exact battery percentage stays in the menu and tooltip. Six attributed EQ presets with readback and one-level undo; no automatic EQ application. Publish an independently licensed GitHub project with universal releases, checksum verification, clear unsigned-build instructions and reproducible, labeled demo images.
