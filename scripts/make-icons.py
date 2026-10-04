#!/usr/bin/env python3
"""Draws Djassa Pro's Android icons: the Djassa mark with "pro" under it.

    python3 scripts/make-icons.py     (needs rsvg-convert and fontTools)

"pro" is set in Instrument Serif italic (assets/fonts) and turned into
outlines, so the result does not depend on the fonts installed. It sits in a
green pill: paper text that reads on the green icon and on the paper splash
screen alike, and on any wallpaper: the icons have no tile behind them (the
adaptive icon's background layer is transparent). Everything stays inside the
circle a launcher keeps when it crops the adaptive icon (61% of the canvas),
which Android 12+ also uses as the splash icon.

Writes, for each density: mipmap-*/ic_launcher_foreground.png (adaptive icon),
mipmap-*/ic_launcher.png (pre-Android 8 launchers, no tile) and drawable-*/launch_logo.png
(splash before Android 12).
"""

import re
import subprocess
import tempfile
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"
MARK = ROOT / "scripts/icons/djassa-mark.svg"
FONT = ROOT / "assets/fonts/InstrumentSerif-Italic.ttf"

PAPER, GREEN = "#f5f1e8", "#234b39"
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def mark_body() -> str:
    """The mark's drawing, without its <svg> wrapper (a 1024 x 1024 canvas)."""
    svg = MARK.read_text()
    return re.sub(r"^.*?<svg[^>]*>|</svg>\s*$", "", svg, flags=re.S)


def word(text: str, cap_height: float) -> tuple[str, float, float]:
    """`text` as one SVG path, scaled so its x-height is `cap_height`.
    Returns the path, its width and its height, origin at the top left."""
    font = TTFont(FONT)
    glyphs, cmap = font.getGlyphSet(), font.getBestCmap()
    x_height = font["OS/2"].sxHeight
    scale = cap_height / x_height
    pen = SVGPathPen(glyphs)
    x = 0
    for ch in text:
        name = cmap[ord(ch)]
        # Font units have y going up; flip, and put the x-height line at y=0.
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x * scale, x_height * scale)))
        x += glyphs[name].width
    # "p" drops below the baseline by the font's descender.
    descent = -font["hhea"].descent * scale
    return pen.getCommands(), x * scale, cap_height + descent


def composition() -> str:
    """Mark and pill on a transparent 1024 canvas, inside the safe circle."""
    path, w, h = word("pro", 92)
    pill_h, pad = 150, 52
    pill_w = w + 2 * pad
    pill_x, pill_y = 512 - pill_w / 2, 640
    # The x-height sits centred in the pill; the descender hangs into the
    # lower padding, as it would on a line of text.
    text_x = 512 - w / 2
    text_y = pill_y + (pill_h - 92) / 2 - 12
    return (
        # The mark, scaled to 46% and raised so the pill fits below it.
        f'<g transform="translate(512 408) scale(0.46) translate(-512 -512)">{mark_body()}</g>'
        f'<rect x="{pill_x:.1f}" y="{pill_y}" width="{pill_w:.1f}" height="{pill_h}" rx="{pill_h / 2}" fill="{GREEN}"/>'
        f'<path transform="translate({text_x:.1f} {text_y:.1f})" fill="{PAPER}" d="{path}"/>'
    )


def svg(body: str, background: str = "") -> str:
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
        f"{background}{body}</svg>"
    )


def render(source: str, out: Path, size: int, tmp: Path) -> None:
    src = tmp / "icon.svg"
    src.write_text(source)
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), str(src), "-o", str(out)], check=True)


def main() -> None:
    art = composition()
    # Adaptive foreground: 108 dp, the launcher supplies the green background.
    foreground = svg(art)
    # Legacy launchers: no mask to crop for, so enlarge the art. No tile
    # behind it, as on the adaptive icon.
    legacy = svg(f'<g transform="translate(512 512) scale(1.4) translate(-512 -512)">{art}</g>')
    # Splash before Android 12: on paper, centred by launch_background.xml.
    splash = svg(f'<g transform="translate(512 512) scale(1.5) translate(-512 -512)">{art}</g>')
    with tempfile.TemporaryDirectory() as tmp:
        for density, k in DENSITIES.items():
            render(foreground, RES / f"mipmap-{density}/ic_launcher_foreground.png", round(108 * k), Path(tmp))
            render(legacy, RES / f"mipmap-{density}/ic_launcher.png", round(48 * k), Path(tmp))
            render(splash, RES / f"drawable-{density}/launch_logo.png", round(112 * k), Path(tmp))
    print("Wrote Djassa Pro icons for", ", ".join(DENSITIES))


if __name__ == "__main__":
    main()
