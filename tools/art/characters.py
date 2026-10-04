"""Layered, palette-indexed character parts.

Every part is drawn in index space (ramp, shade) so the game can recolour it
per customer (skin tone, hair, clothing, cyberware metal and LED colour) and
composite a unique portrait (64x64) and full-body sprite (32x64) at runtime.

Ramps: 0 skin, 1 hair, 2 cloth A, 3 cloth B, 4 metal, 5 glow, 6 iris, 7 fixed.
"""
from __future__ import annotations

import json
import math
import os
import random

from . import palette as pal
from .lib import Canvas, ROOT, poly_pixels, clamp

SK, HR, CA, CB, MT, GL, IR, FX = range(8)
# Fixed ramp indices
F_OUT, F_EYEW, F_PUPIL, F_HI, F_BLOOD, F_INK, F_LENS, F_RIM = range(8)

PORTRAIT = (64, 64)
BODY = (32, 64)

FACE_SHAPES = ["narrow", "broad", "round"]
EXPRESSIONS = ["neutral", "hard", "smirk", "tired"]
HAIR_STYLES = ["buzz", "short", "undercut", "long", "tied", "mohawk", "locs", "slick", "bald"]
OUTFITS = ["mercenary", "gang", "corporate", "smuggler", "dock", "bounty", "fixer", "criminal", "civilian",
           "bm_tech", "medical", "boss"]
BUILDS = ["slim", "average", "heavy"]


def pc(indexed=True):
    return Canvas(*PORTRAIT, indexed=indexed)


def bc():
    return Canvas(*BODY, indexed=True)


def f(c: Canvas, x, y, ramp, shade):
    c.set(int(x), int(y), (ramp, int(clamp(shade, 0, 7))))


def hline(c, x0, x1, y, ramp, shade):
    for x in range(int(x0), int(x1) + 1):
        f(c, x, y, ramp, shade)


def vline(c, x, y0, y1, ramp, shade):
    for y in range(int(y0), int(y1) + 1):
        f(c, x, y, ramp, shade)


# =============================================================================
# PORTRAIT (64x64): head and shoulders, front view, key light top-left,
# cool rim light on the right (screen glow).
# =============================================================================

def head_mask(shape: str):
    """Pixels of head (cranium + jaw) for a face shape."""
    rx = {"narrow": 10.5, "broad": 12.0, "round": 11.5}[shape]
    cran = set()
    for y in range(8, 34):
        for x in range(16, 48):
            if ((x + 0.5 - 32) / rx) ** 2 + ((y + 0.5 - 23) / 13.5) ** 2 <= 1.0:
                cran.add((x, y))
    if shape == "narrow":
        jaw = [(21.5, 24), (22.5, 31), (27, 37), (32, 38.5), (37, 37), (41.5, 31), (42.5, 24)]
    elif shape == "broad":
        jaw = [(20, 24), (20.5, 32), (25, 37), (32, 38.5), (39, 37), (43.5, 32), (44, 24)]
    else:
        jaw = [(20.5, 24), (21.5, 32), (26.5, 37.5), (32, 38.5), (37.5, 37.5), (42.5, 32), (43.5, 24)]
    return cran | set(poly_pixels(jaw))


def _skin_shade(x, y, cx=32.0, cy=25.0, rx=12.5, ry=15.0, lo=1.3, hi=6.2):
    nx = (x + 0.5 - cx) / rx
    ny = (y + 0.5 - cy) / ry
    d = min(0.98, nx * nx + ny * ny)
    nz = math.sqrt(1.0 - d)
    L = (-0.55, -0.6, 0.58)
    i = clamp(nx * L[0] + ny * L[1] + nz * L[2], 0.0, 1.0)
    return lo + (hi - lo) * i


