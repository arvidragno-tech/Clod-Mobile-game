"""HD street views (520x150 art px, drawn at 2 units per pixel) for every
city location, in the style of a wet neon alley: a hazy layered skyline
with lit windows and holo ads, the place's own front (bar, market stalls,
flood tunnel, stacks, plaza towers, checkpoint...), signage, cables and
lamps overhead, and a wet street that mirrors the lights.

Each location gets a night and a day variant:
assets/sprites/streets/<id>_night.png / <id>_day.png. LocationView adds the
moving parts (people, rain, police lights, the hour's tint) on top.
"""
from __future__ import annotations

import json
import os
import random

import numpy as np

from . import hd
from .hd import PAL, Scene, hexc, mix, shade

W, H = 520, 150
GROUND = 124
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))


def C(name, k=0.0):
    return shade(PAL[name], k) if k else PAL[name]


def _load():
    with open(os.path.join(ROOT, "data", "districts.json")) as fh:
        d = json.load(fh)
    ds = d.get("districts", d)
    dist = {x["id"]: x for x in (ds if isinstance(ds, list) else ds.values())}
    with open(os.path.join(ROOT, "data", "locations.json")) as fh:
        l = json.load(fh)
    locs = l if isinstance(l, list) else l["locations"]
    return dist, locs


NEONS = ["pink", "cyan", "amber", "violet", "green", "magenta", "blue", "yellow", "red"]


# =============================================================================
# Layers
# =============================================================================

def sky(s: Scene, pal, night):
    top = shade(hexc(pal[0]), -0.8 if night else -0.35)
    low = mix(hexc(pal[1]), C("violet") if night else C("fluoro"), 0.25 if night else 0.35)
    low = shade(low, -0.35 if night else 0.1)
    s.vgrad(0, 0, W, GROUND, top, low)
    if not night:
        s.glow(0, 0, W, 1, mix(low, C("white"), 0.2), 0.0)


def skyline(s: Scene, rng, pal, night, depth, y_min, y_max, dark, lit_p, step=(10, 26)):
    """A row of buildings with lit windows, rooftop clutter and holo ads."""
    x = -6
    base = shade(hexc(pal[0]), dark)
    while x < W + 6:
        w = rng.randint(*step)
        top = rng.randint(y_min, y_max)
        col = shade(base, rng.uniform(-0.12, 0.08))
        s.rect(x, top, w, GROUND - top, col)
        s.vline(x, top, GROUND - 1, shade(col, 0.12))  # lit edge (sky behind)
        # Rooftop: antennas, tanks, dishes.
        r = rng.random()
        if r < 0.3:
            ax = x + rng.randint(2, max(3, w - 3))
            s.vline(ax, top - rng.randint(4, 12), top, shade(col, 0.1))
            if night and rng.random() < 0.6:
                s.gpx(ax, top - 12 if top > 12 else top, C("red"), 0.9)
        elif r < 0.5:
            s.rect(x + 2, top - 4, min(8, w - 3), 4, shade(col, 0.05))
        # Windows: a regular grid per building, whole floors lit together.
        ww = 2 if depth else 3
        gx, gy = (4, 5) if depth else (6, 7)
        floor_p = lit_p * 2.2
        for wy in range(top + 4, GROUND - 4, gy):
            floor_lit = rng.random() < floor_p
            c = rng.choice(["amber", "tungsten", "tungsten", "cyan", "ice", "pink"])
            for wx in range(x + 2, x + w - ww - 1, gx):
                on = floor_lit and rng.random() < 0.75
                if night and on:
                    s.glow(wx, wy, ww, 2, shade(C(c), -0.25 - 0.2 * depth), 0.55 - 0.15 * depth)
                else:
                    s.rect(wx, wy, ww, 2, shade(col, 0.18 if not night else -0.25))
        # A vertical holo ad on some tall buildings.
        if night and w > 16 and top < y_min + 10 and rng.random() < 0.35:
            ac = C(rng.choice(NEONS))
            hx = x + w // 2 - 3
            s.glow(hx, top + 6, 6, min(30, GROUND - top - 10), shade(ac, -0.5), 0.6)
            for k in range(top + 8, min(top + 34, GROUND - 6), 3):
                s.glow(hx + 1, k, 4, 1, ac, 0.5)
            s.light(hx + 3, top + 18, ac * 0.7, 40, 0.35)
        x += w + rng.randint(-1, 2)


