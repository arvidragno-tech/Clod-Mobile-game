"""Preview HD character layers with a default palette (dev tool).

    python3 -m tools.art.hdc_preview out.png
"""
from __future__ import annotations

import sys

from PIL import Image

from . import palette as pal

DEFAULT = {
    0: pal.ramp(pal.SKIN_TONES[2]), 1: pal.ramp(pal.HAIR_COLORS["dark_brown"]),
    2: pal.ramp(pal.CLOTH["charcoal"]), 3: pal.ramp(pal.CLOTH["corp_white"]), 4: pal.ramp(pal.METALS["chrome"]),
    5: pal.glow_ramp(pal.ACCENT["cyan"]), 6: pal.ramp(pal.IRIS_COLORS["hazel"]),
    7: [pal.hex_to_rgb(h) for h in pal.FIXED], 8: pal.ramp(pal.CLOTH["gang_red"]),
    9: pal.ramp(pal.MATERIALS["leather"]), 10: pal.ramp(pal.MATERIALS["grime"]), 11: pal.ramp(pal.MATERIALS["blood"]),
}


def compose(layers, w, h, cmap=None):
    cmap = cmap or DEFAULT
    img = Image.new("RGBA", (w, h), (18, 22, 30, 255))
    px = img.load()
    for cv in layers:
        for y in range(cv.h):
            row = cv.px[y]
            for x in range(cv.w):
                c = row[x]
                if c is not None:
                    r = cmap[c[0]][c[1]]
                    px[x, y] = (r[0], r[1], r[2], 255)
    return img
