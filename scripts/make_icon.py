#!/usr/bin/env python3
"""Draw the Next Cue app icon and its small website version."""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SIZE = 1024
SCALE = 3
CANVAS = SIZE * SCALE


def box(left: int, top: int, right: int, bottom: int) -> tuple[int, int, int, int]:
    return tuple(value * SCALE for value in (left, top, right, bottom))


def draw_icon() -> Image.Image:
    image = Image.new("RGB", (CANVAS, CANVAS), "#f2efe6")
    draw = ImageDraw.Draw(image)

    draw.rounded_rectangle(box(104, 104, 920, 920), radius=204 * SCALE, fill="#21463f")

    # A short header gives the cue card a clear visual hierarchy.
    draw.rounded_rectangle(box(270, 256, 438, 288), radius=16 * SCALE, fill="#e7e8dc")
    draw.rounded_rectangle(box(270, 313, 570, 337), radius=12 * SCALE, fill="#98b3a6")

    # The highlighted row is the next action. The two quieter rows suggest a routine.
    draw.rounded_rectangle(box(230, 398, 794, 536), radius=42 * SCALE, fill="#f2efe6")
    draw.ellipse(box(280, 441, 350, 511), fill="#ce8255")
    draw.line(
        [(295 * SCALE, 476 * SCALE), (315 * SCALE, 493 * SCALE), (339 * SCALE, 459 * SCALE)],
        fill="#21463f",
        width=11 * SCALE,
        joint="curve",
    )
    draw.rounded_rectangle(box(382, 438, 680, 464), radius=13 * SCALE, fill="#21463f")
    draw.rounded_rectangle(box(382, 479, 612, 501), radius=11 * SCALE, fill="#879b90")

    for y, width in ((634, 280), (757, 220)):
        draw.ellipse(box(280, y, 328, y + 48), outline="#a9bcb1", width=7 * SCALE)
        draw.rounded_rectangle(box(382, y + 10, 382 + width, y + 35), radius=12 * SCALE, fill="#c9d4cb")

    return image.resize((SIZE, SIZE), Image.Resampling.LANCZOS)


def main() -> None:
    icon = draw_icon()
    icon.save(ROOT / "NextCue/Assets.xcassets/AppIcon.appiconset/AppIcon.png", format="PNG", optimize=True)
    icon.resize((256, 256), Image.Resampling.LANCZOS).save(ROOT / "docs/icon_256.png", format="PNG", optimize=True)


if __name__ == "__main__":
    main()