def street(s: Scene, pal, night, rng):
    base = shade(hexc(pal[0]), -0.55 if night else -0.3)
    s.vgrad(0, GROUND, W, H - GROUND, base, shade(base, 0.15))
    s.hline(0, W, GROUND, shade(hexc(pal[2]), -0.2))
    s.rect(0, GROUND + 1, W, 3, shade(base, 0.1))  # kerb
    s.hline(0, W, GROUND + 4, shade(base, -0.3))
    for x in range(6, W, 22):
        s.rect(x, GROUND + 14, 10, 1, shade(hexc(pal[1]), -0.25))
    s.noise(0, GROUND, W, H - GROUND, 0.1, seed=rng.randint(0, 999), scale=2)
    s.gloss[GROUND + 1:, :] = 0.75 if night else 0.45
    s.floor_y = GROUND + 1
    for k in range(6):  # puddles
        px_, py_ = rng.randint(10, W - 60), rng.randint(GROUND + 6, H - 6)
        pw = rng.randint(24, 60)
        for yy in range(py_, min(H, py_ + 4)):
            inset = abs(yy - py_ - 2) * 5
            s.gloss[yy, max(0, px_ + inset):min(W, px_ + pw - inset)] = 0.98


def overhead(s: Scene, rng, night):
    """Cables slung between buildings and a street lamp or two."""
    for k in range(5):
        x0 = rng.randint(-40, W - 80)
        s.cable(x0, rng.randint(4, 20), x0 + rng.randint(80, 200), rng.randint(4, 24), rng.randint(6, 18),
                C("void"), thick=1, hl=C("steel2"))
    for lx in (rng.randint(30, 120), rng.randint(360, 480)):
        s.rect(lx, GROUND - 58, 2, 58, C("steel1"))
        s.hline(lx, lx + 12, GROUND - 58, C("steel2"))
        s.rect(lx + 9, GROUND - 57, 6, 2, C("steel3"))
        if night:
            s.glow(lx + 10, GROUND - 55, 4, 1, C("sodium"), 1.0)
            s.light(lx + 12, GROUND - 52, C("sodium"), 70, 0.7, cone=(0, 1, 50))


def sign(s: Scene, x, y, text, color, big=True, frame=True, on=True):
    tw = len(text) * (6 if big else 4)
    if frame:
        s.box(x - 3, y - 3, tw + 4, (7 if big else 5) + 6, C("void"), 0.1)
    if on:
        s.text(x, y, text, C(color), "emissive", big=big)
        s.light(x + tw / 2, y + 4, C(color), tw * 1.6 + 40, 0.7)
    else:
        s.text(x, y, text, shade(C(color), -0.6), "albedo", big=big)
    return tw


def storefront(s: Scene, x, w, h, col, night, rng, lit=True, color="amber"):
    top = GROUND - h
    s.occlude(x, top, w, h)
    s.panel(x, top, w, h, col, seams=True, rivets=False)
    # Shop window with a warm interior.
    wx, ww = x + 4, w - 8
    wy, wh = GROUND - 26, 20
    s.rect(wx, wy, ww, wh, C("void"))
    if lit:
        s.vgrad(wx + 1, wy + 1, ww - 2, wh - 2, shade(C(color), -0.6), shade(C(color), -0.8))
        for k in range(wy + 4, wy + wh - 8, 4):  # shelves of bottles
            s.hline(wx + 3, wx + ww - 4, k, shade(C(color), -0.85))
            for bx in range(wx + 4, wx + ww - 4, 3):
                if rng.random() < 0.6:
                    s.gpx(bx, k - 1, shade(C(rng.choice(["amber", "green", "cyan", "pink"])), -0.3), 0.6)
        s.rect(wx + 1, wy + wh - 6, ww - 2, 5, shade(C("void"), 0.05))  # counter
        s.hline(wx + 1, wx + ww - 2, wy + wh - 6, shade(C(color), -0.3))
        for k in range(rng.randint(3, 6)):  # silhouettes at the counter
            sx = wx + 4 + rng.randint(0, max(1, ww - 12))
            s.rect(sx, wy + wh - 13, 4, 8, C("void"))
            s.rect(sx + 1, wy + wh - 15, 2, 2, C("void"))
        for k in range(3):  # pendant lamps
            lx = wx + (k + 1) * ww // 4
            s.gpx(lx, wy + 2, C(color), 1.0)
        if night:
            s.light(wx + ww / 2, wy + wh, C(color) * 0.7, 60, 0.5)
    s.hline(wx, wx + ww - 1, wy, C("steel3"))
    # Awning.
    s.box(x - 2, wy - 6, w + 4, 4, shade(C(color), -0.45), 0.2)


# =============================================================================
# Places
# =============================================================================

