"""HD portrait face layers (144x168): head, features, marks.

Logical coordinates follow the v2 96x112 design (CX 48, eyes at y 42);
the fine features are drawn on the HD grid (HCX 72, eyes at HD y 63).
"""
from __future__ import annotations

import math
import random

from .hdc_core import (S, SK, HR, MT, GL, IR, FX, BL, GR, F_OUT, F_EYEW, F_PUPIL, F_HI, F_INK, F_RIM,
                       HDCanvas, grid, f, hl, vl, P, HL, VL, LN, DOT, H, plate, clamp, stipple)

PW, PH = 96, 112
CX = 48
HCX = 72            # HD face centre column (continuous centre 72.75)
HEY = 63            # HD eye row
HEX = (62, 83)      # HD eye centres (left = lit side)
EYE_Y = 42
EYE_X = (41, 55)

FACES = {
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


def portrait() -> HDCanvas:
    return HDCanvas(PW, PH, dither=0.22)


def mirror(pts, cx=CX + 0.5):
    right = [(cx + dx, y) for dx, y in pts]
    left = [(cx - dx, y) for dx, y in reversed(pts)]
    return right + left


_MASKS: dict = {}


def head_mask(shape: str) -> set:
    """HD pixels of the head (cranium ellipse + jaw polygon)."""
    if shape in _MASKS:
        return _MASKS[shape]
    p = FACES[shape]
    out = set()
    for X, Y, x, y in grid(20, 8, 77, 50):
        if ((x + 0.5 - CX) / p["rx"]) ** 2 + ((y + 0.5 - p["cy"]) / p["ry"]) ** 2 <= 1.0:
            out.add((X, Y))
    jaw = mirror([(p["rx"] - 0.3, p["cy"])] + p["jaw"], CX)
    out |= set(map(tuple, poly_hd(jaw)))
    _MASKS[shape] = out
    return out


def poly_hd(pts):
    from .lib import poly_pixels
    return poly_pixels([(x * S, y * S) for x, y in pts])


def skin_light(x, y, shape, lo=0.7, hi=6.5):
    """Hard noir key light from the upper left (x, y logical cell coords)."""
    p = FACES[shape]
    nx = (x + 0.5 - CX) / (p["rx"] + 1.0)
    ny = (y + 0.5 - (p["cy"] + 6)) / (p["ry"] + 8)
    d = min(0.97, nx * nx + ny * ny)
    nz = math.sqrt(1.0 - d)
    L = (-0.74, -0.42, 0.53)
    i = clamp(nx * L[0] + ny * L[1] + nz * L[2], 0.0, 1.0) ** 1.25
    return lo + (hi - lo) * i


def _lx(X):
    return (X + 0.5) / S - 0.5


def draw_head(c: HDCanvas, shape: str):
    p = FACES[shape]
    mask = head_mask(shape)
    # Ears behind the silhouette: helix rim, inner fold, lobe; the far one in shadow.
    for side in (-1, 1):
        ex = CX + 0.5 + side * (p["rx"] + 0.6)
        for X, Y, x, y in grid(ex - 4, 35, ex + 4, 52):
            d = ((x + 0.5 - ex) / 2.7) ** 2 + ((y + 0.5 - 43.3) / 6.7) ** 2
            if d <= 1 and (X, Y) not in mask:
                v = (3.6 if side < 0 else 2.0) - (0.9 if d > 0.6 else 0)
                c.shade_px(X, Y, SK, v)
        ix = H(ex + (0.6 if side < 0 else -0.6))
        VL(c, ix, H(39.5), H(46.5), SK, 1 if side > 0 else 2)
        P(c, ix + side, H(41), SK, 4 if side < 0 else 2)
        P(c, ix, H(48), SK, 4 if side < 0 else 2)  # lobe catch
    for (X, Y) in mask:
        c.shade_px(X, Y, SK, skin_light(_lx(X), _lx(Y), shape))
    # Structure: cheekbones, hollows.
    hollow = p["hollow"]
    for (X, Y) in mask:
        x, y = _lx(X), _lx(Y)
        dx = x - CX
        g = sum(w * math.exp(-((dx - side * 11.5) ** 2) / 14.0 - ((y - 52) ** 2) / 22.0) for side, w in ((-1, 1.0), (1, 0.35)))
        if g > 0.05:
            c.shade_px(X, Y, SK, skin_light(x, y, shape) - (0.45 + hollow) * g)
    # Form shadow on the far edge and under the jaw (2 HD px deep, then 1 lighter).
    for (X, Y) in mask:
        if X > HCX:
            if (X + 1, Y) not in mask or (X + 2, Y) not in mask:
                P(c, X, Y, SK, 1)
            elif (X + 3, Y) not in mask:
                P(c, X, Y, SK, 2)
        if (X, Y + 1) not in mask and Y > H(55):
            P(c, X, Y, SK, 1)
        elif (X, Y + 2) not in mask and Y > H(57):
            P(c, X, Y, SK, 2)
    # Cheekbone highlight (lit side): a small soft cluster.
    for dX, dY in ((0, 0), (1, 0), (-1, 1), (0, 1), (1, 1), (0, 2)):
        X, Y = H(CX - 11) + dX, H(46) + dY
        if (X, Y) in mask:
            P(c, X, Y, SK, 6)
    # Broken rim light (screen glow) along the right edge.
    for (X, Y) in mask:
        if (X + 1, Y) not in mask and X > HCX and (H(22) < Y < H(34) or H(44) < Y < H(52)):
            P(c, X, Y, FX, F_RIM)
    # Eye sockets: the brow ridge shadow and the soft under-eye.
    for ex in HEX:
        for X in range(ex - 7, ex + 8):
            for Y, k in ((HEY - 5, 0.7), (HEY - 4, 1.5), (HEY - 3, 1.1)):
                if (X, Y) in mask:
                    c.shade_px(X, Y, SK, skin_light(_lx(X), _lx(Y), shape) - k * (1 - abs(X - ex) / 9))
        for X in range(ex - 4, ex + 5):
            Y = HEY + 4
            if (X, Y) in mask:
                c.shade_px(X, Y, SK, skin_light(_lx(X), _lx(Y), shape) - 0.9)
    # Philtrum: two soft ridges above the lip.
    VL(c, HCX - 1, H(55), H(57), SK, 4)
    VL(c, HCX + 1, H(55), H(57), SK, 3)
    P(c, HCX, H(56), SK, 2)
    if shape == "heavy":
        HL(c, H(CX - 7), H(CX + 7), H(68), SK, 2)  # chin fold
        HL(c, H(CX - 5), H(CX + 5), H(68) + 1, SK, 3)
    if shape in ("square", "heavy"):
        for Y in range(H(60), H(62)):
            P(c, H(CX - 12), Y, SK, 3)
            P(c, H(CX + 12), Y, SK, 1)
    # Chin highlight.
    for dX in (-2, -1, 0):
        X, Y = HCX + dX, H(p["jaw"][-1][1] - 2.5)
        if (X, Y) in mask:
            P(c, X, Y, SK, 5)


def draw_nose(c: HDCanvas, kind: str):
    top, tip = H(43), H(52)
    bend = 2 if kind == "broken" else 0
    for Y in range(top, tip):
        X = HCX + (bend if Y > H(47) else 0)
        P(c, X - 1, Y, SK, 5 if Y < tip - 3 else 6)   # bridge highlight (lit side)
        if Y > top + 3:
            P(c, X + 2, Y, SK, 3)                       # side plane
            P(c, X + 3, Y, SK, 2 if Y > H(47) else 3)   # shadow side
    if kind == "hooked":
        for Y in range(H(46), H(49)):
            P(c, HCX, Y, SK, 6)
            P(c, HCX + 1, Y, SK, 5)
        P(c, HCX + 3, H(49), SK, 1)
    w = {"broad": 6, "small": 3}.get(kind, 4)
    # Tip ball, alae and nostrils.
    for dX in range(-w + 1, w):
        P(c, HCX + dX, tip, SK, 4 if dX < 0 else 3)
    P(c, HCX - 1, tip - 1, SK, 6)
    P(c, HCX, tip - 1, SK, 5)
    P(c, HCX - 1, tip - 2, SK, 6)
    for side in (-1, 1):
        ax = HCX + side * w
        P(c, ax, tip, SK, 3 if side < 0 else 1)          # ala crease
        P(c, ax, tip - 1, SK, 3 if side < 0 else 2)
        P(c, ax - side, tip + 1, SK, 1)                   # nostril
        P(c, ax - side * 2, tip + 1, SK, 0)
    HL(c, HCX - w + 3, HCX + w - 3, tip + 1, SK, 3)       # columella
    HL(c, HCX - w + 2, HCX + w - 2, tip + 2, SK, 2)       # under-nose shadow
    if kind == "broken":
        P(c, HCX + 1, H(47), SK, 2)
        P(c, HCX + 2, H(47), SK, 2)
        P(c, HCX + 1, H(48), SK, 6)
    # Shadow cast to the right of the nose (key light from the left).
    for Y in range(tip - 5, tip + 2):
        P(c, HCX + w + 2, Y, SK, 2)
        if Y > tip - 3:
            P(c, HCX + w + 3, Y, SK, 2)


MOUTHS = {
    # (corner_left_dy, corner_right_dy, open_px, teeth)  [HD px]
    "neutral": (0, 0, 0, False),
    "angry": (1, 1, 0, False),
    "smirk": (0, -2, 0, False),
    "sad": (2, 2, 0, False),
    "fear": (0, 0, 3, False),
    "pain": (1, 1, 2, True),
}


def draw_mouth(c: HDCanvas, expr: str):
    ly, ry, opening, teeth = MOUTHS[expr]
    Y = H(59) + 1
    half = 7 if expr != "fear" else 6
    if opening:
        for yy in range(Y - 1, Y + opening + 1):
            inset = 1 if yy in (Y - 1, Y + opening) else 0
            HL(c, HCX - half + 1 + inset, HCX + half - 1 - inset, yy, FX, F_OUT)
        if teeth:
            HL(c, HCX - half + 2, HCX + half - 2, Y - 1, FX, F_EYEW)
            for X in range(HCX - half + 3, HCX + half - 2, 3):
                P(c, X, Y - 1, SK, 2)
            HL(c, HCX - half + 3, HCX + half - 3, Y + opening, FX, F_EYEW)
        HL(c, HCX - half + 1, HCX + half - 1, Y - 2, SK, 2)        # upper lip
        HL(c, HCX - half + 2, HCX + half - 2, Y + opening + 1, SK, 3)
        HL(c, HCX - half + 3, HCX + half - 3, Y + opening + 2, SK, 5)  # lower lip light
    else:
        # The lip line: darkest in the middle and at the corners.
        for X in range(HCX - half + 1, HCX + half):
            P(c, X, Y, SK, 0 if abs(X - HCX) < 3 else 1)
        for side, dy in ((-1, ly), (1, ry)):
            cx = HCX + side * half
            P(c, cx, Y + dy, SK, 1)
            if dy:
                P(c, cx - side, Y + (dy > 0) - (dy < 0) * 0, SK, 1)
            P(c, cx + side, Y + dy - (1 if dy < 0 else 0), SK, 3)  # corner pit
        if ry < 0:
            P(c, HCX + half + 2, Y - 2, SK, 3)  # smirk dimple
            P(c, HCX + half + 2, Y - 3, SK, 3)
        # Upper lip: a cupid's bow in a slightly darker tone.
        HL(c, HCX - half + 2, HCX + half - 2, Y - 1, SK, 3)
        HL(c, HCX - 2, HCX + 2, Y - 2, SK, 3)
        P(c, HCX, Y - 2, SK, 4)
        # Lower lip: lit fullness and the shadow beneath.
        HL(c, HCX - half + 3, HCX + half - 3, Y + 1, SK, 4)
        HL(c, HCX - half + 4, HCX + 1, Y + 2, SK, 5)
        P(c, HCX - 2, Y + 1, SK, 6)
        HL(c, HCX - 3, HCX + 3, Y + 3, SK, 3)
        HL(c, HCX - 2, HCX + 2, Y + 4, SK, 2)
    if expr == "angry":
        HL(c, HCX - 4, HCX + 4, Y + 5, SK, 3)
        P(c, HCX - half - 2, Y - 2, SK, 3)
        P(c, HCX + half + 2, Y - 2, SK, 2)
    if expr == "sad":
        P(c, HCX - half - 2, Y + 3, SK, 3)
        P(c, HCX + half + 2, Y + 3, SK, 2)


BROWS = {
    "neutral": (37, 37, 0),
    "angry": (39, 36, 0),
    "smirk": (37, 37, -2),
    "sad": (35, 38, 0),
    "fear": (35, 36, 0),
    "pain": (39, 37, 0),
}


def draw_brows(c: HDCanvas, expr: str, heavy: bool):
    inner, outer, lift = BROWS[expr]
    for side, ex in ((-1, HEX[0]), (1, HEX[1])):
        x_in = ex - side * 1 + (4 if side < 0 else -4)
        x_out = ex + side * 8
        lo_, hi_ = min(x_in, x_out), max(x_in, x_out)
        for X in range(lo_, hi_ + 1):
            t = abs(X - x_in) / max(1, abs(x_out - x_in))
            yl = inner + (outer - inner) * t + (lift if side > 0 else 0)
            # A gentle arch peaking two thirds of the way out.
            Y = H(yl + 0.5) - (1 if 0.45 < t < 0.85 else 0)
            core = 3 if 0.15 < t < 0.7 else 2
            P(c, X, Y, HR, core)
            P(c, X, Y + 1, HR, 1)
            if heavy or t < 0.55:
                P(c, X, Y - 1, HR, 2 if heavy else 1)
            if heavy and t < 0.8:
                P(c, X, Y + 2, HR, 1)
        # A few hairs at the inner head flick upward.
        P(c, x_in, H(inner + 0.5) - 2, HR, 1)
    if expr in ("angry", "pain"):
        for dx in (-2, 2):
            VL(c, HCX + dx, H(38), H(40) + 1, SK, 2)  # glabella crease


def draw_eyes(c: HDCanvas, expr: str, gaze: str):
    """Almond eyes ~11x5 HD px: shaded sclera, a round 5 px iris with a dark
    limbal ring, pupil, two catch-lights, a lash line thickening to the
    outer corner, the lid crease, a lit lower lid and the tear duct."""
    wide = expr == "fear"
    squint = expr in ("angry", "pain")
    heavy_lid = expr == "sad"
    ox = {"center": 0, "left": -2, "right": 2, "closed": 0}[gaze]
    for i, ex in enumerate(HEX):
        lit = i == 0
        outer = -1 if i == 0 else 1
        if gaze == "closed":
            for k, X in enumerate(range(ex - 5, ex + 6)):
                sag = 1 if abs(X - ex) < 4 else 0
                P(c, X, HEY + sag, SK, 0)
            P(c, ex + outer * 6, HEY - 1, SK, 0)
            HL(c, ex - 4, ex + 4, HEY - 1, SK, 4 if lit else 3)
            HL(c, ex - 3, ex + 3, HEY - 3, SK, 3 if lit else 2)   # crease
            HL(c, ex - 3, ex + 3, HEY + 2, SK, 3 if lit else 2)
            continue
        h = 6 if wide else (3 if squint else 5)
        top = HEY - h // 2
        rows = list(range(top, top + h))
        half_w = 5
        # Sclera: almond (narrower on the first and last rows), shaded under the lid.
        for k, Y in enumerate(rows):
            edge = 2 if (k == 0 or k == h - 1) else (1 if (k == 1 or k == h - 2) and h > 4 else 0)
            x0, x1 = ex - half_w + edge, ex + half_w - edge
            for X in range(x0, x1 + 1):
                P(c, X, Y, FX, F_EYEW)
            far = x1 if lit else x0
            P(c, far, Y, SK, 4 if lit else 3)
            if k == 0:
                HL(c, x0, x1, Y, SK, 4 if lit else 3)  # lid shadow on the white
        # Iris: 5 wide, round, dark limbal ring, lighter lower half.
        ix = ex + ox
        icy = HEY + (0 if not wide else 0)
        for Y in rows:
            for dx in range(-2, 3):
                dd = (dx / 2.6) ** 2 + ((Y - icy) / 2.6) ** 2
                if dd > 1.0:
                    continue
                ring = dd > 0.55
                shade = 1 if ring else (4 if Y > icy else 3)
                P(c, ix + dx, Y, IR, shade + (1 if lit and not ring else 0))
        for py in ([icy] if h < 6 else [icy - 1, icy]):
            P(c, ix, py, FX, F_PUPIL)
            P(c, ix + 1, py, FX, F_PUPIL)
        # Upper lid: lash line thickening outward, the crease above, a flick.
        lash_y = top - 1
        HL(c, ex - half_w + 1, ex + half_w - 1, lash_y, SK, 0)
        for d in range(3):
            P(c, ex + outer * (half_w - 1 + d), lash_y + (1 if d == 0 else 0) - (d == 2), SK, 0)
        P(c, ex + outer * (half_w - 2), lash_y - 1, SK, 0)
        HL(c, ex - 4, ex + 4, top - 3, SK, 3 if lit else 2)  # crease
        HL(c, ex - 3, ex + 3, top - 2, SK, 5 if lit else 3)  # lid fold catches light
        if heavy_lid:
            HL(c, ex - half_w + 1, ex + half_w - 1, top, SK, 2)
            HL(c, ex - half_w + 2, ex + half_w - 2, top + 1, SK, 3)
        elif not squint:
            HL(c, ix - 1, ix + 1, top, IR, 0)
        if squint:
            HL(c, ex - half_w + 1, ex + half_w - 1, top + h, SK, 2)
            HL(c, ex - half_w + 2, ex + half_w - 2, top - 1, SK, 0)
        # Lower lid: lit rim, waterline, the tear duct.
        HL(c, ex - 3, ex + 3, top + h, SK, 5 if lit else 3)
        P(c, ex - outer * half_w, HEY, BL, 4)
        P(c, ex + outer * (half_w - 1), top + h, SK, 3)
        # Catch-lights last.
        P(c, ix - 1, icy - 1, FX, F_HI)
        if h > 3:
            P(c, ix + 1, icy + 1, IR, 6)


def draw_age(c: HDCanvas, age: str):
    if age == "young":
        return
    # Forehead lines, crow's feet, nasolabial folds.
    HL(c, H(CX - 7), H(CX - 2), H(31), SK, 4)
    HL(c, H(CX - 6), H(CX - 2), H(31) + 1, SK, 3)
    HL(c, H(CX + 1), H(CX + 5), H(31), SK, 3)
    for side, ex in ((-1, HEX[0]), (1, HEX[1])):
        ox = ex + side * 8
        for k in range(3):
            P(c, ox + side * (k // 2), HEY - 1 + k, SK, 3)
        for k in range(7):
            P(c, HCX + side * (8 + k // 2), H(53.5) + k, SK, 3 if side < 0 else 2)
            if k > 2:
                P(c, HCX + side * (8 + k // 2) - side, H(53.5) + k, SK, 4 if side < 0 else 3)
    if age == "old":
        HL(c, H(CX - 9), H(CX - 3), H(28), SK, 4)
        HL(c, H(CX + 2), H(CX + 7), H(28), SK, 3)
        HL(c, H(CX - 5), H(CX + 4), H(34), SK, 4)
        for side, ex in ((-1, HEX[0]), (1, HEX[1])):
            HL(c, ex - 4, ex + 3, HEY + 5, SK, 3)   # under-eye bags
            HL(c, ex - 3, ex + 2, HEY + 6, SK, 4 if side < 0 else 3)
            P(c, ex + side * 8, HEY - 2, SK, 3)
            P(c, ex + side * 9, HEY + 3, SK, 3)
            for k in range(8):
                P(c, HCX + side * (11 + k // 4), H(60) + k, SK, 3)   # jowl lines
        VL(c, HCX - 4, H(67), H(69) + 1, SK, 3)   # neck cords
        VL(c, HCX + 4, H(67), H(69) + 1, SK, 2)
        for k in range(4):  # age spots
            P(c, HCX - 14 + k * 3, H(30) + (k % 2) * 4, SK, 3)


FACIAL_HAIR = ["stubble", "beard", "goatee", "mustache", "full", "chops"]


def draw_facial_hair(c: HDCanvas, kind: str, shape: str, rng):
    mask = head_mask(shape)
    p = FACES[shape]
    chin = p["jaw"][-1][1]
    mouth_box = lambda X, Y: abs(X - HCX) <= 8 and H(57) <= Y <= H(61) + 1  # noqa: E731
    if kind == "stubble":
        for (X, Y) in mask:
            if Y >= H(55) and not mouth_box(X, Y):
                dens = 0.22 + 0.3 * min(1.0, (Y - H(55)) / 14.0)
                if stipple(X, Y, dens):
                    P(c, X, Y, HR, 1 + stipple(X + 2, Y + 1, 0.3))
    elif kind in ("beard", "full"):
        for (X, Y) in mask:
            y = _lx(Y)
            if y >= 53 and (y >= 57 or abs(X - HCX) > 13 or kind == "full") and not mouth_box(X, Y):
                v = 1 + (rng.random() < 0.35) + (2 if X < HCX - 6 and rng.random() < 0.3 else 0)
                # Strand direction: short vertical runs read as hair, not noise.
                if (X + Y // 3) % 3 == 0:
                    v += 1
                P(c, X, Y, HR, v)
        extra = 6 if kind == "full" else 3
        for X in range(HCX - 13, HCX + 14):
            for Y in range(H(chin), H(chin) + extra - abs(X - HCX) // 4):
                P(c, X, Y, HR, 1 if X > HCX else 2 + ((X + Y) % 3 == 0))
        if kind == "full":  # mustache joins
            for X in range(HCX - 8, HCX + 9):
                P(c, X, H(57), HR, 2 if X < HCX else 1)
    elif kind == "goatee":
        for Y in range(H(60) + 1, H(chin) + 4):
            for X in range(HCX - 4, HCX + 5):
                P(c, X, Y, HR, 1 if X > HCX else 2 + ((X + Y) % 3 == 0))
        HL(c, HCX - 7, HCX + 7, H(57), HR, 1)
        HL(c, HCX - 6, HCX + 6, H(57) - 1, HR, 2)
    elif kind == "mustache":
        HL(c, HCX - 7, HCX + 7, H(57), HR, 1)
        HL(c, HCX - 6, HCX + 6, H(57) - 1, HR, 2)
        HL(c, HCX - 4, HCX + 4, H(57) - 2, HR, 2)
        for side in (-1, 1):
            P(c, HCX + side * 8, H(57) + 1, HR, 1)
            P(c, HCX + side * 9, H(57) + 2, HR, 1)
    elif kind == "chops":
        for (X, Y) in mask:
            y = _lx(Y)
            if 44 <= y <= 60 and abs(_lx(X) - CX) >= p["rx"] - 4:
                if stipple(X, Y, 0.75):
                    P(c, X, Y, HR, 1 + stipple(X + 1, Y + 2, 0.4) + ((X + Y) % 3 == 0))


SCARS = ["cheek", "brow", "lip", "slash", "burn", "stitched"]


def draw_scar(c: HDCanvas, kind: str):
    if kind == "cheek":
        for k in range(11):
            X, Y = H(CX - 13) + k // 2, H(46) + k
            P(c, X, Y, SK, 6)
            P(c, X + 1, Y, SK, 3)
            P(c, X - 1, Y, SK, 4)
    elif kind == "brow":
        for k in range(9):
            X, Y = HEX[1] + 1 + k // 3, H(33.5) + k
            P(c, X, Y, SK, 6)
            P(c, X + 1, Y, SK, 2)
        for X in range(HEX[1], HEX[1] + 3):  # the gap in the brow
            P(c, X, H(37.5), SK, 4)
    elif kind == "lip":
        VL(c, HCX + 3, H(56), H(62) + 1, SK, 6)
        VL(c, HCX + 4, H(56) + 1, H(62), SK, 3)
    elif kind == "slash":
        for k in range(39):
            X, Y = H(CX + 12) - k, H(30) + k
            P(c, X, Y, SK, 6 if k % 4 else 2)
            P(c, X + 1, Y, SK, 3)
            if k % 6 == 0:
                P(c, X - 1, Y + 1, SK, 4)
    elif kind == "burn":
        rng = random.Random(7)
        blot = {}
        for X, Y, x, y in grid(CX + 6, 40, CX + 17, 62):
            if ((x - CX - 11) / 6) ** 2 + ((y - 51) / 11) ** 2 < 1:
                k = (X // 3, Y // 3)  # scar tissue in clusters, not noise
                if k not in blot:
                    blot[k] = rng.choice((2, 3, 5, 6, None))
                if blot[k] is not None:
                    P(c, X, Y, SK, blot[k] - ((X + Y) % 3 == 0))
    elif kind == "stitched":
        for k in range(21):
            P(c, H(CX - 15) + k, H(36) + k // 5, SK, 2)
        for k in range(0, 21, 3):
            P(c, H(CX - 15) + k, H(36) + k // 5 - 2, FX, F_OUT)
            P(c, H(CX - 15) + k, H(36) + k // 5 - 1, FX, F_OUT)
            P(c, H(CX - 15) + k, H(36) + k // 5 + 1, FX, F_OUT)
            P(c, H(CX - 15) + k, H(36) + k // 5 + 2, FX, F_OUT)


TATTOOS = ["neck_code", "cheek_lines", "tear", "forehead_glyph", "jaw_ink", "gang_throat"]


def draw_tattoo(c: HDCanvas, kind: str):
    ink = (FX, F_INK)
    if kind == "neck_code":  # a barcode
        for k in range(14):
            if k % 3 != 2:
                VL(c, H(CX + 5) + k, H(72), H(74.5) + (k % 2) * 2, *ink)
        for k in range(0, 12, 2):
            P(c, H(CX + 5) + k, H(76), *ink)
    elif kind == "cheek_lines":
        for k in range(3):
            HL(c, H(CX + 9), H(CX + 13.5) - k, H(49) + k * 3, *ink)
    elif kind == "tear":
        X, Y = HEX[0] - 2, HEY + 6
        for (dx, dy) in ((0, 0), (0, 1), (-1, 2), (0, 2), (1, 2), (-1, 3), (0, 3), (1, 3), (0, 4)):
            P(c, X + dx, Y + dy, *ink)
    elif kind == "forehead_glyph":
        X, Y = HCX, H(25)
        for (dx, dy) in ((0, 0), (0, 1), (-1, 2), (1, 2), (-2, 3), (2, 3), (0, 3), (0, 4), (0, 5), (-3, 5), (3, 5),
                         (-1, 6), (1, 6)):
            P(c, X + dx, Y + dy, *ink)
    elif kind == "jaw_ink":
        for k in range(15):
            P(c, H(CX - 15) + k, H(56) + k // 2, *ink)
            if k % 3 == 0:
                P(c, H(CX - 15) + k, H(56) + k // 2 - 1, *ink)
                P(c, H(CX - 15) + k, H(56) + k // 2 - 2, *ink)
    elif kind == "gang_throat":
        for k in range(-8, 9):
            P(c, HCX + k, H(75) - abs(k) // 2, BL, 3)
            P(c, HCX + k, H(75) - abs(k) // 2 + 1, BL, 2)
        VL(c, HCX, H(75), H(76) + 2, BL, 3)


PIERCINGS = ["brow_ring", "nose_ring", "lip_ring", "ear_gauges", "septum", "studs"]


def _ring(c, X, Y, r=1):
    for (dx, dy) in ((0, -r), (r, 0), (0, r), (-r, 0)):
        P(c, X + dx, Y + dy, MT, 6 if dx <= 0 and dy <= 0 else 3)


def draw_piercing(c: HDCanvas, kind: str):
    if kind == "brow_ring":
        _ring(c, HEX[1] + 7, H(37))
    elif kind == "nose_ring":
        _ring(c, HCX - 5, H(54))
    elif kind == "lip_ring":
        _ring(c, HCX + 4, H(61) + 1)
    elif kind == "septum":
        HL(c, HCX - 1, HCX + 1, H(55) + 1, MT, 5)
        P(c, HCX - 2, H(55), MT, 6)
        P(c, HCX + 2, H(55), MT, 3)
    elif kind == "ear_gauges":
        for side in (-1, 1):
            ex = H(CX + 0.5 + side * 18)
            for dx in range(-2, 3):
                for dy in range(-2, 3):
                    d = dx * dx + dy * dy
                    if 2 <= d <= 5:
                        P(c, ex + dx, H(49) + dy, MT, 5 if (side < 0 and dx <= 0) else 3)
                    elif d < 2:
                        P(c, ex + dx, H(49) + dy, FX, F_OUT)
    elif kind == "studs":
        for (X, Y) in ((H(CX - 18), H(41)), (H(CX - 18), H(44)), (H(CX - 17), H(47))):
            P(c, X, Y, MT, 7)
            P(c, X + 1, Y + 1, MT, 3)


MAKEUP = ["liner", "lipstick", "smudge", "warpaint"]


def draw_makeup(c: HDCanvas, kind: str):
    if kind == "liner":
        for i, ex in enumerate(HEX):
            outer = -1 if i == 0 else 1
            Y = HEY - 3
            HL(c, ex - 5, ex + 5, Y - 1, FX, F_OUT)
            HL(c, ex - 5, ex + 5, Y, FX, F_OUT)
            for d in range(4):  # the wing
                P(c, ex + outer * (6 + d), Y - 1 - d // 2, FX, F_OUT)
    elif kind == "lipstick":
        HL(c, HCX - 6, HCX + 6, H(59) - 1, BL, 4)
        HL(c, HCX - 6, HCX + 6, H(59) + 2, BL, 5)
        HL(c, HCX - 5, HCX + 5, H(59) + 3, BL, 4)
        P(c, HCX - 3, H(59) + 2, BL, 6)
    elif kind == "smudge":
        for ex in HEX:
            for X in range(ex - 5, ex + 6):
                P(c, X, HEY + 4, GR, 1)
                if X % 2:
                    P(c, X, HEY + 5, GR, 2)
                if X % 3 == 0:
                    P(c, X, HEY + 6, GR, 2)
    elif kind == "warpaint":
        for X, Y, x, y in grid(EYE_X[0] - 5, EYE_Y - 4, EYE_X[1] + 6, EYE_Y + 6):
            if (x - CX) % 9 < 2.0 and abs(x - CX) > 4:
                P(c, X, Y, FX, F_INK)
