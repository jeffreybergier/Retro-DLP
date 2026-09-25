"""Export the five Font Awesome Free Solid glyphs used by the player.

Usage: python3 render_icons.py /path/to/FA7-Solid-900.otf
Requires Pillow. The PNGs are checked in; normal app builds need no font tools.
Source: https://github.com/FortAwesome/Font-Awesome/tree/7.2.0/otfs
"""
from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFont

destination = Path(__file__).resolve().parents[1] / 'RDLPPlayer.bundle'
glyphs = {'headphones': 0xf025, 'backward-fast': 0xf049,
          'forward-fast': 0xf050, 'play': 0xf04b, 'pause': 0xf04c}
for scale in (1, 2, 3):
    font = ImageFont.truetype(sys.argv[1], 20 * scale)
    for name, codepoint in glyphs.items():
        glyph = chr(codepoint)
        left, top, right, bottom = font.getbbox(glyph)
        image = Image.new('RGBA', (26 * scale, 26 * scale))
        origin = ((image.width - (right - left)) / 2 - left,
                  (image.height - (bottom - top)) / 2 - top)
        ImageDraw.Draw(image).text(origin, glyph, font=font, fill='white')
        suffix = '' if scale == 1 else f'@{scale}x'
        image.save(destination / f'{name}{suffix}.png', optimize=True)