def place_clinic(s, rng, pal, night):
    storefront(s, 150, 220, 70, C("concrete2"), night, rng, lit=False)
    s.rect(240, GROUND - 46, 36, 46, C("void"))  # the door
    s.glow(242, GROUND - 44, 32, 2, C("cyan"), 0.6 if night else 0.2)
    sign(s, 200, GROUND - 64, "OPEN 24H", "pink", on=night)
    sign(s, 290, GROUND - 38, "DOC", "cyan", big=False, on=True)
    s.light(258, GROUND - 20, C("cyan"), 70, 0.5)


def place_residential(s, rng, pal, night):
    # Stacked tenement blocks with balconies, laundry and AC units.
    for i in range(5):
        x = 30 + i * 96
        h = 96 - (i % 2) * 14
        col = shade(hexc(pal[1]), -0.35 + (i % 3) * 0.06)
        s.occlude(x, GROUND - h, 97, h)
        s.rect(x, GROUND - h, 84, h, col)
        for fy in range(GROUND - h + 4, GROUND - 6, 12):
            for fx in range(x + 4, x + 80, 13):
                lit = rng.random() < (0.4 if night else 0.1)
                c = rng.choice(["amber", "tungsten", "tungsten", "pink", "cyan"])
                if lit:
                    s.glow(fx, fy, 8, 6, shade(C(c), -0.55), 0.7)
                    s.glow(fx + 1, fy + 4, 6, 2, shade(C(c), -0.35), 0.6)  # warm sill light
                    s.rect(fx + 2, fy + 1, 2, 3, C("void")) if rng.random() < 0.3 else None  # a figure
                    s.light(fx + 4, fy + 3, C(c) * 0.4, 22, 0.2)
                else:
                    s.rect(fx, fy, 8, 6, shade(col, -0.4))
                s.hline(fx - 1, fx + 8, fy + 7, C("steel3"))  # balcony rail
                if rng.random() < 0.2:
                    s.box(fx + 9, fy + 1, 4, 4, C("steel3"), 0.2)  # AC unit
        for k in range(4):  # laundry lines
            y = GROUND - h + 10 + k * 20
            s.hline(x + 84, x + 96, y, C("steel2"))
            for j in range(3):
                s.rect(x + 85 + j * 4, y + 1, 3, 4, C(rng.choice(["pink", "bone", "teal", "amber"]), -0.3))
    sign(s, 70, GROUND - 20, "NOODLE", "amber", big=False, on=night)


def place_bar(s, rng, pal, night, name="VALVE", color="amber"):
    storefront(s, 140, 240, 60, shade(hexc(pal[0]), 0.05), night, rng, color=color)
    # Riveted tank by the entrance, pipes up the wall.
    s.box(150, GROUND - 40, 26, 40, C("rust2"), 0.2)
    for k in range(GROUND - 38, GROUND, 6):
        s.px(152, k, C("steel4"))
    for x in (190, 196):
        s.rect(x, GROUND - 120, 3, 60, C("rust1"))
    s.rect(254, GROUND - 34, 22, 34, C("void"))  # door
    s.glow(256, GROUND - 32, 18, 1, C(color), 0.6)
    sign(s, 214, GROUND - 76, name, "pink" if color == "pink" else color, on=night or True)
    sign(s, 300, GROUND - 52, "OPEN", "green", big=False, on=night)
    s.light(260, GROUND - 4, C(color), 80, 0.6)


def place_black_market(s, rng, pal, night):
    # A flood tunnel mouth: concrete arch, dripping, tarps and a guarded gate.
    s.darken(0, 0, W, GROUND, 0.75)
    cx = W // 2
    for X in range(cx - 120, cx + 121):
        t = (X - cx) / 120
        top = int(GROUND - 100 * (1 - t * t) ** 0.5)
        s.vline(X, top - 8, top, C("concrete2"))
        s.vline(X, top, GROUND - 1, C("void") if abs(t) < 0.9 else C("concrete1"))
        if 0 <= X < W:
            s.emissive[max(0, top - 8):GROUND, X] = 0
    for k in range(9):  # the tunnel's ribs
        s.vline(cx - 100 + k * 25, GROUND - 60, GROUND - 1, shade(C("concrete1"), -0.3))
    for k in range(5):  # stalls inside
        x = cx - 90 + k * 38
        s.box(x, GROUND - 22, 30, 22, C("steel1"), 0.2)
        c = C(rng.choice(["pink", "cyan", "green", "amber", "magenta"]))
        s.box(x - 2, GROUND - 28, 34, 5, shade(c, -0.55), 0.2)
        s.glow(x + 4, GROUND - 20, 6, 2, c, 0.8)
        s.light(x + 15, GROUND - 24, c * 0.6, 40, 0.45)
    for k in range(14):  # drips
        s.vline(rng.randint(cx - 110, cx + 110), GROUND - 96, GROUND - 90, shade(C("ice"), -0.5), "emissive")
    sign(s, cx - 15, GROUND - 92, "NO ID", "red", big=False, on=True)


