"""Environment backdrops: clinic tiers 0-5, the black-market den and the
operating-table backdrops. 180px wide (one art pixel = two UI units).

Everything is drawn as albedo with shaded primitives, then lit by LitScene:
lamps, monitors, neon and emergency lights cast banded, dithered light.
"""
from __future__ import annotations

import math
import random

import json
import os

from . import palette as pal
from . import props
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
    "V": ["101", "101", "101", "101", "010"], "G": ["011", "100", "101", "101", "011"],
    "F": ["111", "100", "110", "100", "100"], "W": ["10001", "10001", "10101", "11011", "10001"],
    "Z": ["111", "001", "010", "100", "111"], "J": ["001", "001", "001", "101", "010"],
    "Q": ["010", "101", "101", "110", "011"], "0": ["111", "101", "101", "101", "111"],
    "1": ["010", "110", "010", "010", "111"], "3": ["110", "001", "010", "001", "110"],
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
    props.fx("monitor", sx0, sy0, sx1 - sx0, sy1 - sy0, color=glow)
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
    props.fx("led", int(ex), int(ey), color="cyan", rate=0.6)
    props.fx("laser", int(hx), int(hy + 8), color="red")
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
    props.fx("holo", x, y, w, h, color=color)
    props.fx("led", cx, y + 14, color="magenta", rate=1.2)


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


def dress(sc, tier, rng):
    """Shared set dressing: power, ventilation, waste, storytelling."""
    grime = max(0, 2 - tier)
    props.power_box(sc, 14, 44, tier, sparks=tier == 0)
    vent_pos = {0: (150, 24), 1: (150, 30), 2: (118, 34), 3: (150, 34), 4: (152, 34), 5: (116, 36)}[tier]
    props.vent(sc, vent_pos[0], vent_pos[1], tier=tier)
    props.waste_bin(sc, 50, tier)
    # Floor storytelling (old stains in the cheap clinics, one fresh drop).
    if tier <= 2:
        props.blood(sc, 92, 188, 9 - tier * 2, 2, rng)
        props.blood(sc, 110, 196, 4, 1, rng)
    props.blood(sc, 100, 184 + tier, 2, 1, rng, fresh=True)
    for k in range(3 - min(tier, 2)):
        props.discarded_implant(sc, 40 + k * 7, FLOOR_Y + 6 + (k % 2) * 3, rng, glow=(k == 0))
    if tier <= 3:
        props.drain(sc, 132, 204)
    if tier >= 1:
        props.tool_cart(sc, 140, 178, tier)
    # Foreground (bottom of the frame) so the floor isn't an empty plane.
    if tier <= 1:
        props.box_stack(sc, 4, 212, rng)
    else:
        props.equipment_case(sc, 6, 222, "cyan" if tier < 5 else "magenta")
    if tier <= 2:
        props.floor_cables(sc, [(0, 206), (40, 202), (90, 204), (138, 200), (150, 198)])
    if tier <= 1:
        props.hidden_compartment(sc, 120 if tier == 0 else 124, 150, "panel")
    else:
        props.hidden_compartment(sc, 60, 214, "hatch")
    # Steam leaking from the ceiling pipe joints (cheap clinics).
    if tier <= 2:
        props.steam(34 + tier * 30, 10)
    if tier <= 2:
        props.steam(160, 10)


def clinic(tier: int) -> Canvas:
    rng = random.Random(100 + tier)
    props.reset_fx()
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
    dress(sc, tier, rng)
    if tier == 0:
        props.graffiti(sc, 66, 100, "NO DOC", "magenta", rng)
        props.tape(sc, 142, 129)
        props.tape(sc, 160, 131, 4, vertical=True)
        floor_cables_t0 = [(150, 146), (150, 176), (126, 186), (60, 182)]
        props.floor_cables(sc, floor_cables_t0)
    elif tier == 1:
        props.graffiti(sc, 112, 100, "R4T", "cyan", rng)
        props.tape(sc, 52, 99)
        props.floor_cables(sc, [(61, 176), (70, 186), (104, 184), (106, 176)])
    elif tier == 2:
        props.graffiti(sc, 96, 150, "XX", "magenta", rng)
        props.ecg_cart(sc, 122, tier)
        props.floor_cables(sc, [(60, 176), (72, 188), (108, 186), (110, 176)])
        props.floor_cables(sc, [(129, 176), (124, 190), (112, 190)])
    elif tier >= 3:
        props.floor_cables(sc, [(60, 176), (76, 192), (106, 190), (108, 176)])
        props.warning_label(sc, 150, 58 if tier < 5 else 84, "BIO")
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


