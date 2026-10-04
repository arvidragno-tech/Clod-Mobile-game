"""Debug previews: composite character parts with sample palettes."""
from __future__ import annotations

import random

from PIL import Image

from . import palette as pal
from .characters import LAYER_ORDER


def palette_map(skin=2, hair="black", cloth_a="charcoal", cloth_b="black", metal="chrome", glow="cyan", iris="brown"):
    return [
        pal.ramp(pal.SKIN_TONES[skin], 0.06),
        pal.ramp(pal.HAIR_COLORS[hair], 0.09),
        pal.ramp(pal.CLOTH[cloth_a], 0.10),
        pal.ramp(pal.CLOTH[cloth_b], 0.10),
        pal.ramp(pal.METALS[metal], 0.06, 1.1),
        pal.glow_ramp(pal.GLOWS[glow]),
        pal.ramp(pal.IRIS_COLORS[iris], 0.05),
        [pal.hex_to_rgb(h) for h in pal.FIXED],
    ]


def compose(parts, view, choice: dict, pmap) -> Image.Image:
    w, h = (64, 64) if view == "portrait" else (32, 64)
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for slot in LAYER_ORDER[view]:
        ids = choice.get(slot, [])
        if isinstance(ids, str):
            ids = [ids]
        for pid in ids:
            cv = parts[view].get(slot, {}).get(pid)
            if cv is None:
                continue
            layer = cv.to_image(pmap)
            img.alpha_composite(layer)
    return img
