"""The seven clinics in HD (art v3): 600x336 art px, 2 canvas units per
pixel on screen (same footprint as the old 400x224 at 3x, 2.25x the pixels).

Inspired by dense tech interiors and wet neon alleys: blue-grey riveted
panels, consoles covered in small lit screens and buttons, a catwalk and
pipe runs overhead, cable bundles, fluorescent tubes with halos, signs
with lettering, glossy floors that mirror the light, haze. Each district
keeps its identity (palette, materials, light colour, signage, filth).

The layout is shared (the room is clickable): door + waiting spots left,
diagnostics console, operating table centre, storage bench, the Clinic
Wall space, supply cabinet, records rack right. Positions are the old
layout x1.5 (see scripts/components/clinic_view.gd).

Upgrade overlays: the scene is re-rendered with the upgrade props, diffed
against the base and cropped; ClinicView composites them at runtime.
"""
from __future__ import annotations

import json
import math
import os

import numpy as np

from . import hd
from .hd import PAL, Scene, hexc, mix, shade

W, H = 600, 336
FLOOR = 243  # back wall meets the floor

# id, district, wall material, floor, ambient, grime 0 (filthy) .. 3 (clean), key light, accents, sign text
CLINICS = [
    {"id": "backalley", "wall": "concrete", "floor": "concrete", "amb": (0.13, 0.13, 0.17), "grime": 0,
     "key": "tungsten", "accent": ["pink", "amber"], "sign": "OPEN 24H", "sign2": "DOC", "window": True, "catwalk": False},
    {"id": "undercity", "wall": "tile", "floor": "concrete", "amb": (0.13, 0.15, 0.19), "grime": 0,
     "key": "fluoro", "accent": ["green", "pink"], "sign": "CLINIC", "sign2": "NO COPS", "window": True, "catwalk": False},
    {"id": "industrial", "wall": "panel", "floor": "metal", "amb": (0.15, 0.14, 0.14), "grime": 1,
     "key": "sodium", "accent": ["orange", "amber"], "sign": "LINE 4", "sign2": "SAFETY 0 DAYS", "window": False, "catwalk": True},
    {"id": "nightmarket", "wall": "concrete", "floor": "tile", "amb": (0.14, 0.12, 0.17), "grime": 1,
     "key": "tungsten", "accent": ["pink", "yellow", "green"], "sign": "CHROME", "sign2": "FIX + BUY", "window": True, "catwalk": False},
    {"id": "professional", "wall": "tile", "floor": "tile", "amb": (0.17, 0.19, 0.22), "grime": 2,
     "key": "fluoro", "accent": ["cyan", "blue"], "sign": "MED BAY", "sign2": "LICENSED", "window": False, "catwalk": True},
    {"id": "corporate", "wall": "clean", "floor": "metal", "amb": (0.20, 0.22, 0.27), "grime": 3,
     "key": "fluoro", "accent": ["blue", "cyan"], "sign": "MERIDIAN", "sign2": "CARE", "window": False, "catwalk": True},
    {"id": "elite", "wall": "hex", "floor": "metal", "amb": (0.17, 0.18, 0.25), "grime": 3,
     "key": "fluoro", "accent": ["violet", "cyan"], "sign": "LYRA", "sign2": "RESEARCH", "window": False, "catwalk": True},
]

UPGRADE_CATEGORIES = ["surgery", "diagnostics", "security", "black_market", "staff", "customer"]

# Layout (art px). Hotspots in ClinicView use the same numbers.
DOOR = (10, 118, 64, FLOOR - 118)
DIAG = (117, 129, 54, 51)
TABLE = (240, 156, 120, 87)
BENCH = (372, 150, 114, 93)
WALLSPACE = (348, 63, 114, 51)
CABINET = (498, 78, 54, 165)
RACK = (555, 111, 42, 132)


def C(name, k=0.0):
    return shade(PAL[name], k) if k else PAL[name]


# =============================================================================
# Structure
# =============================================================================

