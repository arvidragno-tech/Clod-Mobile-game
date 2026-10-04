"""Debug previews for character art v2 (not shipped)."""
from __future__ import annotations

import random
from PIL import Image

from . import palette as pal
from . import characters2 as ch

PORTRAIT_ORDER = ["hair_back", "body", "outfit", "head", "age", "nose", "mouth", "brows", "eyes", "facial_hair",
                  "scar", "tattoo", "makeup", "cyber_low", "piercing", "hair", "cyber", "accessory"]


def pmap(a: dict):
    return [
        pal.ramp(pal.SKIN_TONES[a.get("skin", 2)], 0.06),
        pal.ramp(pal.HAIR_COLORS[a.get("hair_color", "black")], 0.09),
        pal.ramp(pal.CLOTH[a.get("cloth_a", "charcoal")], 0.10),
        pal.ramp(pal.CLOTH[a.get("cloth_b", "black")], 0.10),
        pal.ramp(pal.METALS[a.get("metal", "chrome")], 0.06, 1.1),
        pal.glow_ramp(pal.GLOWS[a.get("glow", "cyan")]),
        pal.ramp(pal.IRIS_COLORS[a.get("iris", "brown")], 0.05),
        [pal.hex_to_rgb(h) for h in pal.FIXED],
        pal.ramp(pal.CLOTH[a.get("cloth_c", "black")], 0.10),
        pal.ramp(pal.MATERIALS["leather"], 0.07, 1.05),
        pal.ramp(pal.MATERIALS["grime"], 0.07, 1.05),
        pal.ramp(pal.MATERIALS["blood"], 0.07, 1.05),
    ]


def render(view: str, layers: list, a: dict) -> Image.Image:
    w, h = (ch.PW, ch.PH) if view == "portrait" else (ch.BW, ch.BH)
    img = Image.new("RGBA", (w, h), (18, 20, 28, 255))
    m = pmap(a)
    for cv in layers:
        if cv is None:
            continue
        lay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        px = lay.load()
        for y in range(h):
            for x in range(w):
                c = cv.px[y][x]
                if c is not None:
                    px[x, y] = m[c[0]][c[1]] + (255,)
        img.alpha_composite(lay)
    return img
