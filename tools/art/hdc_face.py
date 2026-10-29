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
    return HDCanvas(PW, PH, dither=0.0)


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


def cel(v: float, cuts=((3.7, 5), (2.2, 4)), floor=3) -> int:
    """Quantises a continuous light value into flat cel bands."""
    for t, s in cuts:
        if v >= t:
            return s
    return floor


def draw_head(c: HDCanvas, shape: str):
    """Cel-shaded head: a flat lit plane, one form-shadow band on the far
    side and under the cheekbone, a darker core at the far edge. The ink
    contour (characters_hd.ink_outline) closes the silhouette."""
    p = FACES[shape]
    mask = head_mask(shape)
    # Ears: flat plane, the inner fold drawn as one dark line and a lobe catch.
    for side in (-1, 1):
        ex = CX + 0.5 + side * (p["rx"] + 0.6)
        for X, Y, x, y in grid(ex - 4, 35, ex + 4, 52):
            d = ((x + 0.5 - ex) / 2.7) ** 2 + ((y + 0.5 - 43.3) / 6.7) ** 2
            if d <= 1 and (X, Y) not in mask:
                P(c, X, Y, SK, (4 if side < 0 else 3) - (d > 0.62))
        ix = H(ex + (0.6 if side < 0 else -0.6))
        VL(c, ix, H(39.5), H(46.5), SK, 2 if side < 0 else 1)
        P(c, ix + side, H(40), SK, 2 if side < 0 else 1)
        P(c, ix, H(48), SK, 5 if side < 0 else 3)
    hollow = p["hollow"]
    for (X, Y) in mask:
        x, y = _lx(X), _lx(Y)
        nx = (x + 0.5 - CX) / p["rx"]
        ny = (y + 0.5 - p["cy"]) / (p["ry"] + 6)
        # Mostly lit: the shadow band only wraps the far side of the face
        # and dips under the far cheekbone and the jaw.
        dark = nx + 0.18 * ny * ny + 0.35 * max(0.0, ny - 0.55)
        cheek = math.exp(-((x - CX - 11.0) ** 2) / 10.0 - ((y - 53) ** 2) / 14.0) * (0.25 + hollow * 0.4)
        near_cheek = math.exp(-((x - CX + 11.0) ** 2) / 10.0 - ((y - 53) ** 2) / 14.0) * hollow * 0.5
        d = dark + cheek + near_cheek
        P(c, X, Y, SK, 5 if d < 0.52 else (4 if d < 0.86 else 3))
    # Far-side core shadow (3 px) and a light terminator under the jaw.
    for (X, Y) in mask:
        if X > HCX + 4 and ((X + 2, Y) not in mask or (X + 3, Y) not in mask):
            P(c, X, Y, SK, 2 if (X + 1, Y) not in mask else 3)
        if Y > H(56) and ((X, Y + 1) not in mask or (X, Y + 2) not in mask):
            P(c, X, Y, SK, 3)
    # Cheekbone light on the lit side and the forehead sheen.
    for X, Y in ((H(CX - 11) + dx, H(46) + dy) for dx in range(-1, 3) for dy in range(0, 2)):
        if (X, Y) in mask:
            P(c, X, Y, SK, 6)
    for X in range(HCX - 9, HCX - 2):
        if (X, H(29)) in mask:
            P(c, X, H(29), SK, 6)
    # Chin: one light step, one shadow step.
    chin = H(p["jaw"][-1][1])
    HL(c, HCX - 3, HCX, chin - 3, SK, 6)
    HL(c, HCX - 2, HCX + 3, chin - 1, SK, 4)
    if shape == "heavy":
        HL(c, H(CX - 6), H(CX + 6), H(68), SK, 3)
    if shape in ("square", "heavy"):
        VL(c, H(CX + 12), H(59), H(62), SK, 3)


