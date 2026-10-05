"""Character art v2: detailed, adult, grounded underground-cyberpunk people.

Two views, both palette-indexed so every person is recoloured at runtime:

* PORTRAIT 96x112 (bust, 3/4 key light from the left, cool rim on the
  right). Faces are built from separate layers so the game can swap
  expression (brows / eyes / mouth), gaze and blinks without redrawing:
  head (6 shapes) + age + nose + mouth + brows + eyes (+ facial hair,
  scars, tattoos, piercings, makeup, cyberware, hair, accessories,
  occupational outfit per build).
* BODY 40x80 (in-room sprite, ~7.5 heads tall, believable adult
  proportions) drawn from a skeleton with build (slim / average / heavy /
  muscular) and posture (upright / slouch / wide). Outfits follow the same
  skeleton so silhouettes read by occupation: coats, plates, aprons,
  hoods, backpacks, tool belts, weapons, canes.

Ramps (encoded R = ramp*16): 0 skin, 1 hair, 2 cloth A, 3 cloth B, 4 metal,
5 glow, 6 iris, 7 fixed, 8 cloth C, 9 leather, 10 grime, 11 blood.
"""
from __future__ import annotations

import json
import math
import os
import random

from .lib import Canvas, ROOT, poly_pixels, clamp

SK, HR, CA, CB, MT, GL, IR, FX, CC, LT, GR, BL = range(12)
F_OUT, F_EYEW, F_PUPIL, F_HI, F_BLOOD, F_INK, F_LENS, F_RIM = range(8)

PW, PH = 96, 112
BW, BH = 40, 80
CX = 48  # portrait face centre x

FACES = {
    # rx, cranium cy, ry, jaw polygon (half, mirrored), cheek hollow, chin y
    "oval":   dict(rx=16.0, cy=38, ry=21.5, jaw=[(16.0, 44), (15.0, 52), (12.0, 59), (7.0, 64), (0.0, 66)], hollow=0.0),
    "square": dict(rx=17.0, cy=38, ry=21.0, jaw=[(17.0, 44), (17.0, 54), (15.0, 61), (8.0, 66), (0.0, 66.5)], hollow=0.0),
    "long":   dict(rx=15.0, cy=37, ry=22.0, jaw=[(15.0, 44), (14.5, 54), (12.0, 62), (6.5, 68), (0.0, 69)], hollow=0.4),
    "round":  dict(rx=17.5, cy=39, ry=20.5, jaw=[(17.5, 44), (17.0, 52), (14.0, 59), (8.5, 63.5), (0.0, 65)], hollow=0.0),
    "gaunt":  dict(rx=15.5, cy=37, ry=21.5, jaw=[(15.5, 44), (13.5, 52), (12.0, 60), (6.0, 66), (0.0, 67)], hollow=1.2),
    "heavy":  dict(rx=18.5, cy=39, ry=20.5, jaw=[(18.5, 44), (19.0, 54), (17.0, 61), (10.0, 66.5), (0.0, 67.5)], hollow=-0.4),
}
EXPRESSIONS = ["neutral", "angry", "smirk", "sad", "fear", "pain"]
GAZES = ["center", "left", "right", "closed"]
NOSES = ["straight", "broad", "hooked", "broken", "small"]
AGES = ["young", "adult", "old"]
EYE_Y = 42
EYE_X = (41, 55)

BUILDS = ["slim", "average", "heavy", "muscular"]
SHOULDER = {"slim": 23, "average": 27, "heavy": 33, "muscular": 34}


def f(c: Canvas, x, y, ramp, shade):
    c.set(int(x), int(y), (ramp, int(clamp(shade, 0, 7))))


def hl(c, x0, x1, y, ramp, shade):
    for x in range(int(round(x0)), int(round(x1)) + 1):
        f(c, x, y, ramp, shade)


def vl(c, x, y0, y1, ramp, shade):
    for y in range(int(round(y0)), int(round(y1)) + 1):
        f(c, x, y, ramp, shade)


def portrait():
    c = Canvas(PW, PH, indexed=True)
    c.dither_band = 0.22  # cleaner clusters, dithering only at transitions
    return c


def body_canvas():
    c = Canvas(BW, BH, indexed=True)
    c.dither_band = 0.3
    return c


def mirror(pts, cx=CX):
    """Half-outline (dx, y) from top to chin -> full closed polygon."""
    right = [(cx + dx, y) for dx, y in pts]
    left = [(cx - dx, y) for dx, y in reversed(pts)]
    return right + left


# =============================================================================
# PORTRAIT: HEAD
# =============================================================================

def head_mask(shape: str) -> set:
    p = FACES[shape]
    cran = set()
    for y in range(8, 60):
        for x in range(20, 77):
            if ((x + 0.5 - CX) / p["rx"]) ** 2 + ((y + 0.5 - p["cy"]) / p["ry"]) ** 2 <= 1.0 and y < 50:
                cran.add((x, y))
    jaw = set(poly_pixels(mirror([(p["rx"] - 0.3, p["cy"])] + p["jaw"])))
    return cran | jaw


def skin_light(x, y, shape, lo=0.7, hi=6.5):
    # Hard noir key light from the upper left: the far side of the face
    # falls into deep shadow quickly (terminator), lit side stays warm.
    p = FACES[shape]
    nx = (x + 0.5 - CX) / (p["rx"] + 1.0)
    ny = (y + 0.5 - (p["cy"] + 6)) / (p["ry"] + 8)
    d = min(0.97, nx * nx + ny * ny)
    nz = math.sqrt(1.0 - d)
    L = (-0.74, -0.42, 0.53)
    i = clamp(nx * L[0] + ny * L[1] + nz * L[2], 0.0, 1.0)
    i = i ** 1.25
    return lo + (hi - lo) * i


def draw_head(c: Canvas, shape: str):
    p = FACES[shape]
    mask = head_mask(shape)
    # Ears behind the silhouette, the right one in shadow.
    for side in (-1, 1):
        ex = CX + side * (p["rx"] + 0.6)
        for y in range(36, 51):
            for x in range(int(ex - 3), int(ex + 4)):
                if ((x + 0.5 - ex) / 2.6) ** 2 + ((y + 0.5 - 43) / 6.5) ** 2 <= 1 and (x, y) not in mask:
                    f(c, x, y, SK, 3.4 if side < 0 else 2.0)
        # inner ear fold
        ix = int(ex + (1 if side < 0 else -1))
        vl(c, ix, 40, 46, SK, 1 if side > 0 else 2)
    for (x, y) in mask:
        c.shade_px(x, y, SK, skin_light(x, y, shape))
    # Structure: cheekbones, cheek hollows, temple shadow, jaw form shadow.
    hollow = p["hollow"]
    for (x, y) in mask:
        dx = x - CX
        g = sum(w * math.exp(-((dx - side * 11.5) ** 2) / 14.0 - ((y - 52) ** 2) / 22.0) for side, w in ((-1, 1.0), (1, 0.35)))
        if g > 0.05:
            c.shade_px(x, y, SK, skin_light(x, y, shape) - (0.45 + hollow) * g)
    for (x, y) in mask:
        if (x + 1, y) not in mask and x > CX:
            f(c, x, y, SK, 1)
        elif (x + 2, y) not in mask and x > CX:
            f(c, x, y, SK, 2)
        if (x, y + 1) not in mask and y > 55:
            f(c, x, y, SK, 1)
    # Cheekbone highlight on the lit side
    for (x, y) in ((CX - 11, 46), (CX - 10, 46), (CX - 12, 47), (CX - 11, 47)):
        if (x, y) in mask:
            f(c, x, y, SK, 6)
    # Rim light (screen glow) along the right edge, broken.
    for (x, y) in mask:
        if (x + 1, y) not in mask and x > CX and (22 < y < 34 or 44 < y < 52):
            f(c, x, y, FX, F_RIM)
    # Eye sockets (the eyes themselves are a separate layer)
    for ex in EYE_X:
        for x in range(ex - 5, ex + 6):
            for y in (EYE_Y - 3, EYE_Y - 2):
                if (x, y) in mask:
                    c.shade_px(x, y, SK, skin_light(x, y, shape) - (1.6 if y == EYE_Y - 2 else 0.8))
        for x in range(ex - 3, ex + 4):
            if (x, EYE_Y + 2) in mask:
                c.shade_px(x, EYE_Y + 2, SK, skin_light(x, EYE_Y + 2, shape) - 1.0)
    # Neck shadow under the chin (drawn by the body layer); philtrum hint
    f(c, CX, 56, SK, 3)
    if shape == "heavy":
        hl(c, CX - 7, CX + 7, 68, SK, 2)  # chin fold
        hl(c, CX - 5, CX + 5, 69, SK, 3)
    if shape in ("square", "heavy"):
        for y in (60, 61):
            f(c, CX - 12, y, SK, 3)
            f(c, CX + 12, y, SK, 1)


def draw_nose(c: Canvas, kind: str):
    top, tip = 43, 52
    bend = 1 if kind == "broken" else 0
    for y in range(top, tip):
        x = CX + (bend if y > 47 else 0)
        f(c, x - 1, y, SK, 5 if y < tip - 2 else 6)  # bridge highlight (lit side)
        f(c, x + 2, y, SK, 2 if y > 46 else 3)       # shadow side
    if kind == "hooked":
        for y in (46, 47, 48):
            f(c, CX, y, SK, 6)
        f(c, CX + 2, 49, SK, 1)
    w = {"broad": 4, "small": 2}.get(kind, 3)
    # Tip and nostrils
    hl(c, CX - w, CX + w, tip, SK, 3)
    f(c, CX, tip - 1, SK, 6)
    f(c, CX - w + 1, tip + 1, SK, 1)
    f(c, CX + w - 1, tip + 1, SK, 0)
    hl(c, CX - w + 2, CX + w - 2, tip + 1, SK, 3)
    f(c, CX + w + 1, tip, SK, 2)
    if kind == "broken":
        f(c, CX + 1, 47, SK, 2)
        f(c, CX, 48, SK, 6)
    # Shadow cast to the right of the nose (key light from the left)
    for y in range(tip - 3, tip + 2):
        f(c, CX + w + 2, y, SK, 2)


MOUTHS = {
    # (corner_left_dy, corner_right_dy, open_px, teeth)
    "neutral": (0, 0, 0, False),
    "angry": (1, 1, 0, False),
    "smirk": (0, -1, 0, False),
    "sad": (1, 1, 0, False),
    "fear": (0, 0, 2, False),
    "pain": (1, 1, 1, True),
}


def draw_mouth(c: Canvas, expr: str):
    ly, ry, opening, teeth = MOUTHS[expr]
    y = 59
    half = 5 if expr != "fear" else 4
    if opening:
        # Open mouth: dark interior, teeth line when clenched
        for yy in range(y, y + opening + 1):
            hl(c, CX - half + 1, CX + half - 1, yy, FX, F_OUT)
        if teeth:
            hl(c, CX - half + 2, CX + half - 2, y, FX, F_EYEW)
            for x in range(CX - half + 3, CX + half - 2, 2):
                f(c, x, y, SK, 2)
        hl(c, CX - half + 1, CX + half - 1, y - 1, SK, 2)
        hl(c, CX - half + 2, CX + half - 2, y + opening + 1, SK, 5)
    else:
        hl(c, CX - half + 1, CX + half - 1, y, SK, 1)
        f(c, CX - half, y + ly, SK, 1)
        f(c, CX + half, y + ry, SK, 1)
        if ly:
            f(c, CX - half + 1, y, SK, 2)
        if ry < 0:
            f(c, CX + half - 1, y - 1, SK, 2)
            f(c, CX + half + 1, y - 1, SK, 3)  # smirk dimple
        hl(c, CX - half + 2, CX + half - 2, y - 1, SK, 3)   # upper lip
        hl(c, CX - half + 2, CX + half - 2, y + 1, SK, 5)   # lower lip light
        hl(c, CX - 2, CX + 2, y + 2, SK, 3)                 # under-lip shadow
    if expr == "angry":
        hl(c, CX - 3, CX + 3, y + 3, SK, 3)
    if expr == "sad":
        f(c, CX - half - 1, y + 2, SK, 3)
        f(c, CX + half + 1, y + 2, SK, 2)


BROWS = {
    # (inner y, outer y) per side; lifts are applied on top
    "neutral": (37, 37, 0),
    "angry": (39, 36, 0),
    "smirk": (37, 37, -2),   # right brow raised
    "sad": (35, 38, 0),
    "fear": (35, 36, 0),
    "pain": (39, 37, 0),
}


def draw_brows(c: Canvas, expr: str, heavy: bool):
    inner, outer, lift = BROWS[expr]
    for side, ex in ((-1, EYE_X[0]), (1, EYE_X[1])):
        x_in = ex - side * 1 + (3 if side < 0 else -3)
        x_out = ex + side * 5
        xs = range(min(x_in, x_out), max(x_in, x_out) + 1)
        for x in xs:
            t = abs(x - x_in) / max(1, abs(x_out - x_in))
            y = round(inner + (outer - inner) * t) + (lift if side > 0 else 0)
            f(c, x, y, HR, 2 if 0.15 < t < 0.75 else 1)
            if heavy:
                f(c, x, y - 1, HR, 1)
    if expr in ("angry", "pain"):
        vl(c, CX - 1, 38, 40, SK, 2)  # glabella crease
        vl(c, CX + 1, 38, 40, SK, 2)


