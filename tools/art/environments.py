"""Environment backdrops: clinic tiers 0-5, the black-market den and the
operating-table backdrops. 180px wide (one art pixel = two UI units).

Everything is drawn as albedo with shaded primitives, then lit by LitScene:
lamps, monitors, neon and emergency lights cast banded, dithered light.
"""
from __future__ import annotations

import math
import random

from . import palette as pal
from .lib import Canvas, LitScene, poly_pixels, clamp, bayer

W, H = 180, 250
FLOOR_Y = 176

FONT3x5 = {
    "A": ["010", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
    "C": ["011", "100", "100", "100", "011"], "D": ["110", "101", "101", "101", "110"],
    "E": ["111", "100", "110", "100", "111"], "H": ["101", "101", "111", "101", "101"],
    "I": ["111", "010", "010", "010", "111"], "K": ["101", "101", "110", "101", "101"],
    "L": ["100", "100", "100", "100", "111"], "M": ["10001", "11011", "10101", "10001", "10001"],
    "N": ["1001", "1101", "1011", "1001", "1001"], "O": ["010", "101", "101", "101", "010"],
    "P": ["110", "101", "110", "100", "100"], "R": ["110", "101", "110", "101", "101"],
    "S": ["011", "100", "010", "001", "110"], "T": ["111", "010", "010", "010", "010"],
    "U": ["101", "101", "101", "101", "111"], "X": ["101", "101", "010", "101", "101"],
    "Y": ["101", "101", "010", "010", "010"], "2": ["110", "001", "010", "100", "111"],
    "4": ["101", "101", "111", "001", "001"], "-": ["000", "000", "111", "000", "000"],
    " ": ["0", "0", "0", "0", "0"], "+": ["000", "010", "111", "010", "000"],
}


def text_width(text):
    return sum(len(FONT3x5.get(ch, FONT3x5[" "])[0]) + 1 for ch in text) - 1


def text(cv, x, y, s, color):
    for ch in s:
        g = FONT3x5.get(ch, FONT3x5[" "])
        for gy, row in enumerate(g):
            for gx, bit in enumerate(row):
                if bit == "1":
                    cv.set(x + gx, y + gy, color)
        x += len(g[0]) + 1


def R(h, shift=0.07, contrast=1.0):
    return pal.ramp(h, shift, contrast)


def C(ramp, i):
    c = ramp[int(clamp(i, 0, 7))]
    return (c[0], c[1], c[2], 255)


def GLOW(name, i=6):
    return C(pal.glow_ramp(pal.GLOWS[name]), i)


MAT = {
    "concrete": R("4a4c52", 0.05), "tile": R("3c4a50", 0.06), "panel": R("3a4252", 0.06),
    "clean": R("5a6474", 0.05), "glass": R("1c2a36", 0.05), "hex": R("2a3040", 0.06),
    "steel": R("7c8796", 0.06, 1.1), "dark": R("2b2f38", 0.05), "rust": R("6a3c26", 0.08),
    "wood": R("5a3e2a", 0.08), "floor_c": R("2c2e34", 0.05), "floor_t": R("2a3238", 0.05),
    "floor_m": R("262c36", 0.05), "white": R("c8ccd2", 0.05), "cloth": R("2c4a4e", 0.08),
    "cushion": R("3a2a2e", 0.08), "plastic": R("6e6146", 0.06),
}


# =============================================================================
# Building blocks
# =============================================================================

def wall(sc: LitScene, kind: str, rng):
    a = sc.albedo
    m = MAT[{"concrete": "concrete", "tile": "tile", "panel": "panel", "clean": "clean", "hex": "hex", "glass": "glass"}[kind]]
    for y in range(0, FLOOR_Y):
        for x in range(W):
            v = 3.2 + rng.random() * 0.5
            if kind == "concrete":
                v += (0.6 if rng.random() < 0.04 else 0) - (0.8 if (x * 7 + y * 3) % 97 == 0 else 0)
            elif kind == "tile":
                if y % 14 == 0 or x % 14 == 0:
                    v -= 1.4
                elif y % 14 == 1 or x % 14 == 1:
                    v += 0.6
            elif kind == "panel":
                if y % 30 == 0 or x % 36 == 0:
                    v -= 1.6
                elif y % 30 == 1:
                    v += 0.8
                if (x % 36 in (3, 32)) and (y % 30 in (4, 26)):
                    v += 2  # rivets
            elif kind == "clean":
                v = 3.8 + (0.3 if (y // 45) % 2 else 0)
                if y % 45 == 0 or x % 60 == 0:
                    v -= 1.4
            elif kind == "hex":
                q = ((x // 6) + (y // 10)) % 2
                if (y % 10 == 0) or (x % 12 == (0 if q else 6)):
                    v -= 1.2
                v += 0.2
            a.shade_px(x, y, m, v)
    # Grime gradient near floor
    for y in range(FLOOR_Y - 24, FLOOR_Y):
        for x in range(W):
            if bayer(x, y) < (y - (FLOOR_Y - 24)) / 40:
                c = a.px[y][x]
                a.px[y][x] = (int(c[0] * 0.8), int(c[1] * 0.8), int(c[2] * 0.8), 255)
    if kind == "concrete":
        # Cracks and water stains
        for _ in range(5):
            x, y = rng.randrange(10, W - 10), rng.randrange(20, 120)
            for k in range(rng.randrange(8, 22)):
                a.set(x, y, C(m, 1))
                x += rng.choice((-1, 0, 1))
                y += 1
        for _ in range(4):
            x0 = rng.randrange(0, W - 20)
            for y in range(14, rng.randrange(40, 120)):
                for x in range(x0, x0 + rng.randrange(3, 10)):
                    if bayer(x, y) < 0.4:
                        c = a.px[y][x]
                        a.px[y][x] = (int(c[0] * 0.78), int(c[1] * 0.82), int(c[2] * 0.8), 255)


def ceiling(sc: LitScene, tier: int, rng):
    a = sc.albedo
    a.rect(0, 0, W, 12, C(MAT["dark"], 1))
    # Main pipe
    a.cylinder(0, 4, W, 6, MAT["steel"] if tier >= 2 else MAT["rust"], 1, 5, vertical=False)
    for x in range(8, W, 28):
        a.rect(x, 3, 3, 8, C(MAT["dark"], 3))
    if tier <= 1:
        # Hanging cables
        for cx, sag in ((10, 10), (52, 14), (118, 9), (150, 16)):
            for x in range(cx, cx + 22):
                t = (x - cx) / 21
                a.set(x, 12 + int(sag * 4 * t * (1 - t)), (8, 8, 12, 255))
    if tier >= 3:
        # Ceiling light strip
        a.rect(0, 12, W, 2, C(MAT["dark"], 2))
        for x in range(4, W, 3):
            sc.emissive.set(x, 12, GLOW("cyan", 4) if tier < 5 else C(MAT["white"], 7))


def floor(sc: LitScene, kind: str, rng):
    a = sc.albedo
    m = MAT[{"concrete": "floor_c", "tile": "floor_t", "metal": "floor_m"}[kind]]
    vx, vy = W / 2, 60
    for y in range(FLOOR_Y, H):
        for x in range(W):
            v = 3.0 + rng.random() * 0.4 + (y - FLOOR_Y) / (H - FLOOR_Y) * 0.5
            a.shade_px(x, y, m, v)
    a.hline(0, W - 1, FLOOR_Y, C(m, 5))
    for fx in range(-W, 2 * W, 22):  # perspective seams
        t0 = (FLOOR_Y - vy) / (H - vy)
        a.line(vx + (fx - vx) * t0, FLOOR_Y, fx, H - 1, C(m, 1))
    for k, fy in enumerate((180, 187, 197, 210, 228)):
        a.hline(0, W - 1, fy, C(m, 1))
    if kind == "concrete":
        for _ in range(60):
            a.set(rng.randrange(W), rng.randrange(FLOOR_Y, H), C(m, 0))


def puddle(sc, x, y, w, rng, colors):
    a = sc.albedo
    for yy in range(y, y + 5):
        for xx in range(x, x + w):
            if ((xx - x - w / 2) / (w / 2)) ** 2 + ((yy - y - 2.5) / 2.6) ** 2 <= 1:
                a.set(xx, yy, (12, 16, 22, 255))
                if bayer(xx, yy) < 0.18:
                    sc.emissive.set(xx, yy, rng.choice(colors))


def door(sc: LitScene, tier: int):
    a = sc.albedo
    x0, y0, x1 = 10, 92, 44
    a.rect(x0 - 2, y0 - 2, x1 - x0 + 4, FLOOR_Y - y0 + 2, C(MAT["dark"], 1))
    m = MAT["rust"] if tier == 0 else MAT["panel"] if tier < 3 else MAT["clean"]
    a.shaded_poly([(x0, y0), (x1, y0), (x1, FLOOR_Y), (x0, FLOOR_Y)], m, 4.0, 2.4, 1.0, 1.0)
    a.rect(x0 + 4, y0 + 8, x1 - x0 - 8, 14, C(MAT["dark"], 1))  # window slot
    for x in range(x0 + 5, x1 - 4, 2):
        a.vline(x, y0 + 9, y0 + 20, C(MAT["dark"], 3))
    a.rect(x1 - 6, 132, 3, 6, C(MAT["steel"], 5))
    # Warning light above the door
    sc.emissive.rect(x0 + 6, y0 - 4, x1 - x0 - 12, 2, GLOW("amber", 5))
    sc.light(27, y0 - 3, pal.ACCENT["amber"], 34, 0.55, cone=(90, 70))
    if tier >= 3:  # access panel
        a.rect(x1 + 3, 120, 5, 8, C(MAT["dark"], 2))
        sc.emissive.set(x1 + 5, 122, GLOW("green", 6))


def monitor(sc: LitScene, x, y, w, h, style="crt", glow="cyan", stand=True):
    a = sc.albedo
    if stand:
        a.rect(x + w // 2 - 1, y + h, 2, FLOOR_Y - y - h, C(MAT["dark"], 3))
        a.rect(x + w // 2 - 6, FLOOR_Y - 2, 12, 2, C(MAT["dark"], 4))
    case = MAT["plastic"] if style == "crt" else MAT["dark"]
    a.shaded_poly([(x, y), (x + w, y), (x + w, y + h), (x, y + h)], case, 5, 2, 1, 1)
    sx0, sy0, sx1, sy1 = x + 2, y + 2, x + w - 2, y + h - (4 if style == "crt" else 2)
    for yy in range(sy0, sy1):
        for xx in range(sx0, sx1):
            sc.emissive.set(xx, yy, (6, 18, 20, 255) if glow == "cyan" else (20, 8, 16, 255))
    mid = (sy0 + sy1) // 2
    prev = None
    for xx in range(sx0, sx1):
        k = (xx - sx0) % 14
        dy = {6: -1, 7: 3, 8: -5, 9: 4, 10: -1}.get(k, 0)
        yy = clamp(mid + dy, sy0, sy1 - 1)
        if prev is not None:
            for yyy in range(min(prev, yy), max(prev, yy) + 1):
                sc.emissive.set(xx, yyy, GLOW(glow, 6))
        prev = yy
    for yy in range(sy0, sy1, 2):  # scanlines
        for xx in range(sx0, sx1):
            e = sc.emissive.px[yy][xx]
            if e and e != GLOW(glow, 6):
                sc.emissive.px[yy][xx] = (max(0, e[0] - 3), max(0, e[1] - 6), max(0, e[2] - 6), 255)
    sc.light(x + w / 2, y + h / 2, pal.ACCENT[glow], 40, 0.55)
    if style == "crt":
        sc.emissive.set(x + 3, y + h - 2, GLOW("green", 6))
        sc.emissive.set(x + 6, y + h - 2, GLOW("amber", 6))


def neon(sc: LitScene, x, y, s, color, strength=0.7, frame=True):
    w = text_width(s)
    if frame:
        sc.albedo.rect(x - 4, y - 4, w + 8, 13, C(MAT["dark"], 0))
        sc.albedo.rect(x - 4, y - 4, w + 8, 1, C(MAT["dark"], 2))
    for ch_x in range(w):
        pass
    text(sc.emissive, x, y, s, GLOW(color, 6))
    sc.light(x + w / 2, y + 2, pal.ACCENT[color], 30 + w * 0.6, strength)


def emblem_sign(sc: LitScene, x, y):
    """The clinic's mark: a blade crossing a pulse line."""
    sc.emissive.line(x, y + 14, x + 10, y, GLOW("magenta", 6))
    sc.emissive.line(x + 1, y + 14, x + 11, y, GLOW("magenta", 5))
    pts = [(x - 2, y + 8), (x + 3, y + 8), (x + 5, y + 4), (x + 7, y + 11), (x + 9, y + 8), (x + 14, y + 8)]
    for a, b in zip(pts, pts[1:]):
        sc.emissive.line(a[0], a[1], b[0], b[1], GLOW("cyan", 6))


def lamp(sc: LitScene, x, y, kind="bulb"):
    a = sc.albedo
    if kind == "bulb":
        a.vline(x, 12, y, C(MAT["dark"], 1))
        a.rect(x - 2, y, 5, 3, C(MAT["dark"], 3))
        sc.emissive.ellipse(x + 0.5, y + 5, 2.5, 3, (255, 214, 150, 255))
        sc.light(x, y + 6, "ffcf8a", 110, 1.25, cone=(90, 70))
        sc.light(x, FLOOR_Y + 22, "ffcf8a", 60, 0.45)
    elif kind == "surgical":
        a.vline(x, 12, y - 2, C(MAT["dark"], 2))
        a.cylinder(x - 14, y, 28, 6, MAT["steel"], 1.5, 6, vertical=False)
        sc.emissive.rect(x - 11, y + 6, 22, 2, (232, 255, 248, 255))
        sc.light(x, y + 9, pal.ACCENT["white"], 120, 1.15, cone=(90, 38))
        sc.light(x, FLOOR_Y + 20, pal.ACCENT["white"], 70, 0.45)
    elif kind == "ring":
        a.vline(x, 12, y - 3, C(MAT["dark"], 2))
        a.ellipse(x, y, 20, 5, C(MAT["steel"], 4))
        a.ellipse(x, y, 16, 3, C(MAT["dark"], 1))
        for k in range(0, 360, 20):
            sc.emissive.set(x + round(18 * math.cos(math.radians(k))), y + round(4 * math.sin(math.radians(k))) + 1, (240, 255, 250, 255))
        sc.light(x, y + 8, pal.ACCENT["white"], 130, 1.2, cone=(90, 40))
        sc.light(x, FLOOR_Y + 20, pal.ACCENT["white"], 80, 0.5)


def chair(sc: LitScene, x, y, kind):
    a = sc.albedo
    if kind == "improvised":
        # Old door on two sawhorses, taped cushion
        for lx in (x + 6, x + 58):
            a.line(lx - 5, FLOOR_Y, lx, y + 8, C(MAT["wood"], 2))
            a.line(lx + 5, FLOOR_Y, lx, y + 8, C(MAT["wood"], 3))
        a.shaded_poly([(x, y), (x + 66, y), (x + 66, y + 7), (x, y + 7)], MAT["wood"], 4.5, 2, 1, 1)
        a.shaded_poly([(x + 4, y - 4), (x + 40, y - 4), (x + 40, y), (x + 4, y)], MAT["cushion"], 5, 3, 1, 1)
        a.rect(x + 18, y - 4, 4, 4, C(MAT["plastic"], 5))  # tape
    elif kind == "dental":
        a.shaded_poly([(x + 6, y), (x + 62, y), (x + 62, y + 8), (x + 6, y + 8)], MAT["cushion"], 5, 2, 1, 1)
        a.shaded_poly([(x, y - 10), (x + 9, y - 10), (x + 9, y + 2), (x, y + 2)], MAT["cushion"], 5, 2.5, 1, 1)
        a.rect(x + 30, y + 8, 6, FLOOR_Y - y - 12, C(MAT["steel"], 3))
        a.shaded_poly([(x + 20, FLOOR_Y - 4), (x + 46, FLOOR_Y - 4), (x + 46, FLOOR_Y), (x + 20, FLOOR_Y)], MAT["steel"], 5, 2, 1, 1)
    elif kind in ("surgical", "advanced", "elite"):
        bed = MAT["white"] if kind != "surgical" else MAT["steel"]
        a.shaded_poly([(x, y), (x + 70, y), (x + 70, y + 7), (x, y + 7)], bed, 5.5, 2.4, 1, 1)
        a.shaded_poly([(x + 2, y - 3), (x + 68, y - 3), (x + 68, y), (x + 2, y)], MAT["cloth"], 5, 3.5, 1, 0.5)
        a.cylinder(x + 31, y + 7, 8, FLOOR_Y - y - 11, MAT["steel"], 1.5, 5.5)
        a.shaded_poly([(x + 16, FLOOR_Y - 4), (x + 54, FLOOR_Y - 4), (x + 56, FLOOR_Y), (x + 14, FLOOR_Y)], MAT["dark"], 4, 2, 1, 1)
        stripe = "cyan" if kind == "surgical" else "blue" if kind == "advanced" else "white"
        for xx in range(x + 2, x + 68):
            sc.emissive.set(xx, y + 6, GLOW("cyan", 3) if stripe == "cyan" else GLOW("blue", 4) if stripe == "blue" else C(MAT["white"], 7))


def cabinet(sc: LitScene, x, y, w, h, kind, rng):
    a = sc.albedo
    m = MAT["dark"] if kind != "glass" else MAT["glass"]
    a.shaded_poly([(x, y), (x + w, y), (x + w, FLOOR_Y), (x, FLOOR_Y)], m, 4, 2, 1, 1)
    shelves = range(y + 14, FLOOR_Y - 4, 18)
    for sy in shelves:
        a.hline(x + 1, x + w - 2, sy, C(MAT["steel"], 4))
        if kind == "jars":
            for jx in range(x + 3, x + w - 4, 5):
                col = rng.choice(["green", "amber", "cyan", "magenta"])
                a.rect(jx, sy - 6, 3, 6, C(R("223028"), 2))
                for yy in range(sy - 4, sy):
                    sc.emissive.set(jx, yy, GLOW(col, 3))
                    sc.emissive.set(jx + 1, yy, GLOW(col, 4))
        elif kind in ("glass", "implants"):
            for jx in range(x + 3, x + w - 6, 7):
                a.rect(jx, sy - 7, 5, 6, C(MAT["steel"], 2))
                sc.emissive.set(jx + 2, sy - 4, GLOW(rng.choice(["cyan", "blue", "green"]), 6))
                sc.emissive.set(jx + 1, sy - 6, GLOW("cyan", 2))
    if kind in ("glass", "implants"):
        sc.light(x + w / 2, y + h / 2, pal.ACCENT["cyan"], 40, 0.35)
    else:
        sc.light(x + w / 2, y + 40, pal.ACCENT["green"], 26, 0.25)


def iv_stand(sc, x, y):
    a = sc.albedo
    a.vline(x, y, FLOOR_Y - 1, C(MAT["steel"], 4))
    a.hline(x - 4, x + 4, y, C(MAT["steel"], 5))
    a.rect(x - 4, y + 1, 3, 7, C(R("8ab0b8"), 5))
    sc.emissive.set(x - 3, y + 6, GLOW("cyan", 3))
    a.hline(x - 5, x + 5, FLOOR_Y - 1, C(MAT["steel"], 3))


def robot_arm(sc: LitScene, base_x, side=1, reach=(0, 0), kind="pro"):
    """Ceiling-mounted surgical arm: base rail, two segments, tool head."""
    a = sc.albedo
    m = MAT["white"] if kind == "pro" else MAT["steel"]
    bx, by = base_x, 14
    ex, ey = base_x + side * 16 + reach[0], 52 + reach[1]
    hx, hy = base_x + side * 4 + reach[0] * 2, 92 + reach[1]
    a.rect(bx - 5, 12, 10, 5, C(MAT["dark"], 2))
    a.capsule(bx, by + 4, ex, ey, 4.0, m, 1.5, 6.2, r2=3.4)
    a.sphere(ex, ey, 4.2, 4.2, MAT["dark"], 1.5, 5)
    a.capsule(ex, ey, hx, hy, 3.0, m, 1.5, 6.2, r2=2.4)
    a.sphere(hx, hy, 3, 3, MAT["dark"], 1, 4.5)
    a.line(hx, hy + 2, hx, hy + 8, C(MAT["steel"], 6))
    sc.emissive.set(int(ex), int(ey), GLOW("cyan", 6))
    sc.emissive.set(int(hx), int(hy + 8), GLOW("red", 6))
    for k in range(6):  # cable along the arm
        t = k / 5
        a.set(int(bx + (ex - bx) * t) + side * 3, int(by + 4 + (ey - by - 4) * t), C(MAT["dark"], 0))


def holo(sc: LitScene, x, y, w, h, color="cyan"):
    """Translucent holographic panel: emissive lines over the scene."""
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if yy % 3 == 0 and bayer(xx, yy) < 0.5:
                sc.emissive.set(xx, yy, GLOW(color, 2))
    for xx in range(x, x + w):
        sc.emissive.set(xx, y, GLOW(color, 5))
        sc.emissive.set(xx, y + h - 1, GLOW(color, 4))
    # Body silhouette diagram
    cx = x + w // 2
    sc.emissive.ellipse(cx, y + 8, 3, 4, GLOW(color, 5))
    for yy in range(y + 12, y + h - 6):
        hw = 4 if yy < y + 26 else 2
        sc.emissive.set(cx - hw, yy, GLOW(color, 5))
        sc.emissive.set(cx + hw, yy, GLOW(color, 5))
    sc.emissive.set(cx, y + 14, GLOW("magenta", 7))
    sc.light(x + w / 2, y + h / 2, pal.ACCENT[color], 44, 0.5)


def scanner_ring(sc: LitScene, cx, cy):
    a = sc.albedo
    for k in range(0, 360, 3):
        r = math.radians(k)
        x, y = cx + 34 * math.cos(r), cy + 30 * math.sin(r) * 0.95
        if y < cy + 20:
            a.sphere(x, y, 3.2, 3.2, MAT["white"], 1.5, 6)
    for k in range(0, 180, 12):
        r = math.radians(k + 180)
        sc.emissive.set(int(cx + 31 * math.cos(r)), int(cy + 27 * math.sin(r)), GLOW("blue", 6))
    sc.light(cx, cy - 10, pal.ACCENT["blue"], 60, 0.45)


def containment(sc: LitScene, x, y):
    a = sc.albedo
    a.shaded_poly([(x, y), (x + 18, y), (x + 18, y + 6), (x, y + 6)], MAT["steel"], 5, 2, 1, 1)
    a.shaded_poly([(x, FLOOR_Y - 8), (x + 18, FLOOR_Y - 8), (x + 18, FLOOR_Y), (x, FLOOR_Y)], MAT["steel"], 5, 2, 1, 1)
    for yy in range(y + 6, FLOOR_Y - 8):
        for xx in range(x + 2, x + 16):
            sc.emissive.set(xx, yy, GLOW("magenta", 2 + (1 if bayer(xx, yy) < 0.3 else 0)))
    sc.emissive.ellipse(x + 9, (y + FLOOR_Y) / 2, 4, 6, GLOW("magenta", 5))
    sc.light(x + 9, (y + FLOOR_Y) / 2, pal.ACCENT["magenta"], 50, 0.6)


def crate(sc, x, y, w, h, rng, label=None):
    a = sc.albedo
    a.shaded_poly([(x, y), (x + w, y), (x + w, y + h), (x, y + h)], MAT["dark"] if not label else MAT["plastic"], 4.5, 2, 1, 1)
    a.line(x, y, x + w, y + h, C(MAT["dark"], 1))
    if label:
        sc.emissive.rect(x + 2, y + 2, 3, 2, GLOW(label, 5))


def background_station(sc: LitScene, x):
    """Second operating station seen through a glass partition (elite)."""
    a = sc.albedo
    a.rect(x, 60, 56, FLOOR_Y - 70, C(MAT["glass"], 2))
    for yy in range(60, FLOOR_Y - 10, 2):
        for xx in range(x, x + 56):
            if bayer(xx, yy) < 0.15:
                sc.emissive.set(xx, yy, GLOW("cyan", 1))
    a.shaded_poly([(x + 10, 128), (x + 46, 128), (x + 46, 132), (x + 10, 132)], MAT["white"], 4, 2.5, 1, 1)
    a.rect(x + 26, 132, 4, 30, C(MAT["steel"], 2))
    sc.emissive.rect(x + 18, 80, 20, 2, (220, 240, 240, 255))
    sc.light(x + 28, 90, pal.ACCENT["white"], 50, 0.6, cone=(90, 40))
    a.rect(x - 1, 58, 58, 2, C(MAT["steel"], 5))
    a.rect(x - 1, 58, 2, FLOOR_Y - 66, C(MAT["steel"], 4))


# =============================================================================
# Scenes
# =============================================================================

CLINIC_TIERS = [
    "basement", "backroom", "underground", "professional", "advanced", "elite",
]


def clinic(tier: int) -> Canvas:
    rng = random.Random(100 + tier)
    amb = [(0.22, 0.22, 0.30), (0.25, 0.26, 0.34), (0.28, 0.30, 0.38), (0.33, 0.36, 0.44), (0.34, 0.37, 0.46), (0.38, 0.41, 0.50)][tier]
    sc = LitScene(W, H, ambient=amb)
    wall(sc, ["concrete", "tile", "panel", "clean", "hex", "clean"][tier], rng)
    ceiling(sc, tier, rng)
    floor(sc, ["concrete", "concrete", "tile", "tile", "metal", "metal"][tier], rng)
    door(sc, tier)
    if tier == 0:
        sc.albedo.rect(64, 30, 46, 12, C(MAT["dark"], 2))
        neon(sc, 72, 34, "DOC", "red", 0.6, frame=False)
        sc.emissive.rect(98, 34, 2, 2, GLOW("red", 4))
        monitor(sc, 140, 128, 22, 18, "crt", "green", stand=False)
        crate(sc, 136, 146, 30, 30, rng)
        chair(sc, 64, 140, "improvised")
        lamp(sc, 96, 72, "bulb")
        for bx in (52, 150):  # buckets / clutter
            sc.albedo.cylinder(bx, FLOOR_Y - 9, 8, 9, MAT["steel"], 1, 4)
        puddle(sc, 70, 214, 40, rng, [GLOW("red", 3), GLOW("amber", 2)])
        for k in range(3):  # exposed wiring on the wall
            sc.albedo.polyline([(120 + k * 4, 14), (122 + k * 3, 60), (118 + k * 5, 110)], (14, 14, 18, 255))
    elif tier == 1:
        emblem_sign(sc, 66, 22)
        neon(sc, 86, 22, "OPEN", "magenta", 0.65)
        neon(sc, 84, 32, "CLINIC", "cyan", 0.5, frame=False)
        monitor(sc, 50, 98, 22, 20, "crt", "cyan")
        chair(sc, 72, 138, "dental")
        lamp(sc, 106, 78, "bulb")
        cabinet(sc, 146, 76, 26, 100, "jars", rng)
        iv_stand(sc, 140, 96)
        puddle(sc, 60, 216, 44, rng, [GLOW("cyan", 3), GLOW("magenta", 3)])
    elif tier == 2:
        emblem_sign(sc, 64, 20)
        neon(sc, 84, 22, "UNDERCITY", "cyan", 0.55)
        monitor(sc, 48, 92, 24, 18, "flat", "cyan")
        monitor(sc, 48, 72, 24, 16, "flat", "green", stand=False)
        chair(sc, 70, 138, "surgical")
        lamp(sc, 105, 70, "surgical")
        cabinet(sc, 146, 70, 28, 106, "jars", rng)
        iv_stand(sc, 140, 92)
        for x in range(0, W, 2):  # cable tray
            sc.albedo.set(x, 18, C(MAT["dark"], 3))
    elif tier == 3:
        emblem_sign(sc, 20, 24)
        neon(sc, 40, 26, "RIPPER", "magenta", 0.5)
        holo(sc, 48, 70, 26, 44, "cyan")
        chair(sc, 70, 138, "advanced")
        robot_arm(sc, 128, side=-1, reach=(-4, 0), kind="pro")
        lamp(sc, 102, 66, "surgical")
        cabinet(sc, 146, 66, 28, 110, "implants", rng)
    elif tier == 4:
        emblem_sign(sc, 20, 24)
        neon(sc, 40, 26, "RIPPER", "magenta", 0.5)
        holo(sc, 46, 64, 28, 50, "blue")
        scanner_ring(sc, 105, 126)
        chair(sc, 70, 140, "advanced")
        robot_arm(sc, 76, side=1, reach=(4, 0), kind="pro")
        robot_arm(sc, 136, side=-1, reach=(-4, 2), kind="pro")
        lamp(sc, 105, 62, "ring")
        cabinet(sc, 150, 60, 26, 116, "glass", rng)
        for x in range(0, W):
            sc.emissive.set(x, FLOOR_Y + 1, GLOW("blue", 3) if x % 4 else GLOW("blue", 5))
    else:
        background_station(sc, 6)
        neon(sc, 70, 22, "ELITE RIPPER", "magenta", 0.45)
        holo(sc, 140, 40, 30, 34, "cyan")
        scanner_ring(sc, 110, 128)
        chair(sc, 76, 142, "elite")
        robot_arm(sc, 84, side=1, reach=(4, 0), kind="pro")
        robot_arm(sc, 140, side=-1, reach=(-6, 2), kind="pro")
        lamp(sc, 110, 62, "ring")
        containment(sc, 158, 92)
        sc.albedo.rect(0, 14, W, 3, C(MAT["steel"], 5))  # gantry rail
        for x in range(0, W):
            sc.emissive.set(x, FLOOR_Y + 1, C(MAT["white"], 6) if x % 3 else GLOW("cyan", 5))
    return sc.render()


def black_market() -> Canvas:
    rng = random.Random(77)
    sc = LitScene(W, H, ambient=(0.16, 0.13, 0.22))
    wall(sc, "concrete", rng)
    ceiling(sc, 0, rng)
    floor(sc, "concrete", rng)
    a = sc.albedo
    # Steel grate / counter across the den
    a.shaded_poly([(0, 128), (W, 128), (W, 150), (0, 150)], MAT["dark"], 4, 2, 1, 1)
    for x in range(0, W, 6):
        a.vline(x, 60, 127, C(MAT["steel"], 3))
    for y in range(60, 127, 12):
        a.hline(0, W - 1, y, C(MAT["steel"], 2))
    # Hanging implants on hooks behind the grate
    for k, x in enumerate(range(16, W - 10, 22)):
        a.vline(x, 14, 70 + (k % 3) * 8, C(MAT["dark"], 3))
        y = 72 + (k % 3) * 8
        a.sphere(x, y, 4, 5, MAT["steel"], 1, 5.5)
        sc.emissive.set(x, y, GLOW(rng.choice(["magenta", "magenta", "blue", "red"]), 6))
    neon(sc, 40, 22, "NO NAMES", "magenta", 0.9)
    neon(sc, 120, 40, "CASH ONLY", "red", 0.5, frame=False)
    # Warning stripes on the counter edge
    for x in range(0, W):
        a.set(x, 128, (200, 160, 40, 255) if (x // 4) % 2 else (24, 20, 16, 255))
    crate(sc, 8, 150, 34, 26, rng, label="magenta")
    crate(sc, 140, 156, 30, 20, rng, label="red")
    crate(sc, 46, 160, 22, 16, rng)
    monitor(sc, 112, 100, 22, 18, "crt", "magenta", stand=False)
    sc.light(90, 90, pal.ACCENT["magenta"], 150, 0.55)
    puddle(sc, 60, 220, 60, rng, [GLOW("magenta", 4), GLOW("magenta", 2)])
    return sc.render()


def surgery_backdrop(level: int) -> Canvas:
    """Top-down view around the operating table. level 0 = improvised,
    1 = clinic, 2 = advanced (robotic arms)."""
    rng = random.Random(300 + level)
    Wd, Hd = 180, 240
    sc = LitScene(Wd, Hd, ambient=(0.20, 0.21, 0.28))
    a = sc.albedo
    fl = MAT["floor_c"] if level == 0 else MAT["floor_t"] if level == 1 else MAT["floor_m"]
    for y in range(Hd):
        for x in range(Wd):
            v = 2.6 + rng.random() * 0.4
            if level > 0 and (x % 20 == 0 or y % 20 == 0):
                v -= 1.0
            a.shade_px(x, y, fl, v)
    # Table (wider than the field so its rails show on the sides)
    tm = MAT["wood"] if level == 0 else MAT["steel"]
    a.shaded_poly([(12, 0), (168, 0), (168, Hd), (12, Hd)], tm, 4.5, 3.0, 2.0, 1.2)
    for y in range(0, Hd, 16):  # rail grips
        a.rect(12, y, 3, 8, C(MAT["dark"], 2))
        a.rect(165, y + 6, 3, 8, C(MAT["dark"], 2))
    # Surgical drape with folds over everything near the field
    for y in range(4, Hd - 4):
        for x in range(18, 162):
            h = 6 * math.sin(x * 0.07 + 2 * math.sin(y * 0.03)) + 3 * math.sin(y * 0.11 + x * 0.02)
            hx = 6 * 0.07 * math.cos(x * 0.07 + 2 * math.sin(y * 0.03))
            a.shade_px(x, y, MAT["cloth"], 3.2 - hx * 0.6 + (0.4 if rng.random() < 0.03 else 0))
    # Instrument tray (left) with tools glinting
    a.shaded_poly([(0, 150), (26, 150), (26, 220), (0, 220)], MAT["steel"], 5, 3, 1, 1)
    for k in range(5):
        y = 158 + k * 12
        a.line(3, y, 22, y - 3, C(MAT["steel"], 6))
        a.line(3, y + 1, 12, y - 1, C(MAT["dark"], 2))
    # Cables crossing
    for k in range(2):
        pts = [(Wd - 1, 30 + k * 40), (150 - k * 8, 60 + k * 30), (160, 120 + k * 20), (Wd - 1, 160 + k * 30)]
        a.polyline(pts, C(MAT["dark"], 0))
    if level >= 1:
        # Monitor glow from the right edge
        sc.light(Wd + 10, 70, pal.ACCENT["cyan"], 90, 0.45)
    if level >= 2:
        for side, bx in ((1, 0), (-1, Wd - 1)):
            a.capsule(bx, 10, bx + side * 28, 34, 5, MAT["white"], 1.5, 6)
            a.sphere(bx + side * 28, 34, 5, 5, MAT["dark"], 1.5, 5)
            a.capsule(bx + side * 28, 34, bx + side * 34, 58, 3.5, MAT["white"], 1.5, 6)
            sc.emissive.set(bx + side * 28, 34, GLOW("cyan", 6))
            sc.emissive.set(bx + side * 34, 62, GLOW("red", 6))
    # Overhead lamp pool on the field
    sc.light(90, 110, pal.ACCENT["white"], 150, 1.0)
    if level == 0:
        sc.light(90, 100, "ffcf8a", 120, 0.5)
    return sc.render()


def generate():
    for t, name in enumerate(CLINIC_TIERS):
        clinic(t).save(f"clinic/clinic_t{t}_{name}.png")
    black_market().save("blackmarket/den.png")
    for lv in range(3):
        surgery_backdrop(lv).save(f"surgery/backdrop_{lv}.png")
    print("environments: clinic x6, black market, surgery x3")