def title_scene() -> Canvas:
    """Main-menu key art (180x400): a rain-soaked undercity alley. Megastructure
    silhouettes in the haze above (kept dark behind the title), neon signage,
    stairs down to the clinic door glowing red, a customer waiting under the
    cross sign, puddles reflecting the neon."""
    Wt, Ht = 180, 400
    rng = random.Random(4242)
    sc = LitScene(Wt, Ht, ambient=(0.30, 0.27, 0.44))
    a = sc.albedo
    # Haze sky: deep blue-purple, darker at the top.
    sky = R("1c1830", 0.05)
    for y in range(Ht):
        for x in range(Wt):
            v = 1.2 + 1.6 * (y / 220.0) + (0.4 if bayer(x, y) < 0.25 else 0.0)
            a.shade_px(x, y, sky, min(v, 3.4))
    # Distant megastructures (three depth layers, lit windows sparse).
    for layer, (base, tone, density) in enumerate(((150, 1.2, 0.05), (200, 1.7, 0.08), (250, 2.2, 0.1))):
        x = -6
        while x < Wt:
            w = rng.randrange(14, 34)
            top = base - rng.randrange(20, 110) + layer * 10
            for yy in range(top, Ht):
                for xx in range(x, min(Wt, x + w)):
                    a.shade_px(xx, yy, MAT["dark"], tone)
            if layer < 2:  # antenna / spire
                a.vline(x + w // 2, top - rng.randrange(6, 20), top, C(MAT["dark"], 1))
                sc.emissive.set(x + w // 2, top - 6, GLOW("red", 5))
            # Rim light on the roof edge (city glow from below/behind).
            a.hline(x, min(Wt, x + w) - 1, top, C(sky, 4 + layer))
            # Lit floors: whole window strips, not random dots.
            for yy in range(top + 4, Ht - 130, 5):
                if rng.random() < density * 4:
                    col = rng.choice(["amber", "amber", "cyan", "magenta"])
                    start = x + 2 + rng.randrange(0, max(1, w // 3))
                    length = rng.randrange(3, max(4, w - 4))
                    for xx in range(start, min(x + w - 2, start + length)):
                        if xx % 3 != 0:
                            sc.emissive.set(xx, yy, GLOW(col, 1 + layer))
            x += w + rng.randrange(0, 6)
    # Horizon haze: the city's glow bouncing off low cloud.
    sc.light(90, 230, pal.ACCENT["magenta"], 140, 0.35)
    sc.light(30, 260, pal.ACCENT["cyan"], 90, 0.25)
    # Near buildings framing the alley (they hide the city behind them).
    for side in (0, 1):
        x0 = 0 if side == 0 else 132
        x1 = 48 if side == 0 else Wt
        for yy in range(170, Ht):
            for xx in range(x0, x1):
                sc.emissive.px[yy][xx] = None
                v = 2.2 + rng.random() * 0.3 - (1.0 if (yy % 18 == 0) else 0)
                a.shade_px(xx, yy, MAT["concrete"], v)
        for yy in range(186, 300, 26):  # windows with blinds
            for k in range(2):
                wx = x0 + 8 + k * 20
                a.rect(wx, yy, 12, 14, C(MAT["dark"], 0))
                for by in range(yy + 1, yy + 13, 2):
                    a.hline(wx + 1, wx + 10, by, C(MAT["dark"], 2))
                if rng.random() < 0.5:
                    for by in range(yy + 2, yy + 12, 2):
                        sc.emissive.hline(wx + 1, wx + 10, by, GLOW("amber", 2))
    # Fire escape on the right building.
    for yy in range(196, 300, 24):
        a.hline(132, Wt - 1, yy, C(MAT["steel"], 3))
        for xx in range(134, Wt, 4):
            a.vline(xx, yy - 6, yy, C(MAT["steel"], 2))
    # Vertical neon blade on the left building: "RIPPER" stacked letters.
    a.rect(30, 196, 13, 62, C(MAT["dark"], 0))
    for i, ch in enumerate("RIPPER"):
        text(sc.emissive, 34, 199 + i * 10, ch, GLOW("magenta", 6))
    sc.light(36, 226, pal.ACCENT["magenta"], 70, 0.8)
    # Medical cross sign over the stairwell (cyan), slightly broken.
    cx, cy = 92, 252
    sc.albedo.rect(cx - 9, cy - 9, 19, 19, C(MAT["dark"], 0))
    for d in range(-6, 7):
        sc.emissive.set(cx + d, cy, GLOW("cyan", 6))
        sc.emissive.set(cx + d, cy + 1, GLOW("cyan", 5))
        if d != 3:  # dead tube segment
            sc.emissive.set(cx, cy + d, GLOW("cyan", 6))
            sc.emissive.set(cx + 1, cy + d, GLOW("cyan", 5))
    sc.light(cx, cy, pal.ACCENT["cyan"], 60, 0.7)
    # Street, stairs down to the clinic door.
    street_y = 300
    for yy in range(street_y, Ht):
        for xx in range(Wt):
            sc.emissive.px[yy][xx] = None
            a.shade_px(xx, yy, MAT["floor_c"], 2.6 + rng.random() * 0.3)
    for k in range(7):  # stairwell steps going down
        y = street_y + 6 + k * 6
        a.rect(66 - k * 2, y, 52 + k * 4, 2, C(MAT["concrete"], 4))
        a.rect(66 - k * 2, y + 2, 52 + k * 4, 4, C(MAT["concrete"], 2))
    a.rect(58, street_y, 3, 46, C(MAT["steel"], 4))  # railing
    a.rect(123, street_y, 3, 46, C(MAT["steel"], 4))
    a.hline(58, 125, street_y, C(MAT["steel"], 5))
    # The clinic door at the bottom of the stairs, red work light.
    a.shaded_poly([(76, 346), (108, 346), (108, 384), (76, 384)], MAT["rust"], 4.0, 2.2, 1, 1)
    a.rect(80, 352, 24, 8, C(MAT["dark"], 1))
    sc.emissive.rect(82, 342, 20, 2, GLOW("red", 6))
    sc.light(92, 344, pal.ACCENT["red"], 54, 0.9, cone=(90, 70))
    text(sc.emissive, 85, 352, "DOC", GLOW("red", 5))
    # A customer waiting under the sign: silhouette with one glowing optic.
    fx_, fy = 140, 300
    a.ellipse(fx_, fy - 34, 4, 5, (8, 8, 12, 255))
    a.shaded_poly([(fx_ - 7, fy - 28), (fx_ + 7, fy - 28), (fx_ + 6, fy - 8), (fx_ - 6, fy - 8)], MAT["dark"], 1.5, 1, 1, 1)
    a.rect(fx_ - 5, fy - 8, 4, 8, (8, 8, 12, 255))
    a.rect(fx_ + 1, fy - 8, 4, 8, (8, 8, 12, 255))
    sc.emissive.set(fx_ + 2, fy - 35, GLOW("red", 7))
    sc.light(fx_ + 2, fy - 35, pal.ACCENT["red"], 10, 0.6)
    for xx in range(fx_ - 8, fx_ + 9):  # rim light from the cross sign
        if bayer(xx, fy - 20) < 0.5:
            sc.emissive.set(xx, fy - 29, GLOW("cyan", 2))
    # Puddles reflecting the neon.
    for px_, w_, cols in ((20, 30, ["magenta", "magenta", "cyan"]), (140, 34, ["cyan", "amber"]), (60, 18, ["red"])):
        puddle(sc, px_, 384 if px_ != 60 else 392, w_, rng, [GLOW(c, 4) for c in cols])
    # Steam from a street vent.
    a.rect(14, 318, 16, 3, C(MAT["steel"], 3))
    for xx in range(14, 30, 2):
        a.set(xx, 319, (8, 8, 10, 255))
    return sc.render()


def generate():
    fx_all = {}
    for t, name in enumerate(CLINIC_TIERS):
        clinic(t).save(f"clinic/clinic_t{t}_{name}.png")
        fx_all[str(t)] = list(props.FX)
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "clinic_fx.json")
    with open(root, "w") as f:
        json.dump({"_doc": "Animation anchors per clinic tier (art px), generated by tools/art/environments.py", "tiers": fx_all}, f, indent=1)
    black_market().save("blackmarket/den.png")
    title_scene().save("ui/title_keyart.png")
    for lv in range(3):
        surgery_backdrop(lv).save(f"surgery/backdrop_{lv}.png")
    print("environments: clinic x6, black market, surgery x3")