def draw_nose(c: HDCanvas, kind: str):
    """Read as light and shadow, not lines: a lit bridge, the shadow plane
    on the far side ending in a nostril, and the shadow it casts."""
    top, tip = H(44), H(52)
    bend = 2 if kind == "broken" else 0
    w = {"broad": 5, "small": 2, "hooked": 3}.get(kind, 3)
    for Y in range(top, tip):
        X = HCX + (bend if Y > H(48) else 0)
        if Y > top + 2:
            P(c, X + 2, Y, SK, 3)                      # shadow plane
        if Y > tip - 6:
            P(c, X - 1, Y, SK, 6)                      # bridge light
    if kind == "hooked":
        VL(c, HCX + 1, H(46), H(48), SK, 3)
        P(c, HCX, H(47), SK, 6)
    HL(c, HCX - w + 1, HCX + w, tip, SK, 3)            # under-tip shadow
    P(c, HCX - 1, tip - 1, SK, 6)                      # tip highlight
    P(c, HCX + w, tip - 1, SK, 2)                      # far nostril wing
    P(c, HCX + w - 1, tip, SK, 1)                      # nostril
    P(c, HCX - w, tip, SK, 2)                          # near nostril
    for Y in range(tip - 3, tip + 2):                  # cast shadow to the right
        P(c, HCX + w + 2, Y, SK, 3)
    HL(c, HCX - 1, HCX + 3, tip + 1, SK, 3)
    if kind == "broken":
        P(c, HCX + 1, H(48), SK, 2)
        P(c, HCX + 2, H(48), SK, 2)


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
    """A clean lip line in ink, a darker upper lip, a lit lower lip and the
    shadow under it (lipstick recolours the lips, see draw_makeup)."""
    ly, ry, opening, teeth = MOUTHS[expr]
    Y = H(59) + 1
    half = 6 if expr != "fear" else 5
    if opening:
        for yy in range(Y - 1, Y + opening + 1):
            inset = 1 if yy in (Y - 1, Y + opening) else 0
            HL(c, HCX - half + 1 + inset, HCX + half - 1 - inset, yy, FX, F_OUT)
        if teeth:
            HL(c, HCX - half + 2, HCX + half - 2, Y - 1, FX, F_EYEW)
            HL(c, HCX - half + 3, HCX + half - 3, Y + opening, FX, F_EYEW)
        HL(c, HCX - half + 1, HCX + half - 1, Y - 2, SK, 2)
        HL(c, HCX - half + 2, HCX + half - 2, Y + opening + 1, SK, 4)
        HL(c, HCX - half + 3, HCX - 1, Y + opening + 2, SK, 5)
        HL(c, HCX - 2, HCX + 3, Y + opening + 3, SK, 3)
        return
    for X in range(HCX - half + 1, HCX + half):
        P(c, X, Y, SK, 0 if abs(X - HCX) < half - 1 else 1)
    for side, dy in ((-1, ly), (1, ry)):
        cx = HCX + side * half
        P(c, cx, Y + dy, SK, 1)
        if dy:
            P(c, cx - side, Y + (1 if dy > 0 else 0), SK, 1)
    if ry < 0:
        P(c, HCX + half + 1, Y - 2, SK, 3)
    HL(c, HCX - half + 2, HCX + half - 2, Y - 1, SK, 3)   # upper lip
    P(c, HCX - 1, Y - 2, SK, 3)
    P(c, HCX + 1, Y - 2, SK, 3)
    HL(c, HCX - half + 2, HCX + half - 2, Y + 1, SK, 4)   # lower lip
    HL(c, HCX - 3, HCX, Y + 1, SK, 6)                     # its highlight
    HL(c, HCX - 2, HCX + 3, Y + 3, SK, 3)                 # shadow under it
    if expr == "angry":
        HL(c, HCX - 3, HCX + 3, Y + 4, SK, 3)
    if expr == "sad":
        P(c, HCX - half - 1, Y + 3, SK, 3)
        P(c, HCX + half + 1, Y + 3, SK, 3)


BROWS = {
    "neutral": (37, 37, 0),
    "angry": (39, 36, 0),
    "smirk": (37, 37, -2),
    "sad": (35, 38, 0),
    "fear": (35, 36, 0),
    "pain": (39, 37, 0),
}


def draw_brows(c: HDCanvas, expr: str, heavy: bool):
    """Crisp, tapered brows: darkest at the core, thinning to a point at
    the outer end, a lit edge on top when heavy."""
    inner, outer, lift = BROWS[expr]
    for side, ex in ((-1, HEX[0]), (1, HEX[1])):
        x_in = ex - side * 1 + (4 if side < 0 else -4)
        x_out = ex + side * 7
        lo_, hi_ = min(x_in, x_out), max(x_in, x_out)
        for X in range(lo_, hi_ + 1):
            t = abs(X - x_in) / max(1, abs(x_out - x_in))
            yl = inner + (outer - inner) * t + (lift if side > 0 else 0)
            Y = H(yl + 0.5) - (1 if 0.4 < t < 0.8 else 0)
            P(c, X, Y, HR, 0)
            if t < 0.75:
                P(c, X, Y + 1, HR, 1)
            if heavy and t < 0.6:
                P(c, X, Y - 1, HR, 1)
                P(c, X, Y + 2, HR, 0 if t < 0.3 else 1)
    if expr in ("angry", "pain"):
        for dx in (-2, 2):
            VL(c, HCX + dx, H(38), H(40), SK, 3)