def place_industrial(s, rng, pal, night):
    for i in range(4):  # chimney stacks
        x = 60 + i * 110
        s.box(x, GROUND - 110, 16, 110, shade(hexc(pal[0]), -0.1), 0.2)
        for k in range(GROUND - 106, GROUND, 10):
            s.hline(x, x + 15, k, shade(hexc(pal[0]), -0.35))
        if night:
            s.gpx(x + 8, GROUND - 112, C("red"), 1.0)
    s.occlude(20, GROUND - 46, 480, 46)
    s.panel(20, GROUND - 46, 480, 46, C("steel2"), seams=True, rivets=True, vent=True)
    for x in range(30, 500, 40):  # shutter bays with furnace glow
        s.rect(x, GROUND - 30, 28, 30, C("void"))
        s.glow(x + 2, GROUND - 10, 24, 8, C("orange"), 0.7 if night else 0.35)
        s.light(x + 14, GROUND - 6, C("orange"), 50, 0.55)
    for k in range(3):  # pipes
        s.rect(0, GROUND - 56 + k * 4, W, 2, C("rust2" if k == 1 else "steel3"))
    sign(s, 210, GROUND - 42, "LINE 4", "amber", big=False, on=True)
    for k in range(10):
        s.line(30 + k * 48, GROUND - 46, 44 + k * 48, GROUND - 46, C("yellow", -0.3))


def place_night_market(s, rng, pal, night):
    for i in range(7):
        x = 12 + i * 72
        c = C(NEONS[i % len(NEONS)])
        s.occlude(x - 3, GROUND - 40, 66, 40)
        s.box(x, GROUND - 26, 60, 26, C("steel1"), 0.2)  # counter
        s.box(x - 3, GROUND - 40, 66, 6, shade(c, -0.5), 0.2)  # awning
        for k in range(0, 66, 6):
            s.rect(x - 3 + k, GROUND - 34, 3, 3, shade(c, -0.6))
        if night:
            s.glow(x, GROUND - 34, 60, 1, c, 0.8)
            s.light(x + 30, GROUND - 30, c, 70, 0.6)
        for k in range(5):  # goods
            s.rect(x + 4 + k * 11, GROUND - 24, 7, 6, C(rng.choice(["bone", "amber", "teal", "pink", "steel4"]), -0.3))
        sign(s, x + 6, GROUND - 52, rng.choice(["NOODLE", "CHROME", "FIX", "BUY", "EAT", "SIMS"]), NEONS[(i + 3) % len(NEONS)],
             big=False, on=night)
    for k in range(40):  # paper lanterns on a string
        x = 6 + k * 13
        y = 18 + int(6 * np.sin(k * 0.6))
        s.glow(x, y, 3, 3, C(rng.choice(["red", "amber", "pink"])), 0.9 if night else 0.2)


def place_lounge(s, rng, pal, night):
    place_bar(s, rng, pal, night, name="ORCHID", color="pink")
    for k in range(6):  # velvet rope and bulbs
        s.gpx(130 + k * 46, GROUND - 64, C("tungsten"), 1.0 if night else 0.4)
    s.hline(230, 300, GROUND - 10, C("red", -0.3))


def place_transit(s, rng, pal, night):
    cx = W // 2
    for k in range(80):  # the arch of the interchange roof
        t = k / 79
        X = int(cx - 220 + t * 440)
        Y = int(GROUND - 20 - 90 * (1 - (2 * t - 1) ** 2))
        s.rect(X, Y, 3, 2, C("steel3"))
    for x in range(cx - 210, cx + 211, 30):
        s.vline(x, GROUND - 60, GROUND - 1, C("steel2"))
    s.rect(0, GROUND - 22, W, 3, C("steel3"))  # platform edge
    s.box(80, GROUND - 40, 300, 18, C("steel4"), 0.2)  # a train
    for k in range(14):
        s.glow(86 + k * 21, GROUND - 36, 14, 6, C("tungsten"), 0.7 if night else 0.3)
    s.light(230, GROUND - 32, C("tungsten"), 160, 0.5)
    sign(s, cx - 30, GROUND - 92, "SPINDLE", "cyan", on=True)


