"""HD in-room bodies (60x120): skeleton -> skin -> outfit -> extras.

Logical coordinates follow the v2 40x80 skeleton; limbs, torsos and heads
are rasterised at HD, small parts (eyes, buckles, zips, laces, fingers)
are drawn on the HD grid.
"""
from __future__ import annotations

from .hdc_core import (S, SK, HR, CA, CB, MT, GL, FX, CC, LT, GR, BL, F_OUT, F_EYEW, F_PUPIL, F_INK, F_LENS, F_RIM,
                       HDCanvas, grid, f, hl, vl, P, HL, VL, LN, H, plate, stitch_v, zipper)

BW, BH = 40, 80
BCX = 20
BUILDS = ["slim", "average", "heavy", "muscular"]
POSTURES = ["upright", "slouch", "wide", "hunched"]
BODY_W = {"slim": 5.5, "average": 6.5, "heavy": 8.0, "muscular": 8.5}
WAIST_W = {"slim": 4.0, "average": 4.6, "heavy": 7.0, "muscular": 5.2}
LIMB_R = {"slim": 1.3, "average": 1.5, "heavy": 2.0, "muscular": 2.1}


def body_canvas() -> HDCanvas:
    return HDCanvas(BW, BH, dither=0.0)


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
    c.lcapsule(a[0], a[1], b[0], b[1], r, ramp, lo=lo, hi=hi, r2=r2)


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


def _hand(c, sk, side, ramp=SK, lo=1.5, hi=4.5):
    wx, wy = sk["wr_" + side]
    c.lsphere(wx, wy + 1.2, 1.3, 1.7, ramp, lo=lo, hi=hi)
    # Finger separations and a thumb on the inner side.
    X, Y = H(wx), H(wy + 2.2)
    for d in (-1, 1):
        if c.has(X + d, Y + 1, ramp):
            P(c, X + d, Y + 1, ramp, 1)
    P(c, X + (1 if side == "l" else -1) * 2, Y - 1, ramp, 2)


def draw_body_base(b: HDCanvas, build: str, posture: str):
    sk = skeleton(build, posture)
    r = sk["r"]
    for side in ("l", "r"):
        _limb(b, sk["hip_" + side], sk["kn_" + side], r + 0.6, SK, r2=r + 0.2)
        _limb(b, sk["kn_" + side], sk["an_" + side], r + 0.2, SK, r2=r - 0.2)
        _limb(b, sk["sh_" + side], sk["el_" + side], r, SK)
        _limb(b, sk["el_" + side], sk["wr_" + side], r - 0.1, SK, r2=r - 0.4)
        _hand(b, sk, side)
    b.lshaded_poly(_torso_poly(sk), SK, top=4.4, bottom=2.6, left_bias=1.4, edge_dark=0.7)
    nx, ny = sk["neck"]
    for X, Y, x, y in grid(nx - 1.4, ny - 1, nx + 1.6, ny + 3):
        P(b, X, Y, SK, 2 if x > nx else 3)
    hx, hy = sk["head"]
    rx, ry = sk["head_r"]
    b.lsphere(hx + 0.5, hy, rx, ry, SK, lo=1.0, hi=5.6)
    HX, HY = H(hx + 0.5), H(hy)
    # Ear stubs and the rim light on the shadow side.
    P(b, H(hx + 0.5 - rx) - 1, HY + 1, SK, 3)
    P(b, H(hx + 0.5 + rx), HY + 1, SK, 1)
    for k in range(-3, 2):
        if b.has(H(hx + 0.5 + rx) - 1, HY + k):
            P(b, H(hx + 0.5 + rx) - 1, HY + k, FX, F_RIM)
    # Face at HD: brow shadow, eye whites + pupils, nose, mouth, jaw.
    HL(b, HX - 4, HX + 3, HY - 1, SK, 2)
    P(b, HX - 3, HY + 1, FX, F_EYEW)
    P(b, HX - 2, HY + 1, FX, F_PUPIL)
    P(b, HX + 1, HY + 1, FX, F_EYEW)
    P(b, HX + 2, HY + 1, FX, F_PUPIL)
    P(b, HX, HY + 2, SK, 5)       # nose bridge light
    P(b, HX + 1, HY + 3, SK, 2)   # nose shadow (key light from the left)
    HL(b, HX - 1, HX + 1, HY + 5, SK, 1)  # mouth
    P(b, HX + 3, HY + 3, SK, 2)   # cheek in shadow
    HL(b, HX - 2, HX + 2, H(hy + ry) - 1, SK, 2)  # under the jaw


def _boots(b, sk, ramp=LT, tall=False, steel=False):
    for side in ("l", "r"):
        ax, ay = sk["an_" + side]
        top = ay - (6 if tall else 2)
        for X, Y, x, y in grid(ax - 2, top, ax + 3, ay + 3):
            if x < ax + 2 + (1 if y >= ay + 1 else 0):
                P(b, X, Y, ramp, 3 - (x > ax) - (y > ay + 1))
        HL(b, H(ax - 2), H(ax + 3), H(ay + 3), ramp, 0)        # sole
        HL(b, H(ax - 2), H(ax + 3), H(ay + 3) + 1, ramp, 1)
        if tall:  # laces up the shaft
            for Y in range(H(top) + 1, H(ay), 2):
                P(b, H(ax), Y, ramp, 5)
        else:
            P(b, H(ax - 1), H(ay), ramp, 5)
            P(b, H(ax), H(ay) + 1, ramp, 5)
        if steel:  # toe cap
            P(b, H(ax + 2), H(ay + 2), MT, 6)
            P(b, H(ax + 2) + 1, H(ay + 2), MT, 3)


