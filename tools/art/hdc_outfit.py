"""HD portrait neck, shoulders and occupational outfits."""
from __future__ import annotations

import random

from .hdc_core import (S, SK, HR, CA, CB, MT, GL, FX, CC, LT, GR, BL, F_OUT,
                       HDCanvas, grid, f, hl, vl, P, HL, VL, LN, H, plate, stitch_h, stitch_v, zipper, screw, span)
from .hdc_face import CX, HCX, PH, mirror

BUILDS = ["slim", "average", "heavy", "muscular"]
SHOULDER = {"slim": 23, "average": 27, "heavy": 33, "muscular": 34}
HPH = int(round(PH * S))


def neck_w(build):
    return {"slim": 6, "average": 7, "heavy": 9, "muscular": 9}[build]


def torso_outline(build, sh=None):
    s = SHOULDER[build] if sh is None else sh
    n = neck_w(build)
    half = [(n, 73), (n + 5, 78), (s - 8, 82), (s - 2, 86), (s + 1, 92), (s + 3, 102), (s + 4, PH + 1)]
    return mirror(half)


def draw_bust_base(c: HDCanvas, build: str):
    n = neck_w(build)
    for X, Y, x, y in grid(CX - n, 58, CX + n + 1, 82):
        t = (x - CX) / n
        c.shade_px(X, Y, SK, 3.8 - t * 1.8 - (2.2 if y < 70 else 0.4 if y < 74 else 0))
    # Neck: the sternocleidomastoid lines and the throat shadow.
    for side in (-1, 1):
        LN(c, HCX + side * (H(n) - 3), H(66), HCX + side * 3, H(80), SK, 2 if side > 0 else 3)
    c.lshaded_poly(torso_outline(build), SK, top=4.6, bottom=2.6, left_bias=1.6, edge_dark=0.8)
    # Collarbones and the sternum notch.
    for side in (-1, 1):
        for k in range(15):
            Y = H(85) + (k > 10) + (k > 13)
            P(c, HCX + side * (4 + k), Y, SK, 2 if side > 0 else 3)
            P(c, HCX + side * (4 + k), Y - 1, SK, 5 if side < 0 else 3)
    P(c, HCX, H(84), SK, 2)
    P(c, HCX, H(84) + 1, SK, 2)
    if build == "muscular":
        for side in (-1, 1):  # trapezius ridge
            for k in range(9):
                P(c, HCX + side * (H(n) + 1 + k), H(78) + k // 3, SK, 5 if side < 0 else 2)


OUTFITS = ["corporate", "executive", "security", "gang", "worker", "mercenary", "ripperdoc", "medic", "fixer",
           "dealer", "civilian", "performer", "technician", "military", "patient", "addict", "elder", "netrunner"]


def _garment(c, build, ramp, top=4.6, bottom=2.2, inset=0, y0=None, sh_extra=0):
    pts = torso_outline(build, SHOULDER[build] + sh_extra)
    if y0 is not None:
        pts = [(x, max(y, y0)) for x, y in pts]
    if inset:
        pts = [(x + (inset if x < CX + 0.5 else -inset), y) for x, y in pts]
    c.lshaded_poly(pts, ramp, top=top, bottom=bottom, left_bias=1.8, edge_dark=0.9)
    # Shoulder seams: a darker line with a lit edge where the sleeve joins.
    s = SHOULDER[build] + sh_extra - inset
    for side in (-1, 1):
        x0 = CX + 0.5 + side * (s - 6)
        for k in range(14):
            X, Y = H(x0) + side * (k // 4), H(84) + k
            if c.has(X, Y, ramp):
                P(c, X, Y, ramp, 1)
                if c.has(X - side, Y, ramp):
                    P(c, X - side, Y, ramp, 4 if side < 0 else 2)


def _folds(c, rng, build, ramp, n=10, y0=92):
    """Cloth folds: a dark crease with a lit ridge beside it."""
    s = SHOULDER[build]
    for _ in range(n):
        X = rng.randint(H(CX - s), H(CX + s))
        Y = rng.randint(H(y0), HPH - 6)
        for k in range(rng.randint(5, 11)):
            xx, yy = X + k // 3, Y + k
            if c.has(xx, yy, ramp):
                P(c, xx, yy, ramp, 1 if X > HCX else 2)
                if c.has(xx - 1, yy, ramp):
                    P(c, xx - 1, yy, ramp, 4 if X < HCX else 3)


def _collar_v(c, ramp, depth=96, w=8, shade=1):
    for Y in span(76, depth):
        y = (Y + 0.5) / S - 0.5
        t = (y - 76) / (depth - 76)
        half = w * (1 - t) + 1
        for X in range(H(CX + 0.5 - half), H(CX + 0.5 + half) + 1):
            c.set(X, Y, None)
    for Y in span(76, depth):  # lapel edges: lit left, shadowed right, 2 px
        y = (Y + 0.5) / S - 0.5
        t = (y - 76) / (depth - 76)
        half = w * (1 - t) + 1
        xl, xr = H(CX + 0.5 - half) - 1, H(CX + 0.5 + half) + 1
        P(c, xl, Y, ramp, shade + 3)
        P(c, xl - 1, Y, ramp, shade + 2)
        P(c, xr, Y, ramp, shade)
        P(c, xr + 1, Y, ramp, shade + 1)


def _sleeve_seams(c, build, ramp):
    s = SHOULDER[build]
    for side in (-1, 1):
        x = CX + 0.5 + side * (s - 4)
        for Y in range(H(88), HPH):
            if Y % 3 == 0:
                P(c, H(x) + side * ((Y - H(88)) // 15), Y, ramp, 1)


def _stains(c, rng, ramp_shade_list, n, box):
    x0, y0, x1, y1 = box
    for _ in range(n):
        cx, cy = rng.uniform(x0, x1), rng.uniform(y0, y1)
        r = rng.uniform(1.0, 3.2)
        for X, Y, x, y in grid(cx - r, cy - r, cx + r + 1, cy + r + 1):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r and c.get(X, Y) is not None and rng.random() < 0.78:
                P(c, X, Y, *rng.choice(ramp_shade_list))


def _leather_sheen(c, rng, ramp, n=16, box=None):
    x0, y0, x1, y1 = box
    for _ in range(int(n * 1.8)):
        X, Y = rng.randint(H(x0), H(x1)), rng.randint(H(y0), H(y1))
        if c.has(X, Y, ramp):
            P(c, X, Y, ramp, 6 if X < HCX else 5)
            if rng.random() < 0.6 and c.has(X + 1, Y):
                P(c, X + 1, Y, ramp, 5 if X < HCX else 4)
            if rng.random() < 0.3 and c.has(X, Y + 1):
                P(c, X, Y + 1, ramp, 2)


def _buttons(c, X, Y0, Y1, ramp=MT, step=9):
    for Y in range(Y0, Y1, step):
        P(c, X, Y, ramp, 6)
        P(c, X + 1, Y, ramp, 3)
        P(c, X, Y + 1, ramp, 2)


def draw_outfit(c: HDCanvas, outfit: str, build: str, rng):
    s = SHOULDER[build]
    nw = neck_w(build)
    if outfit == "corporate":
        _garment(c, build, CA, top=4.0, bottom=2.0, sh_extra=1)
        _collar_v(c, CA, depth=100, w=9)
        for Y in span(76, 100):  # shirt in the V, with a placket line
            y = (Y + 0.5) / S - 0.5
            half = 9 * (1 - (y - 76) / 24) + 1
            HL(c, H(CX + 0.5 - half), H(CX + 0.5 + half), Y, CB, 6 if y < 80 else 5)
        for Y in span(78, 100):  # tie with a knot and a sheen line
            y = (Y + 0.5) / S - 0.5
            w = 2 if y < 80 else (2 + (y > 90))
            HL(c, HCX - w + 1, HCX + w, Y, CC, 2 + (y < 80))
            P(c, HCX - w + 2, Y, CC, 4)
        HL(c, H(CX - 4), H(CX + 4), H(75), CB, 6)  # collar points
        P(c, H(CX - 4), H(75) + 1, CB, 4)
        P(c, H(CX + 4), H(75) + 1, CB, 3)
        HL(c, H(CX + s - 14), H(CX + s - 9), H(98), CB, 6)  # pocket square
        HL(c, H(CX + s - 13), H(CX + s - 10), H(98) - 1, CB, 5)
        stitch_h(c, H(CX - s + 6), H(CX - s + 14), H(104), CA, 1)  # pocket welt
        _sleeve_seams(c, build, CA)
    elif outfit == "executive":
        _garment(c, build, CA, top=3.6, bottom=1.6, sh_extra=2)
        for X, Y, x, y in grid(CX - nw - 4, 66, CX + nw + 5, 82):
            if abs(x - CX) >= nw - 1:
                c.shade_px(X, Y, CA, 4.6 - (x > CX) * 2.0 - (y > 76))
        VL(c, H(CX + 2), H(80), HPH - 1, CA, 1)   # closure
        VL(c, H(CX + 2) - 1, H(80), HPH - 1, CA, 4)
        stitch_v(c, H(CX + 2) + 2, H(82), HPH - 2, CA, 2)
        plate(c, CX - 2, 88, CX + 3, 91, MT)
        P(c, H(CX + 1), H(89), GL, 5)
        P(c, H(CX + 1) + 1, H(89), GL, 3)
    elif outfit == "security":
        _garment(c, build, CA, top=4.0, bottom=1.8)
        for side in (-1, 1):  # shoulder armour
            x0 = CX + side * (s - 10) - (10 if side > 0 else 0)
            plate(c, min(x0, x0 + side * 12), 84, max(x0, x0 + side * 12), 96, MT, screws=True)
        plate(c, CX - 12, 92, CX + 12, PH - 2, MT, lo=1.6, hi=4.6, screws=True)  # chest plate
        HL(c, H(CX - 10), H(CX + 10), H(100), MT, 1)
        HL(c, H(CX - 10), H(CX + 10), H(100) + 1, MT, 5)
        for X, Y, x, y in grid(CX - nw - 2, 66, CX - nw + 1, 80):  # collar guard
            P(c, X, Y, CB, 3)
        for X, Y, x, y in grid(CX + nw, 66, CX + nw + 3, 80):
            P(c, X, Y, CB, 1)
        plate(c, CX - 9, 95, CX - 4, 99, CC, lo=3, hi=6)  # badge
        P(c, H(CX - 7), H(97), GL, 6)
        P(c, H(CX - 7) + 1, H(97), GL, 4)
    elif outfit == "gang":
        _garment(c, build, CB, top=3.4, bottom=1.6, inset=6)
        _garment(c, build, LT, top=3.6, bottom=1.4)
        _collar_v(c, LT, depth=PH, w=12, shade=0)
        for Y in span(80, PH):
            y = (Y + 0.5) / S - 0.5
            half = 12 * (1 - (y - 76) / (PH - 76)) + 2
            HL(c, H(CX + 0.5 - half), H(CX + 0.5 + half), Y, CB, 2 + (y < 86) - (Y % 10 == 0))
        for Y in range(H(96), H(104)):  # tear in the shirt
            P(c, HCX - 2 + (Y % 4), Y, SK, 3)
            P(c, HCX - 1 + (Y % 4), Y, FX, F_OUT)
        plate(c, CX - s - 1, 82, CX - s + 13, 94, MT, lo=1.0, hi=5.0)
        for k in range(5):  # spikes
            X = H(CX - s + 1) + k * 5
            for d in range(6):
                HL(c, X - (d > 2), X + (d > 2), H(82) - d, MT, 6 if d > 1 else 4)
        for k in range(8):
            P(c, H(CX + s - 6), H(90) + k * 4, MT, 7)  # studs on the right lapel
            P(c, H(CX + s - 6) + 1, H(90) + k * 4 + 1, MT, 3)
        _leather_sheen(c, rng, LT, 26, (CX - s, 86, CX + s, PH - 1))
        for k in range(8):  # faction patch with a stitched border
            HL(c, H(CX + s - 14), H(CX + s - 8), H(100) + k, CC, 3 if 0 < k < 7 else 5)
        stitch_v(c, H(CX + s - 14) - 1, H(100), H(100) + 7, CC, 6, 1)
    elif outfit == "worker":
        _garment(c, build, CA, top=3.8, bottom=1.8, sh_extra=3)
        for k in range(4):  # quilting with stitching
            Y = H(92 + k * 6)
            HL(c, H(CX - s - 2), H(CX + s + 2), Y, CA, 1)
            stitch_h(c, H(CX - s - 2), H(CX + s + 2), Y + 1, CA, 4, 3)
        for side in (-1, 1):
            for Y in range(H(88), HPH):  # hi-vis stripes
                for d in range(3):
                    P(c, H(CX + 0.5 + side * (s - 8)) + d, Y, CB, (6 if side < 0 else 4) - (d == 2))
        HL(c, H(CX - s), H(CX + s), H(104), CB, 5)
        HL(c, H(CX - s), H(CX + s), H(104) + 1, CB, 6)
        HL(c, H(CX - s), H(CX + s), H(104) + 2, CB, 3)
        _collar_v(c, CA, depth=86, w=6)
        for X, Y, x, y in grid(CX - 3, 76, CX + 4, 86):
            P(c, X, Y, CC, 3 + (X < HCX))
        zipper(c, HCX + 1, H(86), HPH - 1)
        _stains(c, rng, [(GR, 2), (GR, 3), (GR, 1)], 9, (CX - s, 90, CX + s, PH - 2))
    elif outfit == "mercenary":
        _garment(c, build, CB, top=3.6, bottom=1.8)
        plate(c, CX - s + 6, 86, CX + s - 6, PH - 1, CA, lo=1.4, hi=4.2)  # plate carrier
        stitch_h(c, H(CX - s + 7), H(CX + s - 7), H(88), CA, 4, 2)
        for k in range(3):  # magazine pouches with flaps
            plate(c, CX - 14 + k * 10, 100, CX - 7 + k * 10, PH - 1, CC, lo=1.5, hi=4.0)
            HL(c, H(CX - 14 + k * 10) + 1, H(CX - 7 + k * 10), H(102), CC, 1)
            P(c, H(CX - 10.5 + k * 10), H(103), MT, 5)
        for k in range(24):  # sling strap
            X, Y = H(CX - s + 6) + k * 2 - k // 2, H(86) + k
            P(c, X, Y, LT, 3)
            P(c, X + 1, Y, LT, 2)
            P(c, X + 2, Y, LT, 1)
        for X, Y, x, y in grid(CX - nw - 3, 70, CX + nw + 4, 82):
            P(c, X, Y, CB, 2 + (y < 72) + ((X + Y) % 4 == 0))
        _stains(c, rng, [(GR, 2), (GR, 1)], 5, (CX - s, 92, CX + s, PH - 2))
    elif outfit == "ripperdoc":
        _garment(c, build, CB, top=3.8, bottom=2.0)
        for X, Y, x, y in grid(CX - 26, 84, CX + 27, PH):  # leather apron
            half = 14 + (y - 84) / 4
            if abs(x - CX) <= half:
                c.shade_px(X, Y, LT, 3.6 - (x - CX) / half * 1.2 - (y - 84) / 40)
        for Y in range(H(84), HPH):  # apron edge stitching
            for side in (-1, 1):
                y = (Y + 0.5) / S - 0.5
                X = H(CX + 0.5 + side * (14 + (y - 84) / 4)) - side * 2
                if Y % 3 == 0:
                    P(c, X, Y, LT, 5)
        for side in (-1, 1):
            VL(c, H(CX + side * (nw + 1)), H(70), H(86), LT, 2)
            VL(c, H(CX + side * (nw + 1)) + 1, H(70), H(86), LT, 3 if side < 0 else 1)
        _leather_sheen(c, rng, LT, 18, (CX - 20, 86, CX + 20, PH - 1))
        _stains(c, rng, [(BL, 2), (BL, 3), (BL, 1), (GR, 2)], 9, (CX - 16, 90, CX + 16, PH - 2))
        for k in range(5):  # tool loops on the apron: scalpel, probe, clamp...
            X = H(CX - 12) + k * 7
            VL(c, X, H(94), H(102), MT, 6 - (k % 2) * 2)
            VL(c, X + 1, H(94), H(102), MT, 3)
            P(c, X, H(93), MT, 7)
        HL(c, H(CX - 18), H(CX + 18), H(96), LT, 1)
        HL(c, H(CX - 18), H(CX + 18), H(96) + 1, LT, 4)
    elif outfit == "medic":
        _garment(c, build, CB, top=5.0, bottom=2.6, sh_extra=1)
        _collar_v(c, CB, depth=104, w=10, shade=2)
        for Y in span(76, 104):
            y = (Y + 0.5) / S - 0.5
            half = 10 * (1 - (y - 76) / 28) + 1
            HL(c, H(CX + 0.5 - half), H(CX + 0.5 + half), Y, CA, 3 + (y < 80))
        _buttons(c, H(CX - 11), H(92), HPH - 2, CB)
        _stains(c, rng, [(GR, 4), (GR, 3), (BL, 3), (BL, 2)], 10, (CX - s, 88, CX + s, PH - 2))
        plate(c, CX + s - 16, 96, CX + s - 9, 104, CC, lo=3, hi=6)  # ID card
        HL(c, H(CX + s - 15), H(CX + s - 11), H(101), CC, 2)
        P(c, H(CX + s - 13), H(98), GL, 4)
        VL(c, H(CX + s - 12), H(84), H(95), CC, 1)
        stitch_h(c, H(CX - s + 4), H(CX - s + 13), H(100), CB, 3)  # breast pocket
    elif outfit == "fixer":
        _garment(c, build, CA, top=3.4, bottom=1.4, sh_extra=3)
        _collar_v(c, CA, depth=PH, w=11, shade=1)
        for Y in span(80, PH):
            y = (Y + 0.5) / S - 0.5
            half = 11 * (1 - (y - 76) / (PH - 76)) + 1
            HL(c, H(CX + 0.5 - half), H(CX + 0.5 + half), Y, CB, 2 + (y < 84))
        for side in (-1, 1):  # big leather collar
            for X, Y, x, y in grid(CX - 30, 62, CX + 31, 84):
                k = side * (x - CX) - (nw + 2) - (y - 62) / 4
                if 0 <= k < 5:
                    c.shade_px(X, Y, LT, 4.2 - k / 2 - (side > 0) * 2)
        for k in range(21):  # chain links
            X, Y = H(CX - 7) + k, H(84) + abs(k - 10) // 3
            P(c, X, Y, MT, 6 if k % 3 == 0 else (4 if k % 3 == 1 else 2))
        _leather_sheen(c, rng, LT, 10, (CX - 22, 62, CX + 22, 84))
    elif outfit == "dealer":
        _garment(c, build, CA, top=3.4, bottom=1.4, sh_extra=2)
        for side in (-1, 1):  # hood bunched behind the neck
            for X, Y, x, y in grid(CX - 20, 64, CX + 21, 84):
                k = side * (x - CX) - (nw + 1)
                if 0 <= k < 7 and y > 64 + k:
                    c.shade_px(X, Y, CA, 4.2 - k / 3 - (side > 0) - ((X + Y) % 5 == 0) * 0.6)
        _collar_v(c, CA, depth=PH, w=9)
        for Y in span(80, PH):
            y = (Y + 0.5) / S - 0.5
            half = 9 * (1 - (y - 76) / (PH - 76)) + 1
            HL(c, H(CX + 0.5 - half), H(CX + 0.5 + half), Y, CB, 1 + (Y % 7 == 0))
        for k in range(3):  # chains
            for j in range(15):
                P(c, H(CX - 5) + j, H(86 + k * 5) + abs(j - 7) // 3, MT, 6 if j % 2 else 3)
    elif outfit == "civilian":
        _garment(c, build, CA, top=4.2, bottom=2.0)  # hoodie
        for side in (-1, 1):
            for X, Y, x, y in grid(CX - 16, 70, CX + 17, 86):
                k = side * (x - CX) - nw
                if 0 <= k < 6:
                    c.shade_px(X, Y, CA, 4.2 - k / 2 - (side > 0) * 2)
        for side in (-1, 1):  # drawstrings with metal tips
            VL(c, HCX + side * 6, H(84), H(98), CB, 5 if side < 0 else 3)
            P(c, HCX + side * 6, H(98) + 1, MT, 6)
            P(c, HCX + side * 6, H(98) + 2, MT, 3)
        HL(c, H(CX - 12), H(CX + 12), H(104), CA, 1)  # kangaroo pocket
        HL(c, H(CX - 12), H(CX + 12), H(104) + 1, CA, 4)
        for side in (-1, 1):
            LN(c, H(CX + side * 12), H(104), H(CX + side * 14), HPH - 1, CA, 1)
        _folds(c, rng, build, CA, 10)
    elif outfit == "performer":
        _garment(c, build, CB, top=4.4, bottom=2.0, inset=4)
        for X, Y, x, y in grid(CX - s + 6, 86, CX + s - 5, PH):  # mesh top
            if (X + Y) % 3 == 0:
                P(c, X, Y, SK, 3)
        for X, Y, x, y in grid(CX - s - 2, 84, CX + s + 3, 100):  # cropped jacket
            if x < CX - 10 or x >= CX + 11:
                c.shade_px(X, Y, CA, 4.0 - (x > CX) * 1.8 - (y - 84) / 10)
        HL(c, H(CX - s - 2), H(CX - 10), H(100), GL, 4)  # LED trim
        HL(c, H(CX - s - 2), H(CX - 10), H(100) + 1, GL, 2)
        HL(c, H(CX + 11), H(CX + s + 2), H(100), GL, 3)
        HL(c, H(CX + 11), H(CX + s + 2), H(100) + 1, GL, 1)
        for k in range(12):
            P(c, H(CX - s + 1) + k * 4, H(90) + (k % 3) * 2, CC, 6)  # sequins
    elif outfit == "technician":
        _garment(c, build, CA, top=4.0, bottom=2.0)  # jumpsuit
        zipper(c, HCX, H(76), H(92))
        for side in (-1, 1):  # harness straps with buckles
            for Y in range(H(80), HPH):
                X = H(CX + 0.5 + side * 10) + side * ((Y - H(80)) // 9)
                P(c, X, Y, LT, 3 if side < 0 else 1)
                P(c, X + side, Y, LT, 2)
                P(c, X + 2 * side, Y, LT, 1)
            plate(c, CX + side * 11 - 1, 98, CX + side * 11 + 1, 100, MT)
        plate(c, CX - 15, 90, CX - 9, 96, MT, screws=True)  # chest lamp
        for d in range(3):
            P(c, H(CX - 12) + d, H(93), GL, 7 - d)
        for k in range(4):
            VL(c, H(CX + 12) + k * 3, H(94), H(102), MT, 6 - k)  # pocket tools
        stitch_h(c, H(CX + 11), H(CX + 22), H(102), CA, 4, 1)
        _stains(c, rng, [(GR, 2), (GR, 3)], 7, (CX - s, 90, CX + s, PH - 2))
    elif outfit == "military":
        _garment(c, build, CA, top=3.8, bottom=1.8)
        for k in range(3):
            Y = H(96 + k * 6)
            HL(c, H(CX - s + 4), H(CX + s - 4), Y, CB, 2)
            HL(c, H(CX - s + 4), H(CX + s - 4), Y + 1, CB, 1)
            stitch_h(c, H(CX - s + 4), H(CX + s - 4), Y + 2, CB, 3, 4)
        for side in (-1, 1):
            VL(c, H(CX + 0.5 + side * 12), H(84), HPH - 1, CB, 2)
        plate(c, CX + s - 15, 86, CX + s - 7, 91, CC, lo=2, hi=5)  # rank patch
        for k in range(3):
            HL(c, H(CX + s - 14), H(CX + s - 9), H(87) + k * 2, MT, 6)
        for X, Y, x, y in grid(CX - nw - 2, 70, CX + nw + 3, 80):
            P(c, X, Y, CA, 2 + (y < 72))
        for k in range(6):  # dog tag chain
            P(c, HCX - 3 + k, H(82) + k, MT, 6 if k % 2 else 4)
    elif outfit == "patient":
        _garment(c, build, CA, top=5.6, bottom=3.0, inset=-1)  # thin gown
        for Y in span(76, 88):
            y = (Y + 0.5) / S - 0.5
            half = 6 * (1 - (y - 76) / 12) + 1
            for X in range(H(CX + 0.5 - half), H(CX + 0.5 + half) + 1):
                c.set(X, Y, None)
        rngx = random.Random(3)
        for k in range(4):  # electrode stickers + leads
            x, y = CX - 16 + k * 10, 90 + (k % 2) * 6
            plate(c, x, y, x + 3, y + 3, CB, lo=4, hi=6)
            P(c, H(x + 1.5), H(y + 1.5), MT, 5)
            for d in range(HPH - H(y + 4)):
                P(c, H(x + 1.5) + (d // 8) * (1 if k % 2 else -1), H(y + 4) + d, MT, 3 + (d % 2))
        _stains(c, rngx, [(BL, 3), (GR, 4)], 5, (CX - s, 92, CX + s, PH - 2))
        for k in range(12):  # print pattern
            P(c, H(CX - s + 3) + k * 6, H(90) + (k % 2) * 3, CA, 3)
            P(c, H(CX - s + 3) + k * 6 + 1, H(90) + (k % 2) * 3, CA, 3)
    elif outfit == "addict":
        _garment(c, build, CA, top=4.6, bottom=2.4, inset=5)  # stained tank
        for X, Y, x, y in grid(CX - 8, 76, CX + 9, 90):
            if abs(x - CX) < 9 - (y - 76) / 2:
                c.set(X, Y, None)
        for X, Y, x, y in grid(CX - s - 2, 86, CX + s + 3, PH):  # torn open hoodie
            if x < CX - s + 8 or x >= CX + s - 7:
                c.shade_px(X, Y, CB, 3.2 - (x > CX) * 1.6)
        for k in range(6):
            X, Y = H(CX - s + 2) + rng.randint(0, 6), H(96) + k * 4
            P(c, X, Y, SK, 3)
            P(c, X + 1, Y, FX, F_OUT)
        _stains(c, rng, [(GR, 2), (GR, 3), (BL, 2)], 12, (CX - s, 88, CX + s, PH - 2))
        for k in range(9):  # injection marks on the shoulder
            P(c, H(CX - s + 3) + k, H(90) - (k % 2), BL, 3)
    elif outfit == "elder":
        _garment(c, build, CA, top=3.6, bottom=1.6, sh_extra=1)  # worn coat
        _collar_v(c, CA, depth=104, w=8, shade=1)
        for X, Y, x, y in grid(CX - 12, 70, CX + 13, 92):  # knitted scarf
            if abs(x - CX) < 13 - max(0, y - 82) and (y < 82 or abs(x - CX - 4) < 4):
                knit = (X + (Y // 2) * 2) % 4 < 2
                P(c, X, Y, CB, 3 + knit - (x > CX))
        for k in range(9):  # patched shoulder with stitches
            HL(c, H(CX - s + 1), H(CX - s + 7), H(94) + k, CC, 2 + (k % 2))
        stitch_v(c, H(CX - s + 1) - 1, H(94), H(94) + 8, CC, 5, 1)
        _buttons(c, H(CX - 9), H(96), HPH - 2, MT, 8)
        _folds(c, rng, build, CA, 12)
        _stains(c, rng, [(GR, 2)], 4, (CX - s, 96, CX + s, PH - 2))
    elif outfit == "netrunner":
        _garment(c, build, CA, top=3.4, bottom=1.4, inset=1)  # tight bodysuit
        for X, Y, x, y in grid(CX - nw - 1, 66, CX + nw + 2, 80):  # turtleneck ribbing
            P(c, X, Y, CA, 2 + (y < 70) - (y > 76) + (X % 3 == 0))
        for side in (-1, 1):  # cable ports along the collarbone
            for k in range(3):
                x = CX + side * (8 + k * 5)
                plate(c, x - 1, 84, x + 2, 87, MT)
                P(c, H(x + 0.5), H(85.5), GL, 6 - k)
                P(c, H(x + 0.5) + 1, H(85.5), GL, 3)
        for Y in range(H(88), HPH):  # faint trace lines
            if Y % 9 == 0:
                HL(c, HCX - 5, HCX + 5, Y, GL, 1)
                P(c, HCX + 6, Y + 1, GL, 1)
            P(c, HCX, Y, GL, 1 if Y % 4 else 2)
