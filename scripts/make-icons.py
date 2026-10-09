#!/usr/bin/env python3
"""Draws Fidelia Pro's Android icons: the Fidelia mark with "pro" under it.

    python3 scripts/make-icons.py     (needs rsvg-convert and fontTools)

The mark is the logo's geometric F with its orange point (fidelia-brand,
make_logo.py), in paper on the brand green. "pro" is set in Instrument Serif
italic (assets/fonts) and turned into outlines, so the result does not depend
on the fonts installed; it sits in an orange pill under the F.

The adaptive icon's background layer is the green (@color/fidelia_green), so
each launcher cuts the tile to its own shape; the foreground holds only the F,
the point and the pill, inside the circle a launcher keeps when it crops (61%
of the canvas), which Android 12+ also uses as the splash icon.

Also writes the Google Play listing's icon (512 x 512) and feature graphic
(1024 x 500) to android/fastlane/metadata/android/fr-FR/images/.

Writes, for each density: mipmap-*/ic_launcher_foreground.png (adaptive icon),
mipmap-*/ic_launcher.png (pre-Android 8 launchers: the full green tile) and
drawable-*/launch_logo.png (splash before Android 12: the tile on paper).
"""

import subprocess
import tempfile
from pathlib import Path

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
RES = ROOT / "android/app/src/main/res"
FONT = ROOT / "assets/fonts/InstrumentSerif-Italic.ttf"
SERIF = ROOT / "assets/fonts/InstrumentSerif-Regular.ttf"
# Google Play listing images (fastlane layout, uploaded by hand or by supply).
STORE = ROOT / "android/fastlane/metadata/android/fr-FR/images"

# Set to None for an icon without a label under the F.
LABEL = "pro"

PAPER, GREEN, GREEN_DARK, ORANGE = "#f5f1e8", "#234b39", "#173427", "#e65e32"
INK, MUTED = "#18221f", "#5a615a"
NAME, SLOGAN = "Fidelia Pro", "LA FIDÉLITÉ, ÇA COMPTE"
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def letter(cx: float, cy: float, scale: float) -> str:
    """The F and its point, drawn on the logo's 100 grid, centred on (cx, cy)."""
    # The F with its point spans x 31..71.5 and y 24..76 on that grid.
    tx, ty = cx - 51.25 * scale, cy - 50 * scale
    return (
        f'<g transform="translate({tx:.1f} {ty:.1f}) scale({scale})">'
        f'<rect x="31" y="24" width="11" height="52" rx="1.5" fill="{PAPER}"/>'
        f'<rect x="31" y="24" width="40" height="11" rx="1.5" fill="{PAPER}"/>'
        f'<rect x="31" y="45" width="26" height="10" rx="1.5" fill="{PAPER}"/>'
        f'<circle cx="66" cy="50" r="5.5" fill="{ORANGE}"/>'
        "</g>"
    )


def word(text: str, x_height: float) -> tuple[str, float, float]:
    """`text` as one SVG path, scaled so its x-height is `x_height`.
    Returns the path, its width and its height, origin at the top left."""
    font = TTFont(FONT)
    glyphs, cmap = font.getGlyphSet(), font.getBestCmap()
    font_x_height = font["OS/2"].sxHeight
    scale = x_height / font_x_height
    pen = SVGPathPen(glyphs)
    x = 0
    for ch in text:
        name = cmap[ord(ch)]
        # Font units have y going up; flip, and put the x-height line at y=0.
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x * scale, font_x_height * scale)))
        x += glyphs[name].width
    descent = -font["hhea"].descent * scale
    return pen.getCommands(), x * scale, x_height + descent


def composition() -> str:
    """The F (and the label's pill) on a transparent 1024 canvas, inside the safe circle."""
    if not LABEL:
        return letter(512, 512, 6.2)
    path, w, _ = word(LABEL, 78)
    pill_h, pad = 128, 46
    pill_w = w + 2 * pad
    pill_x, pill_y = 512 - pill_w / 2, 600
    text_x = 512 - w / 2
    text_y = pill_y + (pill_h - 78) / 2 - 18
    return (
        letter(512, 425, 5.0)
        + f'<rect x="{pill_x:.1f}" y="{pill_y}" width="{pill_w:.1f}" height="{pill_h}" rx="{pill_h / 2}" fill="{ORANGE}"/>'
        + f'<path transform="translate({text_x:.1f} {text_y:.1f})" fill="{PAPER}" d="{path}"/>'
    )