def _pants(b, sk, ramp, lo=1.2, hi=3.8, baggy=0.0):
    r = sk["r"]
    for side in ("l", "r"):
        _limb(b, sk["hip_" + side], sk["kn_" + side], r + 1.0 + baggy, ramp, lo, hi, r2=r + 0.7 + baggy)
        _limb(b, sk["kn_" + side], sk["an_" + side], r + 0.7 + baggy, ramp, lo, hi, r2=r + 0.6 + baggy)
        kx, ky = sk["kn_" + side]  # knee crease
        HL(b, H(kx - 1), H(kx + 1), H(ky), ramp, 1)
        P(b, H(kx - 1), H(ky) - 1, ramp, hi - 0.5)
    HL(b, H(BCX - sk["hip_w"]), H(BCX + sk["hip_w"]), H(sk["hip_y"]), ramp, 1)
    VL(b, H(BCX), H(sk["hip_y"]), H(sk["hip_y"] + 6), ramp, 1)   # fly seam
    stitch_v(b, H(BCX) + 2, H(sk["hip_y"]) + 1, H(sk["hip_y"] + 5), ramp, int(hi), 1)


def _top(b, sk, ramp, length=None, extra=0.6, sleeves="long", lo=1.4, hi=4.4, open_front=False, inner=None):
    bottom = sk["hip_y"] + 1 if length is None else length
    b.lshaded_poly(_torso_poly(sk, extra, bottom), ramp, top=hi, bottom=lo, left_bias=1.6, edge_dark=0.8)
    r = sk["r"]
    for side in ("l", "r"):
        if sleeves in ("long", "short"):
            _limb(b, sk["sh_" + side], sk["el_" + side], r + 0.7, ramp, lo, hi)
        if sleeves == "long":
            _limb(b, sk["el_" + side], sk["wr_" + side], r + 0.5, ramp, lo, hi, r2=r + 0.3)
            wx, wy = sk["wr_" + side]  # cuff
            HL(b, H(wx - 1.2), H(wx + 1.4), H(wy) - 1, ramp, 1)
        if sleeves == "short":
            ex, ey = sk["el_" + side]
            HL(b, H(ex - 1.4), H(ex + 1.6), H(ey) - 1, ramp, 1)
    if open_front:
        ir = inner if inner is not None else ramp
        for Y in range(H(sk["sh_l"][1]) + 2, H(bottom)):
            P(b, H(BCX), Y, ir, 2)
            P(b, H(BCX) - 1, Y, ir, 3)
            P(b, H(BCX) + 1, Y, ramp, 1)
            P(b, H(BCX) - 2, Y, ramp, hi)  # lit lapel edge
    if length and length > sk["hip_y"] + 4:  # coat hem split
        VL(b, H(BCX), H(sk["hip_y"]), H(length) - 1, ramp, 1)
        HL(b, H(BCX - sk["hip_w"] - 1), H(BCX + sk["hip_w"] + 1), H(length) - 1, ramp, lo - 0.5)


def _belt(b, sk, ramp=LT, buckle=True, y=None):
    y = sk["waist_y"] + 3 if y is None else y
    HL(b, H(BCX - sk["waist_w"] - 1), H(BCX + sk["waist_w"] + 1), H(y), ramp, 2)
    HL(b, H(BCX - sk["waist_w"] - 1), H(BCX + sk["waist_w"] + 1), H(y) + 1, ramp, 1)
    if buckle:
        P(b, H(BCX), H(y), MT, 6)
        P(b, H(BCX) + 1, H(y), MT, 4)
        P(b, H(BCX), H(y) + 1, MT, 3)


def _grime(b, rng, n, box, ramps=((GR, 2), (GR, 1))):
    x0, y0, x1, y1 = box
    for _ in range(int(n * 1.8)):
        X, Y = rng.randint(H(x0), H(x1)), rng.randint(H(y0), H(y1))
        p = b.get(X, Y)
        if p is not None and p[0] not in (SK, FX):
            P(b, X, Y, *rng.choice(ramps))


OUTFITS = ["corporate", "executive", "security", "gang", "worker", "mercenary", "ripperdoc", "medic", "fixer",
           "dealer", "civilian", "performer", "technician", "military", "patient", "addict", "elder", "netrunner"]


