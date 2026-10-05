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
    generate_title()
    generate_den()


# =============================================================================
# Title key art (960x540): a deep neon alley, the clinic door on the right.
# =============================================================================

TW, TH = 960, 540
T_GROUND = 430
# Anchors mirrored in scripts/components/city_backdrop.gd.
T_CROSS = (783, 300, 22, 22)
T_DOOR_LIGHT = (770, 418, 44, 3)
T_VENT = (600, 428)
T_EYE = (688, 334)


def _tsign_v(s, x, y, text, color, on=True):
    """A vertical blade sign hanging off a wall: one letter per row."""
    h = len(text) * 10 + 6
    s.box(x - 3, y - 3, 14, h, C("void"), 0.1)
    for k, ch in enumerate(text):
        if on:
            s.text(x + 1, y + k * 10, ch, C(color), "emissive", big=True)
        else:
            s.text(x + 1, y + k * 10, ch, shade(C(color), -0.6), "albedo", big=True)
    if on:
        s.light(x + 4, y + h / 2, C(color), 120, 0.75)
    s.hline(x - 10, x - 3, y + 2, C("steel2"))  # bracket


def title_scene() -> Scene:
    rng = random.Random(1337)
    s = Scene(TW, TH, ambient=(0.38, 0.36, 0.5), seed=1337)
    s.haze = 0.4
    s.haze_color = hexc("2a1840")
    pal = ["1a1624", "3a2a48", "6a3c26", "c0a040"]
    s.vgrad(0, 0, TW, T_GROUND, hexc("05040a"), hexc("2a1a3a"))
    # Far towers seen through the alley's mouth, then two mid rows.
    for depth, (y0, y1, dark, lit, step) in enumerate(((60, 200, -0.2, 0.2, (14, 34)), (140, 260, -0.45, 0.16, (20, 46)))):
        x = 0
        base = shade(hexc(pal[1]), dark)
        while x < TW:
            w = rng.randint(*step)
            top = rng.randint(y0, y1)
            col = shade(base, rng.uniform(-0.1, 0.06))
            s.rect(x, top, w, T_GROUND - top, col)
            s.vline(x, top, T_GROUND - 1, shade(col, 0.15))
            for wy in range(top + 4, T_GROUND - 4, 6 + depth):
                if rng.random() < lit * 1.4:
                    c = C(rng.choice(["amber", "tungsten", "tungsten", "cyan", "pink"]))
                    for wx in range(x + 2, x + w - 3, 5):
                        if rng.random() < 0.6:
                            s.glow(wx, wy, 3, 2, shade(c, -0.3 - 0.15 * depth), 0.5)
            if top < y0 + 40 and rng.random() < 0.5:
                s.vline(x + w // 2, top - 18, top, shade(col, 0.1))
                s.gpx(x + w // 2, top - 18, C("red"), 1.0)
            x += w + rng.randint(0, 3)
    # A holo billboard high up.
    s.box(780, 150, 120, 60, C("void"), 0.1)
    s.glow(784, 154, 112, 52, shade(C("magenta"), -0.6), 1.0)
    s.text(796, 166, "CHROME", C("pink"), "emissive", big=True)
    s.text(804, 184, "ON CREDIT", C("cyan"), "emissive", big=True)
    s.light(840, 180, C("magenta"), 200, 0.7)
    # Near walls: the alley's left and right buildings.
    s.occlude(330, 120, 150, T_GROUND - 120)
    s.panel(330, 120, 150, T_GROUND - 120, shade(hexc(pal[1]), -0.3), seams=True, rivets=True)
    for fy in range(140, T_GROUND - 30, 40):
        for fx in (345, 395, 445):
            if rng.random() < 0.6:
                s.glow(fx, fy, 22, 24, shade(C(rng.choice(["amber", "tungsten"])), -0.62), 0.8)
                for k in range(fy + 2, fy + 24, 3):  # blinds
                    s.emissive[k, fx:fx + 22] *= 0.35
                if rng.random() < 0.4:  # someone at the window
                    s.emissive[fy + 8:fy + 24, fx + 8:fx + 14] *= 0.1
            else:
                s.rect(fx, fy, 22, 24, C("void"))
            s.hline(fx - 2, fx + 23, fy + 25, C("steel3"))
    _tsign_v(s, 480, 150, "RIPPER", "pink")
    s.occlude(720, 230, 240, T_GROUND - 230)
    s.panel(720, 230, 240, T_GROUND - 230, shade(hexc(pal[1]), -0.38), seams=True, rivets=True, vent=True)
    for fy in range(250, 360, 36):
        for fx in range(830, 950, 34):
            if rng.random() < 0.55:
                s.glow(fx, fy, 22, 22, shade(C(rng.choice(["amber", "tungsten", "pink"])), -0.6), 0.75)
                for k in range(fy + 2, fy + 22, 3):
                    s.emissive[k, fx:fx + 22] *= 0.35
            else:
                s.rect(fx, fy, 22, 22, C("void"))
            s.hline(fx - 2, fx + 23, fy + 23, C("steel3"))
    # The clinic door with a cross sign and a red work light.
    s.rect(756, 330, 60, T_GROUND - 330, C("void"))
    s.box(752, 326, 68, 6, C("steel2"), 0.2)
    s.box(T_CROSS[0] - 2, T_CROSS[1] - 2, T_CROSS[2] + 4, T_CROSS[3] + 4, C("void"), 0.1)
    s.glow(T_CROSS[0] + 8, T_CROSS[1] + 2, 6, 18, C("cyan"), 1.0)
    s.glow(T_CROSS[0] + 2, T_CROSS[1] + 8, 18, 6, C("cyan"), 1.0)
    s.light(T_CROSS[0] + 11, T_CROSS[1] + 11, C("cyan"), 140, 0.8)
    s.glow(*T_DOOR_LIGHT, C("red"), 0.9)
    s.light(T_DOOR_LIGHT[0] + 22, T_DOOR_LIGHT[1], C("red"), 110, 0.7)
    s.text(772, 404, "DOC", C("red"), "emissive", big=True)
    # Cables and wires across the alley.
    for k in range(9):
        y0 = rng.randint(110, 260)
        s.cable(330 + rng.randint(0, 120), y0, 720 + rng.randint(0, 200), y0 + rng.randint(-30, 40), rng.randint(10, 40),
                C("void"), thick=rng.choice((1, 1, 2)), hl=C("steel2"))
    # AC units and pipes on the walls, a dumpster, the vent.
    for (ax, ay) in ((482, 300), (484, 360), (722, 260)):
        s.box(ax, ay, 22, 16, C("steel3"), 0.2)
        for k in range(ay + 2, ay + 15, 2):
            s.hline(ax + 2, ax + 13, k, C("steel1"))
    s.rect(708, 230, 4, T_GROUND - 230, C("rust2"))
    s.box(860, T_GROUND - 40, 80, 40, shade(C("teal"), -0.6), 0.2)
    s.box(T_VENT[0] - 14, T_VENT[1] - 2, 28, 4, C("steel2"), 0.2)
    # The street.
    s.vgrad(0, T_GROUND, TW, TH - T_GROUND, hexc("0e0c16"), hexc("1c1826"))
    s.noise(0, T_GROUND, TW, TH - T_GROUND, 0.1, seed=4, scale=2)
    s.gloss[T_GROUND + 1:, :] = 0.85
    s.floor_y = T_GROUND + 1
    for k in range(10):
        px_, py_ = rng.randint(340, TW - 80), rng.randint(T_GROUND + 8, TH - 8)
        pw = rng.randint(40, 110)
        for yy in range(py_, min(TH, py_ + 5)):
            inset = abs(yy - py_ - 2) * 8
            s.gloss[yy, max(0, px_ + inset):min(TW, px_ + pw - inset)] = 1.0
    # The waiting customer: a coated silhouette with one red optic.
    ex, ey = T_EYE
    s.rect(ex - 6, ey - 4, 10, 10, C("void"))            # head + hood
    s.poly([(ex - 12, ey + 6), (ex + 9, ey + 6), (ex + 12, T_GROUND - 18), (ex - 15, T_GROUND - 18)], C("void"))
    s.rect(ex - 10, T_GROUND - 18, 6, 18, C("void"))
    s.rect(ex + 1, T_GROUND - 18, 6, 18, C("void"))
    s.vline(ex + 8, ey + 6, T_GROUND - 20, shade(C("cyan"), -0.2))  # rim light from the cross
    s.vline(ex + 9, ey + 10, T_GROUND - 22, shade(C("cyan"), -0.5))
    s.hline(ex - 5, ex + 3, ey - 4, shade(C("sodium"), -0.4))      # lamp light on the hood
    s.vline(ex - 12, ey + 8, T_GROUND - 22, shade(C("sodium"), -0.55))
    s.gpx(ex, ey, C("red"), 1.0)
    # A street lamp near the left wall.
    s.rect(560, T_GROUND - 170, 3, 170, C("steel1"))
    s.hline(560, 582, T_GROUND - 170, C("steel2"))
    s.glow(574, T_GROUND - 167, 8, 2, C("sodium"), 1.0)
    s.light(578, T_GROUND - 160, C("sodium"), 220, 1.0, cone=(0, 1, 45))
    return s


def generate_title():
    s = title_scene()
    s.save("ui/title_keyart.png")
    print("HD title key art: %dx%d" % (TW, TH))


# =============================================================================
# Black-market banner (900x111): the undermarket's back room.
# =============================================================================

def den_scene() -> Scene:
    w, h, floor = 900, 111, 96
    rng = random.Random(78)
    s = Scene(w, h, ambient=(0.4, 0.34, 0.5), seed=78)
    s.haze = 0.3
    s.haze_color = hexc("2a1030")
    s.vgrad(0, 0, w, floor, hexc("0a0610"), hexc("1e1024"))
    # Steel grate wall.
    for x in range(0, w, 6):
        s.vline(x, 0, floor - 1, hexc("1a1420"))
    for y in range(0, floor, 6):
        s.hline(0, w, y, hexc("1a1420"))
    # Rails of hooks with chrome hanging: arms, optics, spines.
    for rail in (14, 34):
        s.hline(0, w, rail, C("steel3"))
        s.hline(0, w, rail + 1, C("steel1"))
        for x in range(10, w, rng.randint(22, 30)):
            kind = rng.random()
            s.vline(x, rail + 1, rail + 4, C("steel4"))
            if kind < 0.4:  # a chrome forearm
                s.box(x - 2, rail + 4, 5, 14, C("steel4"), 0.3)
                s.hline(x - 2, x + 2, rail + 10, C("steel2"))
                s.gpx(x, rail + 7, C(rng.choice(["cyan", "pink", "green"])), 0.9)
            elif kind < 0.7:  # an optic on a wire
                s.box(x - 2, rail + 6, 5, 5, C("steel2"), 0.2)
                s.gpx(x, rail + 8, C(rng.choice(["red", "cyan", "amber"])), 1.0)
            else:  # a spine segment
                for k in range(4):
                    s.rect(x - 1, rail + 5 + k * 3, 3, 2, C("bone", -0.3))
    # Booths with neon under the counters.
    for i in range(6):
        x = 20 + i * 150
        col = C(["magenta", "pink", "violet", "cyan", "magenta", "green"][i])
        s.occlude(x, 52, 120, floor - 52)
        s.box(x, 66, 120, floor - 66, C("steel1"), 0.2)
        s.box(x - 4, 52, 128, 6, shade(col, -0.55), 0.2)
        s.glow(x - 4, 58, 128, 1, col, 0.9)
        s.light(x + 60, 62, col, 120, 0.7)
        for k in range(5):  # goods on the counter
            gx = x + 8 + k * 22
            s.box(gx, 60, 14, 6, C("steel3"), 0.2)
            s.gpx(gx + 7, 62, C(rng.choice(["cyan", "pink", "amber", "green"])), 0.9)
        s.text(x + 10, 72, rng.choice(["NO REFUNDS", "CASH ONLY", "CHROME", "WETWARE", "NO ID", "OPTICS"]), shade(col, -0.1), "emissive")
    # Vendor silhouettes behind two booths, cables overhead.
    for vx in (95, 545):
        s.rect(vx, 40, 8, 12, C("void"))
        s.rect(vx + 2, 36, 4, 4, C("void"))
        s.gpx(vx + 4, 37, C("red"), 1.0)
    for k in range(6):
        x0 = rng.randint(-50, w - 150)
        s.cable(x0, 2, x0 + rng.randint(100, 260), 4, rng.randint(6, 14), C("void"), thick=1, hl=C("steel2"))
    # Wet floor.
    s.vgrad(0, floor, w, h - floor, hexc("0e0a12"), hexc("1a1420"))
    s.gloss[floor + 1:, :] = 0.8
    s.floor_y = floor + 1
    return s


def generate_den():
    den_scene().save("blackmarket/den.png")
    print("HD black-market banner: 900x111")
