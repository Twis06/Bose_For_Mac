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

def text(x, y, message, size=32, weight=400, color="#17352b", anchor="start"):
    return f'<text x="{x}" y="{y}" text-anchor="{anchor}" font-family="Avenir Next" font-style="normal" font-size="{size}" font-weight="{weight}" fill="{color}">{html.escape(message)}</text>'

def plate(name, theme, elements, height=1000):
    spec = STYLE[theme]
    source = OUT / f"{name}.svg"
    source.write_text(f'<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="{height}"><rect width="1600" height="{height}" fill="{spec["background"]}"/>' + ''.join(elements) + '</svg>')
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

# Product-first: one short heading, centered native UI, one honest demo label.
hero = plate("hero", "sage", [
    text(800, 126, "Bose Bar", 48, 500, anchor="middle"),
    text(800, 936, "Demo", 16, color="#566b5d", anchor="middle")
])
place(hero, RAW / "menu-light.png", 500, 550, 220)

eq = plate("equalizer", "midnight", [
    text(800, 110, "Equalizer", 48, 500, "#edf4ec", anchor="middle"),
    text(800, 950, "Demo", 16, color="#aebcb1", anchor="middle")
])
place(eq, RAW / "equalizer-dark.png", 500, 550, 170)

battery = plate("battery", "sage", [
    text(800, 138, "Battery", 48, 500, anchor="middle"),
    text(800, 586, "Demo", 16, color="#566b5d", anchor="middle")
], height=640)
place(battery, RAW / "battery-light.png", 880, 360, 250)

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
