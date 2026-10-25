# Native menu

## Overview

Operate mode. Use an NSStatusItem and NSMenu: system type, colors, spacing, checkmarks, submenus, keyboard navigation and light/dark appearance. The persistent surface is an 18-point SF Symbols headphone icon with an optional 4 × 14-point vertical battery bar (on by default), within a 28 × 18-point template image. Turning the bar off restores an 18 × 18-point image. Charge fills upward; unknown charge has a dash. Exact percentage stays in the menu and tooltip.

Validation scope: checked against the final AppKit source. Documentation previews are exported from the real NSMenu definitions and NSSlider views with seeded demo data. These verify rendered control content and artwork composition, not live menu placement or assistive-technology behavior. Runtime screenshots of the menu-only LSUIElement app were unavailable; new hardware behavior was not visually tested. The finish review returned a scoped ship decision after all four flagged fixes were resolved.

## Colors

Use AppKit's native menu and control colors. The device header uses `NSColor.labelColor`; slider endpoint hints use `NSColor.secondaryLabelColor`. The headphone symbol is a template image, allowing macOS to supply its appearance.

## Typography

The device header is 13-point semibold system type. Slider labels use 13-point system type; right-aligned values use 12-point regular system type with monospaced digits. Endpoint hints use 10-point system type. Standard menu items retain AppKit typography.

## Layout

Order: device name and battery; connection status; listening modes; noise and immersive audio when reported; equalizer; device selection; refresh or retry and Bluetooth Settings; settings; quit.

A custom native slider row is 264 × 62 points, increasing to 264 × 78 points when endpoint hints are present. Labels and hints have a 16-point leading inset; the NSSlider frame begins at 14 points and is 236 points wide. Keep native menu spacing and separators elsewhere.

## Components

Labels use Bose's actual mode names. The noise-cancellation slider, when supported, reads from 0 · Aware to 10 · Quiet. Sliders use discrete tick values and send on release. Mode items use native checkmarks. Busy device controls are disabled, and connection recovery uses Refresh or Retry connection. The Equalizer submenu includes six presets: three published recommendations, two Bose Bar starting points and Flat. Rows show bass/mid/treble values, actual-value checkmarks and description/source tooltips; a guide link provides attribution. The submenu title names the matching preset or Custom. Presets outside reported ranges are disabled. Undo last preset restores one previous EQ snapshot, with readback verification. Settings and About use native macOS controls and panels.

### Documentation artwork

Sage (#dbe5dc) and Midnight (#15171b) presentation backgrounds adapt Screenshot.rocks MIT presets. Presentation titles and captions use Avenir Next (Medium for titles, Regular for captions); the embedded native UI retains system type. Type is dark green (#17352b) or pale neutral (#edf4ec). Use centered, UI-first compositions: one short title and a small Demo label, without marketing paragraphs or feature lists. Main and EQ images are 1600 × 1000; the battery detail is 1600 × 640. Keep soft offset shadows and generous whitespace. Public images contain synthetic device values, never private identifiers. ImageMagick is a build-time art tool only. These presentation colors do not replace native AppKit colors in the application.

## Do's and Don'ts

- Do preserve the native AppKit appearance and hardware-reported capabilities, ranges and values.
- Don't invent device readings or expose unsupported controls.
- Don't add decorative branding, animation, onboarding or a main window.