def wall(s: Scene, spec):
    kind = spec["wall"]
    g = spec["grime"]
    if kind == "concrete":
        base = C("concrete2") if g < 2 else C("concrete3")
        s.vgrad(0, 0, W, FLOOR, shade(base, -0.25), base)
        s.noise(0, 0, W, FLOOR, 0.12, seed=3, scale=2)
        s.noise(0, 0, W, FLOOR, 0.06, seed=4)
        # Formwork seams and tie holes.
        for x in range(0, W, 96):
            s.vline(x, 34, FLOOR - 1, shade(base, -0.35))
        for y in range(70, FLOOR, 64):
            s.hline(0, W, y, shade(base, -0.3))
            for x in range(24, W, 48):
                s.px(x, y - 20, shade(base, -0.5))
                s.px(x + 1, y - 20, shade(base, -0.5))
    elif kind == "tile":
        base = C("tile1") if g < 2 else shade(C("steel3"), 0.1)
        s.rect(0, 0, W, FLOOR, base)
        grout = shade(base, -0.4)
        for y in range(34, FLOOR, 12):
            s.hline(0, W, y, grout)
        for y in range(34, FLOOR, 12):
            off = 0 if (y // 12) % 2 else 6
            for x in range(off, W, 12):
                s.vline(x, y, y + 11, grout)
        s.noise(0, 34, W, FLOOR - 34, 0.08, seed=5, scale=1)
        # A few cracked or missing tiles.
        for k in range(14 if g < 2 else 4):
            x = s.rng.randrange(0, W // 12) * 12
            y = 34 + s.rng.randrange(0, (FLOOR - 34) // 12) * 12
            s.rect(x + 1, y + 1, 11, 11, shade(base, -0.45 if g < 2 else -0.15))
    elif kind == "panel":
        base = C("steel2")
        s.rect(0, 0, W, FLOOR, shade(base, -0.3))
        for x in range(0, W, 40):
            s.panel(x + 1, 36, 38, FLOOR - 37, base, seams=True, rivets=True, vent=(x // 40) % 4 == 1)
    elif kind == "clean":
        base = shade(C("steel4"), 0.12)
        s.vgrad(0, 0, W, FLOOR, shade(base, -0.1), shade(base, 0.08))
        for x in range(0, W, 60):
            s.vline(x, 34, FLOOR - 1, shade(base, -0.2))
            s.vline(x + 1, 34, FLOOR - 1, shade(base, 0.15))
        s.hline(0, W, 150, shade(base, -0.25))
        s.rect(0, 151, W, 4, shade(C("blue"), -0.55))
        s.glow(0, 152, W, 1, C("blue"), 0.35)
    elif kind == "hex":
        base = shade(C("steel2"), 0.05)
        s.rect(0, 0, W, FLOOR, shade(base, -0.25))
        for row, y in enumerate(range(34, FLOOR, 14)):
            off = 0 if row % 2 == 0 else 12
            for x in range(-24 + off, W, 24):
                s.poly([(x + 6, y), (x + 18, y), (x + 23, y + 7), (x + 18, y + 13), (x + 6, y + 13), (x + 1, y + 7)], base)
                s.hline(x + 7, x + 17, y + 1, shade(base, 0.25))
        s.noise(0, 34, W, FLOOR - 34, 0.05, seed=6)
    # Skirting and a cable tray along the base of the wall.
    s.rect(0, FLOOR - 8, W, 8, shade(C("steel1"), -0.1))
    s.hline(0, W, FLOOR - 8, C("steel3"))
    for x in range(0, W, 6):
        s.px(x, FLOOR - 5, C("steel3", -0.2))


def ceiling(s: Scene, spec):
    s.vgrad(0, 0, W, 34, C("void"), C("steel0"))
    s.hline(0, W, 33, C("steel2"))
    # Beams.
    for x in range(30, W, 120):
        s.box(x, 0, 14, 36, C("steel1"), 0.15, True, 0.3)
        s.vline(x + 3, 2, 34, C("steel3"))
    # Pipe runs with joints, valves and a drip.
    for py, col, th in ((8, "steel3", 5), (16, "rust2" if spec["grime"] < 2 else "steel4", 4), (24, "steel2", 3)):
        c = C(col)
        s.rect(0, py, W, th, c)
        s.hline(0, W, py, shade(c, 0.3))
        s.hline(0, W, py + th - 1, shade(c, -0.4))
        for x in range(40, W, 90):
            s.box(x, py - 1, 5, th + 2, shade(c, 0.1), 0.2, True, 0.3)
    s.box(212, 13, 7, 8, C("red", -0.45), 0.2)
    s.anchor("drip", 218, 28, 1, 40, "cyan")
    s.anchor("steam", 405, 12, 1, 1, "white")
    # Cable bundles sagging between beams (the reference's tangle).
    cols = [C("steel0"), C("void"), C("steel1"), shade(C("rust1"), -0.2)]
    for k in range(9):
        x0 = s.rng.randrange(0, W - 120)
        s.cable(x0, 30 + s.rng.randrange(0, 4), x0 + s.rng.randrange(60, 160), 30 + s.rng.randrange(0, 4),
                s.rng.randrange(6, 22), cols[k % len(cols)], thick=s.rng.choice((1, 1, 2)), hl=C("steel3"))


def tube_light(s: Scene, x, y, w, color="fluoro", flicker=False, strength=1.0):
    s.box(x - 2, y - 3, w + 4, 3, C("steel1"), 0.2)
    s.vline(x + 2, y - 10, y - 3, C("steel2"))
    s.vline(x + w - 3, y - 10, y - 3, C("steel2"))
    s.glow(x, y, w, 2, C(color), 0.95 * strength)
    s.light(x + w / 2, y + 6, C(color) * 0.9, 210, 0.85 * strength, cone=(0, 1, 75))
    if flicker:
        s.anchor("led", x + w // 2, y, 1, 1, "white", rate=0.3)


def hanging_lamp(s: Scene, x, y, color="tungsten", r=150, i=1.0):
    s.vline(x, 34, y - 4, C("void"))
    s.poly([(x - 7, y), (x + 7, y), (x + 4, y - 5), (x - 4, y - 5)], C("steel2"))
    s.hline(x - 7, x + 7, y, C("steel4"))
    s.glow(x - 3, y + 1, 7, 2, C(color), 1.0)
    s.light(x, y + 4, C(color), r, i, cone=(0, 1, 62))


def floor_(s: Scene, spec):
    kind = spec["floor"]
    top, bottom = FLOOR, H
    if kind == "concrete":
        base = C("concrete1")
        s.vgrad(0, top, W, bottom - top, shade(base, -0.2), shade(base, 0.12))
        s.noise(0, top, W, bottom - top, 0.14, seed=11, scale=2)
        gloss = 0.5
    elif kind == "tile":
        base = C("tile0")
        s.vgrad(0, top, W, bottom - top, shade(base, -0.15), shade(base, 0.15))
        gloss = 0.5
    else:
        base = C("steel1")
        s.vgrad(0, top, W, bottom - top, shade(base, -0.2), shade(base, 0.12))
        gloss = 0.45
    # Perspective grid: rows get taller towards the viewer, verticals fan out.
    y, h = top, 6
    rows = []
    while y < bottom:
        rows.append(y)
        y += h
        h = int(h * 1.28) + 1
    for ry in rows:
        s.hline(0, W, ry, shade(base, -0.35))
    cx = W / 2
    for k in range(-14, 15):
        x_far = cx + k * 30
        x_near = cx + k * 30 * 1.9
        s.line(x_far, top, x_near, bottom, shade(base, -0.32))
    if kind == "metal":
        for ry in rows[1:]:
            for x in range(4, W, 14):
                s.px(x, ry + 2, shade(base, 0.25))
    s.gloss[top:bottom, :] = gloss
    s.floor_y = top
    # Puddles: high gloss patches.
    for k in range(5 if spec["grime"] < 2 else 2):
        px_, py_ = s.rng.randrange(40, W - 80), s.rng.randrange(top + 10, bottom - 8)
        pw = s.rng.randrange(30, 80)
        for yy in range(py_, py_ + 6):
            inset = abs(yy - py_ - 3) * 4
            s.gloss[yy, max(0, px_ + inset):min(W, px_ + pw - inset)] = 0.95
            s.rect(px_ + inset, yy, pw - 2 * inset, 1, shade(base, -0.3))


def door(s: Scene, spec):
    x, y, w, h = DOOR
    s.box(x - 4, y - 6, w + 8, h + 6, C("steel1"), 0.15)
    if spec["grime"] >= 2:
        # Sliding door with a lit status strip.
        s.box(x, y, w, h, C("steel3"), 0.2)
        s.vline(x + w // 2, y, y + h, C("steel1"))
        s.glow(x + 4, y + 8, w - 8, 2, C(spec["accent"][0]), 0.8)
        s.glow(x + w + 6, y + 50, 4, 8, C("green"), 0.9)
        s.anchor("led", x + w + 7, y + 52, 2, 1, "green", rate=0.5)
    else:
        # Roll-up shutter half open: slats, a glow of the street below.
        slats = shade(C("steel2"), -0.05)
        for k in range(0, int(h * 0.6), 4):
            s.rect(x, y + k, w, 3, slats)
            s.hline(x, x + w - 1, y + k, shade(slats, 0.25))
        s.rect(x, y + int(h * 0.6), w, h - int(h * 0.6), C("void"))
        s.glow(x + 2, y + h - 10, w - 4, 10, C(spec["accent"][0]), 0.25)
        s.light(x + w / 2, y + h - 4, C(spec["accent"][0]), 90, 0.5)
        s.box(x - 2, y + int(h * 0.6) - 2, w + 4, 3, C("steel3"), 0.2)
    # Door sign / buzzer.
    s.box(x + w + 4, y + 20, 8, 10, C("steel1"), 0.2)
    s.gpx(x + w + 7, y + 23, C("red"), 1.0)
    s.anchor("led", x + w + 7, y + 23, 1, 1, "red", rate=1.3)


def window_to_street(s: Scene, x, y, w, h, spec):
    """A barred window onto a neon alley (the first reference)."""
    s.box(x - 3, y - 3, w + 6, h + 6, C("steel1"), 0.2)
    s.vgrad(x, y, w, h, C("void"), shade(C("violet"), -0.75))
    # Far buildings with lit windows.
    r = s.rng
    for bx in range(x, x + w, 9):
        bh = r.randrange(h // 3, h)
        s.rect(bx, y + h - bh, 8, bh, shade(C("steel0"), r.uniform(-0.2, 0.2)))
        for wy in range(y + h - bh + 2, y + h - 2, 4):
            for wx in (bx + 2, bx + 5):
                if r.random() < 0.35:
                    s.gpx(wx, wy, C(r.choice(["amber", "tungsten", "cyan"])), 0.6)
    # Neon signs across the street.
    for k, col in enumerate(spec["accent"]):
        sx, sy = x + 6 + k * (w // len(spec["accent"])), y + 6 + (k % 2) * 12
        s.glow(sx, sy, min(16, w // 3), 6, C(col), 0.9)
        s.text(sx + 1, sy + 1, ["NOODL", "BAR", "24H", "HOTEL"][k % 4][:4], C("void"), "emissive")
    s.light(x + w / 2, y + h / 2, C(spec["accent"][0]) * 0.8, 120, 0.6)
    # Rain streaks and bars.
    for k in range(18):
        rx, ry = x + r.randrange(0, w), y + r.randrange(0, h - 6)
        s.vline(rx, ry, ry + 4, shade(C("ice"), -0.5), "emissive")
    for bx in range(x + 6, x + w, 10):
        s.rect(bx, y, 2, h, C("steel2"))
        s.vline(bx, y, y + h, C("steel4"))


def catwalk(s: Scene):
    """Upper walkway with railing across the back (second reference)."""
    y = 46
    s.rect(0, y, W, 5, C("steel2"))
    s.hline(0, W, y, C("steel4"))
    s.hline(0, W, y + 5, C("void"))
    for x in range(0, W, 3):
        s.px(x, y + 2, C("steel1"))
    # Railing.
    s.hline(0, W, y - 12, C("steel4"))
    s.hline(0, W, y - 6, C("steel3"))
    for x in range(8, W, 22):
        s.vline(x, y - 12, y, C("steel3"))
    # Support struts down the wall.
    for x in range(60, W, 180):
        s.line(x, y + 5, x + 14, y + 22, C("steel2"))
    # Warning lights on the rail.
    for x in range(100, W, 200):
        s.gpx(x, y - 13, C("amber"), 1.0)
        s.anchor("led", x, y - 13, 1, 1, "amber", rate=0.9)


# =============================================================================
# Furniture (the clickable layout)
# =============================================================================

def screen(s: Scene, x, y, w, h, color="cyan", kind="ui"):
    """A lit screen with something on it: UI lines, a graph, a face, text."""
    col = C(color)
    s.box(x - 2, y - 2, w + 4, h + 4, C("steel0"), 0.2)
    s.glow(x, y, w, h, shade(col, -0.82), 1.0)
    r = s.rng
    if kind == "ui":
        for yy in range(y + 2, y + h - 1, 3):
            ln = r.randrange(w // 4, w - 3)
            s.glow(x + 2, yy, ln, 1, col, r.uniform(0.35, 0.8))
    elif kind == "graph":
        prev = y + h // 2
        for xx in range(x + 1, x + w - 1):
            ny = max(y + 1, min(y + h - 2, prev + r.randrange(-2, 3)))
            s.gpx(xx, ny, col, 0.9)
            prev = ny
        s.glow(x + 1, y + h - 3, w - 2, 1, col, 0.3)
    elif kind == "bars":
        for xx in range(x + 2, x + w - 2, 3):
            bh = r.randrange(2, h - 2)
            s.glow(xx, y + h - 1 - bh, 2, bh, col, 0.7)
    elif kind == "face":
        cx, cy = x + w // 2, y + h // 2
        for yy in range(y + 2, y + h - 1):
            for xx in range(x + 2, x + w - 2):
                if ((xx - cx) / (w * 0.28)) ** 2 + ((yy - cy) / (h * 0.38)) ** 2 < 1:
                    s.gpx(xx, yy, col, 0.55 + 0.25 * ((xx + yy) % 2))
        s.gpx(cx - 2, cy - 1, C("white"), 0.9)
        s.gpx(cx + 2, cy - 1, C("white"), 0.9)
    elif kind == "text":
        for yy in range(y + 2, y + h - 4, 6):
            s.text(x + 2, yy, r.choice(["SYS OK", "PULSE", "LOAD 23", "SCAN", "ID ??", "LINK"]), col)
    s.light(x + w / 2, y + h / 2, col * 0.8, max(w, h) * 2.2, 0.45)
    s.anchor("monitor", x, y, w, h, color)


def console(s: Scene, x, y, w, h, spec, screens=2):
    """Desk console with screens, button grids, a keyboard."""
    body = C("steel2")
    s.box(x, y + h // 2, w, h - h // 2, body, 0.15)
    s.panel(x + 2, y + h // 2 + 3, w - 4, h - h // 2 - 5, shade(body, -0.1), seams=False, rivets=True)
    # Button grid with lit keys.
    for by in range(y + h // 2 + 6, y + h - 6, 4):
        for bx in range(x + 6, x + w - 6, 4):
            c = s.rng.choice(["steel3", "steel4", "red", "amber", "green", "cyan", "steel3", "steel3"])
            if c in ("red", "amber", "green", "cyan"):
                s.gpx(bx, by, C(c), 0.85)
                s.gpx(bx + 1, by, C(c), 0.85)
            else:
                s.rect(bx, by, 2, 2, C(c))
    s.anchor("led", x + 8, y + h // 2 + 6, 3, 1, "green", rate=0.7)
    # Screens on arms.
    sw = (w - 6) // screens - 4
    kinds = ["graph", "ui", "bars", "face", "text"]
    for k in range(screens):
        sx = x + 4 + k * (sw + 4)
        s.vline(sx + sw // 2, y + h // 2 - 4, y + h // 2, C("steel3"))
        screen(s, sx, y + 2, sw, h // 2 - 8, spec["accent"][k % len(spec["accent"])] if k else "cyan", kinds[(k + len(spec["id"])) % len(kinds)])


def op_table(s: Scene, spec):
    x, y, w, h = TABLE
    # Pedestal and hydraulics.
    s.box(x + w // 2 - 10, y + 40, 20, h - 40, C("steel2"), 0.2)
    s.box(x + w // 2 - 22, FLOOR - 6, 44, 6, C("steel1"), 0.2)
    for k in range(3):
        s.hline(x + w // 2 - 8, x + w // 2 + 7, y + 48 + k * 8, C("steel4"))
    # Table top with padding and straps.
    s.box(x + 4, y + 26, w - 8, 14, C("steel3"), 0.25)
    pad = C("teal", -0.55) if spec["grime"] >= 2 else C("rust1", -0.1)
    s.box(x + 8, y + 20, w - 16, 8, pad, 0.2)
    s.noise(x + 8, y + 20, w - 16, 8, 0.1, seed=21)
    for sx in (x + 30, x + w - 40):
        s.rect(sx, y + 19, 6, 10, C("void"))
        s.px(sx + 2, y + 23, C("steel5"))
    if spec["grime"] < 2:
        for k in range(10):
            s.px(x + 20 + s.rng.randrange(0, w - 40), y + 21 + s.rng.randrange(0, 6), C("blood"))
    # Surgical lamp on an arm from the ceiling: the brightest thing in the room.
    lx, ly = x + w // 2, y - 46
    s.line(lx - 30, 34, lx - 6, ly, C("steel3"))
    s.line(lx - 29, 34, lx - 5, ly, C("steel2"))
    s.poly([(lx - 22, ly), (lx + 22, ly), (lx + 14, ly - 9), (lx - 14, ly - 9)], C("steel3"))
    s.hline(lx - 22, lx + 22, ly, C("steel5"))
    for k in range(5):
        s.glow(lx - 16 + k * 7, ly + 1, 5, 2, C("white"), 1.0)
    s.light(lx, ly + 6, C("white") * 1.05, 150, 1.25, cone=(0, 1, 38), falloff=1.2)
    # Side monitor on a pole: vitals.
    mx, my = x + w - 8, y - 18
    s.vline(mx + 8, my + 14, FLOOR - 1, C("steel3"))
    s.box(mx + 2, FLOOR - 4, 14, 4, C("steel1"))
    screen(s, mx, my, 18, 14, "green", "graph")
    s.anchor("ecg", mx + 1, my + 2, 16, 10, "green")


def bench(s: Scene, spec):
    x, y, w, h = BENCH
    top = y + 40
    s.box(x, top, w, 6, C("steel3") if spec["grime"] >= 1 else C("rust2"), 0.25)
    for lx in (x + 4, x + w - 8):
        s.box(lx, top + 6, 4, FLOOR - top - 6, C("steel1"), 0.2)
    s.box(x + 10, top + 30, w - 20, 4, C("steel2"))  # lower shelf
    # Pegboard with tools behind.
    s.box(x + 6, y - 6, w - 12, 44, shade(C("steel1"), -0.1), 0.15)
    for py in range(y - 2, y + 36, 5):
        for px_ in range(x + 10, x + w - 10, 5):
            s.px(px_, py, C("void"))
    for k, tx in enumerate(range(x + 14, x + w - 14, 12)):
        tool = k % 4
        if tool == 0:
            s.vline(tx, y + 2, y + 20, C("steel5"))
            s.rect(tx - 1, y + 20, 3, 6, C("red", -0.3))
        elif tool == 1:
            s.line(tx - 3, y + 4, tx + 3, y + 18, C("steel4"))
        elif tool == 2:
            s.rect(tx - 2, y + 4, 5, 10, C("amber", -0.4))
            s.vline(tx, y + 14, y + 22, C("steel4"))
        else:
            for k2 in range(3):
                s.px(tx + k2 - 1, y + 6 + k2 * 4, C("steel5"))
    # Clutter on the bench: crates, a lamp, implants.
    s.box(x + 10, top - 10, 22, 10, C("amber", -0.62), 0.2)
    s.text(x + 12, top - 8, "MED", C("amber", -0.3), "albedo")
    s.box(x + 36, top - 7, 14, 7, C("steel2"), 0.2)
    for k in range(3):
        s.rect(x + 56 + k * 7, top - 5, 5, 5, C("steel4"))
        s.gpx(x + 58 + k * 7, top - 3, C(["cyan", "pink", "green"][k]), 0.9)
    s.anchor("led", x + 58, top - 3, 1, 1, "cyan", rate=0.6)
    hanging_lamp(s, x + w - 24, top - 26, "tungsten", 70, 0.6)
    # Crates under the bench.
    s.box(x + 14, FLOOR - 18, 26, 18, C("steel2"), 0.2)
    s.text(x + 17, FLOOR - 14, "BIO", C("yellow", -0.25), "albedo")
    s.box(x + 44, FLOOR - 12, 20, 12, C("rust1"), 0.2)


def cabinet(s: Scene, spec):
    x, y, w, h = CABINET
    s.box(x, y, w, h, C("steel3"), 0.2)
    s.vline(x + w // 2, y + 2, y + h - 2, C("steel1"))
    # Glass upper doors with stock behind.
    for gx in (x + 3, x + w // 2 + 2):
        s.rect(gx, y + 4, w // 2 - 5, 70, shade(C("teal"), -0.78))
        for sy in range(y + 18, y + 72, 16):
            s.hline(gx, gx + w // 2 - 6, sy, C("steel4"))
            for k in range(0, w // 2 - 8, 5):
                c = s.rng.choice(["white", "bone", "amber", "pink", "cyan"])
                s.rect(gx + 1 + k, sy - 6, 3, 6, shade(C(c), -0.35))
        s.glow(gx, y + 4, 1, 70, C("ice"), 0.25)
    s.glow(x + 4, y + 2, w - 8, 1, C("cyan"), 0.6)
    s.light(x + w / 2, y + 30, C("cyan") * 0.5, 70, 0.4)
    # Drawers below.
    for dy in range(y + 82, y + h - 6, 16):
        s.box(x + 3, dy, w - 6, 13, C("steel2"), 0.2)
        s.hline(x + w // 2 - 5, x + w // 2 + 4, dy + 6, C("steel5"))
    s.text(x + 4, y + h - 12, "SUPPLY", C("yellow", -0.2), "albedo")


def rack(s: Scene, spec):
    x, y, w, h = RACK
    s.box(x, y, w, h, C("steel1"), 0.2)
    for uy in range(y + 4, y + h - 6, 7):
        s.box(x + 3, uy, w - 6, 6, C("steel2"), 0.15)
        for k in range(4):
            if s.rng.random() < 0.7:
                col = s.rng.choice(["green", "green", "cyan", "amber", "red"])
                s.gpx(x + 6 + k * 3, uy + 2, C(col), 0.95)
        s.glow(x + w - 14, uy + 2, 8, 1, C("cyan"), 0.35)
    for k in range(5):
        s.anchor("led", x + 6 + (k % 4) * 3, y + 6 + k * 21, 1, 1, ["green", "cyan", "amber", "green", "red"][k], rate=0.4 + k * 0.23)
    s.anchor("fan", x + w // 2 - 5, y + h - 16, 10, 10, "dark")
    # Cables spilling from the top into the ceiling.
    for k in range(4):
        s.cable(x + 6 + k * 8, y, x + 10 + k * 6, 34, 4, C("void"), 1)


def wallspace(s: Scene, spec):
    """Where the Clinic Wall pins go: a cork/metal board."""
    x, y, w, h = WALLSPACE
    base = shade(C("rust1"), -0.2) if spec["grime"] < 2 else C("steel2")
    s.box(x - 4, y - 4, w + 8, h + 8, C("steel1"), 0.2)
    s.rect(x - 2, y - 2, w + 4, h + 4, base)
    s.noise(x - 2, y - 2, w + 4, h + 4, 0.12, seed=31)
    s.light(x + w / 2, y - 6, C("tungsten") * 0.6, 80, 0.45, cone=(0, 1, 70))


def diag(s: Scene, spec):
    x, y, w, h = DIAG
    console(s, x, y, w, h + 6, spec, screens=2)
    s.box(x - 2, y + h + 6, w + 4, FLOOR - (y + h + 6), C("steel1"), 0.2)
    s.anchor("led", x + w - 10, y + h + 12, 1, 1, "cyan", rate=0.8)


def waiting_area(s: Scene, spec):
    """Two plastic chairs and a bench by the door."""
    for k, cx in enumerate((84, 102)):
        col = C(["amber", "teal", "pink", "steel3"][(k + len(spec["id"])) % 4], -0.45)
        s.box(cx, FLOOR - 16, 14, 4, col, 0.2)
        s.box(cx + 1, FLOOR - 30, 12, 14, col, 0.2)
        s.vline(cx + 2, FLOOR - 12, FLOOR - 1, C("steel3"))
        s.vline(cx + 11, FLOOR - 12, FLOOR - 1, C("steel3"))


def wall_dressing(s: Scene, spec):
    """Dense wall clutter like the references: pipes, conduit, boxes, an AC unit, cables."""
    g = spec["grime"]
    pipe = C("rust2") if g < 2 else C("steel4")
    # Vertical pipes with brackets and a valve.
    for px_, th in ((176, 6), (491, 4)):
        s.rect(px_, 34, th, FLOOR - 42, pipe)
        s.vline(px_ + 1, 34, FLOOR - 9, shade(pipe, 0.35))
        s.vline(px_ + th - 1, 34, FLOOR - 9, shade(pipe, -0.45))
        for by in range(60, FLOOR - 10, 46):
            s.box(px_ - 2, by, th + 4, 4, C("steel3"), 0.25)
    s.box(172, 168, 14, 6, C("red", -0.4), 0.25)
    s.vline(179, 160, 168, C("steel4"))
    s.hline(174, 184, 160, C("red", -0.3))
    # Conduit with junction boxes along the top of the wall.
    s.rect(0, 56, 84, 3, C("steel3"))
    s.hline(0, 84, 56, C("steel4"))
    for jx in (20, 58):
        s.box(jx, 51, 14, 12, C("steel2"), 0.2, True, 0.4)
        s.gpx(jx + 10, 54, C("green" if jx == 20 else "amber"), 0.9)
    # AC unit around the fan anchor.
    s.box(504, 36, 44, 28, C("steel3"), 0.2, True, 0.45)
    for yy in range(39, 61, 3):
        s.hline(507, 528, yy, C("steel1"))
    s.rect(530, 39, 15, 22, C("steel1"))
    s.anchor("drip", 540, 64, 1, 30, "cyan") if g < 2 else None
    # Breaker box with a hazard stripe.
    bx, by = 466, 70
    s.box(bx, by, 22, 30, C("steel2"), 0.2, True, 0.4)
    for k in range(0, 22, 4):
        s.line(bx + k, by + 30, bx + k + 3, by + 26, C("yellow", -0.3))
    for k in range(3):
        s.rect(bx + 4 + k * 5, by + 6, 3, 8, C("steel4"))
    s.gpx(bx + 17, by + 4, C("red"), 1.0)
    s.anchor("led", bx + 17, by + 4, 1, 1, "red", rate=0.9)
    # Cable bundles dropping from the ceiling into boxes.
    cols = [C("void"), C("steel0"), shade(C(spec["accent"][0]), -0.6)]
    for k, (x0, x1) in enumerate(((150, 176), (226, 250), (440, 468), (470, 498))):
        s.cable(x0, 34, x1, 34 + 30 + k * 6, 10 + k * 3, cols[k % 3], thick=2, hl=C("steel3"))
    # A wall clock / day counter and a small exit-style sign.
    s.box(296, 40, 30, 12, C("void"), 0.1)
    s.text(299, 43, "03:17", C("red"), "emissive")
    s.light(311, 46, C("red"), 30, 0.35)
    # Small vent grilles.
    for vx, vy in ((200, 64), (420, 100)):
        s.box(vx, vy, 20, 12, C("steel2"), 0.2)
        for k in range(vy + 2, vy + 11, 2):
            s.hline(vx + 2, vx + 17, k, C("void"))


def floor_dressing(s: Scene, spec):
    """Cables across the floor, a drain, buckets and foreground silhouettes."""
    g = spec["grime"]
    # Power cables from the rack to the table base and console.
    for k, (x0, x1, y) in enumerate(((560, 330, 252), (556, 180, 258), (150, 290, 249))):
        pts = []
        for t in range(0, 41):
            u = t / 40
            x = x0 + (x1 - x0) * u
            yy = y + math.sin(u * math.pi * 2 + k) * 3 + u * 2
            pts.append((x, yy))
        col = C("void") if k != 1 else shade(C(spec["accent"][0]), -0.55)
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            s.line(ax, ay, bx, by, col)
            s.line(ax, ay + 1, bx, by + 1, shade(col, 0.2))
    # Floor drain.
    s.box(282, 300, 34, 8, C("steel0"), 0.2)
    for k in range(285, 314, 3):
        s.vline(k, 301, 306, C("void"))
    s.gloss[296:312, 276:322] = 0.9
    if g < 3:
        # Bucket and mop, a stack of crates, a trash bag.
        s.box(80, 262, 14, 14, C("yellow", -0.45), 0.25)
        s.line(90, 230, 86, 270, C("steel4"))
        s.box(530, 268, 40, 28, C("rust1"), 0.2)
        s.box(536, 248, 30, 20, C("steel2"), 0.2)
        s.text(539, 254, "FRAG", C("yellow", -0.3), "albedo")
        s.poly([(14, 300), (40, 296), (48, 318), (30, 326), (8, 320)], hexc("101318"))
        s.hline(18, 38, 299, C("steel3"))
    # Foreground silhouettes (depth like the references): a pipe and a cable tray.
    s.rect(0, 326, W, 10, hexc("07090d"))
    s.box(0, 318, 120, 8, hexc("0c1016"), 0.1)
    s.box(480, 314, 120, 12, hexc("0c1016"), 0.1)
    s.hline(0, 120, 318, C("steel1"))
    s.hline(480, W, 314, C("steel1"))


# =============================================================================
# Signs, grime, dressing
# =============================================================================

def neon_sign(s: Scene, x, y, text, color, big=True, frame=True):
    col = C(color)
    tw = len(text) * (6 if big else 4)
    if frame:
        s.box(x - 4, y - 4, tw + 6, (7 if big else 5) + 8, C("void"), 0.1)
    s.text(x, y, text, col, "emissive", big=big)
    s.light(x + tw / 2, y + 4, col, tw * 2.2 + 40, 0.8)
    return tw


def poster(s: Scene, x, y, w, h, color, lines=3):
    s.box(x, y, w, h, shade(C(color), -0.55), 0.1)
    s.rect(x + 2, y + 2, w - 4, h // 2, shade(C(color), -0.3))
    for k in range(lines):
        s.hline(x + 3, x + w - 4 - (k % 2) * 5, y + h // 2 + 4 + k * 3, shade(C(color), -0.2))
    s.darken(x, y + h - 4, w, 4, 0.8)


def grime(s: Scene, spec):
    g = spec["grime"]
    if g >= 3:
        s.darken(0, FLOOR - 2, W, 2, 0.85)
        return
    r = s.rng
    # Water streaks and rust runs down the wall.
    for k in range(10 - g * 3):
        x = r.randrange(0, W)
        y0 = 34 + r.randrange(0, 40)
        length = r.randrange(40, 160)
        s.darken(x, y0, r.randrange(2, 5), length, 0.75)
        if r.random() < 0.5:
            s.rect(x, y0, 1, length // 2, C("rust2", -0.2))
    # Floor trash and stains.
    for k in range(20 - g * 6):
        x, y = r.randrange(0, W), r.randrange(FLOOR + 6, H - 4)
        c = r.choice(["grime", "rust0", "concrete0", "bone", "blood"])
        s.rect(x, y, r.randrange(2, 7), r.randrange(1, 3), C(c, -0.2))
    # Mould in the corners.
    for cx in (0, W - 30):
        for k in range(60):
            s.px(cx + r.randrange(0, 30), 34 + r.randrange(0, 40), hexc("1e2618"))


def sticker_wall(s: Scene, x, y, w, h, spec):
    """Stickers, tags and flyers (the alley reference's wall clutter)."""
    r = s.rng
    for k in range(18):
        px_, py_ = x + r.randrange(0, w - 10), y + r.randrange(0, h - 8)
        c = r.choice(spec["accent"] + ["bone", "steel4", "white"])
        s.rect(px_, py_, r.randrange(5, 12), r.randrange(4, 9), shade(C(c), -0.4))
    for k in range(3):
        s.text(x + r.randrange(0, w - 20), y + r.randrange(0, h - 6), r.choice(["RIP", "404", "NO", "SAINTS", "X"]), shade(C(spec["accent"][0]), -0.3), "albedo")


# =============================================================================
# The rooms
# =============================================================================

def base(cid: int) -> Scene:
    spec = CLINICS[cid]
    s = Scene(W, H, ambient=tuple(a * 3.4 for a in spec["amb"]), seed=cid * 101 + 7)
    s.haze = 0.18 if spec["grime"] < 2 else 0.1
    s.haze_color = shade(C(spec["accent"][0]), -0.6)
    wall(s, spec)
    ceiling(s, spec)
    floor_(s, spec)
    if spec["catwalk"]:
        catwalk(s)
    # Window to the street (left of the diagnostics console) or a big sign.
    if spec["window"]:
        window_to_street(s, 84, 70, 70, 46, spec)
    else:
        screen(s, 90, 66, 54, 34, spec["accent"][0], "text")
        s.anchor("holo", 90, 66, 54, 34, spec["accent"][0]) if spec["grime"] >= 3 else None
    wall_dressing(s, spec)
    door(s, spec)
    waiting_area(s, spec)
    diag(s, spec)
    op_table(s, spec)
    bench(s, spec)
    wallspace(s, spec)
    cabinet(s, spec)
    rack(s, spec)
    # Signage: the clinic's name in neon above the table, a second sign by the door.
    neon_sign(s, 252, 70, spec["sign"], spec["accent"][0], big=True)
    neon_sign(s, 14, 92, spec["sign2"], spec["accent"][-1], big=False)
    if spec["grime"] < 2:
        sticker_wall(s, 180, 90, 60, 50, spec)
        poster(s, 186, 150, 26, 34, spec["accent"][-1])
    # Lights: tubes over the room, the key colour.
    tube_light(s, 110, 40, 60, spec["key"], flicker=spec["grime"] == 0)
    tube_light(s, 400, 40, 70, spec["key"])
    if spec["key"] in ("tungsten", "sodium"):
        hanging_lamp(s, 60, 80, spec["key"], 120, 0.8)
    # Fill light so the room reads (the game lifts shadows too).
    s.light(W / 2, 140, C(spec["key"]) * 0.5, 460, 0.7, falloff=1.0)
    s.anchor("spark", 160, 32, 1, 1, "amber") if spec["grime"] < 2 else None
    s.anchor("fan", 520, 40, 12, 12, "dark")
    grime(s, spec)
    floor_dressing(s, spec)
    return s


# =============================================================================
# Upgrades (category x level) as props added to the room
# =============================================================================

def upgrade(s: Scene, cat: str, lv: int, spec):
    if cat == "surgery":
        x = TABLE[0] - 22
        s.box(x, FLOOR - 40, 18, 3, C("steel4"), 0.3)  # instrument tray
        s.vline(x + 9, FLOOR - 37, FLOOR - 1, C("steel3"))
        for k in range(4):
            s.px(x + 2 + k * 4, FLOOR - 41, C("white"))
        if lv >= 2:  # anaesthesia cart
            cx = TABLE[0] + TABLE[2] + 2
            s.box(cx, FLOOR - 44, 22, 42, C("teal", -0.5), 0.2)
            for k in range(2):
                s.box(cx + 3 + k * 9, FLOOR - 66, 7, 22, C(["green", "steel4"][k], -0.4), 0.3)
            screen(s, cx + 3, FLOOR - 38, 16, 10, "green", "graph")
            s.anchor("ecg", cx + 4, FLOOR - 37, 14, 8, "green")
        if lv >= 3:  # robotic arm from the ceiling
            ax = TABLE[0] + TABLE[2] // 2 + 30
            s.box(ax - 6, 34, 12, 8, C("steel3"), 0.3)
            s.line(ax, 42, ax + 12, 74, C("steel4"))
            s.line(ax + 1, 42, ax + 13, 74, C("steel3"))
            s.line(ax + 12, 74, ax - 2, 104, C("steel4"))
            s.box(ax - 5, 104, 8, 6, C("steel3"), 0.3)
            s.gpx(ax - 2, 111, C("amber"), 1.0)
            s.light(ax - 2, 112, C("amber"), 40, 0.6)
            s.anchor("laser", ax - 2, 111, 1, 1, "amber")
    elif cat == "diagnostics":
        x, y = DIAG[0], DIAG[1]
        s.box(x + DIAG[2] + 2, y + 24, 8, 12, C("steel3"), 0.2)  # handheld scanner
        s.gpx(x + DIAG[2] + 5, y + 27, C("cyan"), 1.0)
        s.anchor("led", x + DIAG[2] + 5, y + 27, 1, 1, "cyan", rate=0.6)
        if lv >= 2:
            screen(s, x + 4, y - 40, 46, 26, "green", "graph")
            s.anchor("ecg", x + 6, y - 36, 42, 16, "green")
        if lv >= 3:
            sx, sy = 196, 106
            s.box(sx - 3, sy - 3, 40, 52, C("steel1"), 0.2)
            s.glow(sx, sy, 34, 46, shade(C("ice"), -0.7), 1.0)
            for k in range(0, 40, 4):
                s.glow(sx + 6, sy + 4 + k, 22, 1, C("ice"), 0.35)
            s.anchor("holo", sx, sy, 34, 46, "cyan")
            s.light(sx + 17, sy + 22, C("ice") * 0.7, 90, 0.5)
    elif cat == "security":
        cx, cy = DOOR[0] + DOOR[2] + 12, 60
        s.box(cx, cy, 12, 7, C("steel3"), 0.3)  # camera
        s.box(cx + 10, cy + 2, 6, 4, C("steel1"))
        s.gpx(cx + 2, cy + 3, C("red"), 1.0)
        s.anchor("led", cx + 2, cy + 3, 1, 1, "red", rate=1.0)
        if lv >= 2:
            for bx in range(DOOR[0] + 4, DOOR[0] + DOOR[2] - 2, 8):
                s.rect(bx, DOOR[1] + 2, 3, DOOR[3] - 4, C("steel4"))
                s.vline(bx, DOOR[1] + 2, DOOR[1] + DOOR[3] - 3, C("steel5"))
        if lv >= 3:
            ax = DOOR[0] + DOOR[2] + 26
            s.box(ax, FLOOR - 120, 6, 120, C("steel2"), 0.2)
            s.glow(ax + 2, FLOOR - 112, 2, 100, C("red"), 0.7)
            s.light(ax + 3, FLOOR - 60, C("red"), 70, 0.5)
            s.anchor("led", ax + 2, FLOOR - 112, 1, 1, "red", rate=0.5)
    elif cat == "black_market":
        x = BENCH[0] + 70
        s.box(x, FLOOR - 26, 30, 26, C("rust1", -0.2), 0.2)  # a crate that isn't on the books
        s.text(x + 3, FLOOR - 20, "XX", C("pink", -0.2), "albedo")
        if lv >= 2:
            sx, sy = BENCH[0] + 6, BENCH[1] - 30
            screen(s, sx, sy, 30, 18, "pink", "text")
            s.anchor("monitor", sx, sy, 30, 18, "magenta")
        if lv >= 3:
            gx, gy = 470, 140
            s.box(gx, gy, 24, 60, C("void"), 0.1)
            for k in range(4):
                s.glow(gx + 4, gy + 6 + k * 13, 16, 2, C("pink"), 0.6)
                s.rect(gx + 6, gy + 2 + k * 13, 12, 4, C("steel4"))
            s.light(gx + 12, gy + 30, C("pink"), 70, 0.5)
            s.anchor("led", gx + 6, gy + 8, 1, 1, "magenta", rate=0.7)
    elif cat == "staff":
        lx = 186
        s.box(lx, FLOOR - 72, 22, 72, C("steel3"), 0.2)  # locker
        for k in range(3):
            s.hline(lx + 4, lx + 17, FLOOR - 66 + k * 3, C("steel1"))
        if lv >= 2:
            s.box(lx + 26, FLOOR - 40, 16, 40, C("steel1"), 0.2)  # coffee machine
            s.glow(lx + 29, FLOOR - 36, 10, 6, C("amber"), 0.5)
            s.anchor("steam", lx + 34, FLOOR - 42, 1, 1, "white")
        if lv >= 3:
            s.box(lx - 4, FLOOR - 16, 48, 6, C("teal", -0.45), 0.2)  # staff bench
            screen(s, lx, FLOOR - 104, 40, 22, "cyan", "ui")
    elif cat == "customer":
        for k in range(1, lv + 1):
            cx = 120 + k * 18
            col = C(["amber", "teal", "pink"][k % 3], -0.45)
            s.box(cx, FLOOR - 16, 14, 4, col, 0.2)
            s.box(cx + 1, FLOOR - 30, 12, 14, col, 0.2)
            s.vline(cx + 2, FLOOR - 12, FLOOR - 1, C("steel3"))
            s.vline(cx + 11, FLOOR - 12, FLOOR - 1, C("steel3"))
        if lv >= 2:
            screen(s, 112, 104, 36, 20, "amber", "text")  # waiting-room screen
        if lv >= 3:
            vx = 64 + DOOR[2] - 46
            s.box(vx + 80, FLOOR - 64, 24, 64, C("steel2"), 0.2)  # vending machine
            s.glow(vx + 83, FLOOR - 60, 18, 26, C("yellow"), 0.35)
            for k in range(3):
                s.rect(vx + 85 + k * 5, FLOOR - 56, 3, 18, C(["red", "green", "blue"][k], -0.3))
            s.light(vx + 92, FLOOR - 46, C("yellow"), 60, 0.4)


# =============================================================================
# Generation
# =============================================================================

def _diff(base_img, img):
    d = np.abs(img - base_img).sum(axis=2) > 1e-4
    if not d.any():
        return None
    ys, xs = np.where(d)
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1, d


def generate(with_overlays=True):
    fx_all, overlays = {}, {}
    for cid, spec in enumerate(CLINICS):
        s = base(cid)
        img = s.render()
        s.save(f"clinic/clinic_{spec['id']}.png", img)
        fx_all[spec["id"]] = s.fx
        if not with_overlays:
            continue
        for cat in UPGRADE_CATEGORIES:
            for lv in (1, 2, 3):
                u = s.copy()
                upgrade(u, cat, lv, spec)
                uimg = u.render()
                r = _diff(img, uimg)
                if r is None:
                    continue
                x0, y0, x1, y1, mask = r
                rel = f"clinic/upgrades/{spec['id']}_{cat}_{lv}.png"
                hd.save_rgba(rel, uimg[y0:y1, x0:x1], mask[y0:y1, x0:x1].astype(np.float32))
                fx = [e for e in u.fx]
                overlays[f"{spec['id']}/{cat}/{lv}"] = {"path": "res://assets/sprites/" + rel, "x": int(x0), "y": int(y0), "fx": fx}
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data")
    with open(os.path.join(root, "clinic_fx.json"), "w") as f:
        json.dump({"_doc": "Animation anchors per clinic (HD art px, 600x336 rooms), generated by tools/art/rooms_hd.py",
                   "clinics": fx_all}, f, indent=1)
    if with_overlays:
        with open(os.path.join(root, "clinic_overlays.json"), "w") as f:
            json.dump({"_doc": "Upgrade overlay sprites per clinic/category/level (HD art px offsets), generated by tools/art/rooms_hd.py",
                       "overlays": overlays}, f, indent=1)
    print("HD clinics: %d rooms, %d upgrade overlays" % (len(CLINICS), len(overlays)))