def draw_eyes(c: Canvas, expr: str, gaze: str):
    """Almond eyes, 3 px tall: shaded sclera, a round iris with a dark rim,
    pupil and catch-light, a heavy upper lid with a crease, soft corners.
    Fear opens them, anger and pain narrow them, sadness drops the lid."""
    wide = expr == "fear"
    squint = expr in ("angry", "pain")
    heavy_lid = expr == "sad"
    ox = {"center": 0, "left": -1, "right": 1, "closed": 0}[gaze]
    for i, ex in enumerate(EYE_X):
        lit = i == 0  # key light from the left: the right eye sits in shadow
        y = EYE_Y
        if gaze == "closed":
            # closed lid: a curved lash line and the lid's form
            hl(c, ex - 3, ex + 3, y, SK, 0)
            f(c, ex - 4, y - 1, SK, 1)
            f(c, ex + 4, y - 1, SK, 1)
            hl(c, ex - 2, ex + 2, y - 1, SK, 4 if lit else 3)
            hl(c, ex - 2, ex + 2, y + 1, SK, 3 if lit else 2)
            continue
        h = 4 if wide else (2 if squint else 3)
        top = y - (1 if wide else 0) - (0 if squint else 1)
        rows = list(range(top, top + h))
        # Sclera: almond (the end columns only on the middle rows).
        for k, yy in enumerate(rows):
            edge = k == 0 or k == h - 1
            x0, x1 = (ex - 2, ex + 2) if edge and h > 2 else (ex - 3, ex + 3)
            hl(c, x0, x1, yy, FX, F_EYEW)
            # the corner away from the light and the tear duct sink into shadow
            f(c, x1 if lit else x0, yy, SK, 4 if lit else 3)
        # Iris: 3 wide, round, darker rim, lighter lower half (light falls in).
        ix = ex + ox
        for k, yy in enumerate(rows):
            for dx in (-1, 0, 1):
                rim = dx != 0 and (k == 0 or k == h - 1)
                shade = 2 if rim else (4 if k >= h // 2 else 3)
                f(c, ix + dx, yy, IR, shade + (1 if lit and not rim else 0))
        pupil_rows = {2: [top + 1], 3: [top + 1], 4: [top + 1, top + 2]}[h]
        for py in pupil_rows:
            f(c, ix, py, FX, F_PUPIL)
        # Upper lid: a dark lash line, thicker at the outer corner, and the
        # crease above it. The lid casts a little shadow onto the eye.
        hl(c, ex - 3, ex + 3, top - 1, SK, 0)
        outer = ex + (4 if i == 1 else -4)
        f(c, outer, top - 1, SK, 0)
        f(c, outer, top, SK, 1)
        hl(c, ex - 2, ex + 2, top - 3, SK, 3 if lit else 2)  # crease
        if heavy_lid:
            hl(c, ex - 3, ex + 3, top, SK, 2)
        elif not squint:
            hl(c, ix - 1, ix + 1, top, IR, 1)  # lid shadow on the iris
        if squint:
            hl(c, ex - 3, ex + 3, top + h, SK, 2)
        # Lower lid: a soft lit line and the waterline shadow.
        hl(c, ex - 2, ex + 2, top + h, SK, 5 if lit else 3)
        f(c, ex - 3 if lit else ex + 3, top + h, SK, 3)
        # Catch-light last, so nothing covers it.
        f(c, ix - 1, top + (1 if h > 2 else 0), FX, F_HI)


def draw_age(c: Canvas, age: str):
    if age == "young":
        return
    hl(c, CX - 7, CX - 2, 31, SK, 4)
    hl(c, CX + 1, CX + 5, 31, SK, 3)
    # crow's feet + nasolabial folds
    for side, ex in ((-1, EYE_X[0]), (1, EYE_X[1])):
        ox = ex + side * 5
        f(c, ox, EYE_Y, SK, 3)
        f(c, ox + side, EYE_Y + 1, SK, 3)
        for k in range(4):
            f(c, CX + side * (5 + k // 2), 54 + k, SK, 3 if side < 0 else 2)
    if age == "old":
        hl(c, CX - 9, CX - 3, 28, SK, 4)
        hl(c, CX + 2, CX + 7, 28, SK, 3)
        hl(c, CX - 5, CX + 4, 34, SK, 4)
        for side, ex in ((-1, EYE_X[0]), (1, EYE_X[1])):
            hl(c, ex - 2, ex + 2, EYE_Y + 3, SK, 3)       # under-eye bags
            f(c, ex + side * 5, EYE_Y - 1, SK, 3)
            f(c, ex + side * 6, EYE_Y + 2, SK, 3)
            for k in range(5):
                f(c, CX + side * (7 + k // 3), 60 + k, SK, 3)   # jowl lines
        vl(c, CX - 3, 67, 69, SK, 3)  # neck cords
        vl(c, CX + 3, 67, 69, SK, 2)


FACIAL_HAIR = ["stubble", "beard", "goatee", "mustache", "full", "chops"]


def draw_facial_hair(c: Canvas, kind: str, shape: str, rng):
    mask = head_mask(shape)
    p = FACES[shape]
    def jaw_zone(x, y):
        return (x, y) in mask and y >= 53
    if kind == "stubble":
        for (x, y) in mask:
            if y >= 55 and not (CX - 6 <= x <= CX + 6 and 57 <= y <= 61) and rng.random() < 0.42:
                f(c, x, y, HR, 1)
    elif kind in ("beard", "full"):
        for (x, y) in mask:
            if jaw_zone(x, y) and (y >= 57 or abs(x - CX) > 9 or kind == "full"):
                if CX - 5 <= x <= CX + 5 and 58 <= y <= 60:
                    continue
                f(c, x, y, HR, 1 + (rng.random() < 0.35) + (2 if x < CX - 4 and rng.random() < 0.3 else 0))
        extra = 4 if kind == "full" else 2
        for x in range(CX - 9, CX + 10):
            for y in range(int(p["jaw"][-1][1]), int(p["jaw"][-1][1]) + extra - abs(x - CX) // 4):
                f(c, x, y, HR, 1 if x > CX else 2)
    elif kind == "goatee":
        for y in range(60, int(p["jaw"][-1][1]) + 3):
            for x in range(CX - 3, CX + 4):
                f(c, x, y, HR, 1 if x > CX else 2)
        hl(c, CX - 5, CX + 5, 57, HR, 1)
    elif kind == "mustache":
        hl(c, CX - 5, CX + 5, 57, HR, 1)
        hl(c, CX - 4, CX + 4, 56, HR, 2)
        f(c, CX - 6, 58, HR, 1)
        f(c, CX + 6, 58, HR, 1)
    elif kind == "chops":
        for (x, y) in mask:
            if 44 <= y <= 60 and abs(x - CX) >= p["rx"] - 4:
                f(c, x, y, HR, 1 + (rng.random() < 0.4))


SCARS = ["cheek", "brow", "lip", "slash", "burn", "stitched"]


def draw_scar(c: Canvas, kind: str):
    if kind == "cheek":
        for k in range(7):
            f(c, CX - 13 + k // 2, 46 + k, SK, 6)
            f(c, CX - 12 + k // 2, 46 + k, SK, 3)
    elif kind == "brow":
        for k in range(6):
            f(c, EYE_X[1] + 1 + k // 3, 34 + k, SK, 6)
            f(c, EYE_X[1] + 2 + k // 3, 34 + k, SK, 2)
    elif kind == "lip":
        vl(c, CX + 2, 56, 62, SK, 6)
        vl(c, CX + 3, 57, 61, SK, 3)
    elif kind == "slash":
        for k in range(26):
            x, y = CX + 12 - k, 30 + k
            f(c, x, y, SK, 6 if k % 3 else 2)
            f(c, x + 1, y, SK, 3)
    elif kind == "burn":
        rng = random.Random(7)
        for y in range(40, 62):
            for x in range(CX + 6, CX + 17):
                if rng.random() < 0.55 and ((x - CX - 11) / 6) ** 2 + ((y - 51) / 11) ** 2 < 1:
                    f(c, x, y, SK, rng.choice((2, 3, 6)))
    elif kind == "stitched":
        for k in range(14):
            f(c, CX - 15 + k, 36 + k // 4, SK, 2)
        for k in range(0, 14, 3):
            f(c, CX - 15 + k, 35 + k // 4, FX, F_OUT)
            f(c, CX - 15 + k, 37 + k // 4, FX, F_OUT)


TATTOOS = ["neck_code", "cheek_lines", "tear", "forehead_glyph", "jaw_ink", "gang_throat"]


def draw_tattoo(c: Canvas, kind: str):
    ink = (FX, F_INK)
    if kind == "neck_code":
        for k in range(9):
            vl(c, CX + 5 + k, 72, 75 if k % 2 else 74, *ink)
    elif kind == "cheek_lines":
        for k in range(3):
            hl(c, CX + 9, CX + 13, 49 + k * 2, *ink)
    elif kind == "tear":
        f(c, EYE_X[0] - 1, EYE_Y + 4, *ink)
        f(c, EYE_X[0] - 1, EYE_Y + 5, *ink)
        f(c, EYE_X[0] - 2, EYE_Y + 5, *ink)
    elif kind == "forehead_glyph":
        for (x, y) in ((0, 0), (1, 1), (-1, 1), (0, 2), (0, 3), (-2, 3), (2, 3)):
            f(c, CX + x, 26 + y, *ink)
    elif kind == "jaw_ink":
        for k in range(10):
            f(c, CX - 15 + k, 56 + k // 2, *ink)
            if k % 3 == 0:
                f(c, CX - 15 + k, 55 + k // 2, *ink)
    elif kind == "gang_throat":
        for k in range(-5, 6):
            f(c, CX + k, 75 - abs(k) // 2, BL, 3)
        f(c, CX, 76, BL, 3)


PIERCINGS = ["brow_ring", "nose_ring", "lip_ring", "ear_gauges", "septum", "studs"]


def draw_piercing(c: Canvas, kind: str):
    if kind == "brow_ring":
        f(c, EYE_X[1] + 4, 36, MT, 6)
        f(c, EYE_X[1] + 4, 38, MT, 4)
    elif kind == "nose_ring":
        f(c, CX - 3, 54, MT, 6)
        f(c, CX - 4, 55, MT, 4)
    elif kind == "lip_ring":
        f(c, CX + 3, 61, MT, 6)
        f(c, CX + 3, 62, MT, 3)
    elif kind == "septum":
        hl(c, CX - 1, CX + 1, 55, MT, 5)
    elif kind == "ear_gauges":
        for side in (-1, 1):
            ex = CX + side * 18
            for (x, y) in ((ex - 1, 48), (ex + 1, 48), (ex - 1, 50), (ex + 1, 50), (ex, 47), (ex, 51)):
                f(c, x, y, MT, 5 if side < 0 else 3)
            f(c, ex, 49, FX, F_OUT)
    elif kind == "studs":
        for (x, y) in ((CX - 18, 41), (CX - 18, 44), (CX - 17, 47)):
            f(c, x, y, MT, 6)


MAKEUP = ["liner", "lipstick", "smudge", "warpaint"]


def draw_makeup(c: Canvas, kind: str):
    if kind == "liner":
        for ex in EYE_X:
            hl(c, ex - 3, ex + 4, EYE_Y - 1, FX, F_OUT)
            f(c, ex + 5, EYE_Y - 2, FX, F_OUT)
    elif kind == "lipstick":
        hl(c, CX - 4, CX + 4, 58, BL, 4)
        hl(c, CX - 3, CX + 3, 60, BL, 5)
    elif kind == "smudge":
        for ex in EYE_X:
            for x in range(ex - 3, ex + 4):
                f(c, x, EYE_Y + 2, GR, 1)
                if x % 2:
                    f(c, x, EYE_Y + 3, GR, 2)
    elif kind == "warpaint":
        for y in range(EYE_Y - 4, EYE_Y + 6):
            for x in range(EYE_X[0] - 5, EYE_X[1] + 6):
                if (x - CX) % 9 in (0, 1) and abs(x - CX) > 4:
                    f(c, x, y, FX, F_INK)


# =============================================================================
# PORTRAIT: HAIR
# =============================================================================

HAIR = ["buzz", "short", "messy", "undercut", "slick", "long", "bob", "tied", "topknot", "mohawk", "locs",
        "receding", "braids", "shaved"]


def hairline(x):
    dx = x - CX
    return min(44.0, 27.0 + 0.045 * dx * dx)


def _hair_px(c, x, y, rng, base=2.0, light_x=None):
    # Lit from the top-left: lighter on the upper-left crown, strands dithered.
    nx = (x - CX) / 20.0
    ny = (y - 20) / 22.0
    v = base + 2.2 * clamp(-nx * 0.7 - ny * 0.8 + 0.4, 0, 1)
    # Strands: thin darker lines that run down and outwards from the crown
    # (instead of salt-and-pepper noise), with a few stray hairs.
    lean = int((x - CX) * 0.35 * max(0, y - 10) / 30.0)
    if (x - lean + (y // 5)) % 4 == 0:
        v -= 0.9
    elif (x - lean) % 4 == 2 and v > base + 1.0:
        v += 0.35
    if rng.random() < 0.04:
        v -= 0.8
    c.shade_px(x, y, HR, v)


def _cap(c, rng, grow=2.5, top_extra=0.0, line=hairline, base=2.0, side_cut=None, max_y=46):
    for y in range(4, max_y):
        for x in range(24, 73):
            rx, ry = 16.6 + grow * 0.32, 21.6 + grow * 0.7
            if ((x + 0.5 - CX) / rx) ** 2 + ((y + 0.5 - (37 - top_extra)) / ry) ** 2 > 1.0:
                continue
            if y > line(x):
                continue
            if side_cut and side_cut(x, y):
                continue
            _hair_px(c, x, y, rng, base)


def _hair_shadow(c):
    """1-2 px skin shadow under the hair edge on the forehead/temples."""
    for x in range(30, 67):
        bottom = None
        for y in range(4, 50):
            p = c.get(x, y)
            if p is not None and p[0] == HR:
                bottom = y
        if bottom is None or bottom > 44:
            continue
        for d, shade in ((1, 1), (2, 2)):
            y = bottom + d
            if ((x + 0.5 - CX) / 15.5) ** 2 + ((y + 0.5 - 38) / 21.5) ** 2 <= 1 and c.get(x, y) is None:
                f(c, x, y, SK, shade)


def _strand_highlights(c, rng, x0, x1, y0, y1, n=20):
    for _ in range(n):
        x = rng.randint(x0, x1)
        y = rng.randint(y0, y1)
        if c.get(x, y) is not None and c.get(x, y)[0] == HR:
            f(c, x, y, HR, 5 if x < CX else 4)
            f(c, x + 1, y + 1, HR, 4 if x < CX else 3)


def _fall(c, rng, x0, x1, y0, y1, taper=0):
    for y in range(y0, y1):
        t = (y - y0) / max(1, y1 - y0)
        for x in range(x0 + int(taper * t), x1 - int(taper * t) + 1):
            _hair_px(c, x, y, rng, 1.6 if x > CX else 2.2)


def draw_hair(c: Canvas, style: str, rng):
    _draw_hair(c, style, rng)
    if style not in ("buzz", "mohawk", "topknot"):
        _hair_shadow(c)


def _draw_hair(c: Canvas, style: str, rng):
    if style == "buzz":
        for y in range(14, 40):
            for x in range(28, 69):
                if ((x + 0.5 - CX) / 17.2) ** 2 + ((y + 0.5 - 37) / 22.6) ** 2 <= 1 and y <= hairline(x) and rng.random() < 0.7:
                    f(c, x, y, HR, 1 + (rng.random() < 0.3) + (x < CX - 4 and y < 26))
    elif style == "short":
        _cap(c, rng, grow=2.6)
        for k in range(6):  # fringe
            x = CX - 10 + k * 4
            vl(c, x, 26, 29 + (k % 2), HR, 2)
        _strand_highlights(c, rng, 30, 56, 14, 26)
    elif style == "messy":
        _cap(c, rng, grow=3.5)
        for k in range(9):
            x = CX - 16 + k * 4
            h = rng.randint(2, 5)
            for d in range(h):
                f(c, x + (d % 2), 13 - d + abs(x - CX) // 6, HR, 2 + (d == 0))
        for k in range(5):
            vl(c, CX - 9 + k * 4, 26, 30 + rng.randint(0, 2), HR, 1)
        _strand_highlights(c, rng, 28, 58, 12, 28, 26)
    elif style == "undercut":
        _cap(c, rng, grow=4.0, top_extra=1.5, line=lambda x: 30 if x < CX + 12 else 28,
             side_cut=lambda x, y: y > 30 and (x < CX - 13 or x > CX + 13))
        for y in range(30, 42):  # shaved sides
            for x in (range(30, 35) if True else []):
                if rng.random() < 0.5:
                    f(c, x, y, HR, 1)
            for x in range(62, 67):
                if rng.random() < 0.5:
                    f(c, x, y, HR, 1)
        for k in range(12):  # swept fringe to the right
            hl(c, CX - 8 + k, CX + 2 + k, 22 + k // 3, HR, 3 if k < 6 else 2)
        _strand_highlights(c, rng, 32, 56, 12, 24)
    elif style == "slick":
        _cap(c, rng, grow=1.2, line=lambda x: min(44.0, 25.0 + 0.05 * (x - CX) ** 2), base=1.4)
        for k in range(14):
            f(c, CX - 12 + k, 18 + abs(k - 6) // 3, HR, 6)
            f(c, CX - 11 + k, 19 + abs(k - 6) // 3, HR, 5)
    elif style in ("long", "bob", "braids"):
        _cap(c, rng, grow=3.2, line=lambda x: min(46.0, 26.0 + 0.04 * (x - CX) ** 2))
        bottom = {"long": 92, "bob": 64, "braids": 96}[style]
        _fall(c, rng, CX - 21, CX - 16, 30, bottom, taper=0)
        _fall(c, rng, CX + 16, CX + 21, 30, bottom, taper=0)
        if style == "braids":
            for side in (-1, 1):
                x = CX + side * 18
                for y in range(48, bottom, 3):
                    hl(c, x - 2, x + 2, y, HR, 1)
        for k in range(8):  # parted fringe
            vl(c, CX - 2 - k, 24 + k // 2, 28 + k // 2, HR, 3)
            vl(c, CX + 2 + k, 24 + k // 2, 28 + k // 2, HR, 2)
        _strand_highlights(c, rng, 28, 60, 14, 50, 30)
    elif style == "tied":
        _cap(c, rng, grow=1.6, line=lambda x: min(44.0, 25.5 + 0.05 * (x - CX) ** 2), base=1.8)
        for k in range(16):
            f(c, CX - 14 + k * 2, 19 + abs(k - 7) // 3, HR, 4)
        hl(c, CX + 12, CX + 16, 18, CC, 4)  # tie band
    elif style == "topknot":
        _cap(c, rng, grow=0.6, side_cut=lambda x, y: y > 24 and abs(x - CX) > 9, base=1.6)
        c.sphere(CX + 1, 9, 5.5, 4.5, HR, lo=1.0, hi=5.0)
        hl(c, CX - 3, CX + 4, 13, CC, 3)
    elif style == "mohawk":
        for y in range(4, 34):
            w = 4 if y < 28 else 3
            for x in range(CX - w, CX + w + 1):
                f(c, x, y, HR, 2 + (x < CX) + (y < 12) - (rng.random() < 0.2))
        for k in range(5):  # spikes
            x = CX - 3 + k * 2
            vl(c, x, 0, 4, HR, 3)
        for y in range(18, 40):
            for x in list(range(30, 39)) + list(range(58, 67)):
                if y <= hairline(x) and rng.random() < 0.3:
                    f(c, x, y, HR, 1)
    elif style == "locs":
        _cap(c, rng, grow=3.6)
        for k in range(10):
            x = CX - 21 + k * 4 + (2 if k > 4 else 0)
            if abs(x - CX) < 12:
                continue
            for y in range(28, 86):
                f(c, x, y, HR, 2 + ((y // 3) % 2) - (x > CX))
                f(c, x + 1, y, HR, 1 + ((y // 3) % 2))
        for k in range(6):
            vl(c, CX - 9 + k * 3, 24, 34, HR, 2 + (k % 2))
    elif style == "receding":
        _cap(c, rng, grow=1.4, line=lambda x: 22.0 if abs(x - CX) < 7 else min(44.0, 24.0 + 0.06 * (x - CX) ** 2),
             side_cut=lambda x, y: y < 22 and abs(x - CX) < 9)
        for x in range(CX - 8, CX + 9):
            if rng.random() < 0.35:
                f(c, x, 19 + rng.randint(0, 2), HR, 3)
    elif style == "shaved":
        for y in range(15, 42):
            for x in range(29, CX + 1):
                if ((x + 0.5 - CX) / 17.2) ** 2 + ((y + 0.5 - 37) / 22.6) ** 2 <= 1 and y <= hairline(x) and rng.random() < 0.45:
                    f(c, x, y, HR, 1)
        _cap(c, rng, grow=3.0, side_cut=lambda x, y: x < CX - 1)
        for x in range(CX + 2, CX + 21):
            vl(c, x, 30, 46 + (x % 4), HR, 2 if x < CX + 12 else 1)
        _strand_highlights(c, rng, CX, CX + 16, 14, 30)

def draw_hair_back(c: Canvas, style: str, rng):
    if style == "long":
        for y in range(36, 98):
            for x in range(CX - 25, CX + 26):
                if abs(x - CX) > 14 and abs(x - CX) < 25 - max(0, y - 80) * 0.6:
                    f(c, x, y, HR, 1 + (rng.random() < 0.4) + (x < CX))
    elif style == "tied":
        for y in range(30, 70):
            x = CX + 17 + (y - 30) // 8
            for d in range(-2, 3):
                f(c, x + d, y, HR, 1 + (d < 0) + (rng.random() < 0.3))
    elif style == "locs":
        for k in range(8):
            x = CX - 24 + k * 7
            for y in range(40, 96 - (k % 3) * 4):
                f(c, x, y, HR, 1 + ((y // 3) % 2))
                f(c, x + 1, y, HR, 1)
    elif style == "braids":
        for side in (-1, 1):
            x = CX + side * 22
            for y in range(40, 100):
                f(c, x, y, HR, 2 if (y // 2) % 2 else 1)
                f(c, x + side, y, HR, 1)


# =============================================================================
# PORTRAIT: NECK, SHOULDERS, OUTFITS
# =============================================================================

def neck_w(build):
    return {"slim": 6, "average": 7, "heavy": 9, "muscular": 9}[build]


def torso_outline(build, sh=None):
    s = SHOULDER[build] if sh is None else sh
    n = neck_w(build)
    half = [(n, 73), (n + 5, 78), (s - 8, 82), (s - 2, 86), (s + 1, 92), (s + 3, 102), (s + 4, PH + 1)]
    return mirror(half)


def draw_bust_base(c: Canvas, build: str):
    n = neck_w(build)
    for y in range(58, 82):
        for x in range(CX - n, CX + n + 1):
            t = (x - CX) / n
            c.shade_px(x, y, SK, 3.8 - t * 1.8 - (2.2 if y < 70 else 0.4 if y < 74 else 0))
    c.shaded_poly(torso_outline(build), SK, top=4.6, bottom=2.6, left_bias=1.6, edge_dark=0.8)
    # Collarbones and sternum notch
    for side in (-1, 1):
        for k in range(10):
            f(c, CX + side * (3 + k), 85 + (k > 6), SK, 2 if side > 0 else 3)
    f(c, CX, 84, SK, 2)
    if build == "muscular":
        for side in (-1, 1):  # trapezius ridge
            for k in range(6):
                f(c, CX + side * (n + 1 + k), 78 + k // 2, SK, 5 if side < 0 else 2)


OUTFITS = ["corporate", "executive", "security", "gang", "worker", "mercenary", "ripperdoc", "medic", "fixer",
           "dealer", "civilian", "performer", "technician", "military", "patient", "addict", "elder", "netrunner"]


def _garment(c, build, ramp, top=4.6, bottom=2.2, inset=0, y0=None, sh_extra=0):
    pts = torso_outline(build, SHOULDER[build] + sh_extra)
    if y0 is not None:
        pts = [(x, max(y, y0)) for x, y in pts]
    if inset:
        pts = [(x + (inset if x < CX else -inset), y) for x, y in pts]
    c.shaded_poly(pts, ramp, top=top, bottom=bottom, left_bias=1.8, edge_dark=0.9)


def _folds(c, rng, build, ramp, n=10, y0=92):
    s = SHOULDER[build]
    for _ in range(n):
        x = rng.randint(CX - s, CX + s)
        y = rng.randint(y0, PH - 4)
        for k in range(rng.randint(3, 7)):
            if c.get(x + k // 3, y + k) is not None and c.get(x + k // 3, y + k)[0] == ramp:
                f(c, x + k // 3, y + k, ramp, 1 if x > CX else 2)


def _collar_v(c, ramp, depth=96, w=8, shade=1):
    for y in range(76, depth):
        t = (y - 76) / (depth - 76)
        half = int(w * (1 - t)) + 1
        for x in range(CX - half, CX + half + 1):
            c.set(x, y, None)
    # lapel edge lines
    for y in range(76, depth):
        t = (y - 76) / (depth - 76)
        half = int(w * (1 - t)) + 1
        f(c, CX - half - 1, y, ramp, shade + 3)
        f(c, CX + half + 1, y, ramp, shade)


def _sleeve_seams(c, build, ramp):
    s = SHOULDER[build]
    for side in (-1, 1):
        x = CX + side * (s - 4)
        for y in range(88, PH):
            if y % 2 == 0:
                f(c, x + side * ((y - 88) // 10), y, ramp, 1)


def _stains(c, rng, ramp_shade_list, n, box):
    x0, y0, x1, y1 = box
    for _ in range(n):
        cx, cy = rng.randint(x0, x1), rng.randint(y0, y1)
        r = rng.uniform(1.0, 3.2)
        for y in range(int(cy - r), int(cy + r) + 1):
            for x in range(int(cx - r), int(cx + r) + 1):
                if (x - cx) ** 2 + (y - cy) ** 2 <= r * r and c.get(x, y) is not None and rng.random() < 0.8:
                    f(c, x, y, *rng.choice(ramp_shade_list))


def _leather_sheen(c, rng, ramp, n=16, box=None):
    """Leather reads as dark with tight, sharp highlights and creases."""
    x0, y0, x1, y1 = box
    for _ in range(n):
        x, y = rng.randint(x0, x1), rng.randint(y0, y1)
        if c.get(x, y) is not None and c.get(x, y)[0] == ramp:
            f(c, x, y, ramp, 6 if x < CX else 5)
            if rng.random() < 0.5 and c.get(x + 1, y) is not None:
                f(c, x + 1, y, ramp, 5 if x < CX else 4)


def _plate(c, x0, y0, x1, y1, ramp=MT, lo=2.0, hi=5.6):
    pts = [(x0 + 1, y0), (x1 - 1, y0), (x1, y0 + 1), (x1, y1 - 1), (x1 - 1, y1), (x0 + 1, y1), (x0, y1 - 1), (x0, y0 + 1)]
    c.shaded_poly(pts, ramp, top=hi, bottom=lo, left_bias=2.0, edge_dark=0.5)
    hl(c, x0 + 1, x1 - 1, y0, ramp, 7)  # bevel highlight
    hl(c, x0 + 1, x1 - 1, y1, ramp, 0)


def draw_outfit(c: Canvas, outfit: str, build: str, rng):
    s = SHOULDER[build]
    if outfit == "corporate":
        # tailored suit: sharp shoulders, white shirt, dark tie, pocket square
        _garment(c, build, CA, top=4.0, bottom=2.0, sh_extra=1)
        _collar_v(c, CA, depth=100, w=9)
        for y in range(76, 100):  # shirt in the V
            half = int(9 * (1 - (y - 76) / 24)) + 1
            hl(c, CX - half, CX + half, y, CB, 6 if y < 80 else 5)
        for y in range(78, 100):  # tie
            hl(c, CX - 1, CX + 1 + (y > 90), y, CC, 2 + (y < 80))
        hl(c, CX - 4, CX + 4, 75, CB, 6)
        hl(c, CX + s - 14, CX + s - 9, 98, CB, 6)  # pocket square
        _sleeve_seams(c, build, CA)
    elif outfit == "executive":
        # high-collared long coat, closed, one metal clasp, no visible wear
        _garment(c, build, CA, top=3.6, bottom=1.6, sh_extra=2)
        for y in range(66, 82):
            for x in range(CX - neck_w(build) - 4, CX + neck_w(build) + 5):
                if abs(x - CX) >= neck_w(build) - 1:
                    c.shade_px(x, y, CA, 4.6 - (x > CX) * 2.0 - (y > 76))
        vl(c, CX + 2, 80, PH - 1, CA, 1)
        _plate(c, CX - 2, 88, CX + 3, 91, MT)
        f(c, CX + 1, 89, GL, 4)
    elif outfit == "security":
        _garment(c, build, CA, top=4.0, bottom=1.8)
        for side in (-1, 1):  # shoulder armor
            x0 = CX + side * (s - 10) - (10 if side > 0 else 0)
            _plate(c, min(x0, x0 + side * 12), 84, max(x0, x0 + side * 12), 96, MT)
        _plate(c, CX - 12, 92, CX + 12, PH - 2, MT, lo=1.6, hi=4.6)  # chest plate
        hl(c, CX - 10, CX + 10, 100, MT, 1)
        for y in range(66, 80):  # collar guard
            hl(c, CX - neck_w(build) - 2, CX - neck_w(build), y, CB, 3)
            hl(c, CX + neck_w(build), CX + neck_w(build) + 2, y, CB, 1)
        _plate(c, CX - 9, 95, CX - 4, 99, CC, lo=3, hi=6)  # badge
        f(c, CX - 7, 97, GL, 5)
    elif outfit == "gang":
        # asymmetric: leather jacket open, one studded/spiked pauldron, torn tee
        _garment(c, build, CB, top=3.4, bottom=1.6, inset=6)
        _garment(c, build, LT, top=3.6, bottom=1.4)
        _collar_v(c, LT, depth=PH, w=12, shade=0)
        for y in range(80, PH):
            half = int(12 * (1 - (y - 76) / (PH - 76))) + 2
            hl(c, CX - half, CX + half, y, CB, 2 + (y < 86) - (y % 7 == 0))
        for y in range(96, 104):  # tear in the shirt
            f(c, CX - 2 + (y % 3), y, SK, 3)
        _plate(c, CX - s - 1, 82, CX - s + 13, 94, MT, lo=1.0, hi=5.0)
        for k in range(4):  # spikes
            vl(c, CX - s + 1 + k * 4, 78 - (k % 2), 82, MT, 6)
        for k in range(6):
            f(c, CX + s - 6, 90 + k * 3, MT, 6)  # studs on the right lapel
        _leather_sheen(c, rng, LT, 26, (CX - s, 86, CX + s, PH - 1))
        for k in range(5):  # red faction patch
            hl(c, CX + s - 14, CX + s - 8, 100 + k, CC, 3 if k else 5)
    elif outfit == "worker":
        _garment(c, build, CA, top=3.8, bottom=1.8, sh_extra=3)  # padded jacket
        for k in range(4):
            hl(c, CX - s - 2, CX + s + 2, 92 + k * 6, CA, 1)  # quilting
        for side in (-1, 1):
            for y in range(88, PH):  # hi-vis stripes
                f(c, CX + side * (s - 8), y, CB, 6 if side < 0 else 4)
                f(c, CX + side * (s - 7), y, CB, 5 if side < 0 else 3)
        hl(c, CX - s, CX + s, 104, CB, 5)
        hl(c, CX - s, CX + s, 105, CB, 3)
        _collar_v(c, CA, depth=86, w=6)
        for y in range(76, 86):
            hl(c, CX - 3, CX + 3, y, CC, 3)
        _stains(c, rng, [(GR, 2), (GR, 3), (GR, 1)], 9, (CX - s, 90, CX + s, PH - 2))
    elif outfit == "mercenary":
        _garment(c, build, CB, top=3.6, bottom=1.8)
        _plate(c, CX - s + 6, 86, CX + s - 6, PH - 1, CA, lo=1.4, hi=4.2)  # plate carrier
        for k in range(3):  # magazine pouches
            _plate(c, CX - 14 + k * 10, 100, CX - 7 + k * 10, PH - 1, CC, lo=1.5, hi=4.0)
        for k in range(16):  # sling strap
            f(c, CX - s + 6 + k * 2, 86 + k, LT, 3)
            f(c, CX - s + 7 + k * 2, 86 + k, LT, 2)
        for y in range(70, 82):
            hl(c, CX - neck_w(build) - 3, CX + neck_w(build) + 3, y, CB, 2 + (y < 72))
        _stains(c, rng, [(GR, 2), (GR, 1)], 5, (CX - s, 92, CX + s, PH - 2))
    elif outfit == "ripperdoc":
        _garment(c, build, CB, top=3.8, bottom=2.0)  # dark shirt, rolled sleeves
        for y in range(84, PH):  # leather apron with straps over the neck
            half = 14 + (y - 84) // 4
            for x in range(CX - half, CX + half + 1):
                c.shade_px(x, y, LT, 3.6 - (x - CX) / half * 1.2 - (y - 84) / 40)
        for side in (-1, 1):
            for y in range(70, 86):
                f(c, CX + side * (neck_w(build) + 1), y, LT, 2)
        _leather_sheen(c, rng, LT, 18, (CX - 20, 86, CX + 20, PH - 1))
        _stains(c, rng, [(BL, 2), (BL, 3), (BL, 1), (GR, 2)], 9, (CX - 16, 90, CX + 16, PH - 2))
        for k in range(4):  # tool loops on the apron
            vl(c, CX - 12 + k * 6, 94, 102, MT, 6 - (k % 2) * 2)
            f(c, CX - 12 + k * 6, 93, MT, 7)
        hl(c, CX - 18, CX + 18, 96, LT, 1)
    elif outfit == "medic":
        _garment(c, build, CB, top=5.0, bottom=2.6, sh_extra=1)  # dirty lab coat
        _collar_v(c, CB, depth=104, w=10, shade=2)
        for y in range(76, 104):
            half = int(10 * (1 - (y - 76) / 28)) + 1
            hl(c, CX - half, CX + half, y, CA, 3 + (y < 80))  # scrubs
        _stains(c, rng, [(GR, 4), (GR, 3), (BL, 3), (BL, 2)], 10, (CX - s, 88, CX + s, PH - 2))
        _plate(c, CX + s - 16, 96, CX + s - 9, 104, CC, lo=3, hi=6)  # ID card
        f(c, CX + s - 13, 99, GL, 3)
        vl(c, CX + s - 12, 84, 95, CC, 1)
    elif outfit == "fixer":
        _garment(c, build, CA, top=3.4, bottom=1.4, sh_extra=3)
        _collar_v(c, CA, depth=PH, w=11, shade=1)
        for y in range(80, PH):
            half = int(11 * (1 - (y - 76) / (PH - 76))) + 1
            hl(c, CX - half, CX + half, y, CB, 2 + (y < 84))
        for side in (-1, 1):  # big leather collar
            for y in range(62, 84):
                for k in range(5):
                    x = CX + side * (neck_w(build) + 2 + k + (y - 62) // 4)
                    f(c, x, y, LT, 4 - k // 2 - (side > 0) * 2)
        for k in range(14):  # chain
            f(c, CX - 7 + k, 84 + abs(k - 7) // 2, MT, 6 if k % 2 else 4)
        _leather_sheen(c, rng, LT, 10, (CX - 22, 62, CX + 22, 84))
    elif outfit == "dealer":
        _garment(c, build, CA, top=3.4, bottom=1.4, sh_extra=2)
        for side in (-1, 1):  # hood bunched behind the neck
            for y in range(66, 84):
                for k in range(7):
                    x = CX + side * (neck_w(build) + 1 + k)
                    if y > 64 + k:
                        f(c, x, y, CA, 4 - k // 3 - (side > 0))
        _collar_v(c, CA, depth=PH, w=9)
        for y in range(80, PH):
            half = int(9 * (1 - (y - 76) / (PH - 76))) + 1
            hl(c, CX - half, CX + half, y, CB, 1 + (y % 5 == 0))
        for k in range(3):
            for j in range(10):
                f(c, CX - 5 + j, 86 + k * 5 + abs(j - 5) // 2, MT, 5 if j % 2 else 3)
    elif outfit == "civilian":
        _garment(c, build, CA, top=4.2, bottom=2.0)  # hoodie
        for side in (-1, 1):
            for y in range(70, 86):
                for k in range(6):
                    f(c, CX + side * (neck_w(build) + k), y, CA, 4 - k // 2 - (side > 0) * 2)
        for side in (-1, 1):  # drawstrings
            vl(c, CX + side * 4, 84, 98, CB, 5 if side < 0 else 3)
        hl(c, CX - 12, CX + 12, 104, CA, 2)  # pocket
        _folds(c, rng, build, CA, 10)
    elif outfit == "performer":
        _garment(c, build, CB, top=4.4, bottom=2.0, inset=4)
        for y in range(86, PH, 2):  # mesh top
            for x in range(CX - s + 6, CX + s - 5, 2):
                f(c, x, y, SK, 3)
        for y in range(84, 100):  # cropped jacket
            for x in list(range(CX - s - 2, CX - 10)) + list(range(CX + 11, CX + s + 3)):
                c.shade_px(x, y, CA, 4.0 - (x > CX) * 1.8 - (y - 84) / 10)
        hl(c, CX - s - 2, CX - 10, 100, GL, 3)  # restrained LED trim
        hl(c, CX + 11, CX + s + 2, 100, GL, 2)
        for k in range(8):
            f(c, CX - s + 1 + k * 3, 90 + (k % 3), CC, 6)  # sequins
    elif outfit == "technician":
        _garment(c, build, CA, top=4.0, bottom=2.0)  # jumpsuit
        for y in range(76, 92):
            hl(c, CX - 1, CX + 1, y, MT, 4 if y % 3 else 6)  # zip
        for side in (-1, 1):  # harness straps
            for y in range(80, PH):
                x = CX + side * (10 + (y - 80) // 6)
                f(c, x, y, LT, 3 if side < 0 else 1)
                f(c, x + side, y, LT, 2)
        _plate(c, CX - 15, 90, CX - 9, 96, MT)  # chest lamp
        f(c, CX - 12, 93, GL, 6)
        f(c, CX - 11, 93, GL, 5)
        for k in range(3):
            vl(c, CX + 12 + k * 3, 94, 102, MT, 6 - k)  # pocket tools
        _stains(c, rng, [(GR, 2), (GR, 3)], 7, (CX - s, 90, CX + s, PH - 2))
    elif outfit == "military":
        _garment(c, build, CA, top=3.8, bottom=1.8)
        for k in range(3):
            hl(c, CX - s + 4, CX + s - 4, 96 + k * 6, CB, 2)  # webbing
            hl(c, CX - s + 4, CX + s - 4, 97 + k * 6, CB, 1)
        for side in (-1, 1):
            vl(c, CX + side * 12, 84, PH - 1, CB, 2)
        _plate(c, CX + s - 15, 86, CX + s - 7, 91, CC, lo=2, hi=5)  # rank patch
        for y in range(70, 80):
            hl(c, CX - neck_w(build) - 2, CX + neck_w(build) + 2, y, CA, 2 + (y < 72))
        for k in range(4):  # dog tag chain
            f(c, CX - 2 + k, 82 + k, MT, 6)
    elif outfit == "patient":
        _garment(c, build, CA, top=5.6, bottom=3.0, inset=-1)  # thin gown
        for y in range(76, 88):
            half = int(6 * (1 - (y - 76) / 12)) + 1
            for x in range(CX - half, CX + half + 1):
                c.set(x, y, None)
        rngx = random.Random(3)
        for k in range(4):  # electrode stickers + leads
            x, y = CX - 16 + k * 10, 90 + (k % 2) * 6
            _plate(c, x, y, x + 3, y + 3, CB, lo=4, hi=6)
            for d in range(PH - y):
                f(c, x + 1 + (d // 5) * (1 if k % 2 else -1), y + 4 + d, MT, 3 + (d % 2))
        _stains(c, rngx, [(BL, 3), (GR, 4)], 5, (CX - s, 92, CX + s, PH - 2))
        for k in range(8):
            f(c, CX - s + 3 + k * 6, 90 + (k % 2), CA, 3)  # print pattern
    elif outfit == "addict":
        _garment(c, build, CA, top=4.6, bottom=2.4, inset=5)  # stained tank
        for y in range(76, 90):
            for x in range(CX - 8, CX + 9):
                if abs(x - CX) < 9 - (y - 76) // 2:
                    c.set(x, y, None)
        for y in range(86, PH):  # torn open hoodie
            for x in list(range(CX - s - 2, CX - s + 8)) + list(range(CX + s - 7, CX + s + 3)):
                c.shade_px(x, y, CB, 3.2 - (x > CX) * 1.6)
        for k in range(5):
            f(c, CX - s + 2 + rng.randint(0, 4), 96 + k * 3, SK, 3)  # holes
        _stains(c, rng, [(GR, 2), (GR, 3), (BL, 2)], 12, (CX - s, 88, CX + s, PH - 2))
        for k in range(6):  # injection marks / dermal ports on the shoulder
            f(c, CX - s + 3 + k, 90 - (k % 2), BL, 3)
    elif outfit == "elder":
        _garment(c, build, CA, top=3.6, bottom=1.6, sh_extra=1)  # worn coat
        _collar_v(c, CA, depth=104, w=8, shade=1)
        for y in range(70, 92):  # knitted scarf
            for x in range(CX - 12, CX + 13):
                if abs(x - CX) < 13 - max(0, (y - 82)) and (y < 82 or abs(x - CX - 4) < 4):
                    f(c, x, y, CB, 3 + ((x + y) % 3 == 0) - (x > CX))
        for k in range(6):  # patched elbows/shoulders
            hl(c, CX - s + 1, CX - s + 7, 94 + k, CC, 2 + (k % 2))
        _folds(c, rng, build, CA, 12)
        _stains(c, rng, [(GR, 2)], 4, (CX - s, 96, CX + s, PH - 2))
    elif outfit == "netrunner":
        _garment(c, build, CA, top=3.4, bottom=1.4, inset=1)  # tight bodysuit
        for y in range(66, 80):  # turtleneck
            hl(c, CX - neck_w(build) - 1, CX + neck_w(build) + 1, y, CA, 2 + (y < 70) - (y > 76))
        for side in (-1, 1):  # cable ports along the collarbone
            for k in range(3):
                x = CX + side * (8 + k * 5)
                _plate(c, x - 1, 84, x + 2, 87, MT)
                f(c, x, 85, GL, 5 - k)
        for y in range(88, PH):  # faint trace lines
            if y % 6 == 0:
                hl(c, CX - 3, CX + 3, y, GL, 1)
            f(c, CX, y, GL, 1 if y % 3 else 2)


# =============================================================================
# PORTRAIT: CYBERWARE (identity, not decoration)
# =============================================================================

CYBER = ["optic", "twin_optics", "visor", "jaw_plate", "face_half", "temple_ports", "neck_ports", "skull_plate",
         "cheek_leds", "skin_seam", "mouth_grille", "ear_module", "forehead_chip", "shoulder_chrome",
         "spine_cables", "organic_growth", "serial_marks", "patched_implant"]
# Cyberware drawn below the hair (low) vs above it.
CYBER_LOW = {"temple_ports", "skull_plate", "cheek_leds", "skin_seam", "forehead_chip", "serial_marks",
             "organic_growth", "patched_implant", "neck_ports", "jaw_plate", "face_half", "mouth_grille"}


def _lens(c, cx, cy, r, glow_shade=5):
    for y in range(cy - r - 1, cy + r + 2):
        for x in range(cx - r - 1, cx + r + 2):
            d = math.hypot(x + 0.5 - cx - 0.5, y + 0.5 - cy - 0.5)
            if d <= r + 1.2:
                f(c, x, y, MT, 5 if x < cx and y < cy else (2 if x > cx else 3))
            if d <= r - 0.2:
                f(c, x, y, FX, F_OUT)
            if d <= r - 1.0:
                f(c, x, y, GL, glow_shade - (d > r - 2))
    f(c, cx, cy, GL, 7)
    f(c, cx - 1, cy - 1, FX, F_HI)


def draw_cyber(c: Canvas, kind: str, rng):
    ex0, ex1 = EYE_X
    if kind == "optic":
        _lens(c, ex1, EYE_Y, 3)
        for k in range(5):  # housing screws / socket plate
            f(c, ex1 + 4, EYE_Y - 3 + k * 2, MT, 6 - (k % 2) * 3)
        hl(c, ex1 - 4, ex1 + 4, EYE_Y - 5, MT, 3)
    elif kind == "twin_optics":
        for ex in EYE_X:
            _lens(c, ex, EYE_Y, 2, 4)
        hl(c, ex0 + 3, ex1 - 3, EYE_Y - 1, MT, 4)  # bridge
    elif kind == "visor":
        for y in range(EYE_Y - 3, EYE_Y + 3):
            for x in range(CX - 19, CX + 20):
                c.shade_px(x, y, MT, 4.4 - (x - CX) / 12 - (y > EYE_Y + 1) * 1.5)
        hl(c, CX - 16, CX + 16, EYE_Y, GL, 5)
        hl(c, CX - 12, CX + 8, EYE_Y - 1, GL, 3)
        f(c, CX - 10, EYE_Y, GL, 7)
    elif kind == "jaw_plate":
        for y in range(54, 67):
            for x in range(CX + 3, CX + 17 - max(0, y - 60)):
                c.shade_px(x, y, MT, 3.6 - (x - CX) / 9 - (y - 54) / 14)
        hl(c, CX + 3, CX + 15, 54, MT, 6)
        for k in range(3):
            f(c, CX + 6 + k * 4, 60, FX, F_OUT)
            f(c, CX + 6 + k * 4, 59, MT, 6)
    elif kind == "face_half":
        mask = head_mask("oval")
        for (x, y) in mask:
            if x >= CX + 1 and 30 <= y <= 64:
                c.shade_px(x, y, MT, 4.0 - (x - CX) / 9)
        for y in range(30, 65, 4):
            hl(c, CX + 1, CX + 14, y, MT, 2)
        vl(c, CX + 1, 30, 64, MT, 6)
        _lens(c, ex1, EYE_Y, 3)
        for k in range(4):
            f(c, CX + 3 + k * 3, 58, GL, 3)
    elif kind == "temple_ports":
        for side in (-1, 1):
            x = CX + side * 14
            for k in range(3):
                _plate(c, x - 1, 33 + k * 4, x + 1, 35 + k * 4, MT)
                f(c, x, 34 + k * 4, GL, 4 if k == 0 else 2)
    elif kind == "neck_ports":
        for k in range(3):
            y = 68 + k * 4
            _plate(c, CX + 3, y, CX + 6, y + 2, MT)
            f(c, CX + 4, y + 1, FX, F_OUT)
        f(c, CX + 5, 69, GL, 5)
    elif kind == "skull_plate":
        for y in range(16, 31):
            for x in range(CX - 15, CX + 2):
                if ((x - CX + 6) / 10) ** 2 + ((y - 24) / 8) ** 2 <= 1:
                    c.shade_px(x, y, MT, 5.0 - (y - 16) / 6 - (x > CX - 6))
        for k in range(5):
            f(c, CX - 14 + k * 3, 30 - (k % 2), MT, 1)
            f(c, CX - 13 + k * 3, 30 - (k % 2), MT, 6)
    elif kind == "cheek_leds":
        for side in (-1, 1):
            for k in range(4):
                f(c, CX + side * (10 + k), 48 + k, GL, 2)
    elif kind == "skin_seam":
        # Executive synthetic skin: a hairline seam at the jaw and neck,
        # visible only on inspection.
        for k in range(16):
            f(c, CX - 14 + k, 62 + (k > 8) + (k > 13), SK, 3)
        vl(c, CX + 8, 66, 76, SK, 3)
        f(c, CX + 8, 70, GL, 2)
    elif kind == "mouth_grille":
        for y in range(57, 63):
            hl(c, CX - 6, CX + 6, y, MT, 5 - (y - 57) // 2)
        for x in range(CX - 5, CX + 6, 2):
            vl(c, x, 58, 61, FX, F_OUT)
    elif kind == "ear_module":
        _plate(c, CX + 17, 38, CX + 21, 49, MT)
        vl(c, CX + 20, 26, 38, MT, 5)
        f(c, CX + 20, 25, GL, 6)
        f(c, CX + 19, 44, GL, 3)
    elif kind == "forehead_chip":
        _plate(c, CX - 3, 25, CX + 3, 29, MT, lo=2, hi=5)
        hl(c, CX - 2, CX + 2, 27, GL, 4)
        for side in (-1, 1):
            hl(c, CX + side * 4, CX + side * 7, 27, SK, 3)
    elif kind == "shoulder_chrome":
        for y in range(82, PH):
            for x in range(CX - 38, CX - 20):
                if ((x - CX + 28) / 12) ** 2 + ((y - 96) / 16) ** 2 <= 1:
                    c.shade_px(x, y, MT, 5.4 - (x - CX + 38) / 10 - (y - 82) / 22)
        for y in range(86, PH, 5):
            hl(c, CX - 36, CX - 22, y, MT, 1)
        f(c, CX - 27, 92, GL, 4)
    elif kind == "spine_cables":
        for side in (-1, 1):
            for k in range(22):
                x = CX + side * (9 + k)
                y = 72 + int(k * 0.55) + (k % 4 == 0)
                f(c, x, y, MT, 4 if side < 0 else 2)
                f(c, x, y + 1, FX, F_OUT)
        f(c, CX + 9, 72, GL, 4)
    elif kind == "organic_growth":
        # Experimental: wet, vein-like wetware crawling out from the neck.
        rngx = random.Random(11)
        pts = [(CX + 6, 76)]
        for k in range(26):
            x, y = pts[-1]
            pts.append((x + rngx.choice((1, 1, 0)), y - rngx.choice((1, 1, 0, 2)) if k < 18 else y + 1))
        for (x, y) in pts:
            f(c, x, y, BL, 3)
            f(c, x + 1, y, GL, 2)
        for k in range(6):
            x, y = pts[rngx.randint(0, len(pts) - 1)]
            f(c, x - 1, y, GL, 5)
        for y in range(70, 78):
            for x in range(CX + 3, CX + 10):
                if rngx.random() < 0.4:
                    f(c, x, y, BL, 2)
    elif kind == "serial_marks":
        for k in range(7):
            f(c, CX - 15 + k * 2, 70 + (k % 2), FX, F_INK)
        hl(c, CX - 16, CX - 3, 72, FX, F_INK)
    elif kind == "patched_implant":
        _plate(c, CX - 15, 48, CX - 8, 55, MT, lo=1.6, hi=4.4)
        for k in range(6):  # tape + crude stitches
            f(c, CX - 16 + k * 2, 47, CB, 5)
            f(c, CX - 16 + k * 2, 56, FX, F_OUT)
        f(c, CX - 12, 51, GL, 4)
        f(c, CX - 11, 52, BL, 2)


ACCESSORIES = ["shades", "goggles", "glasses", "headset", "surgical_mask", "beanie", "cap", "hood", "helmet",
               "bandana", "scarf", "cigarette", "earpiece", "chain", "dog_tags", "choker", "headlamp",
               "respirator", "monocle"]


def draw_accessory(c: Canvas, kind: str, rng):
    ex0, ex1 = EYE_X
    if kind == "shades":
        for ex in EYE_X:
            for y in range(EYE_Y - 2, EYE_Y + 3):
                hl(c, ex - 4, ex + 4, y, CC, 1 if y > EYE_Y else 0)
            f(c, ex - 3, EYE_Y - 1, FX, F_LENS)
        hl(c, ex0 + 5, ex1 - 5, EYE_Y - 2, MT, 4)
        hl(c, CX - 22, ex0 - 5, EYE_Y - 2, MT, 3)
    elif kind == "goggles":
        hl(c, CX - 22, CX + 22, 31, LT, 2)
        hl(c, CX - 22, CX + 22, 32, LT, 1)
        for ex in (CX - 8, CX + 8):
            _lens(c, ex, 30, 4, 2)
    elif kind == "glasses":
        for ex in EYE_X:
            for x in range(ex - 4, ex + 5):
                f(c, x, EYE_Y - 3, MT, 4)
                f(c, x, EYE_Y + 3, MT, 2)
            vl(c, ex - 4, EYE_Y - 3, EYE_Y + 3, MT, 4)
            vl(c, ex + 4, EYE_Y - 3, EYE_Y + 3, MT, 2)
            f(c, ex - 2, EYE_Y - 2, FX, F_LENS)
        hl(c, ex0 + 5, ex1 - 5, EYE_Y - 2, MT, 4)
    elif kind == "headset":
        for x in range(CX - 20, CX + 21):
            y = int(18 + ((x - CX) / 20) ** 2 * 18)
            f(c, x, y, CC, 2)
        _plate(c, CX - 22, 38, CX - 17, 48, CC, lo=1, hi=4)
        for k in range(10):
            f(c, CX - 18 + k, 52 + k // 2, CC, 2)
        f(c, CX - 8, 57, GL, 4)
    elif kind == "surgical_mask":
        for y in range(50, 66):
            for x in range(CX - 15, CX + 16):
                if abs(x - CX) <= 15 - max(0, y - 60):
                    c.shade_px(x, y, CB, 5.4 - (x - CX) / 10 - (y - 50) / 14)
        for k in range(3):
            hl(c, CX - 12, CX + 12, 54 + k * 3, CB, 3)
        for side in (-1, 1):
            hl(c, CX + side * 15, CX + side * 19, 48, CB, 4)
        _stains(c, rng, [(BL, 3), (GR, 4)], 2, (CX - 10, 56, CX + 10, 63))
    elif kind == "beanie":
        for y in range(10, 30):
            for x in range(CX - 20, CX + 21):
                if ((x - CX) / 20.5) ** 2 + ((y - 30) / 19) ** 2 <= 1:
                    c.shade_px(x, y, CC, 4.6 - (x - CX) / 9 - (y - 10) / 14 - (x % 3 == 0) * 0.6)
        for y in range(26, 31):
            hl(c, CX - 20, CX + 20, y, CC, 3 - (y == 30))
    elif kind == "cap":
        for y in range(12, 28):
            for x in range(CX - 19, CX + 20):
                if ((x - CX) / 19.5) ** 2 + ((y - 28) / 15) ** 2 <= 1:
                    c.shade_px(x, y, CC, 4.4 - (x - CX) / 10)
        for x in range(CX - 20, CX + 12):  # brim
            hl(c, x, x, 28, CC, 2)
            f(c, x, 29, CC, 1)
    elif kind == "hood":
        for y in range(6, 92):
            for x in range(CX - 30, CX + 31):
                outer = ((x - CX) / 27) ** 2 + ((y - 40) / 34) ** 2 <= 1
                inner = ((x - CX) / 19.5) ** 2 + ((y - 42) / 27) ** 2 <= 1
                if outer and not inner:
                    c.shade_px(x, y, CC, 3.8 - (x - CX) / 9 - (y > 60) * 0.8)
        for x in range(CX - 19, CX + 20):  # inner shadow on the forehead
            f(c, x, int(16 + ((x - CX) / 20) ** 2 * 10), CC, 1)
    elif kind == "helmet":
        for y in range(10, 36):
            for x in range(CX - 21, CX + 22):
                if ((x - CX) / 21.5) ** 2 + ((y - 34) / 24) ** 2 <= 1:
                    c.shade_px(x, y, CA, 4.8 - (x - CX) / 10 - (y - 10) / 16)
        hl(c, CX - 21, CX + 21, 34, MT, 5)
        _plate(c, CX - 16, 22, CX + 16, 28, MT, lo=2, hi=5)  # raised visor
        hl(c, CX - 14, CX + 14, 25, GL, 2)
        for side in (-1, 1):
            _plate(c, CX + side * 20 - 2, 34, CX + side * 20 + 2, 50, CA)
    elif kind == "bandana":
        for y in range(53, 72):
            for x in range(CX - 18, CX + 19):
                if abs(x - CX) <= 18 - max(0, y - 64) * 2:
                    c.shade_px(x, y, CC, 4.2 - (x - CX) / 10 - (y > 64))
        for k in range(5):
            f(c, CX - 10 + k * 5, 60 + (k % 2), CC, 1)
    elif kind == "scarf":
        for y in range(66, 86):
            for x in range(CX - 16, CX + 17):
                if abs(x - CX) <= 16 - max(0, y - 80):
                    c.shade_px(x, y, CC, 4.0 - (x - CX) / 10 + ((x + y) % 4 == 0) * 0.8)
    elif kind == "cigarette":
        for k in range(8):
            f(c, CX + 5 + k, 60 + k // 4, CB, 6)
        f(c, CX + 13, 62, GL, 6)
        f(c, CX + 14, 62, GL, 4)
        for k in range(6):
            f(c, CX + 15 + (k % 2), 60 - k * 2, FX, F_EYEW)
    elif kind == "earpiece":
        _plate(c, CX - 20, 43, CX - 17, 47, MT)
        f(c, CX - 18, 45, GL, 5)
        for k in range(8):
            f(c, CX - 19, 48 + k, CC, 1)
    elif kind == "chain":
        for k in range(26):
            f(c, CX - 13 + k, 82 + int(abs(k - 13) * -0.4 + 6), MT, 6 if k % 2 else 3)
    elif kind == "dog_tags":
        for k in range(10):
            f(c, CX - 5 + k, 80 + abs(k - 5) // 2, MT, 5)
        _plate(c, CX - 1, 85, CX + 3, 90, MT)
    elif kind == "choker":
        hl(c, CX - 8, CX + 8, 72, LT, 2)
        hl(c, CX - 8, CX + 8, 73, LT, 1)
        f(c, CX, 74, MT, 6)
    elif kind == "headlamp":
        hl(c, CX - 19, CX + 19, 27, LT, 2)
        _plate(c, CX - 4, 22, CX + 4, 28, MT)
        f(c, CX, 25, GL, 7)
        f(c, CX - 1, 25, GL, 6)
    elif kind == "respirator":
        for y in range(52, 68):
            for x in range(CX - 11, CX + 12):
                if abs(x - CX) <= 11 - max(0, y - 63):
                    c.shade_px(x, y, CB, 3.6 - (x - CX) / 8)
        for side in (-1, 1):
            c.sphere(CX + side * 10, 62, 4, 4.5, MT, lo=1.2, hi=5.0)
            f(c, CX + side * 10, 62, FX, F_OUT)
        for side in (-1, 1):
            hl(c, CX + side * 12, CX + side * 20, 50, LT, 1)
    elif kind == "monocle":
        _lens(c, EYE_X[0], EYE_Y, 3, 3)
        for k in range(10):
            f(c, EYE_X[0] - 3 - k // 3, EYE_Y + 4 + k, MT, 4)


# =============================================================================
# BODY (in-room sprite, 40x80): skeleton -> skin -> outfit -> extras
# =============================================================================

BCX = 20
POSTURES = ["upright", "slouch", "wide", "hunched"]
BODY_W = {"slim": 5.5, "average": 6.5, "heavy": 8.0, "muscular": 8.5}
WAIST_W = {"slim": 4.0, "average": 4.6, "heavy": 7.0, "muscular": 5.2}
LIMB_R = {"slim": 1.3, "average": 1.5, "heavy": 2.0, "muscular": 2.1}


def skeleton(build: str, posture: str) -> dict:
    w = BODY_W[build]
    drop = {"upright": 0, "slouch": 1, "wide": 0, "hunched": 2}[posture]
    lean = {"upright": 0, "slouch": 1, "wide": 0, "hunched": 1}[posture]
    head = (BCX + lean, 11 + drop)
    sy = 20 + drop
    sh_w = w - (0.6 if posture in ("slouch", "hunched") else 0)
    sk = {
        "head": head, "head_r": (3.6 if build != "heavy" else 4.0, 4.8),
        "neck": (BCX + lean * 0.5, 17 + drop),
        "sh_l": (BCX - sh_w, sy), "sh_r": (BCX + sh_w, sy + (1 if posture == "slouch" else 0)),
        "waist_y": 36, "waist_w": WAIST_W[build], "hip_y": 41, "hip_w": WAIST_W[build] + 1.2,
        "r": LIMB_R[build],
    }
    spread = 2.5 if posture == "wide" else 0.0
    sk["el_l"] = (sk["sh_l"][0] - 1 - spread, sy + 11)
    sk["el_r"] = (sk["sh_r"][0] + 1 + spread, sy + 11)
    sk["wr_l"] = (sk["el_l"][0] - 0.5 - spread * 0.4, sy + 21)
    sk["wr_r"] = (sk["el_r"][0] + 0.5 + spread * 0.4, sy + 21)
    leg = 3.0 if build not in ("heavy",) else 3.6
    kn = 1 if posture == "hunched" else 0
    sk["hip_l"], sk["hip_r"] = (BCX - leg, 42), (BCX + leg, 42)
    sk["kn_l"] = (BCX - leg - spread * 0.6 + kn, 58)
    sk["kn_r"] = (BCX + leg + spread * 0.6 + kn, 58)
    sk["an_l"] = (BCX - leg - spread * 1.2, 74)
    sk["an_r"] = (BCX + leg + spread * 1.2, 74)
    return sk


def _limb(c, a, b, r, ramp, lo=1.4, hi=4.8, r2=None):
    c.capsule(a[0], a[1], b[0], b[1], r, ramp, lo=lo, hi=hi, r2=r2)


def _torso_poly(sk, extra=0.0, bottom=None, top_off=0):
    bottom = sk["hip_y"] if bottom is None else bottom
    (lx, ly), (rx, ry) = sk["sh_l"], sk["sh_r"]
    ww = sk["waist_w"] + extra
    hw = sk["hip_w"] + extra
    flare = max(0.0, (bottom - sk["hip_y"]) * 0.18) if bottom > sk["hip_y"] else 0.0
    return [(sk["neck"][0] - 2, ly - 2 + top_off), (lx - extra, ly + top_off), (lx - extra - 0.5, ly + 4),
            (BCX - ww, sk["waist_y"]), (BCX - hw - flare, bottom), (BCX + hw + flare, bottom),
            (BCX + ww, sk["waist_y"]), (rx + extra + 0.5, ry + 4), (rx + extra, ry + top_off),
            (sk["neck"][0] + 2, ry - 2 + top_off)]


def draw_body_base(b: Canvas, build: str, posture: str):
    sk = skeleton(build, posture)
    r = sk["r"]
    for side in ("l", "r"):
        _limb(b, sk["hip_" + side], sk["kn_" + side], r + 0.6, SK, r2=r + 0.2)
        _limb(b, sk["kn_" + side], sk["an_" + side], r + 0.2, SK, r2=r - 0.2)
        _limb(b, sk["sh_" + side], sk["el_" + side], r, SK)
        _limb(b, sk["el_" + side], sk["wr_" + side], r - 0.1, SK, r2=r - 0.4)
        wx, wy = sk["wr_" + side]
        b.sphere(wx, wy + 1.2, 1.3, 1.6, SK, lo=1.5, hi=4.5)  # hand
    b.shaded_poly(_torso_poly(sk), SK, top=4.4, bottom=2.6, left_bias=1.4, edge_dark=0.7)
    nx, ny = sk["neck"]
    for y in range(int(ny) - 1, int(ny) + 3):
        for x in range(int(nx) - 1, int(nx) + 2):
            f(b, x, y, SK, 2 if x > nx else 3)
    hx, hy = sk["head"]
    rx, ry = sk["head_r"]
    b.sphere(hx, hy, rx, ry, SK, lo=1.0, hi=5.6)
    f(b, hx + rx - 0.5, hy, FX, F_RIM)
    # Face at 3x: brow shadow, eyes with a lit white on the light side,
    # nose shadow, mouth, cheek and jaw shading.
    hl(b, hx - 2.5, hx + 2.5, hy - 0.5, SK, 2)
    f(b, hx - 2.5, hy + 0.5, FX, F_EYEW)
    f(b, hx - 1.5, hy + 0.5, FX, F_PUPIL)
    f(b, hx + 1.5, hy + 0.5, FX, F_PUPIL)
    f(b, hx + 0.5, hy + 1.5, SK, 2)       # nose shadow (key light from the left)
    hl(b, hx - 1, hx + 1, hy + 3, SK, 1)  # mouth
    f(b, hx + rx - 1.0, hy + 1.5, SK, 2)  # cheek in shadow
    hl(b, hx - 1, hx + 1, hy + ry - 0.4, SK, 2)  # under the jaw


def _boots(b, sk, ramp=LT, tall=False, steel=False):
    for side in ("l", "r"):
        ax, ay = sk["an_" + side]
        top = ay - (6 if tall else 2)
        for y in range(int(top), int(ay) + 3):
            for x in range(int(ax) - 2, int(ax) + 2 + (1 if y >= ay + 1 else 0)):
                f(b, x, y, ramp, 3 - (x > ax) - (y > ay + 1))
        hl(b, ax - 2, ax + 2, ay + 3, ramp, 0)  # sole
        if steel:
            f(b, ax + 2, ay + 2, MT, 5)


def _pants(b, sk, ramp, lo=1.2, hi=3.8, baggy=0.0):
    r = sk["r"]
    for side in ("l", "r"):
        _limb(b, sk["hip_" + side], sk["kn_" + side], r + 1.0 + baggy, ramp, lo, hi, r2=r + 0.7 + baggy)
        _limb(b, sk["kn_" + side], sk["an_" + side], r + 0.7 + baggy, ramp, lo, hi, r2=r + 0.6 + baggy)
    hl(b, BCX - sk["hip_w"], BCX + sk["hip_w"], sk["hip_y"], ramp, 1)
    vl(b, BCX, sk["hip_y"], sk["hip_y"] + 6, ramp, 1)


def _top(b, sk, ramp, length=None, extra=0.6, sleeves="long", lo=1.4, hi=4.4, open_front=False, inner=None):
    bottom = sk["hip_y"] + 1 if length is None else length
    b.shaded_poly(_torso_poly(sk, extra, bottom), ramp, top=hi, bottom=lo, left_bias=1.6, edge_dark=0.8)
    r = sk["r"]
    for side in ("l", "r"):
        if sleeves in ("long", "short"):
            _limb(b, sk["sh_" + side], sk["el_" + side], r + 0.7, ramp, lo, hi)
        if sleeves == "long":
            _limb(b, sk["el_" + side], sk["wr_" + side], r + 0.5, ramp, lo, hi, r2=r + 0.3)
    if open_front:
        for y in range(int(sk["sh_l"][1]) + 1, int(bottom)):
            f(b, BCX, y, inner if inner is not None else ramp, 2)
            f(b, BCX - 1, y, inner if inner is not None else ramp, 3)
    if length and length > sk["hip_y"] + 4:  # coat hem split + edge shading
        vl(b, BCX, sk["hip_y"], length - 1, ramp, 1)


def _belt(b, sk, ramp=LT, buckle=True, y=None):
    y = sk["waist_y"] + 3 if y is None else y
    hl(b, BCX - sk["waist_w"] - 1, BCX + sk["waist_w"] + 1, y, ramp, 2)
    if buckle:
        f(b, BCX, y, MT, 6)


def _grime(b, rng, n, box, ramps=((GR, 2), (GR, 1))):
    x0, y0, x1, y1 = box
    for _ in range(n):
        x, y = rng.randint(x0, x1), rng.randint(y0, y1)
        p = b.get(x, y)
        if p is not None and p[0] not in (SK, FX):
            f(b, x, y, *rng.choice(ramps))


def draw_body_outfit(b: Canvas, outfit: str, build: str, posture: str, rng):
    sk = skeleton(build, posture)
    hip, waist = sk["hip_y"], sk["waist_y"]
    if outfit == "corporate":
        _pants(b, sk, CA, 1.2, 3.6)
        _boots(b, sk, CC)
        _top(b, sk, CA, length=hip + 2, lo=1.4, hi=4.2)
        vl(b, BCX, sk["sh_l"][1] - 1, sk["sh_l"][1] + 6, CB, 6)  # shirt
        vl(b, BCX, sk["sh_l"][1] + 1, sk["sh_l"][1] + 8, CC, 2)   # tie
    elif outfit == "executive":
        _pants(b, sk, CA, 1.0, 3.2)
        _boots(b, sk, CC)
        _top(b, sk, CA, length=60, extra=1.2, lo=1.0, hi=4.0)  # long tailored coat
        hl(b, sk["neck"][0] - 2, sk["neck"][0] + 2, sk["neck"][1], CA, 4)  # high collar
        f(b, BCX + 1, waist - 4, MT, 6)
    elif outfit == "security":
        _pants(b, sk, CA, 1.2, 3.4)
        _boots(b, sk, LT, tall=True, steel=True)
        _top(b, sk, CA, lo=1.2, hi=3.8)
        for side in ("l", "r"):  # pauldrons
            x, y = sk["sh_" + side]
            b.sphere(x, y + 1, 3.0, 2.4, MT, lo=1.6, hi=5.8)
        _plate(b, BCX - 4, sk["sh_l"][1] + 2, BCX + 4, waist - 2, MT, lo=1.6, hi=4.6)
        for side in ("l", "r"):  # knee guards
            kx, ky = sk["kn_" + side]
            _plate(b, kx - 1, ky - 1, kx + 1, ky + 1, MT)
        _belt(b, sk, CB)
        f(b, BCX - 3, sk["sh_l"][1] + 4, GL, 5)
    elif outfit == "gang":
        _pants(b, sk, CB, 1.0, 3.4, baggy=0.3)
        _boots(b, sk, LT, tall=True)
        _top(b, sk, LT, length=hip + 1, lo=1.0, hi=4.0, open_front=True, inner=CB, sleeves="short")
        for side in ("l", "r"):  # bare forearms with tattoo ink on one
            if side == "l":
                for k in range(4):
                    x, y = sk["el_l"]
                    f(b, x - 0.5, y + 2 + k * 2, FX, F_INK)
        x, y = sk["sh_l"]
        b.sphere(x - 0.5, y, 3.2, 2.6, MT, lo=1.2, hi=5.6)  # spiked pauldron (one side)
        for k in range(3):
            f(b, x - 2 + k * 2, y - 3, MT, 6)
        hl(b, BCX + 2, BCX + 4, waist - 4, CC, 4)  # red rag
        vl(b, sk["kn_r"][0] + 1, sk["kn_r"][1] - 2, sk["kn_r"][1] + 2, CC, 3)
        _belt(b, sk, LT)
        _grime(b, rng, 8, (6, 20, 34, 72))
    elif outfit == "worker":
        _pants(b, sk, CC, 1.2, 3.6, baggy=0.4)
        _boots(b, sk, LT, tall=True, steel=True)
        _top(b, sk, CA, length=hip + 1, extra=1.2, lo=1.4, hi=4.0)  # padded jacket
        for side in ("l", "r"):  # hi-vis stripes on arms and chest
            ex, ey = sk["el_" + side]
            f(b, ex, ey - 1, CB, 6)
            f(b, ex, ey, CB, 5)
        hl(b, BCX - sk["waist_w"] - 1, BCX + sk["waist_w"] + 1, waist - 3, CB, 6)
        hl(b, BCX - sk["waist_w"] - 1, BCX + sk["waist_w"] + 1, waist - 2, CB, 4)
        _grime(b, rng, 14, (6, 22, 34, 76))
    elif outfit == "mercenary":
        _pants(b, sk, CA, 1.2, 3.4, baggy=0.3)
        _boots(b, sk, LT, tall=True, steel=True)
        _top(b, sk, CB, lo=1.2, hi=3.8)
        _plate(b, BCX - 5, sk["sh_l"][1] + 1, BCX + 5, waist, CA, lo=1.2, hi=3.6)  # carrier
        for k in range(3):
            _plate(b, BCX - 5 + k * 3, waist - 4, BCX - 3 + k * 3, waist - 1, CC, lo=1, hi=3)
        for k in range(14):  # sling
            f(b, sk["sh_l"][0] + k * 0.9, sk["sh_l"][1] + k * 1.4, LT, 2)
        for side in ("l", "r"):  # thigh pouch
            kx, ky = sk["kn_" + side]
            _plate(b, kx - 2, ky - 8, kx + 1, ky - 4, CC, lo=1, hi=3)
        _belt(b, sk, CC)
        _grime(b, rng, 10, (6, 22, 34, 76))
    elif outfit == "ripperdoc":
        _pants(b, sk, CB, 1.0, 3.2)
        _boots(b, sk, CC)
        _top(b, sk, CB, lo=1.2, hi=3.8, sleeves="short")  # rolled sleeves
        apron = [(BCX - 4, sk["sh_l"][1] + 3), (BCX + 4, sk["sh_l"][1] + 3), (BCX + sk["hip_w"] + 1.5, 60),
                 (BCX - sk["hip_w"] - 1.5, 60)]
        b.shaded_poly(apron, LT, top=4.0, bottom=1.8, left_bias=1.6, edge_dark=0.6)
        for k in range(5):
            f(b, BCX - 3 + k * 1.5, waist - 2, MT, 6 - (k % 2) * 2)  # tools in loops
        _grime(b, rng, 16, (10, 26, 30, 60), ramps=((BL, 2), (BL, 3), (GR, 2)))
        for side in ("l", "r"):  # cyber gloves
            wx, wy = sk["wr_" + side]
            b.sphere(wx, wy + 1.2, 1.5, 1.8, MT, lo=1.5, hi=5.5)
    elif outfit == "medic":
        _pants(b, sk, CA, 1.6, 4.2)
        _boots(b, sk, CC)
        _top(b, sk, CB, length=56, extra=0.8, lo=2.4, hi=5.6, open_front=True, inner=CA)  # dirty coat
        _grime(b, rng, 14, (8, 22, 32, 56), ramps=((GR, 3), (GR, 4), (BL, 3)))
        f(b, BCX + 3, sk["sh_l"][1] + 4, CC, 5)  # ID card
    elif outfit == "fixer":
        _pants(b, sk, CB, 1.0, 3.2)
        _boots(b, sk, LT)
        _top(b, sk, CA, length=64, extra=1.4, lo=1.0, hi=3.8, open_front=True, inner=CB)  # long coat
        for side in ("l", "r"):  # leather collar
            x, y = sk["sh_" + side]
            for k in range(3):
                f(b, (x + sk["neck"][0]) / 2 + (k if side == "r" else -k), y - 2 + k, LT, 4 - k)
        f(b, BCX, sk["sh_l"][1] + 3, MT, 6)  # chain glint
        f(b, sk["wr_r"][0], sk["wr_r"][1] + 1, MT, 6)  # rings
    elif outfit == "dealer":
        _pants(b, sk, CB, 1.0, 3.0)
        _boots(b, sk, LT)
        _top(b, sk, CA, length=56, extra=1.0, lo=1.0, hi=3.6)  # purple coat
        hx, hy = sk["head"]
        for x in range(int(hx) - 4, int(hx) + 5):  # hood down, bunched
            f(b, x, sk["neck"][1], CA, 3 - (x > hx))
        for k in range(3):
            hl(b, BCX - 2, BCX + 2, sk["sh_l"][1] + 3 + k * 2, MT, 5 - k)
    elif outfit == "civilian":
        _pants(b, sk, CC, 1.2, 3.8)
        _boots(b, sk, CB)
        _top(b, sk, CA, length=hip + 2, extra=0.8, lo=1.4, hi=4.2)  # hoodie
        hx, hy = sk["head"]
        hl(b, hx - 3, hx + 3, sk["neck"][1], CA, 2)
        hl(b, BCX - 3, BCX + 3, waist + 1, CA, 1)  # pouch pocket
    elif outfit == "performer":
        _pants(b, sk, CB, 1.0, 3.6)
        _boots(b, sk, LT, tall=True)
        _top(b, sk, CB, lo=1.4, hi=4.0, sleeves="none")
        for y in range(int(sk["sh_l"][1]), waist, 2):  # mesh
            hl(b, BCX - 3, BCX + 3, y, SK, 3)
        _top(b, sk, CA, length=waist - 3, extra=1.0, lo=1.6, hi=4.6, open_front=True, inner=CB)  # cropped jacket
        hl(b, BCX - sk["waist_w"] - 1, BCX - 1, waist - 3, GL, 3)
        hl(b, BCX + 1, BCX + sk["waist_w"] + 1, waist - 3, GL, 2)
    elif outfit == "technician":
        _pants(b, sk, CA, 1.2, 3.8)
        _boots(b, sk, LT, steel=True)
        _top(b, sk, CA, lo=1.4, hi=4.0)  # jumpsuit
        for side in (-1, 1):  # harness
            vl(b, BCX + side * 3, sk["sh_l"][1], waist + 2, LT, 2)
        _belt(b, sk, LT)
        for k in range(4):  # tool belt
            vl(b, BCX - 5 + k * 3, waist + 3, waist + 6, MT, 5 - k % 2)
        f(b, BCX - 3, sk["sh_l"][1] + 3, GL, 6)
        _grime(b, rng, 10, (6, 22, 34, 76))
    elif outfit == "military":
        _pants(b, sk, CA, 1.2, 3.6, baggy=0.3)
        _boots(b, sk, LT, tall=True)
        _top(b, sk, CA, lo=1.2, hi=3.8)
        for k in range(2):
            hl(b, BCX - sk["waist_w"], BCX + sk["waist_w"], sk["sh_l"][1] + 6 + k * 5, CB, 2)
        for side in (-1, 1):
            vl(b, BCX + side * 3, sk["sh_l"][1], waist, CB, 2)
        _belt(b, sk, CB)
        f(b, sk["sh_r"][0] - 1, sk["sh_r"][1] + 3, CC, 4)  # rank patch
    elif outfit == "patient":
        _top(b, sk, CA, length=56, extra=0.8, lo=3.0, hi=5.6, sleeves="short")  # gown
        for side in ("l", "r"):  # bare shins, socks
            ax, ay = sk["an_" + side]
            hl(b, ax - 2, ax + 2, ay + 2, CB, 5)
            hl(b, ax - 2, ax + 2, ay + 3, CB, 3)
        for k in range(10):  # IV lead + tape
            f(b, sk["wr_l"][0] - 1, sk["wr_l"][1] - k * 2, MT, 4)
        f(b, sk["el_l"][0], sk["el_l"][1] + 2, CB, 6)
        _grime(b, rng, 6, (8, 22, 32, 56), ramps=((BL, 3), (GR, 4)))
    elif outfit == "addict":
        _pants(b, sk, CC, 1.0, 3.4, baggy=0.4)
        _boots(b, sk, CB)
        _top(b, sk, CA, lo=2.0, hi=4.6, sleeves="none")  # stained tank
        _top(b, sk, CB, length=hip + 3, extra=1.0, lo=1.0, hi=3.2, open_front=True, inner=CA, sleeves="long")
        _grime(b, rng, 18, (6, 18, 34, 78), ramps=((GR, 2), (GR, 1), (BL, 2)))
        for k in range(3):  # holes / torn knee
            f(b, sk["kn_l"][0] + k - 1, sk["kn_l"][1], SK, 3)
    elif outfit == "elder":
        _pants(b, sk, CC, 1.2, 3.4, baggy=0.3)
        _boots(b, sk, LT)
        _top(b, sk, CA, length=58, extra=1.0, lo=1.2, hi=3.8)  # worn coat
        hx, hy = sk["head"]
        for x in range(int(hx) - 3, int(hx) + 4):  # scarf
            f(b, x, sk["neck"][1], CB, 4 - (x > hx))
            f(b, x, sk["neck"][1] + 1, CB, 3 - (x > hx))
        vl(b, BCX + 2, sk["neck"][1] + 1, sk["neck"][1] + 8, CB, 3)
        _grime(b, rng, 6, (8, 22, 32, 58))
    elif outfit == "netrunner":
        _pants(b, sk, CA, 1.0, 3.2)
        _boots(b, sk, CC)
        _top(b, sk, CA, lo=1.0, hi=3.6)
        for y in range(int(sk["sh_l"][1]) + 2, 70, 3):
            f(b, BCX, y, GL, 2)
        for side in ("l", "r"):
            x, y = sk["sh_" + side]
            f(b, x, y + 1, MT, 5)
            f(b, x, y + 2, GL, 4)


BODY_HAIR = HAIR


def draw_body_hair(b: Canvas, style: str, build: str, posture: str, rng):
    if style == "bald":
        return
    sk = skeleton(build, posture)
    hx, hy = sk["head"]
    rx, ry = sk["head_r"]
    def cap(top_extra=0.6, down=-1.0, side=1.0):
        for y in range(int(hy - ry - 2), int(hy + 2)):
            for x in range(int(hx - rx - 2), int(hx + rx + 3)):
                if ((x + 0.5 - hx) / (rx + side * 0.6)) ** 2 + ((y + 0.5 - hy + 0.4) / (ry + top_extra)) ** 2 <= 1 \
                        and y <= hy + down:
                    f(b, x, y, HR, 2 + (x < hx) - (rng.random() < 0.2))
    if style == "buzz":
        cap(0.2, -2.5)
    elif style in ("short", "messy", "slick", "receding", "undercut", "shaved", "topknot"):
        cap(0.8 if style != "messy" else 1.3, -2.0)
        if style == "topknot":
            b.sphere(hx, hy - ry - 1.5, 1.8, 1.5, HR, lo=1.0, hi=4.0)
        if style == "messy":
            for k in range(3):
                f(b, hx - 2 + k * 2, hy - ry - 1.5, HR, 3)
    elif style in ("long", "bob", "braids", "locs"):
        cap(1.0, -1.5)
        bottom = {"long": hy + 12, "bob": hy + 4, "braids": hy + 14, "locs": hy + 12}[style]
        for side in (-1, 1):
            x = hx + side * (rx + 0.5)
            for y in range(int(hy - 1), int(bottom)):
                f(b, x, y, HR, 2 if side < 0 else 1)
                f(b, x + side * 0.9, y, HR, 1)
    elif style == "tied":
        cap(0.5, -2.0)
        for y in range(int(hy - 1), int(hy + 7)):
            f(b, hx + rx + 0.8, y, HR, 1)
    elif style == "mohawk":
        for y in range(int(hy - ry - 3), int(hy - 1)):
            f(b, hx, y, HR, 3)
            f(b, hx + 1, y, HR, 2)


BODY_CYBER = ["arm_l", "arm_r", "legs", "eye", "face_plate", "spine", "shoulder", "hands", "jaw"]


def draw_body_cyber(b: Canvas, kind: str, build: str, posture: str):
    sk = skeleton(build, posture)
    r = sk["r"]
    if kind in ("arm_l", "arm_r"):
        side = kind[-1]
        _limb(b, sk["el_" + side], sk["wr_" + side], r + 0.4, MT, lo=1.6, hi=6.0)
        wx, wy = sk["wr_" + side]
        b.sphere(wx, wy + 1.2, 1.6, 1.8, MT, lo=1.6, hi=6.0)
        ex, ey = sk["el_" + side]
        f(b, ex, ey, GL, 3)
        f(b, ex, ey + 3, FX, F_OUT)
    elif kind == "legs":
        for side in ("l", "r"):
            kx, ky = sk["kn_" + side]
            _limb(b, sk["kn_" + side], sk["an_" + side], r + 0.6, MT, lo=1.4, hi=5.6)
            f(b, kx, ky, GL, 3)
    elif kind == "eye":
        hx, hy = sk["head"]
        f(b, hx + 1.5, hy + 0.5, GL, 6)
    elif kind == "face_plate":
        hx, hy = sk["head"]
        for y in range(int(hy - 3), int(hy + 4)):
            for x in range(int(hx) + 1, int(hx + sk["head_r"][0] + 1)):
                f(b, x, y, MT, 4 - (x > hx + 2))
        f(b, hx + 1.5, hy + 0.5, GL, 6)
    elif kind == "spine":
        for side in ("l", "r"):
            x, y = sk["sh_" + side]
            nx, ny = sk["neck"]
            b.line(nx, ny, x, y + 1, (MT, 4 if side == "l" else 2))
        f(b, sk["neck"][0], sk["neck"][1], GL, 4)
    elif kind == "shoulder":
        x, y = sk["sh_r"]
        b.sphere(x + 0.5, y + 1, 3.4, 3.0, MT, lo=1.4, hi=6.0)
        f(b, x + 1, y + 1, GL, 4)
    elif kind == "hands":
        for side in ("l", "r"):
            wx, wy = sk["wr_" + side]
            b.sphere(wx, wy + 1.2, 1.5, 1.8, MT, lo=1.6, hi=6.0)
    elif kind == "jaw":
        hx, hy = sk["head"]
        hl(b, hx - 1, hx + 3, hy + 3, MT, 4)
        hl(b, hx - 1, hx + 3, hy + 4, MT, 2)


BODY_ACC = ["backpack", "rifle", "holster", "blade", "toolbelt", "briefcase", "cane", "crutch", "cigarette",
            "hood", "helmet", "medkit", "datapad", "bandolier", "shoulder_lamp", "respirator", "cap", "beanie",
            "mask", "eyewear"]


def draw_body_acc(b: Canvas, kind: str, build: str, posture: str):
    sk = skeleton(build, posture)
    hx, hy = sk["head"]
    rx, ry = sk["head_r"]
    if kind == "backpack":
        for side in ("l", "r"):
            x, y = sk["sh_" + side]
            vl(b, x + (1 if side == "l" else -1), y, y + 12, LT, 2)
        _plate(b, int(sk["sh_r"][0]) + 1, int(sk["sh_r"][1]) + 1, int(sk["sh_r"][0]) + 3, int(sk["waist_y"]), CC, lo=1, hi=3)
    elif kind == "rifle":
        x0, y0 = sk["sh_r"][0] + 2, sk["sh_r"][1] - 3
        for k in range(26):
            f(b, x0 - k * 0.15, y0 + k, MT if k < 18 else LT, 3 if k % 5 else 5)
        f(b, x0 + 1, y0 + 12, MT, 2)
    elif kind == "holster":
        hx2 = BCX + sk["hip_w"] + 1
        _plate(b, int(hx2) - 1, sk["hip_y"] - 2, int(hx2) + 1, sk["hip_y"] + 5, LT, lo=1, hi=3)
        f(b, hx2, sk["hip_y"] - 3, MT, 4)
    elif kind == "blade":
        x, y = sk["hip_l"][0] - 3, sk["hip_y"] - 4
        for k in range(14):
            f(b, x + k * 0.1, y + k, MT, 6 if k > 3 else 2)
    elif kind == "toolbelt":
        for k in range(5):
            vl(b, BCX - 6 + k * 3, sk["waist_y"] + 3, sk["waist_y"] + 7, MT if k % 2 else LT, 4 if k % 2 else 2)
        _belt(b, sk, LT)
    elif kind == "briefcase":
        wx, wy = sk["wr_r"]
        _plate(b, int(wx) - 2, int(wy) + 2, int(wx) + 3, int(wy) + 7, CC, lo=1, hi=3)
        f(b, wx, wy + 1, MT, 5)
    elif kind in ("cane", "crutch"):
        wx, wy = sk["wr_r"]
        ax, ay = sk["an_r"]
        b.line(wx + 1, wy, ax + 3, ay + 3, (MT if kind == "crutch" else LT, 4))
        if kind == "crutch":
            hl(b, wx - 1, wx + 3, sk["el_r"][1], MT, 4)
    elif kind == "cigarette":
        wx, wy = sk["wr_l"]
        f(b, wx, wy + 2, CB, 6)
        f(b, wx, wy + 3, GL, 6)
    elif kind == "hood":
        for y in range(int(hy - ry - 1.5), int(hy + ry)):
            for x in range(int(hx - rx - 2), int(hx + rx + 3)):
                outer = ((x + 0.5 - hx) / (rx + 1.6)) ** 2 + ((y + 0.5 - hy) / (ry + 1.4)) ** 2 <= 1
                inner = ((x + 0.5 - hx) / (rx - 0.6)) ** 2 + ((y + 0.5 - hy - 1.2) / (ry - 1.0)) ** 2 <= 1
                if outer and not inner:
                    f(b, x, y, CC, 3 - (x > hx) - (y > hy + 2))
    elif kind == "helmet":
        b.sphere(hx, hy - 1.2, rx + 0.9, ry - 0.4, CA, lo=1.4, hi=5.0)
        hl(b, hx - rx, hx + rx, hy, MT, 5)
        hl(b, hx - rx + 1, hx + rx - 1, hy + 0.9, GL, 3)
    elif kind == "medkit":
        x, y = sk["hip_l"]
        _plate(b, int(x) - 3, int(y) - 1, int(x), int(y) + 3, CB, lo=3, hi=5)
        f(b, x - 1.5, y + 1, BL, 4)
    elif kind == "datapad":
        wx, wy = sk["wr_l"]
        _plate(b, int(wx) - 1, int(wy) - 2, int(wx) + 2, int(wy) + 2, MT)
        f(b, wx, wy, GL, 4)
    elif kind == "bandolier":
        for k in range(16):
            f(b, sk["sh_r"][0] - k * 0.8, sk["sh_r"][1] + k * 1.2, LT, 2)
            if k % 3 == 0:
                f(b, sk["sh_r"][0] - k * 0.8, sk["sh_r"][1] + k * 1.2 - 1, MT, 5)
    elif kind == "shoulder_lamp":
        x, y = sk["sh_l"]
        _plate(b, int(x) - 1, int(y) - 2, int(x) + 1, int(y), MT)
        f(b, x - 1, y - 1, GL, 7)
    elif kind == "respirator":
        hl(b, hx - 2, hx + 2, hy + 2.5, CB, 2)
        f(b, hx - 2, hy + 3.5, MT, 4)
        f(b, hx + 2, hy + 3.5, MT, 2)
    elif kind == "mask":
        # Cloth over the lower face (bandana, scarf, surgical mask).
        for y in range(int(hy + 1), int(hy + ry + 2)):
            for x in range(int(hx - rx), int(hx + rx + 1)):
                if ((x + 0.5 - hx) / (rx + 0.4)) ** 2 + ((y + 0.5 - hy) / (ry + 0.6)) ** 2 <= 1.15:
                    f(b, x, y, CC, 4 - (x > hx) - (y > hy + 2))
    elif kind == "eyewear":
        hl(b, hx - 2.5, hx + 2.5, hy + 0.5, CC, 0)
        f(b, hx - 1.5, hy + 0.5, FX, F_LENS)
    elif kind in ("cap", "beanie"):
        for y in range(int(hy - ry - 1), int(hy - 1)):
            for x in range(int(hx - rx - 1), int(hx + rx + 2)):
                if ((x + 0.5 - hx) / (rx + 0.6)) ** 2 + ((y + 0.5 - hy + 0.4) / (ry + 0.8)) ** 2 <= 1:
                    f(b, x, y, CC, 3 - (x > hx))
        if kind == "cap":
            hl(b, hx - rx - 1, hx + 1, hy - 1.5, CC, 1)


# =============================================================================
# GENERATION: parts -> per-slot atlases (cropped to bbox) + manifest
# =============================================================================

PORTRAIT_ORDER = ["hair_back", "body", "outfit", "head", "age", "nose", "mouth", "brows", "eyes", "facial_hair",
                  "scar", "tattoo", "makeup", "cyber_low", "piercing", "hair", "cyber", "accessory"]
BODY_ORDER = ["body", "outfit", "cyber", "hair", "acc"]


def build_parts():
    parts = {"portrait": {}, "body": {}}

    def put(view, slot, pid, fn, *args):
        cv = portrait() if view == "portrait" else body_canvas()
        fn(cv, *args)
        parts[view].setdefault(slot, {})[pid] = cv

    rng = lambda k: random.Random(hash(k) & 0xffff)  # noqa: E731
    # --- portrait ---
    for build in BUILDS:
        put("portrait", "body", build, draw_bust_base, build)
        for outfit in OUTFITS:
            put("portrait", "outfit", f"{outfit}_{build}", draw_outfit, outfit, build, random.Random(len(outfit) * 7 + len(build)))
    for shape in FACES:
        put("portrait", "head", shape, draw_head, shape)
        for kind in FACIAL_HAIR:
            put("portrait", "facial_hair", f"{kind}_{shape}", draw_facial_hair, kind, shape, random.Random(len(kind) + len(shape)))
    for age in AGES:
        put("portrait", "age", age, draw_age, age)
    for kind in NOSES:
        put("portrait", "nose", kind, draw_nose, kind)
    for expr in EXPRESSIONS:
        put("portrait", "mouth", expr, draw_mouth, expr)
        put("portrait", "brows", f"{expr}_thin", draw_brows, expr, False)
        put("portrait", "brows", f"{expr}_heavy", draw_brows, expr, True)
        for gaze in GAZES:
            put("portrait", "eyes", f"{expr}_{gaze}", draw_eyes, expr, gaze)
    for kind in SCARS:
        put("portrait", "scar", kind, draw_scar, kind)
    for kind in TATTOOS:
        put("portrait", "tattoo", kind, draw_tattoo, kind)
    for kind in MAKEUP:
        put("portrait", "makeup", kind, draw_makeup, kind)
    for kind in PIERCINGS:
        put("portrait", "piercing", kind, draw_piercing, kind)
    for kind in CYBER:
        put("portrait", "cyber_low" if kind in CYBER_LOW else "cyber", kind, draw_cyber, kind, random.Random(len(kind)))
    for style in HAIR:
        put("portrait", "hair", style, draw_hair, style, random.Random(len(style) * 13))
        if style in ("long", "tied", "locs", "braids"):
            put("portrait", "hair_back", style, draw_hair_back, style, random.Random(len(style)))
    for kind in ACCESSORIES:
        put("portrait", "accessory", kind, draw_accessory, kind, random.Random(len(kind) * 3))
    # --- body ---
    for build in BUILDS:
        for posture in POSTURES:
            key = f"{build}_{posture}"
            put("body", "body", key, draw_body_base, build, posture)
            for outfit in OUTFITS:
                put("body", "outfit", f"{outfit}_{key}", draw_body_outfit, outfit, build, posture, random.Random(len(outfit) + len(key)))
            for kind in BODY_CYBER:
                put("body", "cyber", f"{kind}_{key}", draw_body_cyber, kind, build, posture)
            for style in HAIR:
                put("body", "hair", f"{style}_{key}", draw_body_hair, style, build, posture, random.Random(len(style)))
            for kind in BODY_ACC:
                put("body", "acc", f"{kind}_{key}", draw_body_acc, kind, build, posture)
    return parts


def _bbox(cv):
    xs, ys = [], []
    for y in range(cv.h):
        for x in range(cv.w):
            if cv.px[y][x] is not None:
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return min(xs), min(ys), max(xs) - min(xs) + 1, max(ys) - min(ys) + 1


def generate():
    from PIL import Image
    parts = build_parts()
    out_dir = os.path.join(ROOT, "assets", "sprites", "characters2")
    os.makedirs(out_dir, exist_ok=True)
    manifest = {"version": 2, "sizes": {"portrait": [PW, PH], "body": [BW, BH]},
                "layer_order": {"portrait": PORTRAIT_ORDER, "body": BODY_ORDER},
                "eyes": {"y": EYE_Y, "x": list(EYE_X)}, "atlases": {}, "parts": {}}
    total = 0
    for view, slots in parts.items():
        manifest["parts"][view] = {}
        for slot, items in slots.items():
            boxes = []
            for pid, cv in items.items():
                bb = _bbox(cv)
                if bb:
                    boxes.append((pid, cv, bb))
            # shelf pack, max width 512
            x = y = row_h = 0
            placed = {}
            width = 512
            for pid, cv, (bx, by, bw, bh) in sorted(boxes, key=lambda t: -t[2][3]):
                if x + bw > width:
                    x, y, row_h = 0, y + row_h + 1, 0
                placed[pid] = (x, y, bw, bh, bx, by)
                x += bw + 1
                row_h = max(row_h, bh)
            height = max(1, y + row_h)
            atlas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
            px = atlas.load()
            for pid, cv, (bx, by, bw, bh) in boxes:
                ax, ay = placed[pid][0], placed[pid][1]
                for yy in range(bh):
                    for xx in range(bw):
                        c = cv.px[by + yy][bx + xx]
                        if c is not None:
                            px[ax + xx, ay + yy] = (c[0] * 16, c[1] * 32, 0, 255)
            name = f"{view}_{slot}.png"
            atlas.save(os.path.join(out_dir, name), optimize=True)
            manifest["atlases"][f"{view}/{slot}"] = "res://assets/sprites/characters2/" + name
            manifest["parts"][view][slot] = {pid: list(v) for pid, v in placed.items()}
            total += len(placed)
    path = os.path.join(ROOT, "data", "character_parts.json")
    with open(path, "w") as fh:
        json.dump(manifest, fh, separators=(",", ":"))
        fh.write("\n")
    print("character parts v2:", total, "in", len(manifest["atlases"]), "atlases")
    return parts
