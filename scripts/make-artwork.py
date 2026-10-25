#!/usr/bin/env python3
"""Compose native-control previews with ImageMagick (no app runtime dependency)."""
import json
import pathlib
import subprocess
import html
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "docs/images"
RAW = OUT / "raw"
STYLE = json.loads((ROOT / "scripts/assets/demo-style.json").read_text())

def run(*args):
    subprocess.run([str(a) for a in args], check=True)

def text(x, y, message, size=32, weight=400, color="#17352b"):
    return f'<text x="{x}" y="{y}" font-family="Helvetica" font-size="{size}" font-weight="{weight}" fill="{color}">{html.escape(message)}</text>'

def plate(name, theme, elements):
    spec = STYLE[theme]
    source = OUT / f"{name}.svg"
    source.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1000"><rect width="1600" height="1000" fill="{spec["background"]}"/>' + ''.join(elements) + '</svg>')
    target = OUT / f"{name}.png"
    run("magick", "-background", "none", source, target)
    return target

def place(canvas, source, width, x, y):
    resized = OUT / ".foreground.png"
    shadow = OUT / ".shadow.png"
    run("magick", source, "-resize", f"{width}x", resized)
    run("magick", resized, "(", "+clone", "-background", "black", "-shadow", "20x24+0+16", ")", "+swap", "-background", "none", "-layers", "merge", "+repage", shadow)
    # The shadow adds a 48px margin. Keep the foreground at the specified origin.
    run("magick", canvas, shadow, "-geometry", f"+{x-48}+{y-32}", "-composite", canvas)
    resized.unlink(); shadow.unlink()

hero = plate("hero", "sage", [
    text(104, 192, "Bose Bar", 88, 700),
    text(108, 294, "Your headphones.", 56, 500),
    text(108, 364, "Within reach.", 56, 500),
    text(110, 458, "Modes, EQ and battery", 30),
    text(110, 502, "from a tiny native Mac menu.", 30),
    text(110, 760, "Local Bluetooth. No account.", 26),
    text(110, 804, "Free & open source.", 26),
    text(110, 936, "macOS 13+  /  Apple silicon + Intel", 20),
    text(958, 936, "Rendered app preview · Example values", 18)
])
place(hero, RAW / "menu-light.png", 500, 982, 206)

eq = plate("equalizer", "midnight", [
    text(104, 166, "Find your sound.", 68, 700, "#edf4ec"),
    text(108, 250, "Three bands. Six starting points.", 30, color="#c4d2c7"),
    text(108, 294, "Fine-tune, apply, undo.", 30, color="#c4d2c7"),
    text(108, 456, "Vocal clarity", 30, 700, "#c1e9b2"),
    text(108, 502, "Bass −6   /   Mid +4   /   Treble +2", 27, color="#edf4ec"),
    text(108, 546, "RecordingNow V1 · source linked in the app", 20, color="#aebcb1"),
    text(108, 710, "Every preset shows its values.", 25, color="#c4d2c7"),
    text(108, 754, "Your last EQ is one undo away.", 25, color="#c4d2c7"),
    text(108, 936, "Bose Bar  /  Bose_For_Mac", 20, color="#aebcb1"),
    text(958, 936, "Rendered app preview · Example values", 18, color="#aebcb1")
])
place(eq, RAW / "equalizer-dark.png", 522, 970, 110)

battery = plate("battery", "sage", [
    text(104, 164, "A little bar. One less number.", 66, 700),
    text(108, 252, "Battery at a glance, without crowding your menu bar.", 30),
    text(108, 684, "Fills from the bottom as charge increases.", 28),
    text(108, 734, "The exact percentage stays in the menu and tooltip.", 28),
    text(108, 936, "Bose Bar  /  Optional vertical battery indicator", 20),
    text(1050, 936, "Rendered demo · 100 / 60 / 15%", 18)
])
place(battery, RAW / "battery-light.png", 1120, 240, 358)

if "--skip-icon" in sys.argv:
    print("Created hero.png, equalizer.png and battery.png")
    sys.exit(0)

# Original project icon, authored as vector geometry (no Bose logo/assets).
iconset = ROOT / "build/AppIcon.iconset"
iconset.mkdir(parents=True, exist_ok=True)
for base in [16, 32, 128, 256, 512]:
    for scale in [1, 2]:
        suffix = "@2x" if scale == 2 else ""
        run("magick", "-background", "none", ROOT / "scripts/assets/app-icon.svg", "-resize", f"{base*scale}x{base*scale}", iconset / f"icon_{base}x{base}{suffix}.png")
run("iconutil", "-c", "icns", iconset, "-o", ROOT / "Resources/AppIcon.icns")
print("Created hero.png, equalizer.png, battery.png and AppIcon.icns")