def draw_eyes(c: HDCanvas, expr: str, gaze: str):
    """Reference-style eyes ~11x6 HD px: a heavy ink lash line that winds
    out past the outer corner, a tall iris filling the opening (dark under
    the lid, light at the bottom), a 2 px pupil, a hard white catch-light,
    a little sclera either side, the lid crease and a short lower lid."""
    wide = expr == "fear"
    squint = expr in ("angry", "pain")
    heavy_lid = expr == "sad"
    ox = {"center": 0, "left": -2, "right": 2, "closed": 0}[gaze]
    for i, ex in enumerate(HEX):
        lit = i == 0
        outer = -1 if i == 0 else 1
        if gaze == "closed":
            for X in range(ex - 5, ex + 6):
                sag = 1 if abs(X - ex) < 4 else 0
                P(c, X, HEY + sag, FX, F_OUT)
                if abs(X - ex) < 3:
                    P(c, X, HEY + sag + 1, FX, F_OUT)
            P(c, ex + outer * 6, HEY - 1, FX, F_OUT)
            P(c, ex + outer * 7, HEY - 2, FX, F_OUT)
            HL(c, ex - 3, ex + 3, HEY - 3, SK, 3)
            continue
        h = 7 if wide else (4 if squint else 6)
        top = HEY - h // 2
        half_w = 5
        rows = list(range(top, top + h))
        for k, Y in enumerate(rows):
            edge = 2 if k == h - 1 else (1 if k == 0 or k == h - 2 else 0)
            for X in range(ex - half_w + edge, ex + half_w - edge + 1):
                P(c, X, Y, FX, F_EYEW)
            if k == 0:
                HL(c, ex - half_w + edge, ex + half_w - edge, Y, SK, 3)  # lid shadow on the white
        ix = ex + ox
        for Y in rows:
            k = Y - top
            for dx in range(-2, 3):
                if (k == h - 1 and abs(dx) == 2) or (k == 0 and abs(dx) == 2 and h < 6):
                    continue
                shade = 1 if k <= 1 else (3 if k < h - 2 else 5)
                if abs(dx) == 2:
                    shade = max(0, shade - 1)
                P(c, ix + dx, Y, IR, shade + (1 if lit and k > 1 and abs(dx) < 2 else 0))
        py = top + max(1, h // 2 - 1)
        for dy in range(2 if h >= 6 else 1):
            P(c, ix, py + dy, FX, F_PUPIL)
            P(c, ix + 1, py + dy, FX, F_PUPIL)
        # Lash line: two rows of ink, the wing at the outer corner.
        HL(c, ex - half_w, ex + half_w, top - 1, FX, F_OUT)
        HL(c, ex - half_w + 1 if outer < 0 else ex - half_w + 3, ex + half_w - 3 if outer < 0 else ex + half_w - 1, top - 2, FX, F_OUT)
        P(c, ex + outer * (half_w + 1), top - 1, FX, F_OUT)
        P(c, ex + outer * (half_w + 2), top - 2, FX, F_OUT)
        P(c, ex + outer * half_w, top, FX, F_OUT)
        P(c, ex + outer * half_w, top + 1, FX, F_OUT)
        HL(c, ex - 3, ex + 3, top - 4, SK, 3)                  # crease
        if heavy_lid:
            HL(c, ex - half_w + 1, ex + half_w - 1, top, SK, 2)
            HL(c, ex - half_w + 1, ex + half_w - 1, top + 1, FX, F_OUT)
        if squint:
            HL(c, ex - half_w + 1, ex + half_w - 1, top + h, SK, 2)
        # Lower lid: a short dark stroke at the outer half, lit inner rim.
        for X in range(ex, ex + outer * (half_w + 1), outer):
            P(c, X, top + h, SK, 2)
        P(c, ex - outer * 3, top + h, SK, 5 if lit else 4)
        # Catch-light last.
        P(c, ix - 1, top + 1 + (h >= 6), FX, F_HI)
        P(c, ix - 1, top + 2 + (h >= 6), FX, F_HI) if h >= 6 else None
        P(c, ix + 1, top + h - 2, IR, 7)


def draw_age(c: HDCanvas, age: str):
    """Age as a few clean strokes in the shadow tone, not a net of lines."""
    if age == "young":
        return
    for side, ex in ((-1, HEX[0]), (1, HEX[1])):
        P(c, ex + side * 7, HEY + 1, SK, 3)                         # crow's foot
        for k in range(5):                                          # nasolabial fold
            P(c, HCX + side * (7 + k // 2), H(54) + k, SK, 3)
    if age == "old":
        HL(c, H(CX - 7), H(CX - 1), H(29), SK, 3)
        HL(c, H(CX + 1), H(CX + 6), H(30), SK, 3)
        HL(c, H(CX - 4), H(CX + 4), H(33), SK, 3)
        for side, ex in ((-1, HEX[0]), (1, HEX[1])):
            HL(c, ex - 3, ex + 3, HEY + 5, SK, 3)                   # under-eye bags
            P(c, ex + side * 7, HEY + 3, SK, 3)
            for k in range(6):
                P(c, HCX + side * (11 + k // 3), H(60) + k, SK, 3)  # jowls
        VL(c, HCX - 4, H(67), H(69) + 1, SK, 3)
        VL(c, HCX + 4, H(67), H(69) + 1, SK, 3)


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