def draw_body_outfit(b: HDCanvas, outfit: str, build: str, posture: str, rng):
    sk = skeleton(build, posture)
    hip, waist = sk["hip_y"], sk["waist_y"]
    sy = sk["sh_l"][1]
    if outfit == "corporate":
        _pants(b, sk, CA, 1.2, 3.6)
        _boots(b, sk, CC)
        _top(b, sk, CA, length=hip + 2, lo=1.4, hi=4.2)
        VL(b, H(BCX), H(sy - 1), H(sy + 6), CB, 6)   # shirt
        VL(b, H(BCX) - 1, H(sy - 1), H(sy + 3), CB, 5)
        VL(b, H(BCX), H(sy + 1), H(sy + 8), CC, 2)   # tie
        P(b, H(BCX), H(sy + 1), CC, 4)
        for k in range(2):  # jacket buttons
            P(b, H(BCX) + 2, H(sy + 9 + k * 3), MT, 5)
    elif outfit == "executive":
        _pants(b, sk, CA, 1.0, 3.2)
        _boots(b, sk, CC)
        _top(b, sk, CA, length=60, extra=1.2, lo=1.0, hi=4.0)
        HL(b, H(sk["neck"][0] - 2), H(sk["neck"][0] + 2), H(sk["neck"][1]), CA, 4)  # high collar
        HL(b, H(sk["neck"][0] - 2), H(sk["neck"][0] + 2), H(sk["neck"][1]) + 1, CA, 3)
        P(b, H(BCX + 1), H(waist - 4), MT, 6)
        P(b, H(BCX + 1) + 1, H(waist - 4), GL, 4)
    elif outfit == "security":
        _pants(b, sk, CA, 1.2, 3.4)
        _boots(b, sk, LT, tall=True, steel=True)
        _top(b, sk, CA, lo=1.2, hi=3.8)
        for side in ("l", "r"):  # pauldrons
            x, y = sk["sh_" + side]
            b.lsphere(x, y + 1, 3.0, 2.4, MT, lo=1.6, hi=5.8)
            HL(b, H(x - 2), H(x + 2), H(y + 2), MT, 2)
        plate(b, BCX - 4, sy + 2, BCX + 3, waist - 3, MT, lo=1.6, hi=4.6)
        for side in ("l", "r"):  # knee guards
            kx, ky = sk["kn_" + side]
            plate(b, kx - 1, ky - 1, kx + 0.5, ky + 1, MT)
        _belt(b, sk, CB)
        P(b, H(BCX - 3), H(sy + 4), GL, 6)
        P(b, H(BCX - 3) + 1, H(sy + 4), GL, 3)
    elif outfit == "gang":
        _pants(b, sk, CB, 1.0, 3.4, baggy=0.3)
        _boots(b, sk, LT, tall=True)
        _top(b, sk, LT, length=hip + 1, lo=1.0, hi=4.0, open_front=True, inner=CB, sleeves="short")
        x, y = sk["el_l"]
        for k in range(6):  # forearm ink
            P(b, H(x - 0.5), H(y + 2) + k * 2, FX, F_INK)
            P(b, H(x - 0.5) + 1, H(y + 2) + k * 2 + 1, FX, F_INK)
        x, y = sk["sh_l"]
        b.lsphere(x - 0.5, y, 3.2, 2.6, MT, lo=1.2, hi=5.6)  # spiked pauldron
        for k in range(4):
            VL(b, H(x - 2.5) + k * 2, H(y - 3.5), H(y - 2), MT, 6)
        HL(b, H(BCX + 2), H(BCX + 4), H(waist - 4), CC, 4)  # red rag
        HL(b, H(BCX + 2), H(BCX + 4), H(waist - 4) + 1, CC, 2)
        VL(b, H(sk["kn_r"][0] + 1), H(sk["kn_r"][1] - 2), H(sk["kn_r"][1] + 2), CC, 3)
        _belt(b, sk, LT)
        _grime(b, rng, 8, (6, 20, 34, 72))
    elif outfit == "worker":
        _pants(b, sk, CC, 1.2, 3.6, baggy=0.4)
        _boots(b, sk, LT, tall=True, steel=True)
        _top(b, sk, CA, length=hip + 1, extra=1.2, lo=1.4, hi=4.0)
        for side in ("l", "r"):  # hi-vis bands on the arms
            ex, ey = sk["el_" + side]
            HL(b, H(ex - 1.5), H(ex + 1.5), H(ey - 1), CB, 6)
            HL(b, H(ex - 1.5), H(ex + 1.5), H(ey - 1) + 1, CB, 4)
        HL(b, H(BCX - sk["waist_w"] - 1), H(BCX + sk["waist_w"] + 1), H(waist - 3), CB, 6)
        HL(b, H(BCX - sk["waist_w"] - 1), H(BCX + sk["waist_w"] + 1), H(waist - 3) + 1, CB, 5)
        HL(b, H(BCX - sk["waist_w"] - 1), H(BCX + sk["waist_w"] + 1), H(waist - 2) + 1, CB, 3)
        zipper(b, H(BCX), H(sy + 1), H(hip))
        _grime(b, rng, 14, (6, 22, 34, 76))
    elif outfit == "mercenary":
        _pants(b, sk, CA, 1.2, 3.4, baggy=0.3)
        _boots(b, sk, LT, tall=True, steel=True)
        _top(b, sk, CB, lo=1.2, hi=3.8)
        plate(b, BCX - 5, sy + 1, BCX + 4, waist - 1, CA, lo=1.2, hi=3.6)  # carrier
        for k in range(3):
            plate(b, BCX - 5 + k * 3, waist - 4, BCX - 3.5 + k * 3, waist - 1, CC, lo=1, hi=3)
        for k in range(21):  # sling
            P(b, H(sk["sh_l"][0]) + int(k * 0.9), H(sy) + int(k * 1.4), LT, 2)
            P(b, H(sk["sh_l"][0]) + int(k * 0.9) + 1, H(sy) + int(k * 1.4), LT, 3)
        for side in ("l", "r"):  # thigh pouches
            kx, ky = sk["kn_" + side]
            plate(b, kx - 2, ky - 8, kx + 0.5, ky - 4.5, CC, lo=1, hi=3)
        _belt(b, sk, CC)
        _grime(b, rng, 10, (6, 22, 34, 76))
    elif outfit == "ripperdoc":
        _pants(b, sk, CB, 1.0, 3.2)
        _boots(b, sk, CC)
        _top(b, sk, CB, lo=1.2, hi=3.8, sleeves="short")
        apron = [(BCX - 4, sy + 3), (BCX + 4, sy + 3), (BCX + sk["hip_w"] + 1.5, 60), (BCX - sk["hip_w"] - 1.5, 60)]
        b.lshaded_poly(apron, LT, top=4.0, bottom=1.8, left_bias=1.6, edge_dark=0.6)
        for side in (-1, 1):  # neck straps
            LN(b, H(BCX + side * 3.5), H(sy + 3), H(sk["neck"][0] + side * 1.5), H(sk["neck"][1] + 1), LT, 2)
        for k in range(5):  # tools in loops
            X = H(BCX - 3 + k * 1.5)
            VL(b, X, H(waist - 3), H(waist - 1), MT, 6 - (k % 2) * 2)
        _grime(b, rng, 16, (10, 26, 30, 60), ramps=((BL, 2), (BL, 3), (GR, 2)))
        for side in ("l", "r"):  # cyber gloves
            _hand(b, sk, side, MT, 1.5, 5.5)
    elif outfit == "medic":
        _pants(b, sk, CA, 1.6, 4.2)
        _boots(b, sk, CC)
        _top(b, sk, CB, length=56, extra=0.8, lo=2.4, hi=5.6, open_front=True, inner=CA)  # dirty coat
        _grime(b, rng, 14, (8, 22, 32, 56), ramps=((GR, 3), (GR, 4), (BL, 3)))
        plate(b, BCX + 2.5, sy + 3, BCX + 4, sy + 5, CC, lo=3, hi=6)  # ID card
        for side in ("l", "r"):  # coat pockets
            x = BCX + (-3.5 if side == "l" else 3)
            HL(b, H(x - 1), H(x + 1), H(waist + 3), CB, 2)
    elif outfit == "fixer":
        _pants(b, sk, CB, 1.0, 3.2)
        _boots(b, sk, LT)
        _top(b, sk, CA, length=64, extra=1.4, lo=1.0, hi=3.8, open_front=True, inner=CB)  # long coat
        for side in ("l", "r"):  # leather collar
            x, y = sk["sh_" + side]
            for k in range(4):
                P(b, H((x + sk["neck"][0]) / 2) + (k if side == "r" else -k), H(y - 2) + k, LT, 4 - k // 2)
                P(b, H((x + sk["neck"][0]) / 2) + (k if side == "r" else -k), H(y - 2) + k + 1, LT, 2)
        P(b, H(BCX), H(sy + 3), MT, 6)  # chain glint
        P(b, H(BCX) + 1, H(sy + 3) + 1, MT, 4)
        P(b, H(sk["wr_r"][0]), H(sk["wr_r"][1] + 1), MT, 6)  # rings
    elif outfit == "dealer":
        _pants(b, sk, CB, 1.0, 3.0)
        _boots(b, sk, LT)
        _top(b, sk, CA, length=56, extra=1.0, lo=1.0, hi=3.6)
        hx, hy = sk["head"]
        for X in range(H(hx - 4), H(hx + 5)):  # hood down, bunched
            P(b, X, H(sk["neck"][1]), CA, 3 - (X > H(hx)))
            P(b, X, H(sk["neck"][1]) + 1, CA, 2 - (X > H(hx)))
        for k in range(3):
            HL(b, H(BCX - 2), H(BCX + 2), H(sy + 3 + k * 2), MT, 5 - k)
    elif outfit == "civilian":
        _pants(b, sk, CC, 1.2, 3.8)
        _boots(b, sk, CB)
        _top(b, sk, CA, length=hip + 2, extra=0.8, lo=1.4, hi=4.2)  # hoodie
        hx, hy = sk["head"]
        HL(b, H(hx - 3), H(hx + 3), H(sk["neck"][1]), CA, 2)
        HL(b, H(hx - 3), H(hx + 3), H(sk["neck"][1]) + 1, CA, 3)
        for side in (-1, 1):  # drawstrings
            VL(b, H(BCX) + side * 2, H(sy + 1), H(sy + 5), CB, 5)
        HL(b, H(BCX - 3), H(BCX + 3), H(waist + 1), CA, 1)  # pouch pocket
        HL(b, H(BCX - 3), H(BCX + 3), H(waist + 1) + 1, CA, 4)
    elif outfit == "performer":
        _pants(b, sk, CB, 1.0, 3.6)
        _boots(b, sk, LT, tall=True)
        _top(b, sk, CB, lo=1.4, hi=4.0, sleeves="none")
        for Y in range(H(sy), H(waist), 2):  # mesh
            for X in range(H(BCX - 3), H(BCX + 3) + 1, 2):
                P(b, X + (Y // 2) % 2, Y, SK, 3)
        _top(b, sk, CA, length=waist - 3, extra=1.0, lo=1.6, hi=4.6, open_front=True, inner=CB)
        HL(b, H(BCX - sk["waist_w"] - 1), H(BCX - 1), H(waist - 3), GL, 4)
        HL(b, H(BCX + 1), H(BCX + sk["waist_w"] + 1), H(waist - 3), GL, 3)
    elif outfit == "technician":
        _pants(b, sk, CA, 1.2, 3.8)
        _boots(b, sk, LT, steel=True)
        _top(b, sk, CA, lo=1.4, hi=4.0)  # jumpsuit
        zipper(b, H(BCX), H(sy), H(waist))
        for side in (-1, 1):  # harness
            VL(b, H(BCX + side * 3), H(sy), H(waist + 2), LT, 2)
            VL(b, H(BCX + side * 3) + 1, H(sy), H(waist + 2), LT, 3 if side < 0 else 1)
        _belt(b, sk, LT)
        for k in range(4):  # tool belt
            VL(b, H(BCX - 5 + k * 3), H(waist + 3), H(waist + 6), MT, 5 - k % 2)
        P(b, H(BCX - 3), H(sy + 3), GL, 7)
        P(b, H(BCX - 3) + 1, H(sy + 3), GL, 5)
        _grime(b, rng, 10, (6, 22, 34, 76))
    elif outfit == "military":
        _pants(b, sk, CA, 1.2, 3.6, baggy=0.3)
        _boots(b, sk, LT, tall=True)
        _top(b, sk, CA, lo=1.2, hi=3.8)
        for k in range(2):
            HL(b, H(BCX - sk["waist_w"]), H(BCX + sk["waist_w"]), H(sy + 6 + k * 5), CB, 2)
            HL(b, H(BCX - sk["waist_w"]), H(BCX + sk["waist_w"]), H(sy + 6 + k * 5) + 1, CB, 1)
        for side in (-1, 1):
            VL(b, H(BCX + side * 3), H(sy), H(waist), CB, 2)
        _belt(b, sk, CB)
        P(b, H(sk["sh_r"][0] - 1), H(sk["sh_r"][1] + 3), CC, 4)  # rank patch
        P(b, H(sk["sh_r"][0] - 1) + 1, H(sk["sh_r"][1] + 3), CC, 5)
    elif outfit == "patient":
        _top(b, sk, CA, length=56, extra=0.8, lo=3.0, hi=5.6, sleeves="short")  # gown
        for side in ("l", "r"):  # bare shins, socks
            ax, ay = sk["an_" + side]
            HL(b, H(ax - 2), H(ax + 2), H(ay + 2), CB, 5)
            HL(b, H(ax - 2), H(ax + 2), H(ay + 3), CB, 3)
        for k in range(15):  # IV lead + tape
            P(b, H(sk["wr_l"][0] - 1), H(sk["wr_l"][1]) - k * 2, MT, 4)
        P(b, H(sk["el_l"][0]), H(sk["el_l"][1] + 2), CB, 6)
        P(b, H(sk["el_l"][0]) + 1, H(sk["el_l"][1] + 2), CB, 5)
        for k in range(6):  # tie at the back
            P(b, H(BCX + 3), H(sy + 4) + k * 3, CA, 2)
        _grime(b, rng, 6, (8, 22, 32, 56), ramps=((BL, 3), (GR, 4)))
    elif outfit == "addict":
        _pants(b, sk, CC, 1.0, 3.4, baggy=0.4)
        _boots(b, sk, CB)
        _top(b, sk, CA, lo=2.0, hi=4.6, sleeves="none")
        _top(b, sk, CB, length=hip + 3, extra=1.0, lo=1.0, hi=3.2, open_front=True, inner=CA, sleeves="long")
        _grime(b, rng, 18, (6, 18, 34, 78), ramps=((GR, 2), (GR, 1), (BL, 2)))
        for k in range(4):  # torn knee
            P(b, H(sk["kn_l"][0]) + k - 2, H(sk["kn_l"][1]), SK, 3)
            P(b, H(sk["kn_l"][0]) + k - 2, H(sk["kn_l"][1]) + 1, FX, F_OUT)
    elif outfit == "elder":
        _pants(b, sk, CC, 1.2, 3.4, baggy=0.3)
        _boots(b, sk, LT)
        _top(b, sk, CA, length=58, extra=1.0, lo=1.2, hi=3.8)
        hx, hy = sk["head"]
        for X in range(H(hx - 3), H(hx + 4)):  # scarf
            P(b, X, H(sk["neck"][1]), CB, 4 - (X > H(hx)) + (X % 3 == 0))
            P(b, X, H(sk["neck"][1]) + 1, CB, 3 - (X > H(hx)))
        VL(b, H(BCX + 2), H(sk["neck"][1] + 1), H(sk["neck"][1] + 8), CB, 3)
        VL(b, H(BCX + 2) + 1, H(sk["neck"][1] + 1), H(sk["neck"][1] + 8), CB, 2)
        for k in range(3):  # buttons
            P(b, H(BCX) - 1, H(sy + 4) + k * 5, MT, 5)
        _grime(b, rng, 6, (8, 22, 32, 58))
    elif outfit == "netrunner":
        _pants(b, sk, CA, 1.0, 3.2)
        _boots(b, sk, CC)
        _top(b, sk, CA, lo=1.0, hi=3.6)
        for Y in range(H(sy + 2), H(70), 4):  # trace line down the suit
            P(b, H(BCX), Y, GL, 2)
            P(b, H(BCX), Y + 1, GL, 1)
        for side in ("l", "r"):
            x, y = sk["sh_" + side]
            P(b, H(x), H(y + 1), MT, 5)
            P(b, H(x), H(y + 2), GL, 5)
            P(b, H(x), H(y + 2) + 1, GL, 3)


BODY_HAIR = ["buzz", "short", "messy", "undercut", "slick", "long", "bob", "tied", "topknot", "mohawk", "locs",
             "receding", "braids", "shaved"]


def draw_body_hair(b: HDCanvas, style: str, build: str, posture: str, rng):
    if style == "bald":
        return
    sk = skeleton(build, posture)
    hx, hy = sk["head"]
    hx += 0.5
    rx, ry = sk["head_r"]

    def cap(top_extra=0.6, down=-1.0, side=1.0):
        for X, Y, x, y in grid(hx - rx - 2, hy - ry - 2, hx + rx + 3, hy + 2):
            if ((x + 0.5 - hx) / (rx + side * 0.6)) ** 2 + ((y + 0.5 - hy + 0.4) / (ry + top_extra)) ** 2 <= 1 \
                    and y <= hy + down:
                v = 2 + (x < hx) - (rng.random() < 0.2) + ((X + Y // 2) % 3 == 0 and y < hy - 2)
                P(b, X, Y, HR, v)
    if style == "buzz":
        cap(0.2, -2.5)
    elif style in ("short", "messy", "slick", "receding", "undercut", "shaved", "topknot"):
        cap(0.8 if style != "messy" else 1.3, -2.0)
        if style == "topknot":
            b.lsphere(hx, hy - ry - 1.5, 1.8, 1.5, HR, lo=1.0, hi=4.0)
        if style == "messy":
            for k in range(5):
                P(b, H(hx - 2) + k * 2, H(hy - ry - 1.5), HR, 3)
                P(b, H(hx - 2) + k * 2, H(hy - ry - 1.5) - 1, HR, 2)
        if style == "slick":
            HL(b, H(hx - 2), H(hx + 1), H(hy - ry) + 1, HR, 5)
    elif style in ("long", "bob", "braids", "locs"):
        cap(1.0, -1.5)
        bottom = {"long": hy + 12, "bob": hy + 4, "braids": hy + 14, "locs": hy + 12}[style]
        for side in (-1, 1):
            x = hx + side * (rx + 0.5)
            for Y in range(H(hy - 1), H(bottom)):
                P(b, H(x), Y, HR, 2 if side < 0 else 1)
                P(b, H(x) + side, Y, HR, 1)
                if style in ("braids", "locs") and Y % 3 == 0:
                    P(b, H(x), Y, HR, 3)
    elif style == "tied":
        cap(0.5, -2.0)
        for Y in range(H(hy - 1), H(hy + 7)):
            P(b, H(hx + rx + 0.8), Y, HR, 1)
            P(b, H(hx + rx + 0.8) + 1, Y, HR, 2 if Y % 3 else 1)
    elif style == "mohawk":
        for Y in range(H(hy - ry - 3), H(hy - 1)):
            P(b, H(hx), Y, HR, 3)
            P(b, H(hx) + 1, Y, HR, 2)
            P(b, H(hx) - 1, Y, HR, 2 if Y % 2 else 1)


BODY_CYBER = ["arm_l", "arm_r", "legs", "eye", "face_plate", "spine", "shoulder", "hands", "jaw"]


def draw_body_cyber(b: HDCanvas, kind: str, build: str, posture: str):
    sk = skeleton(build, posture)
    r = sk["r"]
    hx, hy = sk["head"]
    HX, HY = H(hx + 0.5), H(hy)
    if kind in ("arm_l", "arm_r"):
        side = kind[-1]
        _limb(b, sk["el_" + side], sk["wr_" + side], r + 0.4, MT, lo=1.6, hi=6.0)
        _hand(b, sk, side, MT, 1.6, 6.0)
        ex, ey = sk["el_" + side]
        wx, wy = sk["wr_" + side]
        P(b, H(ex), H(ey), GL, 4)
        P(b, H(ex), H(ey) + 1, GL, 2)
        for k in range(1, 4):  # segment seams
            t = k / 4
            X, Y = H(ex + (wx - ex) * t), H(ey + (wy - ey) * t)
            HL(b, X - 1, X + 1, Y, FX, F_OUT)
    elif kind == "legs":
        for side in ("l", "r"):
            kx, ky = sk["kn_" + side]
            _limb(b, sk["kn_" + side], sk["an_" + side], r + 0.6, MT, lo=1.4, hi=5.6)
            P(b, H(kx), H(ky), GL, 4)
            P(b, H(kx), H(ky) + 1, GL, 2)
            ax, ay = sk["an_" + side]
            HL(b, H(kx - 1), H(kx + 1), H((ky + ay) / 2), FX, F_OUT)
    elif kind == "eye":
        P(b, HX + 2, HY + 1, GL, 7)
        P(b, HX + 3, HY + 1, GL, 4)
    elif kind == "face_plate":
        for X, Y, x, y in grid(hx + 1.5, hy - 3, hx + sk["head_r"][0] + 1.5, hy + 4):
            P(b, X, Y, MT, 4 - (x > hx + 2.5) + (Y == H(hy - 3)))
        P(b, HX + 2, HY + 1, GL, 7)
        VL(b, HX + 1, H(hy - 3), H(hy + 4) - 1, MT, 6)
    elif kind == "spine":
        nx, ny = sk["neck"]
        for side in ("l", "r"):
            x, y = sk["sh_" + side]
            LN(b, H(nx), H(ny), H(x), H(y + 1), MT, 4 if side == "l" else 2)
            LN(b, H(nx), H(ny) + 1, H(x), H(y + 1) + 1, FX, F_OUT)
        P(b, H(nx), H(ny), GL, 5)
    elif kind == "shoulder":
        x, y = sk["sh_r"]
        b.lsphere(x + 0.5, y + 1, 3.4, 3.0, MT, lo=1.4, hi=6.0)
        HL(b, H(x - 2), H(x + 3), H(y + 1), MT, 2)
        P(b, H(x + 1), H(y + 2), GL, 5)
    elif kind == "hands":
        for side in ("l", "r"):
            _hand(b, sk, side, MT, 1.6, 6.0)
    elif kind == "jaw":
        HL(b, HX - 1, HX + 4, HY + 4, MT, 5)
        HL(b, HX - 1, HX + 4, HY + 5, MT, 3)
        HL(b, HX - 1, HX + 4, HY + 6, MT, 2)


BODY_ACC = ["backpack", "rifle", "holster", "blade", "toolbelt", "briefcase", "cane", "crutch", "cigarette",
            "hood", "helmet", "medkit", "datapad", "bandolier", "shoulder_lamp", "respirator", "cap", "beanie",
            "mask", "eyewear"]


def draw_body_acc(b: HDCanvas, kind: str, build: str, posture: str):
    sk = skeleton(build, posture)
    hx, hy = sk["head"]
    hx += 0.5
    rx, ry = sk["head_r"]
    HX, HY = H(hx), H(hy)
    if kind == "backpack":
        for side in ("l", "r"):
            x, y = sk["sh_" + side]
            VL(b, H(x + (1 if side == "l" else -1)), H(y), H(y + 12), LT, 2)
            VL(b, H(x + (1 if side == "l" else -1)) + 1, H(y), H(y + 12), LT, 3 if side == "l" else 1)
        plate(b, int(sk["sh_r"][0]) + 1, int(sk["sh_r"][1]) + 1, int(sk["sh_r"][0]) + 3, int(sk["waist_y"]), CC, lo=1, hi=3)
    elif kind == "rifle":
        x0, y0 = sk["sh_r"][0] + 2, sk["sh_r"][1] - 3
        for k in range(39):
            X, Y = H(x0) - int(k * 0.15), H(y0) + k
            ramp = MT if k < 27 else LT
            P(b, X, Y, ramp, 3 if k % 7 else 5)
            P(b, X + 1, Y, ramp, 2)
        P(b, H(x0 + 1), H(y0 + 12), MT, 2)
        P(b, H(x0 + 1) + 1, H(y0 + 12), MT, 1)
    elif kind == "holster":
        hx2 = BCX + sk["hip_w"] + 1
        plate(b, int(hx2) - 1, sk["hip_y"] - 2, int(hx2) + 1, sk["hip_y"] + 5, LT, lo=1, hi=3)
        P(b, H(hx2), H(sk["hip_y"] - 3), MT, 4)
        P(b, H(hx2) + 1, H(sk["hip_y"] - 3), MT, 6)
    elif kind == "blade":
        x, y = sk["hip_l"][0] - 3, sk["hip_y"] - 4
        for k in range(21):
            P(b, H(x) + int(k * 0.1), H(y) + k, MT, 6 if k > 5 else 2)
            if k > 5:
                P(b, H(x) + int(k * 0.1) + 1, H(y) + k, MT, 3)
    elif kind == "toolbelt":
        for k in range(5):
            VL(b, H(BCX - 6 + k * 3), H(sk["waist_y"] + 3), H(sk["waist_y"] + 7), MT if k % 2 else LT, 4 if k % 2 else 2)
            VL(b, H(BCX - 6 + k * 3) + 1, H(sk["waist_y"] + 3), H(sk["waist_y"] + 7), MT if k % 2 else LT, 2 if k % 2 else 1)
        _belt(b, sk, LT)
    elif kind == "briefcase":
        wx, wy = sk["wr_r"]
        plate(b, int(wx) - 2, int(wy) + 2, int(wx) + 3, int(wy) + 7, CC, lo=1, hi=3)
        HL(b, H(wx) - 1, H(wx) + 1, H(wy) + 2, MT, 5)
    elif kind in ("cane", "crutch"):
        wx, wy = sk["wr_r"]
        ax, ay = sk["an_r"]
        LN(b, H(wx + 1), H(wy), H(ax + 3), H(ay + 3), MT if kind == "crutch" else LT, 4)
        LN(b, H(wx + 1) + 1, H(wy), H(ax + 3) + 1, H(ay + 3), MT if kind == "crutch" else LT, 2)
        if kind == "crutch":
            HL(b, H(wx - 1), H(wx + 3), H(sk["el_r"][1]), MT, 4)
    elif kind == "cigarette":
        wx, wy = sk["wr_l"]
        P(b, H(wx), H(wy + 2), CB, 6)
        P(b, H(wx), H(wy + 2) + 1, CB, 5)
        P(b, H(wx), H(wy + 3) + 1, GL, 7)
    elif kind == "hood":
        for X, Y, x, y in grid(hx - rx - 2, hy - ry - 1.5, hx + rx + 3, hy + ry):
            outer = ((x + 0.5 - hx) / (rx + 1.6)) ** 2 + ((y + 0.5 - hy) / (ry + 1.4)) ** 2 <= 1
            inner = ((x + 0.5 - hx) / (rx - 0.6)) ** 2 + ((y + 0.5 - hy - 1.2) / (ry - 1.0)) ** 2 <= 1
            if outer and not inner:
                P(b, X, Y, CC, 3 - (x > hx) - (y > hy + 2) + ((X + Y) % 5 == 0))
    elif kind == "helmet":
        b.lsphere(hx, hy - 1.2, rx + 0.9, ry - 0.4, CA, lo=1.4, hi=5.0)
        HL(b, H(hx - rx), H(hx + rx), H(hy), MT, 5)
        HL(b, H(hx - rx + 1), H(hx + rx - 1), H(hy + 0.9), GL, 3)
        HL(b, H(hx - rx + 1), H(hx), H(hy + 0.9), GL, 5)
    elif kind == "medkit":
        x, y = sk["hip_l"]
        plate(b, int(x) - 3, int(y) - 1, int(x), int(y) + 3, CB, lo=3, hi=5)
        P(b, H(x - 1.5), H(y + 1), BL, 4)
        P(b, H(x - 1.5) - 1, H(y + 1), BL, 4)
        P(b, H(x - 1.5) + 1, H(y + 1), BL, 4)
        P(b, H(x - 1.5), H(y + 1) - 1, BL, 4)
        P(b, H(x - 1.5), H(y + 1) + 1, BL, 4)
    elif kind == "datapad":
        wx, wy = sk["wr_l"]
        plate(b, int(wx) - 1, int(wy) - 2, int(wx) + 2, int(wy) + 2, MT)
        for k in range(3):
            HL(b, H(wx) - 1, H(wx) + 2 - k, H(wy) - 2 + k * 2, GL, 4 - k)
    elif kind == "bandolier":
        for k in range(24):
            X, Y = H(sk["sh_r"][0]) - int(k * 0.8), H(sk["sh_r"][1]) + int(k * 1.2)
            P(b, X, Y, LT, 2)
            P(b, X + 1, Y, LT, 3)
            if k % 4 == 0:
                P(b, X, Y - 1, MT, 6)
                P(b, X + 1, Y - 1, MT, 4)
    elif kind == "shoulder_lamp":
        x, y = sk["sh_l"]
        plate(b, int(x) - 1, int(y) - 2, int(x) + 1, int(y), MT)
        P(b, H(x - 1), H(y - 1), GL, 7)
        P(b, H(x - 1) + 1, H(y - 1), GL, 5)
    elif kind == "respirator":
        HL(b, HX - 3, HX + 3, H(hy + 2.5), CB, 2)
        HL(b, HX - 3, HX + 3, H(hy + 2.5) + 1, CB, 1)
        P(b, HX - 3, H(hy + 3.5), MT, 5)
        P(b, HX + 3, H(hy + 3.5), MT, 2)
    elif kind == "mask":
        for X, Y, x, y in grid(hx - rx, hy + 1, hx + rx + 1, hy + ry + 2):
            if ((x + 0.5 - hx) / (rx + 0.4)) ** 2 + ((y + 0.5 - hy) / (ry + 0.6)) ** 2 <= 1.15:
                P(b, X, Y, CC, 4 - (x > hx) - (y > hy + 2))
        HL(b, HX - 3, HX + 3, H(hy + 1) + 1, CC, 5)
    elif kind == "eyewear":
        HL(b, HX - 4, HX + 3, HY + 1, CC, 0)
        HL(b, HX - 3, HX + 2, HY + 2, CC, 1)
        P(b, HX - 3, HY + 1, FX, F_LENS)
        P(b, HX + 1, HY + 1, FX, F_LENS)
    elif kind in ("cap", "beanie"):
        for X, Y, x, y in grid(hx - rx - 1, hy - ry - 1, hx + rx + 2, hy - 1):
            if ((x + 0.5 - hx) / (rx + 0.6)) ** 2 + ((y + 0.5 - hy + 0.4) / (ry + 0.8)) ** 2 <= 1:
                P(b, X, Y, CC, 3 - (x > hx) + (kind == "beanie" and X % 3 == 0))
        if kind == "cap":
            HL(b, H(hx - rx - 1), H(hx + 1), H(hy - 1.5), CC, 1)
            HL(b, H(hx - rx - 1), H(hx + 1), H(hy - 1.5) + 1, CC, 2)
