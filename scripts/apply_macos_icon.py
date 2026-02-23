#!/usr/bin/env python3
"""
Applies the macOS squircle mask to all icons in AppIcon.appiconset.

Run from the project root:
    python3 scripts/apply_macos_icon.py

Requires Pillow:
    pip3 install Pillow
"""

from PIL import Image, ImageDraw
from pathlib import Path
import sys


def apply_squircle(path: Path) -> None:
    """Apply the macOS squircle mask (~22.37% radius) to a PNG icon in place."""
    img = Image.open(path).convert("RGBA")
    size = img.size[0]
    radius = int(size * 0.2237)  # Apple HIG recommended radius

    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)

    result = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    result.paste(img, mask=mask)
    result.save(path, "PNG")
    print(f"  ✓ {path.name} ({size}×{size})")


def main() -> None:
    iconset = Path("macos/Runner/Assets.xcassets/AppIcon.appiconset")
    if not iconset.exists():
        print(f"Error: {iconset} not found. Run from the project root.", file=sys.stderr)
        sys.exit(1)

    icons = sorted(iconset.glob("*.png"))
    if not icons:
        print("No PNG icons found.", file=sys.stderr)
        sys.exit(1)

    print(f"Applying macOS squircle mask to {len(icons)} icons…")
    for icon in icons:
        apply_squircle(icon)
    print("Done! Rebuild the app to see the rounded icons.")


if __name__ == "__main__":
    main()
