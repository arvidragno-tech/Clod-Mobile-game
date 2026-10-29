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
    f = 1.0 / s.res
    r = s.rng
    if kind == "concrete":
        base = C("concrete2") if g < 2 else C("concrete3")
        s.vgrad(0, 0, W, FLOOR, shade(base, -0.25), base)
        s.noise(0, 0, W, FLOOR, 0.10, seed=3, scale=2)
        s.noise(0, 0, W, FLOOR, 0.07, seed=4, scale=1)
        # Formwork seams (a dark groove with a lit lip) and tie holes.
        for x in range(0, W, 96):
            s.vline(x, 34, FLOOR - 1, shade(base, -0.35))
            s.fvline(x + 1, 34, FLOOR - 1, shade(base, 0.12))
        for y in range(70, FLOOR, 64):
            s.hline(0, W, y, shade(base, -0.3))
            s.fhline(0, W, y + 1, shade(base, 0.1))
            for x in range(24, W, 48):
                s.disc(x + 1, y - 19.5, 1.1, shade(base, -0.55))
                s.fhline(x, x + 2, y - 18, shade(base, 0.2))
        # Hairline cracks wandering down from the seams.
        for k in range(16 if g < 2 else 6):
            cx, cy = r.uniform(0, W), r.uniform(40, FLOOR - 30)
            for i in range(r.randrange(12, 40)):
                nx, ny = cx + r.uniform(-1.2, 1.2), cy + r.uniform(0.3, 1.2)
                s.fline(cx, cy, nx, ny, shade(base, -0.5))
                cx, cy = nx, ny
        # Patches of newer render and pocks.
        for k in range(10):
            px_, py_ = r.uniform(0, W - 30), r.uniform(40, FLOOR - 30)
            s.darken(px_, py_, r.uniform(10, 30), r.uniform(6, 16), r.uniform(0.86, 1.08))
        for k in range(120):
            s.px(r.uniform(0, W), r.uniform(36, FLOOR - 9), shade(base, -0.4), t=f)
    elif kind == "tile":
        base = C("tile1") if g < 2 else shade(C("steel3"), 0.1)
        s.rect(0, 0, W, FLOOR, base)
        grout = shade(base, -0.4)
        # Tiles with their own tone, a glazed top-left glint and grout lines.
        for y in range(34, FLOOR, 12):
            off = 0 if (y // 12) % 2 else 6
            for x in range(off - 12, W, 12):
                t = shade(base, r.uniform(-0.06, 0.06))
                s.rect(x, y, 12, 12, t)
                s.fhline(x + 1, x + 11, y + 1, shade(t, 0.22))
                s.fvline(x + 1, y + 1, y + 11, shade(t, 0.12))
                s.fhline(x + 1, x + 12, y + 11.5, shade(t, -0.2))
                if r.random() < 0.08:
                    s.px(x + 2, y + 2, shade(t, 0.45), t=f)
        for y in range(34, FLOOR, 12):
            s.hline(0, W, y, grout, t=f * 1.5 if s.res > 2 else 1)
        for y in range(34, FLOOR, 12):
            off = 0 if (y // 12) % 2 else 6
            for x in range(off, W, 12):
                s.vline(x, y, y + 11, grout, t=f * 1.5 if s.res > 2 else 1)
        s.noise(0, 34, W, FLOOR - 34, 0.06, seed=5, scale=1)
        # A few cracked or missing tiles.
        for k in range(14 if g < 2 else 4):
            x = r.randrange(0, W // 12) * 12
            y = 34 + r.randrange(0, (FLOOR - 34) // 12) * 12
            if g < 2 and r.random() < 0.5:
                s.rect(x + 1, y + 1, 11, 11, shade(base, -0.5))  # missing: bare render
                s.noise(x + 1, y + 1, 11, 11, 0.2, seed=x + y, scale=1)
            else:
                cx, cy = x + r.uniform(2, 10), y + 1
                while cy < y + 11:
                    nx, ny = cx + r.uniform(-1.5, 1.5), cy + r.uniform(0.6, 1.6)
                    s.fline(cx, cy, nx, ny, grout)
                    cx, cy = nx, ny
    elif kind == "panel":
        base = C("steel2")
        s.rect(0, 0, W, FLOOR, shade(base, -0.3))
        for x in range(0, W, 40):
            s.panel(x + 1, 36, 38, FLOOR - 37, base, seams=True, rivets=True, vent=(x // 40) % 4 == 1)
            # Stencilled panel numbers and hazard corner tape.
            s.ftext(x + 5, 40, "%02d" % (x // 40 + 1), shade(base, -0.4), "albedo")
            if (x // 40) % 3 == 0:
                for k in range(0, 8, 2):
                    s.line(x + 2 + k, FLOOR - 3, x + 4 + k, FLOOR - 6, C("yellow", -0.45), t=f * 2)
    elif kind == "clean":
        base = shade(C("steel4"), 0.12)
        s.vgrad(0, 0, W, FLOOR, shade(base, -0.1), shade(base, 0.08))
        for x in range(0, W, 60):
            s.vline(x, 34, FLOOR - 1, shade(base, -0.2))
            s.fvline(x + 1, 34, FLOOR - 1, shade(base, 0.2))
            s.fvline(x + 1.5, 34, FLOOR - 1, shade(base, 0.08))
            for yy in (60, 120, 200):
                s.rivet(x + 4, yy, base)
        for x in range(30, W, 60):  # recessed light slots
            s.glow(x, 100, f, 40, C("ice"), 0.25)
        s.hline(0, W, 150, shade(base, -0.25))
        s.rect(0, 151, W, 4, shade(C("blue"), -0.55))
        s.glow(0, 152, W, 1, C("blue"), 0.35)
        s.glow(0, 152, W, f, C("ice"), 0.4)
    elif kind == "hex":
        base = shade(C("steel2"), 0.05)
        s.rect(0, 0, W, FLOOR, shade(base, -0.25))
        for row, y in enumerate(range(34, FLOOR, 14)):
            off = 0 if row % 2 == 0 else 12
            for x in range(-24 + off, W, 24):
                t = shade(base, r.uniform(-0.05, 0.05))
                s.poly([(x + 6, y), (x + 18, y), (x + 23, y + 7), (x + 18, y + 13), (x + 6, y + 13), (x + 1, y + 7)], t)
                s.poly([(x + 7, y + 1.5), (x + 17, y + 1.5), (x + 21, y + 7), (x + 17, y + 11.5), (x + 7, y + 11.5), (x + 3, y + 7)], shade(t, 0.06))
                s.fhline(x + 7, x + 17, y + 1, shade(t, 0.3))
                s.fline(x + 1, y + 7, x + 6, y, shade(t, 0.2))
                s.fhline(x + 6, x + 18, y + 12.5, shade(t, -0.3))
                if r.random() < 0.06:
                    s.glow(x + 11, y + 6, 2, 1, C("violet"), 0.5)
        s.noise(0, 34, W, FLOOR - 34, 0.04, seed=6)
    # Skirting and a cable tray along the base of the wall.
    s.rect(0, FLOOR - 8, W, 8, shade(C("steel1"), -0.1))
    s.hline(0, W, FLOOR - 8, C("steel3"))
    s.fhline(0, W, FLOOR - 7, C("steel4"))
    s.fhline(0, W, FLOOR - 1, C("void"))
    for x in range(0, W, 6):
        s.px(x, FLOOR - 5, C("steel3", -0.2))
        s.fpx(x * s.res, (FLOOR - 5) * s.res, C("steel4"))


def ceiling(s: Scene, spec):
    f = 1.0 / s.res
    s.vgrad(0, 0, W, 34, C("void"), C("steel0"))
    s.hline(0, W, 33, C("steel2"))
    s.fhline(0, W, 33, C("steel4"))
    # Beams with flanges and bolt rows.
    for x in range(30, W, 120):
        s.box(x, 0, 14, 36, C("steel1"), 0.15, True, 0.3)
        s.vline(x + 3, 2, 34, C("steel3"))
        s.fvline(x + 3, 2, 34, C("steel4"))
        s.fvline(x + 11, 2, 34, C("void"))
        for by in range(4, 34, 6):
            s.rivet(x + 6, by, C("steel2"))
            s.rivet(x + 9, by + 3, C("steel2"))
    # Pipe runs with joints, valves and a drip.
    for py, col, th in ((8, "steel3", 5), (16, "rust2" if spec["grime"] < 2 else "steel4", 4), (24, "steel2", 3)):
        c = C(col)
        s.rect(0, py, W, th, c)
        s.hline(0, W, py, shade(c, 0.3))
        s.fhline(0, W, py + 1, shade(c, 0.55))
        s.fhline(0, W, py + th * 0.6, shade(c, -0.12))
        s.hline(0, W, py + th - 1, shade(c, -0.4))
        for x in range(40, W, 90):
            s.box(x, py - 1, 5, th + 2, shade(c, 0.1), 0.2, True, 0.3)
            s.fvline(x + 1, py - 1, py + th + 1, shade(c, 0.45))
            s.rivet(x + 2, py + th // 2, shade(c, 0.1))
        if spec["grime"] < 2:
            for k in range(6):
                rx = s.rng.uniform(0, W)
                s.darken(rx, py, s.rng.uniform(4, 14), th, 0.7)
    s.box(212, 13, 7, 8, C("red", -0.45), 0.2)
    s.disc(215.5, 11, 3, C("red", -0.35))
    s.fhline(213, 218, 9, C("red", 0.05))
    s.anchor("drip", 218, 28, 1, 40, "cyan")
    s.anchor("steam", 405, 12, 1, 1, "white")
    # Cable bundles sagging between beams (the reference's tangle).
    cols = [C("steel0"), C("void"), C("steel1"), shade(C("rust1"), -0.2)]
    for k in range(13):
        x0 = s.rng.randrange(0, W - 120)
        s.cable(x0, 30 + s.rng.randrange(0, 4), x0 + s.rng.randrange(60, 160), 30 + s.rng.randrange(0, 4),
                s.rng.randrange(6, 22), cols[k % len(cols)], thick=s.rng.choice((0.5, 1, 1, 1.5)), hl=C("steel3"))
    # Zip-tie bunches holding the cables to the beams.
    for x in range(36, W, 120):
        s.rect(x + 2, 30, 10, 1, C("steel4"))


def tube_light(s: Scene, x, y, w, color="fluoro", flicker=False, strength=1.0):
    f = 1.0 / s.res
    s.box(x - 2, y - 3, w + 4, 3, C("steel1"), 0.2)
    s.fhline(x - 2, x + w + 2, y - 3, C("steel4"))
    s.vline(x + 2, y - 10, y - 3, C("steel2"))
    s.vline(x + w - 3, y - 10, y - 3, C("steel2"))
    s.fvline(x + 2, y - 10, y - 3, C("steel4"))
    s.fvline(x + w - 3, y - 10, y - 3, C("steel4"))
    s.glow(x, y, w, 2, C(color), 0.95 * strength)
    s.glow(x + 1, y + 0.5, w - 2, f, C("white"), 0.9 * strength)  # hot core
    s.rect(x - 1, y, 1, 2, C("steel3"))  # end caps
    s.rect(x + w, y, 1, 2, C("steel3"))
    s.light(x + w / 2, y + 6, C(color) * 0.9, 210, 0.85 * strength, cone=(0, 1, 75))
    if flicker:
        s.anchor("led", x + w // 2, y, 1, 1, "white", rate=0.3)


def hanging_lamp(s: Scene, x, y, color="tungsten", r=150, i=1.0):
    s.vline(x, 34, y - 4, C("void"), t=0.5)
    s.poly([(x - 7, y), (x + 7, y), (x + 4, y - 5), (x - 4, y - 5)], C("steel2"))
    s.poly([(x - 4, y - 5), (x + 4, y - 5), (x + 3, y - 6), (x - 3, y - 6)], C("steel3"))
    s.fline(x - 7, y, x - 4, y - 5, C("steel4"))
    s.hline(x - 7, x + 7, y, C("steel4"))
    s.glow(x - 3, y + 1, 7, 2, C(color), 1.0)
    s.glow(x - 1, y + 1, 3, 1, C("white"), 0.9)
    s.light(x, y + 4, C(color), r, i, cone=(0, 1, 62))


def floor_(s: Scene, spec):
    kind = spec["floor"]
    f = 1.0 / s.res
    top, bottom = FLOOR, H
    if kind == "concrete":
        base = C("concrete1")
        s.vgrad(0, top, W, bottom - top, shade(base, -0.2), shade(base, 0.12))
        s.noise(0, top, W, bottom - top, 0.12, seed=11, scale=2)
        s.noise(0, top, W, bottom - top, 0.08, seed=12, scale=1)
        gloss = 0.5
    elif kind == "tile":
        base = C("tile0")
        s.vgrad(0, top, W, bottom - top, shade(base, -0.15), shade(base, 0.15))
        s.noise(0, top, W, bottom - top, 0.05, seed=12, scale=1)
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
        s.fhline(0, W, ry + 1, shade(base, 0.1))
    cx = W / 2
    for k in range(-14, 15):
        x_far = cx + k * 30
        x_near = cx + k * 30 * 1.9
        s.line(x_far, top, x_near, bottom, shade(base, -0.32))
        s.fline(x_far + 1.5, top, x_near + 1.5, bottom, shade(base, 0.06))
    if kind == "metal":
        # Diamond tread plate: tiny raised bars catching the light.
        for ry, ry2 in zip(rows, rows[1:] + [bottom]):
            step = max(2.0, (ry2 - ry) / 3)
            yy = ry + 1.5
            while yy < ry2 - 1:
                for x in range(4, W, 7):
                    xo = x + (3.5 if int((yy - ry) / step) % 2 else 0)
                    s.fline(xo, yy + 0.5, xo + 1.5, yy, shade(base, 0.3))
                yy += step
    s.set_gloss(0, top, W, bottom - top, gloss)
    s.floor_y = top
    # Puddles: high gloss patches with a dark wet rim.
    for k in range(5 if spec["grime"] < 2 else 2):
        px_, py_ = s.rng.randrange(40, W - 80), s.rng.randrange(top + 10, bottom - 8)
        pw = s.rng.randrange(30, 80)
        for yy in range(py_, py_ + 6):
            inset = abs(yy - py_ - 3) * 4
            s.set_gloss(px_ + inset, yy, pw - 2 * inset, 1, 0.95)
            s.rect(px_ + inset, yy, pw - 2 * inset, 1, shade(base, -0.3))
        s.fhline(px_ + 12, px_ + pw - 12, py_, shade(base, -0.5))


def door(s: Scene, spec):
    x, y, w, h = DOOR
    f = 1.0 / s.res
    s.box(x - 4, y - 6, w + 8, h + 6, C("steel1"), 0.15)
    s.fvline(x - 3, y - 5, y + h, C("steel3"))
    if spec["grime"] >= 2:
        # Sliding door with a lit status strip, window slits and seals.
        s.box(x, y, w, h, C("steel3"), 0.2)
        s.vline(x + w // 2, y, y + h, C("steel1"))
        s.fvline(x + w // 2 + 1, y, y + h, C("steel4"))
        s.glow(x + 4, y + 8, w - 8, 2, C(spec["accent"][0]), 0.8)
        s.glow(x + 4, y + 8.5, w - 8, f, C("white"), 0.5)
        for side in (x + 6, x + w // 2 + 6):
            s.rect(side, y + 20, w // 2 - 12, 26, shade(C("teal"), -0.7))
            s.glass(side, y + 20, w // 2 - 12, 26, 0.06)
            s.fhline(side, side + w // 2 - 12, y + 46, C("steel5"))
            s.label(side + 2, y + 56, 10, 4, C("yellow", -0.25))
        s.glow(x + w + 6, y + 50, 4, 8, C("green"), 0.9)
        s.anchor("led", x + w + 7, y + 52, 2, 1, "green", rate=0.5)
    else:
        # Roll-up shutter half open: slats, a glow of the street below.
        slats = shade(C("steel2"), -0.05)
        for k in range(0, int(h * 0.6), 4):
            s.rect(x, y + k, w, 3, slats)
            s.hline(x, x + w - 1, y + k, shade(slats, 0.25))
            s.fhline(x, x + w, y + k + 1.5, shade(slats, 0.08))
            s.fhline(x, x + w, y + k + 3, C("void"))
        for k in range(14):  # dents and rust on the slats
            dx, dy = x + s.rng.uniform(2, w - 6), y + s.rng.uniform(0, h * 0.6 - 3)
            s.darken(dx, dy, s.rng.uniform(2, 6), 1.5, 0.7)
        s.rect(x, y + int(h * 0.6), w, h - int(h * 0.6), C("void"))
        s.glow(x + 2, y + h - 10, w - 4, 10, C(spec["accent"][0]), 0.25)
        s.light(x + w / 2, y + h - 4, C(spec["accent"][0]), 90, 0.5)
        s.box(x - 2, y + int(h * 0.6) - 2, w + 4, 3, C("steel3"), 0.2)
        s.rect(x + w // 2 - 4, y + int(h * 0.6) - 1, 8, 2, C("steel5"))  # handle
    # Door sign / buzzer.
    s.box(x + w + 4, y + 20, 8, 10, C("steel1"), 0.2)
    s.disc(x + w + 8, y + 27, 1.5, C("steel3"))
    s.gpx(x + w + 7, y + 23, C("red"), 1.0)
    s.anchor("led", x + w + 7, y + 23, 1, 1, "red", rate=1.3)


def window_to_street(s: Scene, x, y, w, h, spec):
    """A barred window onto a neon alley (the first reference)."""
    f = 1.0 / s.res
    s.box(x - 3, y - 3, w + 6, h + 6, C("steel1"), 0.2)
    s.vgrad(x, y, w, h, C("void"), shade(C("violet"), -0.75))
    # Far buildings with lit windows, a nearer row darker and larger.
    r = s.rng
    for layer, (step, dk) in enumerate(((6, 0.0), (9, -0.25))):
        for bx in range(x, x + w, step):
            bh = r.randrange(h // 4, h) if layer == 0 else r.randrange(h // 3, h // 2 + 6)
            s.rect(bx, y + h - bh, step - 1, bh, shade(C("steel0"), r.uniform(-0.2, 0.15) + dk))
            for wy in range(y + h - bh + 2, y + h - 2, 2 if layer == 0 else 3):
                for wx in range(bx + 1, bx + step - 2, 2):
                    if r.random() < 0.25:
                        s.gpx(wx, wy, C(r.choice(["amber", "tungsten", "cyan", "pink"])), 0.55, t=f if layer == 0 else 1)
    # Neon signs across the street.
    for k, col in enumerate(spec["accent"]):
        sx, sy = x + 6 + k * (w // len(spec["accent"])), y + 6 + (k % 2) * 12
        s.glow(sx, sy, min(16, w // 3), 6, shade(C(col), -0.5), 0.9)
        s.text(sx + 1, sy + 0.5, ["NOODL", "BAR", "24H", "HOTEL"][k % 4][:4], C(col), "emissive", neon=True)
    s.light(x + w / 2, y + h / 2, C(spec["accent"][0]) * 0.8, 120, 0.6)
    # Rain streaks, droplets on the glass, and bars.
    for k in range(40):
        rx, ry = x + r.uniform(0, w), y + r.uniform(0, h - 6)
        s.fline(rx, ry, rx - 0.5, ry + r.uniform(2, 5), shade(C("ice"), -0.4), "emissive")
    for k in range(24):
        s.gpx(x + r.uniform(0, w), y + r.uniform(0, h), C("ice"), 0.35, t=f)
    s.glass(x, y, w, h, 0.05)
    for bx in range(x + 6, x + w, 10):
        s.rect(bx, y, 2, h, C("steel2"))
        s.vline(bx, y, y + h, C("steel4"), t=f)
        s.fvline(bx + 2 - f, y, y + h, C("void"))
    s.fhline(x - 3, x + w + 3, y + h + 2, C("steel4"))  # sill highlight


def catwalk(s: Scene):
    """Upper walkway with railing across the back (second reference)."""
    y = 46
    f = 1.0 / s.res
    s.rect(0, y, W, 5, C("steel2"))
    s.hline(0, W, y, C("steel4"))
    s.fhline(0, W, y, C("steel5"))
    s.hline(0, W, y + 5, C("void"))
    for x in range(0, W, 3):  # grating
        s.px(x, y + 2, C("steel1"))
        s.fpx(x * s.res + 1, (y + 3) * s.res, C("steel3"))
    # Railing with a lit top rail.
    s.hline(0, W, y - 12, C("steel4"))
    s.fhline(0, W, y - 12, C("steel5"))
    s.hline(0, W, y - 6, C("steel3"))
    for x in range(8, W, 22):
        s.vline(x, y - 12, y, C("steel3"))
        s.fvline(x, y - 12, y, C("steel4"))
        s.rect(x - 0.5, y - 1, 2, 1, C("steel2"))
    # Support struts down the wall.
    for x in range(60, W, 180):
        s.line(x, y + 5, x + 14, y + 22, C("steel2"), t=1.5)
        s.fline(x + 0.5, y + 5, x + 14.5, y + 22, C("steel4"))
        s.rivet(x + 14, y + 22, C("steel2"))
    # Warning lights on the rail.
    for x in range(100, W, 200):
        s.rect(x - 1, y - 13, 3, 1, C("steel1"))
        s.gpx(x, y - 14, C("amber"), 1.0)
        s.anchor("led", x, y - 13, 1, 1, "amber", rate=0.9)


# =============================================================================
# Furniture (the clickable layout)
# =============================================================================

def screen(s: Scene, x, y, w, h, color="cyan", kind="ui"):
    """A lit screen with something on it: UI rows, a graph, a face, text.
    Contents are drawn at the hi-res grid (half-pixel strokes, micro text),
    with scanlines and a glass glare, inside a bezel with screws."""
    col = C(color)
    s.bezel(x - 2, y - 2, w + 4, h + 4, C("steel0"))
    s.glow(x, y, w, h, shade(col, -0.84), 1.0)
    r = s.rng
    f = 1.0 / s.res
    if kind == "ui":
        s.glow(x + 1, y + 1, w - 2, 1.5, col, 0.45)  # title bar
        s.ftext(x + 1.5, y + 1.5, r.choice(["SYS", "NET", "MED", "IO"]), shade(col, -0.75), "emissive")
        yy = y + 4
        while yy < y + h - 1:
            ln = r.uniform(w * 0.25, w - 3)
            s.glow(x + 2, yy, ln, f, col, r.uniform(0.4, 0.85))
            if r.random() < 0.3:
                s.glow(x + w - 4, yy, 2, f, C("white"), 0.6)
            yy += 1.5
    elif kind == "graph":
        for gx in range(int(x) + 4, int(x + w) - 1, 4):  # grid
            s.glow(gx, y + 1, f, h - 2, col, 0.18)
        s.glow(x + 1, y + h / 2, w - 2, f, col, 0.22)
        prev = y + h / 2
        for i in range(int((w - 2) * s.res)):
            xx = x + 1 + i * f
            ny = max(y + 1, min(y + h - 1.5, prev + r.choice((-f, 0, 0, f))))
            if i % 9 == 4:
                ny = max(y + 1, ny - h * 0.3)
            s.gpx(xx, ny, col, 0.95, t=f)
            s.gpx(xx, ny + f, col, 0.45, t=f)
            prev = ny if i % 9 != 4 else y + h / 2
        s.glow(x + 1, y + h - 2, w - 2, f, col, 0.35)
    elif kind == "bars":
        xx = x + 2
        while xx < x + w - 2:
            bh = r.uniform(2, h - 3)
            s.glow(xx, y + h - 1 - bh, 1.5, bh, col, 0.7)
            s.glow(xx, y + h - 1 - bh, 1.5, f, C("white"), 0.7)
            xx += 2.5
    elif kind == "face":
        cx, cy = x + w / 2, y + h / 2
        for i in range(int((w - 4) * s.res)):
            for j in range(int((h - 3) * s.res)):
                xx, yy = x + 2 + i * f, y + 2 + j * f
                d = ((xx - cx) / (w * 0.28)) ** 2 + ((yy - cy) / (h * 0.38)) ** 2
                if d < 1 and (j % 2 == 0):
                    s.gpx(xx, yy, col, 0.4 + 0.4 * (1 - d), t=f)
        s.gpx(cx - 2, cy - 1, C("white"), 0.9)
        s.gpx(cx + 1.5, cy - 1, C("white"), 0.9)
        s.ftext(x + 1.5, y + h - 3.5, "ID", col, "emissive")
    elif kind == "text":
        yy = y + 1.5
        while yy < y + h - 3:
            s.ftext(x + 1.5, yy, r.choice(["SYS OK", "PULSE 72", "LOAD 23%", "SCAN 04", "ID ????", "LINK UP",
                                            "BP 120/80", "O2 98", "NEURAL OK", "CHROME 3"]), col)
            yy += 3.5
    # Scanlines and glare.
    for k in range(int(h * s.res)):
        if k % 2:
            s.scale_buf(x, y + k * f, w, f, 0.72)
    s.glass(x, y, w, h, 0.08)
    s.light(x + w / 2, y + h / 2, col * 0.8, max(w, h) * 2.2, 0.45)
    s.anchor("monitor", x, y, w, h, color)


def console(s: Scene, x, y, w, h, spec, screens=2):
    """Desk console with screens, bevelled key caps, sliders, a keyboard."""
    body = C("steel2")
    f = 1.0 / s.res
    s.box(x, y + h // 2, w, h - h // 2, body, 0.15)
    s.panel(x + 2, y + h // 2 + 3, w - 4, h - h // 2 - 5, shade(body, -0.1), seams=False, rivets=True)
    # Key caps: a lit top edge, a dark lip, and some backlit ones.
    for by in range(y + h // 2 + 6, y + h - 6, 4):
        for bx in range(x + 6, x + w - 6, 4):
            c = s.rng.choice(["steel3", "steel4", "red", "amber", "green", "cyan", "steel3", "steel3"])
            if c in ("red", "amber", "green", "cyan"):
                s.glow(bx, by, 2.5, 2, C(c), 0.8)
                s.glow(bx, by, 2.5, f, C("white"), 0.5)
            else:
                s.rect(bx, by, 2.5, 2.5, C(c))
                s.fhline(bx, bx + 2.5, by, shade(C(c), 0.4))
                s.fhline(bx, bx + 2.5, by + 2.5 - f, shade(C(c), -0.5))
    # Sliders down the right edge.
    for k in range(3):
        sx = x + w - 5 + k * 0 - 0
        sy = y + h // 2 + 5 + k * 6
        s.fhline(sx - 3, sx + 2, sy + 1, C("void"))
        s.rect(sx - 3 + (k * 1.5), sy, 1.5, 2, C("steel5"))
    s.anchor("led", x + 8, y + h // 2 + 6, 3, 1, "green", rate=0.7)
    # Screens on arms.
    sw = (w - 6) // screens - 4
    kinds = ["graph", "ui", "bars", "face", "text"]
    for k in range(screens):
        sx = x + 4 + k * (sw + 4)
        s.vline(sx + sw // 2, y + h // 2 - 4, y + h // 2, C("steel3"))
        s.fvline(sx + sw // 2, y + h // 2 - 4, y + h // 2, C("steel5"))
        screen(s, sx, y + 2, sw, h // 2 - 8, spec["accent"][k % len(spec["accent"])] if k else "cyan", kinds[(k + len(spec["id"])) % len(kinds)])
    # A keyboard on the desk lip and a coffee cup.
    kx, ky = x + 4, y + h // 2 - 2
    s.rect(kx, ky, w * 0.45, 2, C("steel1"))
    for i in range(int(w * 0.45 * s.res) // 3):
        s.fpx(int(kx * s.res) + i * 3 + 1, int(ky * s.res) + 1, shade(C("steel4"), 0.1))
    cx = x + w - 9
    s.rect(cx, ky - 2.5, 3, 3.5, C("bone", -0.3))
    s.fvline(cx + 0.5, ky - 2, ky + 1, C("bone"))
    s.anchor("steam", cx + 1, ky - 3, 1, 1, "white") if spec["grime"] < 2 else None


def op_table(s: Scene, spec):
    x, y, w, h = TABLE
    f = 1.0 / s.res
    # Pedestal and hydraulics: a chrome ram with a fine highlight.
    s.box(x + w // 2 - 10, y + 40, 20, h - 40, C("steel2"), 0.2)
    s.rect(x + w // 2 - 4, y + 40, 8, h - 46, C("steel4"))
    s.fvline(x + w // 2 - 3, y + 40, y + h - 6, C("steel5"))
    s.fvline(x + w // 2 - 2.5, y + 40, y + h - 6, C("white"))
    s.fvline(x + w // 2 + 3.5, y + 40, y + h - 6, C("steel1"))
    s.box(x + w // 2 - 22, FLOOR - 6, 44, 6, C("steel1"), 0.2)
    for k in range(3):
        s.hline(x + w // 2 - 8, x + w // 2 + 7, y + 48 + k * 8, C("steel4"))
        s.fhline(x + w // 2 - 8, x + w // 2 + 8, y + 49 + k * 8, C("steel1"))
    for bx in (x + w // 2 - 19, x + w // 2 + 17):  # floor bolts
        s.rivet(bx, FLOOR - 4, C("steel3"))
    # Table top with padding, stitching and straps.
    s.box(x + 4, y + 26, w - 8, 14, C("steel3"), 0.25)
    s.fhline(x + 6, x + w - 6, y + 33, C("steel1"))
    for k in range(6):
        s.rect(x + 12 + k * 18, y + 35, 6, 1.5, C("steel1"))
    pad = C("teal", -0.55) if spec["grime"] >= 2 else C("rust1", -0.1)
    s.box(x + 8, y + 20, w - 16, 8, pad, 0.2)
    s.noise(x + 8, y + 20, w - 16, 8, 0.08, seed=21)
    for i in range(int((w - 20) * s.res) // 3):  # stitching
        s.fpx(int((x + 10) * s.res) + i * 3, int((y + 21) * s.res), shade(pad, 0.35))
        s.fpx(int((x + 10) * s.res) + i * 3, int((y + 26.5) * s.res), shade(pad, -0.3))
    s.fhline(x + 10, x + w - 10, y + 24, shade(pad, -0.25))  # cushion seam
    for sx in (x + 30, x + w - 40):
        s.rect(sx, y + 19, 6, 10, C("void"))
        s.rect(sx + 1, y + 22, 4, 3, C("steel4"))  # buckle
        s.fhline(sx + 1, sx + 5, y + 22, C("steel5"))
        s.rect(sx + 2, y + 23, 2, 1, C("void"))
    if spec["grime"] < 2:
        for k in range(14):
            bx, by = x + 20 + s.rng.uniform(0, w - 40), y + 21 + s.rng.uniform(0, 6)
            s.px(bx, by, C("blood"), t=s.rng.choice((0.5, 0.5, 1.0)))
    # Surgical lamp on an arm from the ceiling: the brightest thing in the room.
    lx, ly = x + w // 2, y - 46
    s.line(lx - 30, 34, lx - 6, ly, C("steel3"), t=1.5)
    s.fline(lx - 29.5, 34, lx - 5.5, ly, C("steel5"))
    s.disc(lx - 6, ly - 1, 2, C("steel2"))
    s.poly([(lx - 22, ly), (lx + 22, ly), (lx + 14, ly - 9), (lx - 14, ly - 9)], C("steel3"))
    s.poly([(lx - 14, ly - 9), (lx + 14, ly - 9), (lx + 12, ly - 7.5), (lx - 12, ly - 7.5)], C("steel4"))
    s.fline(lx - 22, ly, lx - 14, ly - 9, C("steel5"))
    s.hline(lx - 22, lx + 22, ly, C("steel5"))
    for k in range(5):
        s.glow(lx - 16 + k * 7, ly + 1, 5, 2, C("white"), 1.0)
        s.glow(lx - 16 + k * 7, ly + 1, 5, f, C("ice"), 1.0)
        s.rect(lx - 16.5 + k * 7, ly + 1, f, 2, C("steel1"))
    s.light(lx, ly + 6, C("white") * 1.05, 150, 1.25, cone=(0, 1, 38), falloff=1.2)
    # Side monitor on a pole: vitals.
    mx, my = x + w - 8, y - 18
    s.vline(mx + 8, my + 14, FLOOR - 1, C("steel3"))
    s.fvline(mx + 8, my + 14, FLOOR - 1, C("steel5"))
    s.box(mx + 2, FLOOR - 4, 14, 4, C("steel1"))
    for wx in (mx + 3, mx + 14):
        s.disc(wx, FLOOR - 0.5, 1, C("void"))
    screen(s, mx, my, 18, 14, "green", "graph")
    s.anchor("ecg", mx + 1, my + 2, 16, 10, "green")
    # Instrument cable from the monitor to the table.
    s.cable(mx + 4, my + 16, x + w - 14, y + 26, 10, C("void"), 1, hl=C("steel3"))


def bench(s: Scene, spec):
    x, y, w, h = BENCH
    f = 1.0 / s.res
    top = y + 40
    tcol = C("steel3") if spec["grime"] >= 1 else C("rust2")
    s.box(x, top, w, 6, tcol, 0.25)
    s.fhline(x + 1, x + w - 1, top + 3, shade(tcol, -0.3))
    for lx in (x + 4, x + w - 8):
        s.box(lx, top + 6, 4, FLOOR - top - 6, C("steel1"), 0.2)
        s.fvline(lx + 1, top + 7, FLOOR - 1, C("steel3"))
    s.box(x + 10, top + 30, w - 20, 4, C("steel2"))  # lower shelf
    # Pegboard: holes with a lit lower lip, tools with highlights and shadows.
    board = shade(C("steel1"), -0.1)
    s.box(x + 6, y - 6, w - 12, 44, board, 0.15)
    for py in range(y - 2, y + 36, 5):
        for px_ in range(x + 10, x + w - 10, 5):
            s.px(px_, py, C("void"))
            s.fpx(px_ * s.res, py * s.res + s.res, shade(board, 0.3))
    for k, tx in enumerate(range(x + 14, x + w - 14, 12)):
        tool = k % 4
        if tool == 0:  # screwdriver
            s.darken(tx + 1, y + 3, 1, 24, 0.6)
            s.vline(tx, y + 2, y + 20, C("steel5"))
            s.fvline(tx, y + 2, y + 20, C("white"))
            s.rect(tx - 1, y + 20, 3, 6, C("red", -0.3))
            s.fvline(tx - 0.5, y + 20.5, y + 25.5, C("red", 0.1))
            s.fhline(tx - 1, tx + 2, y + 22, C("red", -0.6))
        elif tool == 1:  # scalpel
            s.line(tx - 3, y + 4, tx + 3, y + 18, C("steel4"))
            s.fline(tx - 3, y + 4, tx - 1, y + 9, C("white"))
        elif tool == 2:  # forceps / clamp
            s.rect(tx - 2, y + 4, 5, 10, C("amber", -0.4))
            s.fhline(tx - 2, tx + 3, y + 4, C("amber", -0.1))
            s.rect(tx - 1, y + 6, 3, 2, C("void"))
            s.vline(tx, y + 14, y + 22, C("steel4"))
            s.fvline(tx + 0.5, y + 14, y + 22, C("steel5"))
        else:  # sutures on a hook
            for k2 in range(3):
                s.px(tx + k2 - 1, y + 6 + k2 * 4, C("steel5"))
            s.fline(tx - 1, y + 6, tx + 1, y + 15, C("bone"))
    # Clutter on the bench: crates, a lamp, implants in trays, vials.
    s.box(x + 10, top - 10, 22, 10, C("amber", -0.62), 0.2)
    s.text(x + 12, top - 8, "MED", C("amber", -0.3), "albedo")
    s.label(x + 25, top - 8, 5, 3, C("bone", -0.2))
    s.box(x + 36, top - 7, 14, 7, C("steel2"), 0.2)
    s.fhline(x + 37, x + 49, top - 4, C("steel0"))
    for k in range(3):
        s.rect(x + 56 + k * 7, top - 5, 5, 5, C("steel4"))
        s.fhline(x + 56 + k * 7, x + 61 + k * 7, top - 5, C("steel5"))
        s.gpx(x + 58 + k * 7, top - 3, C(["cyan", "pink", "green"][k]), 0.9)
    for k in range(4):
        s.bottle(x + 80 + k * 4, top - 7 - (k % 2), 7 + (k % 2), shade(C(["teal", "amber", "pink", "ice"][k]), -0.35), w=2.5)
    s.anchor("led", x + 58, top - 3, 1, 1, "cyan", rate=0.6)
    hanging_lamp(s, x + w - 24, top - 26, "tungsten", 70, 0.6)
    # Crates under the bench.
    s.box(x + 14, FLOOR - 18, 26, 18, C("steel2"), 0.2)
    s.text(x + 17, FLOOR - 14, "BIO", C("yellow", -0.25), "albedo")
    s.fhline(x + 15, x + 39, FLOOR - 7, C("steel1"))
    s.label(x + 30, FLOOR - 15, 8, 5, C("bone", -0.25))
    s.box(x + 44, FLOOR - 12, 20, 12, C("rust1"), 0.2)
    for k in range(3):
        s.fvline(x + 48 + k * 6, FLOOR - 11, FLOOR - 1, shade(C("rust1"), -0.35))


def cabinet(s: Scene, spec):
    x, y, w, h = CABINET
    f = 1.0 / s.res
    s.box(x, y, w, h, C("steel3"), 0.2)
    s.vline(x + w // 2, y + 2, y + h - 2, C("steel1"))
    s.fvline(x + w // 2 + 1, y + 2, y + h - 2, C("steel4"))
    # Glass upper doors with stock behind: bottles, boxes, vials with caps.
    for gx in (x + 3, x + w // 2 + 2):
        gw = w // 2 - 5
        s.rect(gx, y + 4, gw, 70, shade(C("teal"), -0.78))
        for sy in range(y + 18, y + 72, 16):
            s.hline(gx, gx + gw - 1, sy, C("steel4"))
            s.fhline(gx, gx + gw, sy, C("steel5"))
            k = 0
            while k < gw - 3:
                kind = s.rng.random()
                c = shade(C(s.rng.choice(["white", "bone", "amber", "pink", "cyan", "teal"])), -0.35)
                if kind < 0.5:
                    bh = s.rng.choice((6, 7, 8))
                    s.bottle(gx + 1 + k, sy - bh, bh, c, w=2.5, cap=shade(C(s.rng.choice(["white", "red", "steel4"])), -0.2))
                    k += 3.5
                else:
                    bw = s.rng.choice((4, 5))
                    s.box(gx + 1 + k, sy - 5, bw, 5, c, 0.2)
                    s.fhline(gx + 1.5 + k, gx + k + bw, sy - 3, shade(c, -0.4))
                    k += bw + 1
        s.glow(gx, y + 4, f, 70, C("ice"), 0.35)
        s.glass(gx, y + 4, gw, 70, 0.05)
        s.rect(gx + gw - 2, y + 36, 1, 6, C("steel5"))  # handle
    s.glow(x + 4, y + 2, w - 8, 1, C("cyan"), 0.6)
    s.glow(x + 4, y + 2, w - 8, f, C("white"), 0.5)
    s.light(x + w / 2, y + 30, C("cyan") * 0.5, 70, 0.4)
    # Drawers below: handles, label slots.
    for dy in range(y + 82, y + h - 6, 16):
        s.box(x + 3, dy, w - 6, 13, C("steel2"), 0.2)
        s.hline(x + w // 2 - 5, x + w // 2 + 4, dy + 6, C("steel5"))
        s.fhline(x + w // 2 - 5, x + w // 2 + 5, dy + 7, C("void"))
        s.label(x + 6, dy + 3, 7, 3, C("bone", -0.3))
    s.text(x + 4, y + h - 12, "SUPPLY", C("yellow", -0.2), "albedo")


def rack(s: Scene, spec):
    x, y, w, h = RACK
    f = 1.0 / s.res
    s.box(x, y, w, h, C("steel1"), 0.2)
    for uy in range(y + 4, y + h - 6, 7):
        s.box(x + 3, uy, w - 6, 6, C("steel2"), 0.15)
        for k in range(4):
            if s.rng.random() < 0.7:
                col = s.rng.choice(["green", "green", "cyan", "amber", "red"])
                s.gpx(x + 6 + k * 3, uy + 2, C(col), 0.95, t=1.5)
                s.gpx(x + 6 + k * 3, uy + 2, C("white"), 0.6, t=f)
        s.glow(x + w - 14, uy + 2, 8, 1, C("cyan"), 0.35)
        for vx in range(int((x + w - 14) * s.res), int((x + w - 6) * s.res), 2):  # activity ticks
            if s.rng.random() < 0.5:
                s.fpx(vx, (uy + 2) * s.res, C("ice"), "emissive")
        for k in range(5):  # vent slots
            s.fvline(x + 20 + k * 1.5, uy + 1.5, uy + 4.5, C("steel0"))
        s.rivet(x + 4, uy + 4, C("steel2"))
    for k in range(5):
        s.anchor("led", x + 6 + (k % 4) * 3, y + 6 + k * 21, 1, 1, ["green", "cyan", "amber", "green", "red"][k], rate=0.4 + k * 0.23)
    s.anchor("fan", x + w // 2 - 5, y + h - 16, 10, 10, "dark")
    # Cables spilling from the top into the ceiling.
    for k in range(4):
        s.cable(x + 6 + k * 8, y, x + 10 + k * 6, 34, 4, C("void"), 1, hl=C("steel2"))
    # Patch cables looping down the front.
    for k in range(3):
        cx = x + 8 + k * 9
        s.cable(cx, y + 10 + k * 14, cx + 6, y + 30 + k * 14, 6, shade(C(["cyan", "amber", "pink"][k]), -0.45), 1)


def wallspace(s: Scene, spec):
    """Where the Clinic Wall pins go: a cork/metal board."""
    x, y, w, h = WALLSPACE
    base = shade(C("rust1"), -0.2) if spec["grime"] < 2 else C("steel2")
    s.box(x - 4, y - 4, w + 8, h + 8, C("steel1"), 0.2)
    for cx, cy in ((x - 3, y - 3), (x + w + 2, y - 3), (x - 3, y + h + 2), (x + w + 2, y + h + 2)):
        s.rivet(cx, cy, C("steel3"))
    s.rect(x - 2, y - 2, w + 4, h + 4, base)
    s.noise(x - 2, y - 2, w + 4, h + 4, 0.16, seed=31, scale=1)
    s.noise(x - 2, y - 2, w + 4, h + 4, 0.06, seed=32, scale=2)
    s.fhline(x - 2, x + w + 2, y - 2, shade(base, -0.45))
    s.light(x + w / 2, y - 6, C("tungsten") * 0.6, 80, 0.45, cone=(0, 1, 70))


def diag(s: Scene, spec):
    x, y, w, h = DIAG
    console(s, x, y, w, h + 6, spec, screens=2)
    s.box(x - 2, y + h + 6, w + 4, FLOOR - (y + h + 6), C("steel1"), 0.2)
    s.anchor("led", x + w - 10, y + h + 12, 1, 1, "cyan", rate=0.8)


def waiting_area(s: Scene, spec):
    """Two moulded plastic chairs by the door."""
    for k, cx in enumerate((84, 102)):
        col = C(["amber", "teal", "pink", "steel3"][(k + len(spec["id"])) % 4], -0.45)
        s.box(cx, FLOOR - 16, 14, 4, col, 0.2)
        s.box(cx + 1, FLOOR - 30, 12, 14, col, 0.2)
        s.fvline(cx + 2.5, FLOOR - 29, FLOOR - 17, shade(col, 0.35))
        for i in range(3):
            s.rect(cx + 3 + i * 3, FLOOR - 26, 1.5, 6, shade(col, -0.3))  # back vents
        s.vline(cx + 2, FLOOR - 12, FLOOR - 1, C("steel3"))
        s.vline(cx + 11, FLOOR - 12, FLOOR - 1, C("steel3"))
        s.fvline(cx + 2, FLOOR - 12, FLOOR - 1, C("steel5"))
        s.fvline(cx + 11, FLOOR - 12, FLOOR - 1, C("steel5"))
        s.fhline(cx + 2, cx + 12, FLOOR - 6, C("steel3"))
        s.darken(cx, FLOOR - 1, 14, 1, 0.6)


def wall_dressing(s: Scene, spec):
    """Dense wall clutter like the references: pipes, conduit, boxes, an AC unit, cables."""
    g = spec["grime"]
    f = 1.0 / s.res
    pipe = C("rust2") if g < 2 else C("steel4")
    # Vertical pipes: a round shading profile, brackets with bolts, a valve.
    for px_, th in ((176, 6), (491, 4)):
        s.rect(px_, 34, th, FLOOR - 42, pipe)
        s.vline(px_ + 1, 34, FLOOR - 9, shade(pipe, 0.35))
        s.fvline(px_ + 1.5, 34, FLOOR - 9, shade(pipe, 0.6))
        s.fvline(px_ + th * 0.6, 34, FLOOR - 9, shade(pipe, -0.15))
        s.vline(px_ + th - 1, 34, FLOOR - 9, shade(pipe, -0.45))
        for by in range(60, FLOOR - 10, 46):
            s.box(px_ - 2, by, th + 4, 4, C("steel3"), 0.25)
            s.rivet(px_ - 1, by + 1, C("steel3"))
            s.rivet(px_ + th, by + 1, C("steel3"))
            s.darken(px_, by + 4, th, 2, 0.7)
    s.box(172, 168, 14, 6, C("red", -0.4), 0.25)
    s.vline(179, 160, 168, C("steel4"))
    s.hline(174, 184, 160, C("red", -0.3))
    s.fhline(174, 185, 160, C("red", 0.05))
    s.disc(179, 160.5, 1.2, C("steel4"))
    s.ftext(174, 170, "H2O", C("bone", -0.2), "albedo")
    # Conduit with junction boxes along the top of the wall.
    s.rect(0, 56, 84, 3, C("steel3"))
    s.hline(0, 84, 56, C("steel4"))
    s.fhline(0, 84, 56, C("steel5"))
    for cx in range(8, 84, 16):
        s.rect(cx, 55.5, 2, 4, C("steel2"))
    for jx in (20, 58):
        s.box(jx, 51, 14, 12, C("steel2"), 0.2, True, 0.4)
        s.gpx(jx + 10, 54, C("green" if jx == 20 else "amber"), 0.9)
        s.label(jx + 2, 57, 6, 3, C("bone", -0.35))
        for sx in (jx + 1, jx + 12):
            s.rivet(sx, 52, C("steel2"))
    # AC unit around the fan anchor: louvres, a fan grille, a nameplate.
    s.box(504, 36, 44, 28, C("steel3"), 0.2, True, 0.45)
    for yy in range(39, 61, 3):
        s.hline(507, 528, yy, C("steel1"))
        s.fhline(507, 528, yy + 1, C("steel4"))
    s.rect(530, 39, 15, 22, C("steel1"))
    for k in range(0, 15, 2):
        s.fvline(530 + k + 0.5, 39, 61, C("steel2"))
    s.label(508, 58, 10, 3, C("steel4"), text=None)
    s.anchor("drip", 540, 64, 1, 30, "cyan") if g < 2 else None
    # Breaker box with a hazard stripe, switches and a schematic sticker.
    bx, by = 466, 70
    s.box(bx, by, 22, 30, C("steel2"), 0.2, True, 0.4)
    for k in range(0, 22, 4):
        s.line(bx + k, by + 30, bx + k + 3, by + 26, C("yellow", -0.3))
    for k in range(3):
        s.rect(bx + 4 + k * 5, by + 6, 3, 8, C("steel4"))
        s.rect(bx + 4.5 + k * 5, by + 6.5 + (k % 2) * 4, 2, 3, C("steel5"))
        s.fhline(bx + 4.5 + k * 5, bx + 6.5 + k * 5, by + 6.5 + (k % 2) * 4, C("white"))
    s.label(bx + 4, by + 17, 14, 6, C("bone", -0.25))
    s.gpx(bx + 17, by + 4, C("red"), 1.0)
    s.anchor("led", bx + 17, by + 4, 1, 1, "red", rate=0.9)
    # Cable bundles dropping from the ceiling into boxes.
    cols = [C("void"), C("steel0"), shade(C(spec["accent"][0]), -0.6)]
    for k, (x0, x1) in enumerate(((150, 176), (226, 250), (440, 468), (470, 498))):
        s.cable(x0, 34, x1, 34 + 30 + k * 6, 10 + k * 3, cols[k % 3], thick=2, hl=C("steel3"))
        s.cable(x0 + 2, 34, x1 + 2, 34 + 32 + k * 6, 9 + k * 3, cols[(k + 1) % 3], thick=0.5)
    # A wall clock / day counter.
    s.box(296, 40, 30, 12, C("void"), 0.1)
    s.text(299, 43, "03:17", C("red"), "emissive", neon=True)
    s.light(311, 46, C("red"), 30, 0.35)
    # Small vent grilles with slats that catch the light.
    for vx, vy in ((200, 64), (420, 100)):
        s.box(vx, vy, 20, 12, C("steel2"), 0.2)
        for k in range(vy + 2, vy + 11, 2):
            s.hline(vx + 2, vx + 17, k, C("void"))
            s.fhline(vx + 2, vx + 18, k + 1, C("steel4"))
        for cx, cy in ((vx + 1, vy + 1), (vx + 18, vy + 1), (vx + 1, vy + 10), (vx + 18, vy + 10)):
            s.rivet(cx, cy, C("steel2"))


def floor_dressing(s: Scene, spec):
    """Cables across the floor, a drain, buckets and foreground silhouettes."""
    g = spec["grime"]
    f = 1.0 / s.res
    # Power cables from the rack to the table base and console: round,
    # with a fine top highlight and a contact shadow.
    for k, (x0, x1, y) in enumerate(((560, 330, 252), (556, 180, 258), (150, 290, 249))):
        pts = []
        for t in range(0, 81):
            u = t / 80
            x = x0 + (x1 - x0) * u
            yy = y + math.sin(u * math.pi * 2 + k) * 3 + u * 2
            pts.append((x, yy))
        col = C("void") if k != 1 else shade(C(spec["accent"][0]), -0.55)
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            s.line(ax, ay + 1.5, bx, by + 1.5, shade(C("void"), 0.0), t=0.5)
            s.line(ax, ay, bx, by, col, t=1.5)
            s.fline(ax + 0.5, ay + 0.5, bx + 0.5, by + 0.5, shade(col, 0.35))
    # Floor drain: a grate over a dark sump.
    s.box(282, 300, 34, 8, C("steel0"), 0.2)
    for k in range(285, 314, 3):
        s.vline(k, 301, 306, C("void"))
        s.fvline(k + 1, 301, 306, C("steel3"))
    s.set_gloss(276, 296, 46, 16, 0.9)
    if g < 3:
        # Bucket and mop, a stack of crates, a trash bag.
        s.box(80, 262, 14, 14, C("yellow", -0.45), 0.25)
        s.rect(80, 262, 14, 2, C("steel4"))
        s.fhline(80, 94, 262, C("steel5"))
        s.fvline(82, 264, 276, C("yellow", -0.15))
        s.line(90, 230, 86, 270, C("steel4"))
        s.fline(90.5, 230, 86.5, 270, C("steel5"))
        for k in range(6):
            s.line(86, 266, 82 + k * 2, 276, C("bone", -0.45), t=0.5)
        s.box(530, 268, 40, 28, C("rust1"), 0.2)
        for k in range(4):
            s.fvline(536 + k * 9, 269, 295, shade(C("rust1"), -0.35))
        s.box(536, 248, 30, 20, C("steel2"), 0.2)
        s.text(539, 254, "FRAG", C("yellow", -0.3), "albedo")
        s.label(553, 260, 10, 5, C("bone", -0.3))
        s.poly([(14, 300), (40, 296), (48, 318), (30, 326), (8, 320)], hexc("101318"))
        s.poly([(18, 302), (36, 299), (40, 306), (22, 308)], hexc("1a1f28"))
        s.fline(18, 302, 36, 299, C("steel3"))
        s.hline(18, 38, 299, C("steel3"))
    # Foreground silhouettes (depth like the references): a pipe and a cable tray.
    s.rect(0, 326, W, 10, hexc("07090d"))
    s.box(0, 318, 120, 8, hexc("0c1016"), 0.1)
    s.box(480, 314, 120, 12, hexc("0c1016"), 0.1)
    s.hline(0, 120, 318, C("steel1"))
    s.fhline(0, 120, 318, C("steel2"))
    s.hline(480, W, 314, C("steel1"))
    s.fhline(480, W, 314, C("steel2"))
    for x in range(486, W, 12):
        s.rect(x, 316, 1, 10, hexc("07090d"))


def clutter(s: Scene, spec):
    """Small props that fill the gaps between the furniture: gas cylinders
    by the table, a wall phone and fuse box under the window, a sharps bin,
    a first-aid case, hanging cable tags. Placed clear of every hotspot."""
    g = spec["grime"]
    f = 1.0 / s.res
    # Gas cylinders on a chained rack beside the table.
    for k, (cx, col) in enumerate(((216, "green"), (226, "white"))):
        c = shade(C(col), -0.45 if col == "green" else -0.25)
        top = FLOOR - 38 + k * 3
        s.rect(cx, top + 4, 8, FLOOR - top - 4, c)
        s.disc(cx + 4, top + 4, 4, c)
        s.fvline(cx + 1.5, top + 3, FLOOR - 1, shade(c, 0.45))
        s.fvline(cx + 2, top + 3, FLOOR - 1, shade(c, 0.2))
        s.fvline(cx + 7.5, top + 3, FLOOR - 1, shade(c, -0.45))
        s.rect(cx + 2.5, top - 2, 3, 3, C("steel4"))
        s.fhline(cx + 2.5, cx + 5.5, top - 2, C("steel5"))
        s.rect(cx + 5.5, top - 1, 2, 1, C("steel3"))
        s.label(cx + 1, top + 12, 6, 5, C("bone", -0.2))
        s.fhline(cx, cx + 8, top + 20, C("void"))
    s.rect(214, FLOOR - 22, 22, 1, C("steel3"))
    s.fhline(214, 236, FLOOR - 22, C("steel5"))
    s.cable(216, FLOOR - 30, 236, FLOOR - 32, 3, C("steel3"), 0.5)
    # Wall phone with a coiled cord, and a fuse box with a warning label.
    px_, py_ = 88, 128
    s.box(px_, py_, 9, 14, C("steel2"), 0.2)
    s.rect(px_ + 1.5, py_ + 1.5, 6, 3, shade(C("green"), -0.75))
    s.ftext(px_ + 2, py_ + 2, "OK", C("green", -0.2), "emissive")
    for k in range(3):
        for j in range(3):
            s.rect(px_ + 1.5 + j * 2, py_ + 6 + k * 2, 1.5, 1.5, C("steel4"))
    s.rect(px_ - 3, py_ + 1, 3, 12, C("steel1"))  # handset
    s.fvline(px_ - 2.5, py_ + 1, py_ + 13, C("steel3"))
    for k in range(8):  # coiled cord
        s.disc(px_ - 1.5 + (k % 2) * 0.5, py_ + 14 + k * 1.5, 0.8, C("void"))
    s.box(100, 126, 14, 18, C("steel2"), 0.2)
    s.label(102, 128, 10, 4, C("yellow", -0.2), text="HV")
    for k in range(4):
        s.rect(102 + k * 3, 134, 2, 6, C("steel1"))
        s.fhline(102 + k * 3, 104 + k * 3, 135 + (k % 2) * 3, C("steel5"))
    s.cable(107, 144, 112, 160, 3, C("void"), 0.5)
    # Sharps bin and a first-aid case on the wall above the bench's right end.
    sx, sy = 466, 106
    s.box(sx, sy, 20, 22, C("yellow", -0.35), 0.25)
    s.rect(sx + 2, sy + 2, 16, 3, C("red", -0.35))
    s.fhline(sx + 2, sx + 18, sy + 2, C("red", -0.05))
    s.disc(sx + 10, sy + 13, 3.5, C("void"))
    s.disc(sx + 10, sy + 13, 2.5, C("yellow", -0.35))
    s.disc(sx + 10, sy + 13, 1, C("void"))
    s.ftext(sx + 3, sy + 18, "SHARP", C("void"), "albedo")
    # A first-aid case by the door frame.
    s.box(54, 96, 16, 12, C("white", -0.25), 0.2)
    s.rect(60.5, 98, 3, 8, C("red", -0.2))
    s.rect(58, 100.5, 8, 3, C("red", -0.2))
    s.fhline(54, 70, 96, C("white"))
    # Cable tags hanging from the ceiling tangle.
    for k in range(5):
        tx = 260 + k * 70 + s.rng.uniform(-10, 10)
        ty = 34 + s.rng.uniform(4, 14)
        s.fvline(tx, 32, ty, C("void"))
        s.label(tx - 1.5, ty, 4, 2.5, shade(C(s.rng.choice(["yellow", "white", "red"])), -0.3))



# =============================================================================
# Signs, grime, dressing
# =============================================================================

def neon_sign(s: Scene, x, y, text, color, big=True, frame=True):
    """Neon lettering: glass tubes with hot cores on a dark backing board,
    hung from two chains, with a transformer box and its cable."""
    col = C(color)
    f = 1.0 / s.res
    tw = len(text) * (6 if big else 4)
    th = 7 if big else 5
    if frame:
        bx, by, bw, bh = x - 4, y - 4, tw + 6, th + 8
        s.vline(bx + 3, by - 6, by, C("steel3"), t=f)
        s.vline(bx + bw - 4, by - 6, by, C("steel3"), t=f)
        s.box(bx, by, bw, bh, C("void"), 0.1)
        s.fhline(bx + 1, bx + bw - 1, by + 1, C("steel1"))
        for cx, cy in ((bx + 1, by + 1), (bx + bw - 2, by + 1), (bx + 1, by + bh - 2), (bx + bw - 2, by + bh - 2)):
            s.rivet(cx, cy, C("steel2"))
        s.box(bx + bw, by + bh - 5, 4, 4, C("steel2"), 0.2)
        s.cable(bx + bw + 2, by + bh - 1, bx + bw + 6, by + bh + 14, 3, C("void"), 0.5)
    s.text(x, y, text, shade(col, -0.1), "emissive", big=big, neon=True)
    s.light(x + tw / 2, y + 4, col, tw * 2.2 + 40, 0.8)
    return tw


def poster(s: Scene, x, y, w, h, color, lines=3):
    """A printed poster: a figure silhouette over a sunset band, a headline
    in micro type, body lines, a torn corner and tape."""
    f = 1.0 / s.res
    c = C(color)
    s.box(x, y, w, h, shade(c, -0.55), 0.1)
    s.vgrad(x + 2, y + 2, w - 4, h // 2, shade(c, -0.15), shade(c, -0.5))
    cx = x + w / 2
    s.disc(cx, y + h * 0.2, w * 0.12, shade(c, -0.75))
    s.poly([(cx - w * 0.25, y + h // 2 + 2), (cx + w * 0.25, y + h // 2 + 2), (cx + w * 0.12, y + h * 0.28), (cx - w * 0.12, y + h * 0.28)],
           shade(c, -0.75))
    s.ftext(x + 2, y + h // 2 + 3, "VOTE" if w < 30 else "CHROME", shade(c, 0.2), "albedo")
    for k in range(lines):
        s.fhline(x + 3, x + w - 4 - (k % 2) * 5, y + h // 2 + 7 + k * 2.5, shade(c, -0.2))
    s.poly([(x + w - 6, y + h), (x + w, y + h - 6), (x + w, y + h)], C("concrete2"))  # torn corner
    s.rect(x + w / 2 - 3, y - 1, 6, 2, shade(C("bone"), -0.2))  # tape
    s.darken(x, y + h - 4, w, 4, 0.8)


def grime(s: Scene, spec):
    g = spec["grime"]
    f = 1.0 / s.res
    if g >= 3:
        s.darken(0, FLOOR - 2, W, 2, 0.85)
        return
    r = s.rng
    # Water streaks and rust runs down the wall (fine, tapering).
    for k in range(14 - g * 4):
        x = r.uniform(0, W)
        y0 = 34 + r.uniform(0, 40)
        length = r.uniform(40, 160)
        wd = r.uniform(1.5, 4.5)
        steps = int(length / 4)
        for i in range(steps):
            t = i / steps
            s.darken(x + wd * t * 0.3, y0 + i * 4, wd * (1 - t * 0.7), 4, 0.72 + 0.25 * t)
        if r.random() < 0.6:
            s.fvline(x + 0.5, y0, y0 + length * 0.6, C("rust2", -0.1))
            s.fvline(x + 1, y0, y0 + length * 0.3, C("rust3", -0.3))
    # Floor trash and stains: wrappers, butts, syringes, paper.
    for k in range(26 - g * 6):
        x, y = r.uniform(0, W), r.uniform(FLOOR + 6, H - 4)
        kind = r.random()
        if kind < 0.4:
            c = r.choice(["grime", "rust0", "concrete0", "bone", "blood"])
            s.rect(x, y, r.uniform(2, 7), r.uniform(1, 2.5), C(c, -0.2))
        elif kind < 0.6:  # a cigarette butt
            s.rect(x, y, 2, f * 2, C("bone", -0.1))
            s.rect(x + 2, y, 0.5, f * 2, C("amber", -0.3))
        elif kind < 0.75:  # a syringe
            s.fline(x, y, x + 4, y - 1, C("ice", -0.2))
            s.fline(x + 4, y - 1, x + 6, y - 1.5, C("steel5"))
        else:  # crumpled paper
            s.disc(x, y, 1.2, C("bone", -0.35))
            s.fpx(x * s.res, y * s.res - 1, C("bone"))
    # Mould in the corners: clumps of fine speckles.
    for cx in (0, W - 30):
        for k in range(160):
            s.px(cx + r.uniform(0, 30) * r.random() ** 0.5 * (1 if cx == 0 else -1) + (0 if cx == 0 else 30),
                 34 + r.uniform(0, 40) * r.random(), hexc(r.choice(["1e2618", "28331e", "171d12"])), t=f)


def sticker_wall(s: Scene, x, y, w, h, spec):
    """Stickers, tags and flyers (the alley reference's wall clutter)."""
    r = s.rng
    for k in range(26):
        px_, py_ = x + r.uniform(0, w - 10), y + r.uniform(0, h - 8)
        c = shade(C(r.choice(spec["accent"] + ["bone", "steel4", "white"])), -0.4)
        sw, sh = r.uniform(5, 12), r.uniform(4, 9)
        if r.random() < 0.5:
            s.label(px_, py_, sw, sh, c)
        else:
            s.rect(px_, py_, sw, sh, c)
            s.disc(px_ + sw / 2, py_ + sh / 2, min(sw, sh) * 0.3, shade(c, 0.35))
            s.fhline(px_, px_ + sw, py_, shade(c, 0.3))
    for k in range(3):
        s.text(x + r.randrange(0, w - 20), y + r.randrange(0, h - 6), r.choice(["RIP", "404", "NO", "SAINTS", "X"]), shade(C(spec["accent"][0]), -0.3), "albedo")
    # A spray tag drip under each tag.
    for k in range(6):
        dx = x + r.uniform(0, w)
        s.fvline(dx, y + r.uniform(4, h - 10), y + r.uniform(h - 8, h), shade(C(spec["accent"][0]), -0.45))


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
    clutter(s, spec)
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

def _diff(base_img, img, r):
    """Changed hi-res box, snapped outwards to whole design pixels (r hi-res
    px each) so the overlay lands on the room's design grid."""
    d = np.abs(img - base_img).sum(axis=2) > 1e-4
    if not d.any():
        return None
    ys, xs = np.where(d)
    x0, y0 = xs.min() // r * r, ys.min() // r * r
    x1, y1 = -(-(xs.max() + 1) // r) * r, -(-(ys.max() + 1) // r) * r
    return x0, y0, x1, y1, d


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
                r = _diff(img, uimg, s.res)
                if r is None:
                    continue
                x0, y0, x1, y1, mask = r
                rel = f"clinic/upgrades/{spec['id']}_{cat}_{lv}.png"
                hd.save_rgba(rel, uimg[y0:y1, x0:x1], mask[y0:y1, x0:x1].astype(np.float32))
                fx = [e for e in u.fx]
                overlays[f"{spec['id']}/{cat}/{lv}"] = {"path": "res://assets/sprites/" + rel, "x": int(x0 // s.res), "y": int(y0 // s.res), "fx": fx}
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data")
    with open(os.path.join(root, "clinic_fx.json"), "w") as f:
        json.dump({"_doc": "Animation anchors per clinic (HD art px, 600x336 rooms), generated by tools/art/rooms_hd.py",
                   "clinics": fx_all}, f, indent=1)
    if with_overlays:
        with open(os.path.join(root, "clinic_overlays.json"), "w") as f:
            json.dump({"_doc": "Upgrade overlay sprites per clinic/category/level (HD art px offsets), generated by tools/art/rooms_hd.py",
                       "overlays": overlays}, f, indent=1)
    print("HD clinics: %d rooms, %d upgrade overlays" % (len(CLINICS), len(overlays)))