def draw_body_base(c: Canvas, build="average"):
    """Neck + shoulders in skin (mostly covered by outfits)."""
    w = {"slim": 0, "average": 2, "heavy": 4}[build]
    pts = [(5 - w, 64), (9 - w, 50), (19 - w // 2, 45), (27, 43), (37, 43), (45 + w // 2, 45), (55 + w, 50), (59 + w, 64)]
    c.shaded_poly(pts, SK, top=4.4, bottom=2.4, left_bias=1.6, edge_dark=0.6)
    # Neck: cylinder with jaw shadow at top.
    for y in range(32, 47):
        for x in range(27, 38):
            t = ((x + 0.5 - 27) / 11) * 2 - 1
            v = 4.6 - t * 1.6 - (1.6 if y < 37 else 0.0)
            c.shade_px(x, y, SK, v)
    # Clavicle hints
    for x in range(22, 30):
        f(c, x, 47 + (1 if x < 25 else 0), SK, 2)
    for x in range(35, 43):
        f(c, x, 47 + (1 if x > 39 else 0), SK, 2)


def draw_head(c: Canvas, shape="round", expr="neutral"):
    mask = head_mask(shape)
    # Ears (behind the head silhouette)
    for ex in (19.6, 44.4):
        for y in range(21, 30):
            for x in range(int(ex - 2), int(ex + 3)):
                if ((x + 0.5 - ex) / 2.0) ** 2 + ((y + 0.5 - 25) / 4.2) ** 2 <= 1 and (x, y) not in mask:
                    c.shade_px(x, y, SK, 3.2 if ex < 32 else 2.2)
        f(c, int(ex) + (0 if ex < 32 else 0), 25, SK, 1)
    for (x, y) in mask:
        c.shade_px(x, y, SK, _skin_shade(x, y))
    # Jaw edge darkening (form shadow on the right side and under the chin)
    for (x, y) in mask:
        if (x + 1, y) not in mask and x > 32:
            f(c, x, y, SK, 2)
        if (x, y + 1) not in mask and y > 30:
            f(c, x, y, SK, 2)
    # Rim light (screen glow) on the right edge.
    for (x, y) in mask:
        if (x + 1, y) not in mask and (11 < y < 21 or 30 < y < 35):
            f(c, x, y, FX, F_RIM)
    # Eye sockets: shadow above the eyes
    for ex in (27, 37):
        for x in range(ex - 3, ex + 3):
            c.shade_px(x, 23, SK, _skin_shade(x, 23) - 1.2)
    # Eyes
    lid_drop = 1 if expr == "tired" else 0
    for i, ex in enumerate((27, 37)):
        hline(c, ex - 2, ex + 2, 24, SK, 1)  # upper lid crease / lashes
        f(c, ex - 3 if i == 0 else ex + 3, 25, SK, 2)
        for x in range(ex - 2, ex + 3):
            f(c, x, 25, FX, F_EYEW)
        f(c, ex - 2, 25, SK, 2) if i == 1 else None
        # Iris 2px + pupil + highlight
        f(c, ex, 25, IR, 2)
        f(c, ex + (1 if i == 0 else -1), 25, IR, 4)
        f(c, ex, 24 + lid_drop, SK, 1) if lid_drop else None
        if lid_drop:
            hline(c, ex - 2, ex + 2, 25, SK, 2)
            f(c, ex, 25, IR, 2)
        f(c, ex - 1 if i == 0 else ex + 1, 26, SK, 3)
        hline(c, ex - 1, ex + 1, 26, SK, 3)
    # Catch-lights
    f(c, 27, 25, IR, 3)
    # Brows (hair ramp)
    brow = {
        "neutral": ([(24, 22), (25, 21), (26, 21), (27, 21), (28, 21), (29, 22)], [(35, 22), (36, 21), (37, 21), (38, 21), (39, 21), (40, 22)]),
        "hard": ([(24, 21), (25, 21), (26, 21), (27, 22), (28, 22), (29, 23)], [(35, 23), (36, 22), (37, 22), (38, 21), (39, 21), (40, 21)]),
        "smirk": ([(24, 22), (25, 21), (26, 21), (27, 21), (28, 21), (29, 22)], [(35, 21), (36, 20), (37, 20), (38, 20), (39, 21), (40, 21)]),
        "tired": ([(24, 22), (25, 22), (26, 21), (27, 21), (28, 20), (29, 20)], [(35, 20), (36, 20), (37, 21), (38, 21), (39, 22), (40, 22)]),
    }[expr]
    for side in brow:
        for k, (x, y) in enumerate(side):
            f(c, x, y, HR, 2 if k in (1, 2, 3) else 1)
    # Nose: bridge highlight, shadow side, nostrils
    for y in range(26, 30):
        f(c, 32, y, SK, 6 if y < 29 else 5)
        f(c, 34, y, SK, 3)
    hline(c, 30, 34, 30, SK, 3)
    f(c, 30, 30, SK, 2)
    f(c, 34, 30, SK, 1)
    f(c, 33, 29, SK, 3)
    # Cheekbone highlight (key light side)
    for p in ((24, 28), (25, 28), (25, 29)):
        f(c, p[0], p[1], SK, 6)
    # Mouth
    mouth = {
        "neutral": [(29, 33, 2), (30, 33, 1), (31, 33, 1), (32, 33, 1), (33, 33, 1), (34, 33, 1), (35, 33, 2)],
        "hard": [(29, 34, 2), (30, 33, 1), (31, 33, 1), (32, 33, 1), (33, 33, 1), (34, 33, 1), (35, 34, 2)],
        "smirk": [(29, 33, 2), (30, 33, 1), (31, 33, 1), (32, 33, 1), (33, 33, 1), (34, 32, 1), (35, 32, 2)],
        "tired": [(29, 34, 2), (30, 33, 1), (31, 33, 1), (32, 33, 1), (33, 33, 1), (34, 33, 1), (35, 34, 2)],
    }[expr]
    for x, y, s in mouth:
        f(c, x, y, SK, s)
    hline(c, 30, 34, 34, SK, 5)  # lower lip highlight
    hline(c, 31, 33, 32, SK, 3)  # upper lip shade
    f(c, 32, 36, SK, 3)  # chin dimple shadow
    # Smile lines / age
    if expr in ("hard", "tired"):
        f(c, 28, 31, SK, 3)
        f(c, 36, 31, SK, 2)


# --- Hair ---------------------------------------------------------------------

def _hair_cap(c, top=8, bottom=20, rx=12.6, cx=32.0, cy=18.0, ry=10.5, fringe=True, sides_to=24):
    pix = []
    for y in range(top, bottom + 1):
        for x in range(17, 48):
            if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                pix.append((x, y))
    # Side burns
    for y in range(bottom, sides_to + 1):
        for x in (20, 21, 43, 44):
            pix.append((x, y))
    for x, y in pix:
        nx = (x + 0.5 - cx) / rx
        ny = (y + 0.5 - cy) / ry
        v = 4.2 - nx * 1.8 - ny * 1.2
        c.shade_px(x, y, HR, v)
    return set(pix)


def _strands(c, pix, rng, count=26, length=4, shade=1):
    pl = sorted(pix)
    for _ in range(count):
        x, y = rng.choice(pl)
        for k in range(length):
            if (x, y + k) in pix:
                f(c, x + (k // 3), y + k, HR, shade)


def _highlight(c, pix, band_y, x0, x1):
    for x, y in pix:
        if band_y - 1 <= y <= band_y and x0 <= x <= x1:
            f(c, x, y, HR, 6 if (x + y) % 2 == 0 else 5)


def draw_hair(c: Canvas, style: str, seed=1):
    rng = random.Random(seed)
    if style == "bald":
        for x in range(26, 31):
            f(c, x, 11, SK, 7)
        return
    if style == "buzz":
        for y in range(9, 19):
            for x in range(18, 47):
                if ((x + 0.5 - 32) / 12.2) ** 2 + ((y + 0.5 - 18.5) / 10) ** 2 <= 1.0 and (x * 5 + y * 3) % 4 != 0:
                    f(c, x, y, HR, (1 if x > 34 else 2) + (1 if (x * 7 + y) % 5 == 0 else 0))
        return
    if style == "short":
        pix = _hair_cap(c, 7, 19)
        for x in range(22, 42, 2):  # fringe tips
            f(c, x, 20, HR, 2)
            f(c, x + 1, 19, HR, 3)
        _strands(c, pix, rng)
        _highlight(c, pix, 11, 22, 33)
    elif style == "undercut":
        pix = _hair_cap(c, 6, 17, rx=12.4, cy=16.0)
        for y in range(16, 22):
            for x in range(20, 25):
                if (x + y) % 2 == 0:
                    f(c, x, y, HR, 1)
        for x in range(26, 44):  # swept fringe to the right
            f(c, x, 18 + (x - 26) // 7, HR, 3)
        _strands(c, pix, rng, 30, 5)
        _highlight(c, pix, 10, 22, 36)
    elif style == "long":
        pix = _hair_cap(c, 7, 20, sides_to=30)
        for x in range(22, 42, 3):
            f(c, x, 21, HR, 2)
        _strands(c, pix, rng, 28, 6)
        _highlight(c, pix, 11, 22, 34)
    elif style == "tied":
        pix = _hair_cap(c, 9, 18, rx=12.0, ry=9.5)
        c.sphere(32, 7, 4.5, 4, HR, 1.2, 5.5)
        for x in range(28, 37):
            f(c, x, 11, HR, 1)
        _strands(c, pix, rng, 18, 3)
        _highlight(c, pix, 12, 23, 32)
    elif style == "mohawk":
        for y in range(10, 20):
            for x in range(19, 46):
                if ((x + 0.5 - 32) / 12.2) ** 2 + ((y + 0.5 - 19) / 10) ** 2 <= 1.0 and (x + y) % 3 == 0:
                    f(c, x, y, HR, 1)
        for y in range(1, 18):
            w = 3 if y > 4 else 2
            for x in range(32 - w, 32 + w):
                v = 5.5 - (x - (32 - w)) * 0.8 - (0 if y % 4 else 1)
                c.shade_px(x, y, HR, v)
        for y in (2, 5, 8, 11):
            f(c, 29, y, HR, 2)
            f(c, 35, y + 1, HR, 1)
    elif style == "locs":
        pix = _hair_cap(c, 7, 18, sides_to=22)
        _highlight(c, pix, 10, 23, 33)
        _strands(c, pix, rng, 20, 4)
    elif style == "slick":
        pix = _hair_cap(c, 8, 17, rx=12.2, ry=9.5, cy=17.5, sides_to=22)
        for x, y in pix:
            if (x - y) % 4 == 0:
                f(c, x, y, HR, 2)
        _highlight(c, pix, 11, 23, 38)


def draw_hair_back(c: Canvas, style: str):
    """Hair behind the head/shoulders for long styles."""
    if style == "long":
        for y in range(18, 52):
            for x in list(range(16, 23)) + list(range(41, 48)):
                edge = 0 if x in (16, 47) else 1
                v = 3.2 - (0.8 if x > 32 else 0) - (y - 18) * 0.03 - edge
                c.shade_px(x, y, HR, v)
        for y in range(18, 52, 3):
            f(c, 19, y, HR, 1)
            f(c, 44, y + 1, HR, 0)
    elif style == "locs":
        for k, x in enumerate((17, 20, 23, 41, 44, 47)):
            c.capsule(x, 16, x + (1 if x < 32 else -1), 50 - (k % 3) * 3, 1.6, HR, 0.8, 4.0)
            for y in range(20, 48, 4):
                f(c, x, y, HR, 1)


# --- Outfits (portrait) -----------------------------------------------------

def _shoulders(w=2):
    return [(4 - w, 64), (8 - w, 50), (18 - w // 2, 45), (26, 44), (38, 44), (46 + w // 2, 45), (56 + w, 50), (60 + w, 64)]


def _collar_v(c, ramp, depth=54, open_w=5, shade=1):
    for y in range(44, depth):
        half = max(0, open_w - (y - 44) * open_w // max(1, depth - 44))
        for x in range(32 - half - 1, 32 + half + 1):
            pass
    return


def draw_outfit(c: Canvas, outfit: str, build="average"):
    w = {"slim": 0, "average": 2, "heavy": 4}[build]
    sh = _shoulders(w)
    if outfit == "mercenary":
        c.shaded_poly(sh, CA, 4.0, 2.0, 1.4, 0.8)
        # High tactical collar
        c.shaded_poly([(23, 50), (24, 42), (40, 42), (41, 50), (36, 47), (28, 47)], CA, 3.5, 2.5, 1.2, 0.8)
        # Vest panels + straps
        c.shaded_poly([(17, 64), (19, 52), (28, 50), (28, 64)], CB, 3.6, 2.2, 1.0, 0.8)
        c.shaded_poly([(36, 64), (36, 50), (45, 52), (47, 64)], CB, 3.2, 2.0, 1.0, 0.8)
        for y in range(53, 64, 3):
            hline(c, 19, 26, y, CB, 1)
            hline(c, 38, 45, y, CB, 1)
        # Shoulder armour plates (metal)
        c.sphere(12, 54, 7, 5, MT, 1.0, 6.0)
        c.sphere(52, 54, 7, 5, MT, 1.0, 5.0)
        for p in ((9, 54), (14, 52)):
            f(c, p[0], p[1], MT, 7)
        f(c, 21, 57, GL, 5)  # comm LED
    elif outfit == "gang":
        c.shaded_poly(sh, CA, 3.8, 1.8, 1.8, 0.8)
        # Open leather jacket lapels
        c.shaded_poly([(24, 64), (22, 46), (28, 45), (31, 64)], CA, 4.8, 2.6, 1.2, 1.0)
        c.shaded_poly([(33, 64), (36, 45), (42, 46), (40, 64)], CA, 3.6, 2.0, 1.2, 1.0)
        # Shirt underneath
        c.shaded_poly([(29, 64), (28, 47), (36, 47), (35, 64)], CB, 4.0, 3.0, 0.8, 0.5)
        # Studs on shoulders
        for x in range(10, 22, 3):
            f(c, x, 50 + (21 - x) // 4, MT, 6)
        for x in range(43, 55, 3):
            f(c, x, 47 + (x - 43) // 4, MT, 5)
        # Chain
        for k, x in enumerate(range(28, 37)):
            f(c, x, 50 + int(2 * math.sin(k * 0.6)), MT, 6 if k % 2 else 4)
    elif outfit == "corporate":
        c.shaded_poly(sh, CA, 3.6, 2.0, 1.2, 0.6)
        c.shaded_poly([(26, 64), (27, 45), (37, 45), (38, 64)], CB, 6.2, 5.2, 0.6, 0.6)  # shirt
        c.shaded_poly([(30, 47), (32, 46), (34, 47), (33, 60), (32, 62), (31, 60)], CA, 2.2, 1.0, 0.4, 0.4)  # tie
        # Lapels
        c.shaded_poly([(21, 64), (22, 47), (27, 45), (29, 56), (25, 64)], CA, 4.4, 2.6, 1.0, 1.0)
        c.shaded_poly([(39, 64), (35, 56), (37, 45), (42, 47), (43, 64)], CA, 3.4, 2.0, 1.0, 1.0)
        # ID badge
        c.rect(44, 54, 5, 6, (CB, 6))
        f(c, 45, 55, GL, 5)
        hline(c, 45, 47, 57, CA, 2)
    elif outfit == "smuggler":
        c.shaded_poly(sh, CA, 3.4, 1.6, 1.6, 0.8)
        # Scarf wrapped around neck
        c.shaded_poly([(22, 52), (21, 44), (43, 44), (44, 52), (38, 55), (26, 55)], CB, 4.4, 2.4, 1.0, 0.8)
        for y in (46, 49, 52):
            hline(c, 24, 40, y, CB, 2)
        c.shaded_poly([(36, 55), (40, 54), (42, 64), (37, 64)], CB, 3.6, 2.0, 0.6, 0.6)  # scarf tail
        # Hood bunched at back (behind shoulders line)
        for x in range(10, 56):
            f(c, x, 47 if 18 < x < 46 else 49, CA, 1)
    elif outfit == "dock":
        c.shaded_poly(sh, CA, 3.8, 2.0, 1.4, 0.7)
        c.shaded_poly([(27, 64), (27, 46), (37, 46), (37, 64)], CB, 3.2, 2.0, 0.6, 0.6)  # undershirt (dark)
        # Hi-vis reflective strips
        for x in range(6, 27):
            y = 56 + (26 - x) // 6
            f(c, x, y, FX, F_HI if x % 3 else F_EYEW)
            f(c, x, y + 1, CB, 6)
        for x in range(37, 58):
            y = 56 + (x - 37) // 6
            f(c, x, y, FX, F_EYEW if x % 3 else F_HI)
            f(c, x, y + 1, CB, 5)
        # Collar
        hline(c, 22, 42, 45, CA, 5)
    elif outfit == "bounty":
        c.shaded_poly(sh, CA, 3.2, 1.6, 1.6, 0.8)
        # Long-coat high collar flaring up
        c.shaded_poly([(18, 52), (19, 38), (25, 42), (27, 50)], CA, 4.6, 2.6, 0.8, 1.0)
        c.shaded_poly([(37, 50), (39, 42), (45, 38), (46, 52)], CA, 3.4, 1.8, 0.8, 1.0)
        # Chest holster strap + badge
        for k in range(0, 22):
            f(c, 22 + k, 52 + k // 2, CB, 2 if k % 4 else 1)
        c.sphere(26, 56, 2.5, 2.5, MT, 2.0, 7.0)
        f(c, 26, 56, GL, 4)
    elif outfit == "fixer":
        c.shaded_poly(sh, CA, 4.2, 2.2, 1.2, 0.6)  # blazer
        c.shaded_poly([(27, 64), (26, 45), (38, 45), (37, 64)], CB, 4.6, 3.0, 0.6, 0.6)  # open silk shirt
        c.shaded_poly([(29, 45), (32, 52), (35, 45)], SK, 4.2, 3.0, 0.4, 0.2)  # bare chest V
        for k, x in enumerate(range(28, 37)):  # gold chain (metal ramp)
            f(c, x, 50 + int(1.5 * math.sin(k * 0.7)), MT, 6 if k % 2 else 5)
        # Lapel pin
        f(c, 22, 52, GL, 5)
    elif outfit == "criminal":
        # Tank top: lots of skin, shoulders bare
        c.shaded_poly([(18, 64), (20, 50), (25, 47), (32, 52), (39, 47), (44, 50), (46, 64)], CA, 3.8, 2.2, 1.2, 0.8)
        for y in range(47, 64):
            f(c, 21 if y < 52 else 19, y, CA, 1)
    elif outfit == "civilian":
        c.shaded_poly(sh, CA, 4.0, 2.2, 1.4, 0.6)  # hoodie
        # Hood around the neck
        c.shaded_poly([(19, 51), (20, 43), (26, 46), (32, 48), (38, 46), (44, 43), (45, 51), (32, 53)], CA, 4.8, 2.8, 1.0, 0.8)
        vline(c, 29, 50, 58, CB, 6)  # drawstrings
        vline(c, 35, 50, 57, CB, 6)
        f(c, 29, 59, MT, 6)
        f(c, 35, 58, MT, 5)
    elif outfit == "bm_tech":
        c.shaded_poly(sh, CA, 3.4, 1.8, 1.2, 0.6)  # work shirt
        # Leather harness / apron straps with tools
        for x0 in (20, 40):
            for y in range(46, 64):
                f(c, x0 + (y - 46) // 6, y, CB, 2)
                f(c, x0 + 1 + (y - 46) // 6, y, CB, 3)
        c.rect(42, 54, 4, 7, (MT, 3))  # tool pouch
        f(c, 43, 53, MT, 6)
        f(c, 45, 52, GL, 5)
        hline(c, 16, 26, 58, GL, 3)  # coiled wire
        hline(c, 17, 25, 59, GL, 2)
    elif outfit == "medical":
        c.shaded_poly(sh, CB, 6.0, 4.6, 1.0, 0.6)  # pale uniform
        c.shaded_poly([(26, 64), (27, 45), (37, 45), (38, 64)], CA, 3.6, 2.6, 0.6, 0.4)  # dark undershirt
        for y in range(50, 64):  # zip line
            f(c, 32, y, MT, 5 if y % 2 else 3)
        # Authority insignia (green = medical)
        c.rect(43, 51, 6, 4, (CA, 2))
        hline(c, 44, 47, 52, GL, 5)
        vline(c, 45, 51, 54, GL, 4)
    elif outfit == "boss":
        c.shaded_poly(sh, CA, 3.0, 1.4, 1.2, 0.8)
        # Fur-lined collar (cloth B, noisy)
        rng = random.Random(9)
        for y in range(43, 54):
            for x in range(14, 51):
                if ((x - 32) / 18.5) ** 2 + ((y - 50) / 7.5) ** 2 <= 1 and not (25 < x < 39 and y > 46):
                    c.shade_px(x, y, CB, 3.2 + rng.random() * 2 - (1 if x > 34 else 0))
        for k, x in enumerate(range(27, 38)):
            f(c, x, 52 + int(2 * math.sin(k * 0.5)), MT, 6 if k % 2 else 5)


# --- Face overlays ---------------------------------------------------------------

def draw_facial_hair(c: Canvas, kind: str, shape="round"):
    mask = head_mask(shape)
    if kind == "stubble":
        for (x, y) in mask:
            if y >= 30 and not (29 <= x <= 35 and 32 <= y <= 34) and (x * 3 + y) % 3 == 0:
                f(c, x, y, HR, 1 if x > 32 else 2)
    elif kind == "beard":
        for (x, y) in mask:
            if y >= 29 and not (29 <= x <= 35 and y in (33, 34)) and abs(x - 32) <= 12:
                v = 3.6 - (x - 32) * 0.12 - (y - 29) * 0.1
                c.shade_px(x, y, HR, v)
        for y in range(38, 41):
            for x in range(28, 37):
                c.shade_px(x, y, HR, 2.6)
        hline(c, 29, 35, 32, HR, 2)
    elif kind == "mustache":
        hline(c, 29, 35, 32, HR, 2)
        hline(c, 30, 34, 31, HR, 3)
        f(c, 28, 33, HR, 1)
        f(c, 36, 33, HR, 1)


def draw_scar(c: Canvas, kind: str):
    if kind == "cheek":
        for k in range(6):
            f(c, 37 + k // 2, 27 + k, SK, 6)
            f(c, 38 + k // 2, 27 + k, SK, 2)
    elif kind == "brow":
        for y in range(19, 25):
            f(c, 26 + (y - 19) // 4, y, SK, 6 if y != 22 else 7)
    elif kind == "lip":
        vline(c, 34, 31, 35, SK, 6)


def draw_tattoo(c: Canvas, kind: str):
    if kind == "neck_code":
        for i, x in enumerate(range(34, 38)):
            if i != 2:
                vline(c, x, 39, 45, FX, F_INK)
        hline(c, 34, 37, 46, FX, F_INK)
    elif kind == "face_lines":
        hline(c, 25, 29, 28, FX, F_INK)
        hline(c, 26, 28, 30, FX, F_INK)
    elif kind == "gang_mark":
        for p in ((28, 40), (29, 41), (30, 40), (29, 42), (28, 43), (30, 43)):
            f(c, p[0], p[1], FX, F_INK)
    elif kind == "tear":
        f(c, 38, 27, FX, F_INK)
        f(c, 38, 28, FX, F_INK)


def draw_cyber(c: Canvas, kind: str):
    """Cyberware visible on the face/head. Metal is shaded and screwed in;
    only status LEDs use the glow ramp."""
    if kind == "eye":
        c.sphere(27, 25, 3.6, 3.2, MT, 1.0, 6.0)
        for p in ((27, 25), (28, 25), (27, 24)):
            f(c, *p, GL, 5)
        f(c, 26, 25, GL, 3)
        f(c, 28, 24, FX, F_HI)
        # seam around the socket + screws
        for a in range(0, 360, 30):
            x = 27 + round(4.6 * math.cos(math.radians(a)))
            y = 25 + round(4.0 * math.sin(math.radians(a)))
            f(c, x, y, SK, 1)
        f(c, 23, 25, MT, 6)
        f(c, 31, 28, MT, 5)
    elif kind == "visor":
        for y in range(23, 28):
            for x in range(20, 45):
                if y in (23, 27):
                    f(c, x, y, MT, 2 if y == 27 else 5)
                else:
                    v = 2 + (x - 20) / 25 * 3
                    c.shade_px(x, y, GL, v if y != 24 else v + 1.4)
        f(c, 20, 25, MT, 6)
        f(c, 44, 25, MT, 3)
    elif kind == "jaw":
        # Replaces the right half of the lower jaw: follows the jaw line.
        pts = [(35, 30), (42.5, 26), (43.5, 31), (39, 36.5), (33, 38.5), (33, 35)]
        c.shaded_poly(pts, MT, 4.4, 1.8, 1.4, 1.0)
        for x in range(35, 43):
            f(c, x, 30 - (x - 35) // 2, SK, 1)  # skin seam
        hline(c, 35, 41, 33, MT, 1)
        vline(c, 39, 30, 36, MT, 1)
        for p in ((36, 32), (41, 30), (37, 36)):
            f(c, *p, MT, 7)
        f(c, 42, 32, GL, 5)
    elif kind == "temple_port":
        c.sphere(21.5, 22.5, 2.6, 3, MT, 1.0, 6.0)
        f(c, 21, 22, FX, F_OUT)
        f(c, 22, 22, FX, F_OUT)
        f(c, 21, 24, GL, 5)
        for y in range(18, 21):
            f(c, 22, y, SK, 2)
    elif kind == "circuit":
        path = [(36, 27), (37, 28), (38, 29), (38, 30), (39, 31), (40, 31), (40, 33), (39, 34)]
        for k, (x, y) in enumerate(path):
            f(c, x, y, GL, 4 if k % 3 else 6)
        f(c, 41, 29, GL, 3)
        f(c, 41, 30, GL, 3)
    elif kind == "neck_ports":
        for x in (29, 35):
            c.rect(x, 39, 3, 3, (MT, 3))
            f(c, x + 1, 40, FX, F_OUT)
            f(c, x, 39, MT, 6)
        f(c, 30, 42, GL, 5)
    elif kind == "skull_plate":
        pts = [(37, 9), (44, 13), (45, 19), (39, 18)]
        c.shaded_poly(pts, MT, 5.6, 3.0, 1.0, 1.0)
        for p in ((38, 11), (43, 15), (40, 17)):
            f(c, *p, MT, 7)
        hline(c, 38, 44, 14, MT, 2)
    elif kind == "cheek_mesh":
        for y in range(27, 32):
            for x in range(23, 28):
                if (x + y) % 2 == 0:
                    f(c, x, y, MT, 3)
    elif kind == "arm_shoulder":
        # Cyber shoulder replacing the left shoulder (viewer's right)
        c.sphere(52, 54, 8, 7, MT, 1.2, 6.2)
        hline(c, 45, 59, 54, MT, 1)
        for p in ((49, 50), (56, 51), (52, 58)):
            f(c, *p, MT, 7)
        for k in range(8):  # cable to the neck
            f(c, 44 - k, 50 - k // 3, CB, 1 if k % 2 else 2)
        f(c, 55, 56, GL, 5)
    elif kind == "dermal":
        for y in range(44, 50):
            for x in range(26, 39):
                if (x // 2 + y // 2) % 2 == 0 and abs(x - 32) <= 6:
                    f(c, x, y, MT, 4 if x < 32 else 2)
    elif kind == "respirator":
        c.shaded_poly([(28, 31), (36, 31), (38, 37), (32, 39), (26, 37)], MT, 4.8, 2.4, 1.0, 1.0)
        for x in (29, 31, 33, 35):
            vline(c, x, 33, 36, FX, F_OUT)
        f(c, 37, 34, GL, 5)


def draw_accessory(c: Canvas, kind: str):
    if kind == "earring":
        for p in ((19, 29), (19, 30), (45, 29)):
            f(c, *p, MT, 6)
        f(c, 19, 31, MT, 4)
    elif kind == "shades":
        for ex in (27, 37):
            for y in range(23, 27):
                for x in range(ex - 3, ex + 4):
                    f(c, x, y, FX, F_OUT if y > 23 else F_PUPIL)
            f(c, ex - 2, 24, FX, F_LENS)
            f(c, ex - 1, 24, GL, 3)
        hline(c, 31, 33, 24, MT, 4)
        hline(c, 20, 23, 24, MT, 3)
        hline(c, 41, 44, 24, MT, 2)
    elif kind == "goggles":
        hline(c, 18, 46, 15, CB, 1)
        hline(c, 18, 46, 16, CB, 2)
        for ex in (27, 37):
            c.sphere(ex, 15, 4, 3.4, MT, 1.0, 6.0)
            c.sphere(ex, 15, 2.5, 2.1, GL, 2.0, 6.0)
    elif kind == "headset":
        for y in range(12, 27):
            f(c, 19 if y > 15 else 20 + (15 - y) // 2, y, MT, 4)
        c.sphere(19, 26, 2.5, 3.2, MT, 1.5, 5.5)
        for k in range(7):
            f(c, 21 + k, 31 + k // 3, MT, 3)
        f(c, 28, 33, GL, 5)
    elif kind == "mask":
        c.shaded_poly([(21, 29), (43, 29), (42, 35), (32, 39), (22, 35)], CB, 4.0, 2.2, 1.0, 0.8)
        for x in range(24, 41, 3):
            f(c, x, 31, CB, 1)
    elif kind == "nose_ring":
        f(c, 31, 31, MT, 6)
        f(c, 31, 30, MT, 4)
    elif kind == "beanie":
        for y in range(5, 19):
            for x in range(18, 47):
                if ((x + 0.5 - 32) / 13.5) ** 2 + ((y + 0.5 - 17) / 11.5) ** 2 <= 1.0:
                    v = 4.0 - (x - 32) * 0.11 - (y - 12) * 0.08
                    c.shade_px(x, y, CB, v - (1 if x % 3 == 0 else 0))
        hline(c, 19, 45, 18, CB, 5)
        hline(c, 19, 45, 19, CB, 2)
    elif kind == "hood":
        pts = [(13, 46), (15, 18), (22, 7), (32, 4), (42, 7), (49, 18), (51, 46), (44, 42), (43, 22), (38, 13), (26, 13), (21, 22), (20, 42)]
        c.shaded_poly(pts, CA, 4.0, 1.6, 2.0, 0.8)
        for y in range(14, 40):
            f(c, 21 if y < 22 else 20, y, CA, 0)
            f(c, 43, y, CA, 0)
    elif kind == "cap":
        for y in range(6, 17):
            for x in range(19, 46):
                if ((x + 0.5 - 32) / 13) ** 2 + ((y + 0.5 - 16) / 10) ** 2 <= 1.0:
                    c.shade_px(x, y, CA, 4.2 - (x - 32) * 0.12 - (y - 10) * 0.1)
        for x in range(22, 52):
            f(c, x, 17, CA, 2)
            f(c, x, 16, CA, 5 if x < 44 else 3)
        f(c, 32, 9, GL, 5)


# =============================================================================
# BODY (32x64) — full figure for the clinic doorway. Head ~11px.
# =============================================================================

def draw_body_figure(c: Canvas, build="average"):
    w = {"slim": 0, "average": 1, "heavy": 2}[build]
    # Legs
    c.capsule(13 - w * 0.3, 34, 13 - w * 0.3, 58, 2.3 + w * 0.3, SK, 1.5, 4.5)
    c.capsule(19 + w * 0.3, 34, 19 + w * 0.3, 58, 2.3 + w * 0.3, SK, 1.2, 4.0)
    # Torso
    pts = [(9 - w, 16), (23 + w, 16), (22 + w, 30), (21 + w, 35), (11 - w, 35), (10 - w, 30)]
    c.shaded_poly(pts, SK, 4.6, 3.0, 1.6, 0.6)
    # Arms
    c.capsule(9 - w, 17, 7 - w, 33, 1.9 + w * 0.3, SK, 1.6, 5.0, r2=1.5)
    c.capsule(23 + w, 17, 25 + w, 33, 1.9 + w * 0.3, SK, 1.2, 4.0, r2=1.5)
    # Neck + head
    c.cylinder(14, 12, 5, 4, SK, 2.0, 4.6)
    c.sphere(16.3, 8, 4.6, 5.6, SK, 1.6, 6.0, rim=(FX, F_RIM))
    # Eyes
    f(c, 14, 8, FX, F_PUPIL)
    f(c, 18, 8, FX, F_PUPIL)
    f(c, 16, 10, SK, 2)
    f(c, 16, 11, SK, 3)


def draw_body_hair(c: Canvas, style: str):
    if style == "bald":
        f(c, 14, 3, SK, 7)
        return
    if style == "buzz":
        for x in range(12, 21):
            f(c, x, 3 if 13 < x < 20 else 4, HR, 2)
        return
    cap = []
    for y in range(1, 8):
        for x in range(11, 22):
            if ((x + 0.5 - 16.3) / 5.3) ** 2 + ((y + 0.5 - 6) / 4.5) ** 2 <= 1.0 and y < 7:
                cap.append((x, y))
    if style in ("short", "undercut", "slick", "tied", "locs", "long"):
        for x, y in cap:
            c.shade_px(x, y, HR, 4.4 - (x - 16) * 0.3 - (y - 3) * 0.2)
        if style == "tied":
            c.sphere(16, 1.5, 2, 1.6, HR, 1.5, 5)
        if style == "long":
            for y in range(6, 18):
                f(c, 11, y, HR, 3)
                f(c, 21, y, HR, 1)
                f(c, 12, y, HR, 2) if y > 8 else None
        if style == "locs":
            for x in (11, 13, 19, 21):
                vline(c, x, 5, 16, HR, 1 if x > 16 else 3)
    if style == "mohawk":
        for y in range(-1, 5):
            f(c, 16, y + 1, HR, 5)
            f(c, 17, y + 1, HR, 3)


def draw_body_outfit(c: Canvas, outfit: str, build="average"):
    w = {"slim": 0, "average": 1, "heavy": 2}[build]
    torso = [(8 - w, 15), (24 + w, 15), (23 + w, 30), (22 + w, 36), (10 - w, 36), (9 - w, 30)]
    pants = (CB, 3.2, 1.4)
    top_ramp = CA
    long_coat = outfit in ("bounty", "smuggler", "boss")

    def sleeves(ramp, lo=1.6, hi=4.6, length=1.0):
        ex = 17 + 16 * length
        c.capsule(9 - w, 17, 7.8 - w, ex, 2.2 + w * 0.3, ramp, lo, hi, r2=1.9)
        c.capsule(23 + w, 17, 24.2 + w, ex, 2.2 + w * 0.3, ramp, lo - 0.4, hi - 0.6, r2=1.9)

    # Pants / legs
    if outfit != "criminal" or True:
        c.capsule(13 - w * 0.3, 35, 13 - w * 0.3, 57, 2.6 + w * 0.3, pants[0], pants[2], pants[1] + 1.4)
        c.capsule(19 + w * 0.3, 35, 19 + w * 0.3, 57, 2.6 + w * 0.3, pants[0], pants[2] - 0.4, pants[1] + 1.0)
    # Boots
    for bx in (13, 19):
        for y in range(56, 62):
            for x in range(bx - 3, bx + 3 + (1 if y > 59 else 0)):
                f(c, x, y, FX, F_OUT if y == 61 else F_PUPIL)
        f(c, bx - 2, 57, MT, 4)
    if outfit == "criminal":
        c.shaded_poly([(10 - w, 18), (22 + w, 18), (22 + w, 34), (10 - w, 34)], CA, 4.0, 2.4, 1.2, 0.6)
    else:
        c.shaded_poly(torso, top_ramp, 4.2, 2.2, 1.6, 0.7)
        sleeves(top_ramp, length=1.0 if outfit not in ("fixer",) else 0.9)
    if long_coat:
        c.shaded_poly([(9 - w, 30), (23 + w, 30), (25 + w, 50), (7 - w, 50)], CA, 3.4, 1.6, 1.4, 0.7)
        vline(c, 16, 30, 49, CA, 1)
    # Details per outfit
    if outfit == "mercenary":
        c.rect(10, 20, 12, 9, (CB, 2))
        for y in (22, 25):
            hline(c, 11, 20, y, CB, 4)
        c.sphere(9 - w, 17, 3, 2.4, MT, 1.5, 6)
        c.sphere(23 + w, 17, 3, 2.4, MT, 1.0, 5)
        f(c, 18, 21, GL, 5)
    elif outfit == "gang":
        vline(c, 15, 16, 35, CB, 4)
        vline(c, 17, 16, 35, CB, 3)
        for y in range(17, 22):
            f(c, 16, y, CB, 5)
        for p in ((10, 17), (12, 16), (21, 16), (23, 17)):
            f(c, *p, MT, 6)
    elif outfit == "corporate":
        c.shaded_poly([(14, 15), (18, 15), (17, 24), (15, 24)], CB, 6.2, 5.4, 0.2, 0.2)
        vline(c, 16, 16, 23, GL, 2)
        f(c, 21, 20, GL, 5)
    elif outfit == "smuggler":
        c.shaded_poly([(11, 13), (21, 13), (22, 17), (10, 17)], CB, 4.2, 2.6, 0.8, 0.6)
    elif outfit == "dock":
        for x in range(9 - w, 24 + w):
            f(c, x, 27, FX, F_HI if x % 2 else F_EYEW)
        for y in (21, 31):
            f(c, 8 - w, y, FX, F_HI)
            f(c, 24 + w, y, FX, F_HI)
        hline(c, 13, 19, 16, CB, 2)
    elif outfit == "bounty":
        for k in range(10):
            f(c, 10 + k, 18 + k, CB, 2)
        f(c, 12, 20, MT, 6)
        hline(c, 9 - w, 23 + w, 14, CA, 5)
    elif outfit == "fixer":
        c.shaded_poly([(14, 15), (18, 15), (17, 22), (15, 22)], CB, 5.0, 3.6, 0.2, 0.2)
        hline(c, 14, 18, 17, MT, 6)
    elif outfit == "bm_tech":
        vline(c, 12, 15, 35, CB, 2)
        vline(c, 20, 15, 35, CB, 2)
        c.rect(19, 28, 4, 5, (MT, 3))
        f(c, 20, 27, GL, 5)
    elif outfit == "civilian":
        hline(c, 12, 20, 15, CA, 5)
        vline(c, 15, 16, 21, CB, 6)
        vline(c, 17, 16, 20, CB, 6)
        c.rect(12, 27, 8, 3, (CA, 2))
    elif outfit == "medical":
        c.shaded_poly(torso, CB, 6.0, 4.6, 1.0, 0.6)
        c.capsule(9 - w, 17, 7.8 - w, 33, 2.2 + w * 0.3, CB, 4.0, 6.4, r2=1.9)
        c.capsule(23 + w, 17, 24.2 + w, 33, 2.2 + w * 0.3, CB, 3.6, 5.8, r2=1.9)
        hline(c, 19, 21, 20, GL, 5)
        vline(c, 16, 16, 35, MT, 4)
    elif outfit == "boss":
        for x in range(7 - w, 26 + w):
            f(c, x, 15, CB, 4 + (x % 2))
            f(c, x, 16, CB, 3)
        hline(c, 14, 18, 19, MT, 6)


def draw_body_cyber(c: Canvas, kind: str, build="average"):
    w = {"slim": 0, "average": 1, "heavy": 2}[build]
    if kind == "arm":
        c.capsule(23 + w, 17, 25 + w, 33, 2.1, MT, 1.2, 6.0, r2=1.6)
        f(c, 24 + w, 25, MT, 1)
        f(c, 25 + w, 25, MT, 1)
        f(c, 24 + w, 21, GL, 5)
        f(c, 25 + w, 33, MT, 7)
    elif kind == "legs":
        for lx in (13, 19):
            c.capsule(lx, 44, lx, 55, 2.0, MT, 1.2, 5.6)
            hline(c, lx - 1, lx + 1, 47, MT, 1)
            f(c, lx, 45, GL, 5)
    elif kind == "eye":
        f(c, 14, 8, GL, 6)
    elif kind == "visor":
        hline(c, 13, 20, 8, GL, 5)
        f(c, 12, 8, MT, 4)
    elif kind == "spine":
        for y in range(16, 22, 2):
            f(c, 16, y, MT, 5)


# =============================================================================
# Manifest + generation
# =============================================================================

def build_parts():
    """Draws every part. Returns {view: {slot: {id: Canvas}}}."""
    parts = {"portrait": {}, "body": {}}

    def put(view, slot, pid, canvas):
        parts[view].setdefault(slot, {})[pid] = canvas

    for build in BUILDS:
        cv = pc()
        draw_body_base(cv, build)
        put("portrait", "body", build, cv)
        cv = bc()
        draw_body_figure(cv, build)
        put("body", "body", build, cv)
    for shape in FACE_SHAPES:
        for expr in EXPRESSIONS:
            cv = pc()
            draw_head(cv, shape, expr)
            put("portrait", "head", f"{shape}_{expr}", cv)
    for style in HAIR_STYLES:
        cv = pc()
        draw_hair(cv, style, seed=len(style))
        put("portrait", "hair", style, cv)
        if style in ("long", "locs"):
            cv = pc()
            draw_hair_back(cv, style)
            put("portrait", "hair_back", style, cv)
        cv = bc()
        draw_body_hair(cv, style)
        put("body", "hair", style, cv)
    for outfit in OUTFITS:
        for build in BUILDS:
            cv = pc()
            draw_outfit(cv, outfit, build)
            put("portrait", "outfit", f"{outfit}_{build}", cv)
            cv = bc()
            draw_body_outfit(cv, outfit, build)
            put("body", "outfit", f"{outfit}_{build}", cv)
    for kind in ("stubble", "beard", "mustache"):
        for shape in FACE_SHAPES:
            cv = pc()
            draw_facial_hair(cv, kind, shape)
            put("portrait", "facial_hair", f"{kind}_{shape}", cv)
    for kind in ("cheek", "brow", "lip"):
        cv = pc()
        draw_scar(cv, kind)
        put("portrait", "scar", kind, cv)
    for kind in ("neck_code", "face_lines", "gang_mark", "tear"):
        cv = pc()
        draw_tattoo(cv, kind)
        put("portrait", "tattoo", kind, cv)
    for kind in ("eye", "visor", "jaw", "temple_port", "circuit", "neck_ports", "skull_plate", "cheek_mesh",
                 "arm_shoulder", "dermal", "respirator"):
        cv = pc()
        draw_cyber(cv, kind)
        put("portrait", "cyber", kind, cv)
    for kind in ("arm", "legs", "eye", "visor", "spine"):
        for build in BUILDS:
            cv = bc()
            draw_body_cyber(cv, kind, build)
            put("body", "cyber", f"{kind}_{build}", cv)
    for kind in ("earring", "shades", "goggles", "headset", "mask", "nose_ring", "beanie", "hood", "cap"):
        cv = pc()
        draw_accessory(cv, kind)
        put("portrait", "accessory", kind, cv)
    return parts


# Order in which slots are composited (back to front).
LAYER_ORDER = {
    "portrait": ["hair_back", "body", "outfit", "head", "facial_hair", "scar", "tattoo", "cyber_low", "hair", "cyber", "accessory"],
    "body": ["body", "outfit", "cyber", "hair"],
}


def generate(out_dir_rel="characters") -> dict:
    parts = build_parts()
    manifest = {"layer_order": LAYER_ORDER, "views": {}}
    for view, slots in parts.items():
        manifest["views"][view] = {}
        for slot, items in slots.items():
            manifest["views"][view][slot] = {}
            for pid, canvas in items.items():
                rel = f"{out_dir_rel}/{view}/{slot}/{pid}.png"
                canvas.save(rel)
                manifest["views"][view][slot][pid] = "res://assets/sprites/" + rel
    path = os.path.join(ROOT, "data", "character_parts.json")
    with open(path, "w") as fh:
        json.dump(manifest, fh, indent=1)
        fh.write("\n")
    print("character parts:", sum(len(v) for s in parts.values() for v in s.values()))
    return parts
