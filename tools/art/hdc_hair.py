"""HD portrait hair (front and back layers)."""
from __future__ import annotations

from .hdc_core import (S, SK, HR, CC, grid, P, HL, VL, H, clamp, HDCanvas, stipple)
from .hdc_face import CX, HCX

HAIR = ["buzz", "short", "messy", "undercut", "slick", "long", "bob", "tied", "topknot", "mohawk", "locs",
        "receding", "braids", "shaved"]


def hairline(x):
    dx = x - CX
    return min(44.0, 27.0 + 0.045 * dx * dx)


def _hair_px(c, X, Y, x, y, rng, base=2.0):
    """One HD hair pixel: lit from the top-left, with fine strands that run
    down and outwards from the crown (2 HD px apart) and stray hairs."""
    nx = (x - CX) / 20.0
    ny = (y - 20) / 22.0
    v = base + 2.3 * clamp(-nx * 0.7 - ny * 0.8 + 0.4, 0, 1)
    lean = int((X - HCX) * 0.35 * max(0, Y - 15) / 45.0)
    k = (X - lean + (Y // 6)) % 5
    if k == 0:
        v -= 1.0
    elif k == 2 and v > base + 0.9:
        v += 0.45
    elif k == 3:
        v -= 0.25
    if rng.random() < 0.035:
        v -= 0.9
    c.shade_px(X, Y, HR, v)


def _cap(c, rng, grow=2.5, top_extra=0.0, line=hairline, base=2.0, side_cut=None, max_y=46):
    rx, ry = 16.6 + grow * 0.32, 21.6 + grow * 0.7
    for X, Y, x, y in grid(24, 4, 73, max_y):
        if ((x + 0.5 - CX) / rx) ** 2 + ((y + 0.5 - (37 - top_extra)) / ry) ** 2 > 1.0:
            continue
        if y > line(x):
            continue
        if side_cut and side_cut(x, y):
            continue
        _hair_px(c, X, Y, x, y, rng, base)
    # Edge: a darker 1 px rim where the cap meets the background (right side).
    for Y in range(H(4), H(max_y)):
        for X in range(H(24), H(73)):
            if c.has(X, Y, HR) and not c.has(X + 1, Y) and X > HCX:
                P(c, X, Y, HR, 1)


def _hair_shadow(c):
    """Skin shadow under the hair edge on the forehead and temples."""
    for X in range(H(30), H(67)):
        bottom = None
        for Y in range(H(4), H(50)):
            if c.has(X, Y, HR):
                bottom = Y
        if bottom is None or bottom > H(44):
            continue
        for d, shade in ((1, 1), (2, 2), (3, 2)):
            Y = bottom + d
            x, y = (X + 0.5) / S - 0.5, (Y + 0.5) / S - 0.5
            if ((x + 0.5 - CX) / 15.5) ** 2 + ((y + 0.5 - 38) / 21.5) ** 2 <= 1 and c.get(X, Y) is None:
                P(c, X, Y, SK, shade)


def _strand_highlights(c, rng, x0, x1, y0, y1, n=20):
    """Glossy strand highlights: short diagonal runs of 3 HD px."""
    for _ in range(int(n * 1.6)):
        X = rng.randint(H(x0), H(x1))
        Y = rng.randint(H(y0), H(y1))
        if c.has(X, Y, HR):
            lit = X < HCX
            for k in range(3):
                if c.has(X + k // 2, Y + k, HR):
                    P(c, X + k // 2, Y + k, HR, (6 if lit else 4) - (k == 2))


def _fall(c, rng, x0, x1, y0, y1, taper=0):
    for X, Y, x, y in grid(x0, y0, x1 + 1, y1):
        t = (y - y0) / max(1, y1 - y0)
        if x < x0 + taper * t or x > x1 - taper * t:
            continue
        _hair_px(c, X, Y, x, y, rng, 1.6 if x > CX else 2.2)


def _fringe(c, X, Y0, Y1, shade, w=1):
    for k in range(w):
        VL(c, X + k, Y0, Y1, HR, shade - k)


def draw_hair(c: HDCanvas, style: str, rng):
    _draw_hair(c, style, rng)
    if style not in ("buzz", "mohawk", "topknot"):
        _hair_shadow(c)


def _draw_hair(c: HDCanvas, style: str, rng):
    if style == "buzz":
        for X, Y, x, y in grid(28, 14, 69, 40):
            if ((x + 0.5 - CX) / 17.2) ** 2 + ((y + 0.5 - 37) / 22.6) ** 2 <= 1 and y <= hairline(x):
                edge = y > hairline(x) - 1.5
                if not edge or stipple(X, Y, 0.5):
                    P(c, X, Y, HR, 1 + stipple(X, Y, 0.45) + (x < CX - 4 and y < 26))
    elif style == "short":
        _cap(c, rng, grow=2.6)
        for k in range(9):  # fringe locks
            X = H(CX - 10) + k * 4
            _fringe(c, X, H(26), H(29) + (k % 3), 2 + (X < HCX), 2)
        _strand_highlights(c, rng, 30, 56, 14, 26)
    elif style == "messy":
        _cap(c, rng, grow=3.5)
        rx, ry = 16.6 + 3.5 * 0.32, 21.6 + 3.5 * 0.7
        for k in range(11):  # tufts rising from the scalp
            x = CX - 14 + k * 2.8
            t = (x + 0.5 - CX) / rx
            if abs(t) >= 0.95:
                continue
            top = 37 - ry * (1 - t * t) ** 0.5
            X, Y0 = H(x), H(top) + 2
            h = rng.randint(3, 6)
            lean = -1 if x < CX else 1
            for d in range(h):
                w = max(1, 3 - d // 2)
                for j in range(w):
                    P(c, X + j + (d * lean) // 3, Y0 - d, HR, 2 + (x < CX) + (d == h - 1) - (j == w - 1))
        for k in range(7):
            VL(c, H(CX - 9) + k * 4, H(26), H(30) + rng.randint(0, 3), HR, 1)
        _strand_highlights(c, rng, 28, 58, 12, 28, 26)
    elif style == "undercut":
        _cap(c, rng, grow=4.0, top_extra=1.5, line=lambda x: 30 if x < CX + 12 else 28,
             side_cut=lambda x, y: y > 30 and (x < CX - 13 or x > CX + 13))
        for X, Y, x, y in grid(30, 30, 35, 42):  # shaved sides
            if stipple(X, Y, 0.45):
                P(c, X, Y, HR, 1)
        for X, Y, x, y in grid(62, 30, 67, 42):
            if stipple(X, Y, 0.45):
                P(c, X, Y, HR, 1)
        for k in range(18):  # swept fringe to the right
            Y = H(22) + k // 2
            HL(c, H(CX - 8) + k, H(CX + 2) + k, Y, HR, 4 if k < 6 else (3 if k < 12 else 2))
            P(c, H(CX + 2) + k + 1, Y + 1, HR, 1)
        _strand_highlights(c, rng, 32, 56, 12, 24)
    elif style == "slick":
        _cap(c, rng, grow=1.2, line=lambda x: min(44.0, 25.0 + 0.05 * (x - CX) ** 2), base=1.4)
        for k in range(21):  # the wet sheen: two bright combed bands
            X = H(CX - 12) + k
            Y = H(18) + abs(k - 9) // 4
            P(c, X, Y, HR, 6)
            P(c, X + 1, Y + 1, HR, 5)
            if k % 3:
                P(c, X + 2, Y + 5, HR, 4)
    elif style in ("long", "bob", "braids"):
        _cap(c, rng, grow=3.2, line=lambda x: min(46.0, 26.0 + 0.04 * (x - CX) ** 2))
        bottom = {"long": 92, "bob": 64, "braids": 96}[style]
        _fall(c, rng, CX - 21, CX - 16, 30, bottom, taper=0)
        _fall(c, rng, CX + 16, CX + 21, 30, bottom, taper=0)
        if style == "braids":
            for side in (-1, 1):
                X = H(CX + 0.5 + side * 18)
                for Y in range(H(48), H(bottom), 4):
                    HL(c, X - 3, X + 3, Y, HR, 1)
                    HL(c, X - 2, X + 1, Y + 1, HR, 4)
        if style == "bob":
            for side in (-1, 1):  # blunt cut line
                HL(c, H(CX + 0.5 + side * 18.5) - 4, H(CX + 0.5 + side * 18.5) + 4, H(bottom) - 1, HR, 1)
        for k in range(12):  # parted fringe
            _fringe(c, HCX - 3 - k, H(24) + k // 2, H(28) + k // 2, 3)
            _fringe(c, HCX + 3 + k, H(24) + k // 2, H(28) + k // 2, 2)
        _strand_highlights(c, rng, 28, 60, 14, 50, 30)
    elif style == "tied":
        _cap(c, rng, grow=1.6, line=lambda x: min(44.0, 25.5 + 0.05 * (x - CX) ** 2), base=1.8)
        for k in range(24):  # combed-back lines
            P(c, H(CX - 14) + k + k // 2, H(19) + abs(k - 11) // 4, HR, 4)
            if k % 2:
                P(c, H(CX - 14) + k + k // 2, H(23) + abs(k - 11) // 4, HR, 3)
        HL(c, H(CX + 12), H(CX + 16), H(18), CC, 4)  # tie band
        HL(c, H(CX + 12), H(CX + 16), H(18) + 1, CC, 2)
    elif style == "topknot":
        _cap(c, rng, grow=0.6, side_cut=lambda x, y: y > 24 and abs(x - CX) > 9, base=1.6)
        c.lsphere(CX + 1.5, 9, 5.5, 4.5, HR, lo=1.0, hi=5.0)
        for k in range(5):
            P(c, H(CX - 2) + k * 2, H(7) + (k % 2), HR, 6)
        HL(c, H(CX - 3), H(CX + 4), H(13), CC, 3)
        HL(c, H(CX - 3), H(CX + 4), H(13) + 1, CC, 1)
    elif style == "mohawk":
        for X, Y, x, y in grid(CX - 4, 4, CX + 5, 34):
            w = 4 if y < 28 else 3
            if abs(x - CX) <= w:
                P(c, X, Y, HR, 2 + (x < CX) + (y < 12) - stipple(X, Y, 0.2) + ((X + Y // 2) % 4 == 0))
        for k in range(7):  # spikes
            X = HCX - 5 + k * 2
            VL(c, X, H(0) + (k % 2) * 2, H(4), HR, 3 + (k % 2))
        for X, Y, x, y in grid(30, 18, 39, 40):
            if y <= hairline(x) and stipple(X, Y, 0.3):
                P(c, X, Y, HR, 1)
        for X, Y, x, y in grid(58, 18, 67, 40):
            if y <= hairline(x) and stipple(X, Y, 0.3):
                P(c, X, Y, HR, 1)
    elif style == "locs":
        _cap(c, rng, grow=3.6)
        for k in range(10):
            x = CX - 21 + k * 4 + (2 if k > 4 else 0)
            if abs(x - CX) < 12:
                continue
            X0 = H(x)
            for Y in range(H(28), H(86)):
                seg = (Y // 4) % 2
                P(c, X0, Y, HR, 3 + seg - (x > CX))
                P(c, X0 + 1, Y, HR, 2 + seg - (x > CX))
                P(c, X0 + 2, Y, HR, 1 + seg)
                if Y % 4 == 0:
                    P(c, X0 + 1, Y, HR, 1)
        for k in range(9):
            VL(c, H(CX - 9) + k * 3, H(24), H(34), HR, 2 + (k % 2))
    elif style == "receding":
        _cap(c, rng, grow=1.4, line=lambda x: 22.0 if abs(x - CX) < 7 else min(44.0, 24.0 + 0.06 * (x - CX) ** 2),
             side_cut=lambda x, y: y < 22 and abs(x - CX) < 9)
        for X in range(H(CX - 8), H(CX + 9)):
            if rng.random() < 0.3:
                P(c, X, H(19) + rng.randint(0, 3), HR, 3)
    elif style == "shaved":
        for X, Y, x, y in grid(29, 15, CX + 1, 42):
            if ((x + 0.5 - CX) / 17.2) ** 2 + ((y + 0.5 - 37) / 22.6) ** 2 <= 1 and y <= hairline(x) and stipple(X, Y, 0.4):
                P(c, X, Y, HR, 1)
        _cap(c, rng, grow=3.0, side_cut=lambda x, y: x < CX - 1)
        for X in range(H(CX + 2), H(CX + 21)):  # the long side falling over
            VL(c, X, H(30), H(46) + (X % 5), HR, (3 if X < H(CX + 8) else 2) - (X % 3 == 0))
        _strand_highlights(c, rng, CX, CX + 16, 14, 30)


def draw_hair_back(c: HDCanvas, style: str, rng):
    if style == "long":
        for X, Y, x, y in grid(CX - 25, 36, CX + 26, 98):
            if 14 < abs(x - CX) < 25 - max(0, y - 80) * 0.6:
                v = 1 + (rng.random() < 0.35) + (x < CX) + ((X + Y // 5) % 4 == 0)
                P(c, X, Y, HR, v)
    elif style == "tied":
        for Y in range(H(30), H(70)):
            X = H(CX + 17) + (Y - H(30)) // 12
            for d in range(-3, 4):
                P(c, X + d, Y, HR, 1 + (d < 0) + (rng.random() < 0.25) + (d == -2))
    elif style == "locs":
        for k in range(8):
            X0 = H(CX - 24 + k * 7)
            for Y in range(H(40), H(96 - (k % 3) * 4)):
                seg = (Y // 4) % 2
                P(c, X0, Y, HR, 2 + seg)
                P(c, X0 + 1, Y, HR, 1 + seg)
                P(c, X0 + 2, Y, HR, 1)
    elif style == "braids":
        for side in (-1, 1):
            X = H(CX + 0.5 + side * 22)
            for Y in range(H(40), H(100)):
                P(c, X, Y, HR, 3 if (Y // 3) % 2 else 1)
                P(c, X + side, Y, HR, 2 if (Y // 3) % 2 else 1)
                P(c, X - side, Y, HR, 1)
