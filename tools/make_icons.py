#!/usr/bin/env python3
"""Build the app icons from the two source artworks.

Windows shows two different icons for the same window: the small one in the
title bar and the big one in the taskbar / alt-tab. We give them different
artwork on purpose -- the head reads at 16px, the full character does not.

    python tools/make_icons.py <head.png> <full.png>

Writes assets/icon-head.ico, assets/icon-full.ico and the PNGs the QML side
uses. Only needs re-running when the artwork changes.
"""

import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"

# The title bar tops out at 24px on high-dpi, the taskbar goes up to 256.
HEAD_SIZES = [(16, 16), (20, 20), (24, 24), (32, 32), (48, 48), (64, 64)]
FULL_SIZES = [(32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]


def square(image, size):
    """Fit on a transparent square canvas, preserving the aspect ratio."""
    image = image.convert("RGBA")
    if image.width != image.height:
        side = max(image.width, image.height)
        canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        canvas.paste(image, ((side - image.width) // 2, (side - image.height) // 2))
        image = canvas
    return image.resize((size, size), Image.LANCZOS)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)

    ASSETS.mkdir(exist_ok=True)

    head = Image.open(sys.argv[1])
    full = Image.open(sys.argv[2])

    # PNGs for the in-app logo: 512 is plenty and keeps the binary small.
    square(head, 512).save(ASSETS / "icon-head.png", optimize=True)
    square(full, 512).save(ASSETS / "icon-full.png", optimize=True)

    square(head, 256).save(ASSETS / "icon-head.ico", sizes=HEAD_SIZES)
    square(full, 256).save(ASSETS / "icon-full.ico", sizes=FULL_SIZES)

    for name in ("icon-head.png", "icon-full.png", "icon-head.ico", "icon-full.ico"):
        path = ASSETS / name
        print(f"{name}: {path.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