def place_corporate(s, rng, pal, night):
    for i in range(5):
        x = 40 + i * 92
        h = 110 + (i % 2) * 14
        glass = shade(C("steel4"), 0.1 if not night else -0.25)
        s.occlude(x, GROUND - h, 60, h)
        s.rect(x, GROUND - h, 60, h, glass)
        for fy in range(GROUND - h + 2, GROUND, 4):
            s.hline(x, x + 59, fy, shade(glass, -0.2))
            if night:
                for fx in range(x + 2, x + 58, 6):
                    if rng.random() < 0.5:
                        s.glow(fx, fy + 1, 4, 2, C("ice"), 0.4)
        s.vline(x, GROUND - h, GROUND - 1, shade(glass, 0.3))
    s.rect(150, GROUND - 20, 220, 20, C("steel5"))  # plaza steps
    for k in range(0, 20, 4):
        s.hline(150, 369, GROUND - 20 + k, C("steel4"))
    sign(s, 205, GROUND - 40, "MERIDIAN", "blue", on=True)
    for k in range(3):  # drones
        s.gpx(100 + k * 140, 20 + k * 6, C("red"), 1.0)


def place_restricted(s, rng, pal, night, annex=False):
    for x in range(0, W, 5):  # fence
        s.vline(x, GROUND - 40, GROUND - 1, C("steel4", -0.2))
    for y in (GROUND - 40, GROUND - 26, GROUND - 12):
        s.hline(0, W, y, C("steel5", -0.2))
    for x in range(0, W, 7):  # razor wire
        s.px(x, GROUND - 42, C("steel5"))
        s.px(x + 3, GROUND - 43, C("steel5"))
    s.box(380, GROUND - 90, 40, 90, C("steel2"), 0.2)  # watchtower
    s.glow(384, GROUND - 86, 32, 10, C("ice"), 0.5)
    s.light(400, GROUND - 70, C("ice"), 200, 0.7, cone=(-1, 1, 30))
    if annex:
        s.box(80, GROUND - 100, 200, 100, C("steel4"), 0.2)
        s.glow(90, GROUND - 60, 180, 2, C("violet"), 0.6)
        sign(s, 140, GROUND - 90, "LYRA", "violet", on=True)
    else:
        s.box(200, GROUND - 50, 90, 50, C("steel3"), 0.2)  # checkpoint booth
        s.glow(210, GROUND - 40, 70, 12, C("red", -0.3), 0.6)
        sign(s, 216, GROUND - 64, "STOP", "red", on=True)
        s.rect(290, GROUND - 30, 90, 3, C("yellow", -0.2))  # barrier
        for k in range(0, 90, 10):
            s.rect(290 + k, GROUND - 30, 5, 3, C("void"))


PLACES = {
    "clinic": place_clinic, "sump_tenements": place_residential, "rusty_valve": place_bar,
    "flood_tunnels": place_black_market, "furnace_works": place_industrial,
    "glow_night_market": place_night_market, "velvet_lounge": place_lounge,
    "caldera_stacks": place_residential, "spindle_interchange": place_transit,
    "meridian_plaza": place_corporate, "lyra_checkpoint": place_restricted,
    "lyra_annex": lambda s, rng, pal, night: place_restricted(s, rng, pal, night, annex=True),
}


def scene(loc, dist, night) -> Scene:
    pal = dist.get(loc.get("district") or "undercity", dist["undercity"]).get("palette", ["202028", "404050", "604030", "c0a040"])
    seed = sum(ord(ch) for ch in loc["id"]) * 7
    amb = (0.42, 0.42, 0.55) if night else (0.95, 0.95, 1.0)
    s = Scene(W, H, ambient=amb, seed=seed)
    s.haze = 0.32 if night else 0.2
    s.haze_color = shade(mix(hexc(pal[1]), C("violet"), 0.4), -0.35) if night else shade(hexc(pal[1]), 0.2)
    rng = random.Random(seed)
    sky(s, pal, night)
    skyline(s, rng, pal, night, 1, 8, 50, -0.35, 0.22 if night else 0.08, (12, 30))
    skyline(s, rng, pal, night, 0, 34, 76, -0.55, 0.18 if night else 0.04, (16, 40))
    street(s, pal, night, rng)
    PLACES.get(loc["id"], place_residential)(s, rng, pal, night)
    overhead(s, rng, night)
    if night:
        s.light(W / 2, GROUND - 30, hexc(pal[3]) * 0.5, 320, 0.35, falloff=1.0)
    return s


def generate():
    dist, locs = _load()
    out = 0
    for loc in locs:
        for night in (True, False):
            s = scene(loc, dist, night)
            s.save(f"streets/{loc['id']}_{'night' if night else 'day'}.png")
            out += 1
    print("HD streets: %d views" % out)