def outline(text: str, size: float, x: float, baseline: float, font_path: Path, tracking: float = 0) -> tuple[str, float]:
    """`text` as one SVG path at baseline (x, baseline). Returns the path and its width."""
    font = TTFont(font_path)
    glyphs, cmap = font.getGlyphSet(), font.getBestCmap()
    scale = size / font["head"].unitsPerEm
    pen = SVGPathPen(glyphs)
    cx = x
    for ch in text:
        g = glyphs[cmap[ord(ch)]]
        g.draw(TransformPen(pen, (scale, 0, 0, -scale, cx, baseline)))
        cx += g.width * scale + tracking
    return pen.getCommands(), cx - x - tracking


def feature_graphic() -> str:
    """Play's 1024 x 500 banner: the tile, the name and the slogan on paper."""
    word, ww = outline(NAME, 112, 0, 0, SERIF, tracking=1)
    slogan_size = 26
    _, natural = outline(SLOGAN, slogan_size, 0, 0, SERIF)
    slogan, _ = outline(SLOGAN, slogan_size, 0, 0, SERIF, tracking=(ww - 6 - natural) / (len(SLOGAN) - 1))
    block_w = 260 + 56 + ww
    x0 = (1024 - block_w) / 2
    tx = x0 + 260 + 56
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="500" viewBox="0 0 1024 500">'
        f'<rect width="1024" height="500" fill="{PAPER}"/>'
        f'<g transform="translate({x0:.1f} 120) scale({260 / 1024})">{tile()}'
        f'<g transform="translate(512 512) scale(1.45) translate(-512 -512)">{composition()}</g></g>'
        f'<path transform="translate({tx:.1f} 262)" fill="{INK}" d="{word}"/>'
        f'<path transform="translate({tx + 3:.1f} 318)" fill="{MUTED}" d="{slogan}"/>'
        "</svg>"
    )


def tile() -> str:
    """The logo's green tile, filling the canvas."""
    return (
        '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1">'
        f'<stop offset="0" stop-color="{GREEN}"/><stop offset="1" stop-color="{GREEN_DARK}"/>'
        '</linearGradient></defs><rect width="1024" height="1024" rx="246" fill="url(#g)"/>'
    )


def svg(body: str) -> str:
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">{body}</svg>'


def render(source: str, out: Path, size: int, tmp: Path) -> None:
    src = tmp / "icon.svg"
    src.write_text(source)
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), str(src), "-o", str(out)], check=True)


def main() -> None:
    art = composition()
    # Adaptive foreground: 108 dp, the launcher supplies the green background.
    foreground = svg(art)
    # Legacy launchers and the old splash: no mask, so draw the tile and
    # enlarge the art to fill it as the logo does.
    tiled = svg(tile() + f'<g transform="translate(512 512) scale(1.45) translate(-512 -512)">{art}</g>')
    with tempfile.TemporaryDirectory() as tmp:
        for density, k in DENSITIES.items():
            render(foreground, RES / f"mipmap-{density}/ic_launcher_foreground.png", round(108 * k), Path(tmp))
            render(tiled, RES / f"mipmap-{density}/ic_launcher.png", round(48 * k), Path(tmp))
            render(tiled, RES / f"drawable-{density}/launch_logo.png", round(112 * k), Path(tmp))
        # Play icon: a full square, Play rounds the corners itself.
        STORE.mkdir(parents=True, exist_ok=True)
        square = svg(f'<rect width="1024" height="1024" fill="{GREEN}"/><g transform="translate(512 512) scale(1.45) translate(-512 -512)">{art}</g>')
        render(square, STORE / "icon.png", 512, Path(tmp))
        banner = Path(tmp) / "feature.svg"
        banner.write_text(feature_graphic())
        subprocess.run(["rsvg-convert", "-w", "1024", "-h", "500", "-b", PAPER, str(banner), "-o", str(STORE / "featureGraphic.png")], check=True)
    print("Wrote Fidelia icons for", ", ".join(DENSITIES))


if __name__ == "__main__":
    main()
