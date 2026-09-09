#!/usr/bin/env python3
"""Generate a color-swatch preview PNG per palette, for the walker/elephant
theme picker (see elephant/menus/cachyos_themes.lua). Re-run this whenever
a palette TOML changes or a new one is added -- previews are committed,
not generated on the fly.

Usage: generate-previews.py [preset-name ...]   (default: all presets)
"""
import subprocess
import sys
import tomllib
from pathlib import Path

THEMING = Path(__file__).resolve().parent
PALETTES = THEMING / "palettes"
PREVIEWS = THEMING / "previews"

W, H = 480, 270
ANSI_KEYS = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white"]
BRIGHT_KEYS = [f"bright-{k}" for k in ANSI_KEYS]


def load_palette(path: Path) -> dict:
    with path.open("rb") as f:
        return tomllib.load(f)


def build_preview(preset: str) -> None:
    p = load_palette(PALETTES / f"{preset}.toml")
    out_path = PREVIEWS / f"{preset}.png"

    swatch_w = W / 8
    swatch_h = 48
    ansi_y = 150
    bright_y = ansi_y + swatch_h

    cmd = ["magick", "-size", f"{W}x{H}", f"xc:{p['bg']}"]

    # theme name, top-left, in fg
    cmd += ["-gravity", "NorthWest", "-fill", p["fg"], "-font", "DejaVu-Sans-Bold",
            "-pointsize", "28", "-annotate", "+20+20", p.get("name", preset)]

    # accent / danger swatches, under the title
    for i, key in enumerate(("accent", "danger")):
        x = 20 + i * 90
        cmd += ["-fill", p[key], "-draw", f"rectangle {x},70 {x+70},110"]

    # ANSI + bright rows
    for row_y, keys in ((ansi_y, ANSI_KEYS), (bright_y, BRIGHT_KEYS)):
        for i, key in enumerate(keys):
            x0 = round(i * swatch_w)
            x1 = round((i + 1) * swatch_w)
            cmd += ["-fill", p[key], "-draw", f"rectangle {x0},{row_y} {x1},{row_y+swatch_h}"]

    cmd.append(str(out_path))
    subprocess.run(cmd, check=True)
    print(f"  wrote {out_path}")


def main() -> None:
    PREVIEWS.mkdir(exist_ok=True)
    presets = sys.argv[1:] or sorted(p.stem for p in PALETTES.glob("*.toml"))
    for preset in presets:
        build_preview(preset)


if __name__ == "__main__":
    main()
