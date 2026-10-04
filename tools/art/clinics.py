"""The seven purchasable clinics (400x224 art px, 3x on screen) and their
upgrade overlays.

Every clinic shares the same readable layout so the room stays clickable
(door + waiting spot left, diagnostics, operating table centre, storage
bench, supply cabinet, records server right), but each has its own
district identity: architecture, light colour, signage and how filthy it
is. Most light is dirty tungsten, sodium or cold fluorescent; neon is a
single leaking sign at most. A grime pass adds water streaks, rust, mould,
trash, medical waste and old blood on top of every room - even the
corporate clinic has a stained drain.

Upgrade overlays: for each clinic, category and level the scene is
re-rendered with the upgrade props added, diffed against the base render
and cropped. The result is a small transparent sprite that already carries
the room's lighting, composited at runtime by ClinicView.
"""
from __future__ import annotations

import json
import math
import os
import random

from . import environments as env
from . import palette as pal
from . import props
from .environments import C, GLOW, MAT, R, chair, lamp, monitor, neon, text, text_width
from .lib import LitScene, bayer

W, H, FLOOR = 400, 224, 162

# id, district, wall, floor, ambient, grime (0 filthy .. 3 clean-ish)
CLINICS = [
    {"id": "backalley", "district": "undercity", "wall": "concrete", "floor": "concrete", "amb": (0.20, 0.19, 0.22), "grime": 0},
    {"id": "undercity", "district": "undercity", "wall": "tile", "floor": "concrete", "amb": (0.22, 0.23, 0.27), "grime": 0},
    {"id": "industrial", "district": "industrial", "wall": "panel", "floor": "metal", "amb": (0.25, 0.22, 0.20), "grime": 1},
    {"id": "nightmarket", "district": "market", "wall": "concrete", "floor": "tile", "amb": (0.23, 0.19, 0.25), "grime": 1},
    {"id": "professional", "district": "oldcity", "wall": "tile", "floor": "tile", "amb": (0.27, 0.29, 0.32), "grime": 2},
    {"id": "corporate", "district": "corporate", "wall": "clean", "floor": "metal", "amb": (0.33, 0.36, 0.42), "grime": 3},
    {"id": "elite", "district": "restricted", "wall": "hex", "floor": "metal", "amb": (0.30, 0.32, 0.40), "grime": 3},
]

UPGRADE_CATEGORIES = ["surgery", "diagnostics", "security", "black_market", "staff", "customer"]

DIRT = R("3a3226", 0.05)
RUST = R("6a3c26", 0.08)
MOULD = (30, 38, 26, 255)
WATER = (0, 0, 0, 0)  # placeholder (multiplied, see darken)


# =============================================================================
# Grime helpers
# =============================================================================

def darken(a, x, y, f=0.78, tint=(1.0, 1.0, 1.0)):
    c = a.get(x, y)
    if c is None:
        return
    a.set(x, y, (int(c[0] * f * tint[0]), int(c[1] * f * tint[1]), int(c[2] * f * tint[2]), 255))


def water_streak(a, x, y0, y1, w, rng, f=0.8):
    """Long vertical stain from a leaking pipe joint, ragged at the bottom."""
    for xx in range(x, x + w):
        end = y1 - rng.randrange(0, 12)
        for yy in range(y0, end):
            edge = xx in (x, x + w - 1)
            if bayer(xx, yy) < (0.45 if edge else 0.85):
                darken(a, xx, yy, f, (0.96, 1.0, 0.98))


def rust_run(a, x, y, length, rng):
    for k in range(length):
        if rng.random() < 0.75:
            a.set(x, y + k, C(RUST, 3 if k < length // 2 else 2))
        if k % 5 == 0:
            x += rng.choice((-1, 0, 0, 1))


def mould(a, x, y, w, h, rng):
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            d = ((xx - x - w / 2) / (w / 2)) ** 2 + ((yy - y - h) / h) ** 2
            if d < 1 and rng.random() < 0.55 * (1 - d):
                darken(a, xx, yy, 0.72, (0.85, 1.05, 0.82))


def floor_dirt(sc, level, rng):
    """Scuffs, footprint smears toward the table, trash, cigarette butts."""
    a = sc.albedo
    density = [0.10, 0.06, 0.03, 0.012][level]
    for yy in range(FLOOR + 1, H):
        for xx in range(W):
            if rng.random() < density:
                darken(a, xx, yy, 0.72, (1.05, 1.0, 0.9))
    # A worn path from the door to the table.
    for k in range(40):
        px = 30 + k * 4 + rng.randrange(-2, 3)
        py = FLOOR + 6 + int(math.sin(k * 0.4) * 2) + rng.randrange(0, 3)
        for dx in range(3):
            if rng.random() < 0.6 - level * 0.12:
                darken(a, px + dx, py, 0.8)
    trash = [12, 8, 4, 1][level]
    for _ in range(trash):
        x, y = rng.randrange(50, W - 20), rng.randrange(FLOOR + 6, H - 8)
        kind = rng.random()
        if kind < 0.35:  # cigarette butt
            a.set(x, y, (200, 190, 170, 255))
            a.set(x + 1, y, (150, 90, 40, 255))
        elif kind < 0.6:  # crushed wrapper
            a.rect(x, y, 3, 2, C(R("6e6146", 0.06), 3 + rng.randrange(2)))
        elif kind < 0.8:  # used syringe
            a.line(x, y, x + 4, y - 1, C(MAT["white"], 4))
            a.set(x + 5, y - 1, C(MAT["steel"], 6))
        else:  # bloody gauze
            a.rect(x, y, 3, 2, C(MAT["white"], 3))
            a.set(x + 1, y, (90, 16, 24, 255))


def grime_pass(sc, level, rng):
    a = sc.albedo
    streaks = [7, 5, 3, 1][level]
    for _ in range(streaks):
        x = rng.randrange(50, W - 10)
        water_streak(a, x, 12, rng.randrange(60, FLOOR - 4), rng.randrange(2, 7), rng, 0.82 + level * 0.04)
    for _ in range([10, 7, 3, 0][level]):
        rust_run(a, rng.randrange(0, W), 10, rng.randrange(6, 26), rng)
    if level <= 1:
        mould(a, 0, FLOOR - 26, 30, 26, rng)
        mould(a, W - 34, FLOOR - 22, 34, 22, rng)
        mould(a, rng.randrange(120, 300), 12, 26, 10, rng)
    # Skirting grime band (always - nobody mops behind the cabinets).
    for yy in range(FLOOR - 6, FLOOR):
        for xx in range(W):
            if bayer(xx, yy) < (yy - FLOOR + 7) / (9 - level):
                darken(a, xx, yy, 0.75)
    floor_dirt(sc, level, rng)


# =============================================================================
# New set dressing (environmental storytelling)
# =============================================================================

def dim_emissive(sc, x0, y0, x1, y1, f):
    for y in range(y0, y1):
        row = sc.emissive.px[y]
        for x in range(x0, x1):
            e = row[x]
            if e is not None:
                row[x] = (int(e[0] * f), int(e[1] * f), int(e[2] * f), 255)


def crt_stack(sc, x, y, rng, glow="green"):
    """Two or three dead and dying CRTs stacked on a crate: one cracked
    and dark, one rolling static, one showing a green vitals trace."""
    a = sc.albedo
    env.crate(sc, x - 2, y + 30, 30, FLOOR - y - 30, rng)
    case = R("6b6250", 0.06)
    # bottom: working
    a.shaded_poly([(x, y + 14), (x + 26, y + 14), (x + 26, y + 30), (x, y + 30)], case, 4.6, 2, 1, 1)
    for yy in range(y + 16, y + 27):
        for xx in range(x + 2, x + 22):
            sc.emissive.set(xx, yy, (8, 18, 10, 255) if (yy % 2) else (4, 12, 6, 255))
    for xx in range(x + 2, x + 22):
        k = (xx - x) % 10
        sc.emissive.set(xx, y + 21 + {4: -3, 5: 2, 6: -1}.get(k, 0), GLOW(glow, 5))
    props.fx("monitor", x + 2, y + 16, 20, 11, color=glow)
    sc.light(x + 12, y + 22, pal.ACCENT[glow], 26, 0.28)
    # top: cracked, dead
    a.shaded_poly([(x + 3, y), (x + 23, y), (x + 23, y + 14), (x + 3, y + 14)], case, 4.2, 2, 1, 1)
    a.rect(x + 5, y + 2, 15, 9, (10, 12, 12, 255))
    a.line(x + 7, y + 3, x + 12, y + 7, C(MAT["glass"], 5))
    a.line(x + 12, y + 7, x + 17, y + 4, C(MAT["glass"], 5))
    a.line(x + 12, y + 7, x + 13, y + 10, C(MAT["glass"], 4))
    env.props.tape(sc, x + 4, y + 1, 4)


def security_camera(sc, x, y, facing=1, led=True):
    a = sc.albedo
    a.rect(x, y - 2, 2, 4, C(MAT["dark"], 3))  # bracket
    bx = x + (2 if facing > 0 else -9)
    a.shaded_poly([(bx, y), (bx + 9, y + 1), (bx + 9, y + 5), (bx, y + 4)], MAT["white"] if facing else MAT["steel"], 4.4, 2.2, 1, 1)
    lens = bx + (9 if facing > 0 else 0)
    a.set(lens, y + 3, (10, 10, 14, 255))
    sc.emissive.set(lens, y + 3, GLOW("blue", 2))
    if led:
        sc.emissive.set(bx + 2, y + 1, GLOW("red", 6))
        props.fx("led", bx + 2, y + 1, color="red", rate=0.5)
    a.polyline([(x, y - 2), (x - 3 * facing, y - 6), (x - 3 * facing, 12)], (12, 12, 16, 255))


def encrypted_terminal(sc, x, y):
    """Beige box with a keypad and a scrolling cipher screen (amber)."""
    a = sc.albedo
    case = R("7a705a", 0.06)
    a.shaded_poly([(x, y), (x + 22, y), (x + 22, y + 16), (x, y + 16)], case, 4.4, 2.2, 1, 1)
    for yy in range(y + 2, y + 10):
        for xx in range(x + 2, x + 20):
            sc.emissive.set(xx, yy, (20, 12, 4, 255))
    for row in range(3):
        for k in range(6):
            if (row * 7 + k * 3) % 5:
                sc.emissive.set(x + 3 + k * 3, y + 3 + row * 2, GLOW("amber", 4))
    props.fx("monitor", x + 2, y + 2, 18, 8, color="amber")
    for k in range(4):  # keypad
        a.rect(x + 3 + k * 4, y + 12, 3, 2, C(MAT["dark"], 3))
    sc.emissive.set(x + 19, y + 13, GLOW("red", 6))
    props.fx("led", x + 19, y + 13, color="red", rate=0.9)
    sc.light(x + 11, y + 6, pal.ACCENT["amber"], 20, 0.25)


def coolant_leak(sc, x, y):
    """Coolant line along the wall, wrapped in tape where it split; a pale
    puddle spreads beneath it."""
    a = sc.albedo
    a.cylinder(x, y, 3, FLOOR - y, MAT["steel"], 1, 4)
    a.rect(x - 1, y + 30, 5, 5, C(R("8a8a7a", 0.04), 4))  # tape wrap
    a.rect(x - 1, y + 32, 5, 1, C(R("8a8a7a", 0.04), 2))
    props.fx("drip", x + 1, y + 35, h=FLOOR - y - 33, color="cyan")
    for yy in range(FLOOR + 2, FLOOR + 7):
        for xx in range(x - 10, x + 14):
            if ((xx - x - 2) / 12) ** 2 + ((yy - FLOOR - 4) / 2.6) ** 2 <= 1:
                a.set(xx, yy, (22, 34, 38, 255))
                if bayer(xx, yy) < 0.1:
                    sc.emissive.set(xx, yy, (26, 70, 70, 255))


def waste_bags(sc, x, rng):
    a = sc.albedo
    bag = R("1e1e22", 0.05)
    red = R("6a1a1e", 0.06)
    for k, (dx, w, h, col) in enumerate(((0, 14, 12, bag), (10, 12, 10, red), (-6, 10, 8, bag))):
        cx, cy = x + dx + w / 2, FLOOR - h / 2 + 1
        a.sphere(cx, cy, w / 2, h / 2, col, 1.2, 4.6)
        a.set(int(cx), int(cy - h / 2), C(col, 1))  # knot
    a.set(x + 14, FLOOR - 7, (20, 16, 12, 255))
    a.set(x + 16, FLOOR - 4, (20, 16, 12, 255))


def sharps_box(sc, x, y):
    a = sc.albedo
    a.shaded_poly([(x, y), (x + 8, y), (x + 8, y + 10), (x, y + 10)], R("b8902c", 0.06), 4.6, 2.2, 1, 1)
    a.rect(x + 1, y, 6, 2, C(MAT["dark"], 3))
    a.line(x + 3, y - 3, x + 4, y, C(MAT["steel"], 6))  # needle poking out
    a.line(x + 5, y - 2, x + 6, y, C(MAT["white"], 5))


def mattress(sc, x, rng):
    a = sc.albedo
    m = R("6e6450", 0.07)
    a.shaded_poly([(x, FLOOR - 52), (x + 10, FLOOR - 54), (x + 12, FLOOR), (x + 2, FLOOR)], m, 4.4, 2.2, 1, 1)
    for yy in range(FLOOR - 50, FLOOR, 6):
        a.hline(x + 2, x + 10, yy, C(m, 2))
    props.blood(sc, x + 6, FLOOR - 24, 2, 4, rng)
    for k in range(10):
        darken(a, x + 3 + rng.randrange(8), FLOOR - 40 + rng.randrange(30), 0.7)


def poster(sc, x, y, w, h, rng, tone="7a6a52", title="NO CHROME"):
    """Faded paper poster, one corner torn off and curling."""
    a = sc.albedo
    p = R(tone, 0.06)
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            if xx - x + (y + h - yy) < 4:  # torn corner
                continue
            a.shade_px(xx, yy, p, 3.4 + rng.random() * 0.6)
    tx = x + max(1, (w - text_width(title)) // 2)
    text(a, tx, y + 3, title, C(R("2a2420"), 2))
    a.rect(x + 2, y + 10, w - 4, h - 14, C(p, 2))
    for k in range(6):
        darken(a, x + rng.randrange(w), y + rng.randrange(h), 0.75)


def bucket(sc, x):
    a = sc.albedo
    a.cylinder(x, FLOOR - 9, 9, 9, R("4a5a6a", 0.06), 1, 4)
    a.rect(x + 1, FLOOR - 9, 7, 1, (40, 14, 18, 255))  # dark contents
    a.line(x, FLOOR - 10, x + 4, FLOOR - 13, C(MAT["steel"], 3))
    a.line(x + 4, FLOOR - 13, x + 8, FLOOR - 10, C(MAT["steel"], 3))


def mop(sc, x):
    a = sc.albedo
    a.line(x, FLOOR - 40, x + 4, FLOOR - 2, C(MAT["wood"], 4))
    a.rect(x + 2, FLOOR - 4, 6, 4, C(R("8a8070"), 3))


def door_bars(sc):
    a = sc.albedo
    for xx in range(15, 42, 4):
        a.vline(xx, 99, 114, C(MAT["steel"], 4))
    a.hline(13, 43, 106, C(MAT["steel"], 3))


def chain_hoist(sc, x):
    """Industrial: chain hoist on an I-beam over the table (lifts limbs)."""
    a = sc.albedo
    a.rect(x - 40, 13, 90, 4, C(RUST, 3))
    a.hline(x - 40, x + 49, 13, C(RUST, 5))
    for yy in range(17, 50):
        a.set(x + 14 + (yy % 2), yy, C(MAT["steel"], 3 + (yy % 2)))
    a.rect(x + 11, 50, 7, 5, C(R("b8902c", 0.06), 4))
    a.line(x + 14, 55, x + 14, 60, C(MAT["steel"], 5))
    a.set(x + 13, 60, C(MAT["steel"], 5))


def tarp_curtain(sc, x, y0, w, rng, color="5a2a3a"):
    """Night market: plastic tarp hung as a wall, sagging, patched."""
    a = sc.albedo
    t = R(color, 0.07)
    for xx in range(x, x + w):
        fold = math.sin((xx - x) * 0.5) * 0.9
        for yy in range(y0, FLOOR):
            a.shade_px(xx, yy, t, 3.0 + fold + (0.3 if (xx + yy // 6) % 9 == 0 else 0))
    for k in range(3):
        px = x + rng.randrange(w - 8)
        py = y0 + rng.randrange(10, FLOOR - y0 - 12)
        a.rect(px, py, 6, 5, C(R("8a8a7a", 0.04), 3))  # patch
    a.hline(x, x + w - 1, y0, C(MAT["steel"], 4))


def limb_rack(sc, x, y, rng):
    """Night market: salvaged arms and hands hanging on hooks."""
    a = sc.albedo
    a.hline(x, x + 34, y, C(MAT["steel"], 4))
    for k in range(4):
        hx = x + 3 + k * 9
        a.set(hx, y + 1, C(MAT["steel"], 5))
        col = MAT["steel"] if k % 2 else R("5a5248", 0.06)
        a.capsule(hx, y + 3, hx + rng.randrange(-1, 2), y + 20, 2.2, col, 1.4, 5.4, r2=1.8)
        a.rect(hx - 2, y + 20, 4, 4, C(col, 3))
        if k == 1:
            sc.emissive.set(hx, y + 9, GLOW("amber", 3))


def sodium_lamp(sc, x, y):
    """Caged industrial lamp, orange sodium light."""
    a = sc.albedo
    a.vline(x, 12, y, C(MAT["dark"], 1))
    a.rect(x - 4, y, 9, 3, C(RUST, 3))
    sc.emissive.ellipse(x + 0.5, y + 5, 3, 2.5, (255, 170, 90, 255))
    for k in (-3, 0, 3):
        a.vline(x + k, y + 3, y + 8, C(MAT["dark"], 2))
    sc.light(x, y + 6, "ffa060", 120, 1.15, cone=(90, 62))
    sc.light(x, FLOOR + 20, "ff9050", 60, 0.4)


def fluoro_tube(sc, x, y, w, flicker=True, cold=True):
    a = sc.albedo
    a.rect(x - 1, y - 1, w + 2, 3, C(MAT["dark"], 3))
    col = (220, 236, 240, 255) if cold else (240, 230, 200, 255)
    for xx in range(x, x + w):
        if not (flicker and x + w - 6 < xx < x + w - 2):
            sc.emissive.set(xx, y, col)
    sc.light(x + w / 2, y + 2, "c8dce0" if cold else "e8dcb8", 90, 0.7, cone=(90, 75))
    if flicker:
        props.fx("led", x + w - 5, y, 3, 1, color="white", rate=0.23)


def leaking_sign(sc, x, y, s, color):
    """One dirty neon sign half dead: some letters unlit."""
    w = text_width(s)
    sc.albedo.rect(x - 3, y - 3, w + 6, 11, C(MAT["dark"], 0))
    dead = {1, len(s) - 2}
    cx = x
    for i, ch in enumerate(s):
        g = env.FONT3x5.get(ch, env.FONT3x5[" "])
        for gy, row in enumerate(g):
            for gx, bit in enumerate(row):
                if bit == "1":
                    if i in dead:
                        sc.albedo.set(cx + gx, y + gy, C(R(pal.ACCENT[color], 0.02), 2))
                    else:
                        sc.emissive.set(cx + gx, y + gy, GLOW(color, 5))
        cx += len(g[0]) + 1
    sc.light(x + w / 2, y + 2, pal.ACCENT[color], 24 + w * 0.4, 0.38)


def bloody_sheet(sc, x, y, w):
    """A stained drape over the table edge."""
    a = sc.albedo
    for xx in range(x, x + w):
        drop = 6 + int(2 * math.sin(xx * 0.7))
        for yy in range(y, y + drop):
            a.shade_px(xx, yy, MAT["cloth"], 3.6 - (yy - y) * 0.2)
    for k in range(w // 3):
        a.set(x + 2 + k * 3 % max(1, w - 4), y + 2 + k % 3, (88, 18, 26, 255))


# =============================================================================
# Clinic scenes
# =============================================================================

def _base(cid: int) -> LitScene:
    spec = CLINICS[cid]
    rng = random.Random(900 + cid)
    sc = LitScene(W, H, ambient=spec["amb"])
    tier_like = [0, 1, 2, 2, 3, 4, 5][cid]
    env.wall(sc, spec["wall"], rng)
    env.ceiling(sc, tier_like if cid != 5 else 2, rng)
    env.floor(sc, spec["floor"], rng)
    env.door(sc, tier_like)
    cx = 200
    i = cid
    # ---------------------------------------------------------------- left zone
    props.power_box(sc, 56, 40, tier_like, sparks=i <= 2)
    if i == 0:
        crt_stack(sc, 84, 86, rng)
        mattress(sc, 128, rng)
        bucket(sc, 116)
    elif i == 1:
        monitor(sc, 84, 92, 24, 20, "crt", "green")
        env.iv_stand(sc, 130, 84)
        sharps_box(sc, 116, 70)
        poster(sc, 112, 92, 16, 22, rng, "6a5a48", "OPEN")
    elif i == 2:
        props.ecg_cart(sc, 92, 2)
        coolant_leak(sc, 132, 30)
        props.warning_label(sc, 112, 60, "LOTO")
    elif i == 3:
        tarp_curtain(sc, 48, 30, 26, rng)
        monitor(sc, 84, 92, 24, 20, "crt", "green")
        limb_rack(sc, 110, 52, rng)
    elif i == 4:
        props.ecg_cart(sc, 92, 3)
        env.iv_stand(sc, 130, 80)
        sharps_box(sc, 116, 70)
    elif i == 5:
        env.holo(sc, 80, 70, 32, 46, "cyan")
        props.ecg_cart(sc, 122, 4)
    else:
        env.holo(sc, 78, 56, 34, 56, "blue")
        props.ecg_cart(sc, 122, 5)
    # ------------------------------------------------------------- centre zone
    if i == 0:
        chair(sc, cx - 33, FLOOR - 36, "improvised")
        lamp(sc, cx, 60, "bulb")
        bloody_sheet(sc, cx - 28, FLOOR - 33, 34)
        leaking_sign(sc, cx - 10, 26, "DOC", "red")
    elif i == 1:
        chair(sc, cx - 33, FLOOR - 38, "dental")
        lamp(sc, cx, 62, "bulb")
        leaking_sign(sc, cx - 22, 22, "CLINIC", "cyan")
    elif i == 2:
        chain_hoist(sc, cx)
        chair(sc, cx - 35, FLOOR - 38, "surgical")
        sodium_lamp(sc, cx, 60)
        bloody_sheet(sc, cx - 30, FLOOR - 41, 30)
        props.warning_label(sc, cx + 60, 30, "SHIFT 3")
    elif i == 3:
        chair(sc, cx - 35, FLOOR - 38, "surgical")
        lamp(sc, cx, 58, "surgical")
        leaking_sign(sc, cx - 26, 22, "CHROME DOC", "magenta")
    elif i == 4:
        chair(sc, cx - 35, FLOOR - 38, "advanced")
        env.robot_arm(sc, cx + 26, side=-1, reach=(-4, -12), kind="pro")
        lamp(sc, cx, 54, "surgical")
        env.emblem_sign(sc, cx - 46, 16)
    elif i == 5:
        env.scanner_ring(sc, cx, FLOOR - 50)
        chair(sc, cx - 35, FLOOR - 36, "advanced")
        env.robot_arm(sc, cx - 30, side=1, reach=(4, -12), kind="pro")
        env.robot_arm(sc, cx + 30, side=-1, reach=(-4, -10), kind="pro")
        lamp(sc, cx, 50, "ring")
    else:
        env.scanner_ring(sc, cx, FLOOR - 48)
        chair(sc, cx - 35, FLOOR - 34, "elite")
        env.robot_arm(sc, cx - 30, side=1, reach=(4, -12), kind="pro")
        env.robot_arm(sc, cx + 30, side=-1, reach=(-6, -10), kind="pro")
        lamp(sc, cx, 50, "ring")
        sc.albedo.rect(0, 14, W, 3, C(MAT["steel"], 5))
    if i in (4, 5, 6):
        fluoro_tube(sc, 70, 20, 40, flicker=i == 4, cold=True)
        fluoro_tube(sc, 300, 20, 40, flicker=False, cold=True)
    elif i in (1, 3):
        fluoro_tube(sc, 300, 22, 30, flicker=True, cold=False)
    # -------------------------------------------------------------- right zone
    if i <= 1 or i == 3:
        props.workbench(sc, 252, 52, rng)
    else:
        props.desk(sc, 250, 70, [0, 1, 2, 2, 3, 4, 5][i], rng)
    if i == 2:
        encrypted_terminal(sc, 258, 90)
    cab = {0: "jars", 1: "jars", 2: "jars", 3: "implants", 4: "implants", 5: "glass", 6: "glass"}[i]
    env.cabinet(sc, 334, 52, 30, 110, cab, rng)
    dim_emissive(sc, 334, 52, 364, 162, 0.5)
    if i >= 2:
        props.server_rack(sc, 372, 76 + min(i, 5) * 4)
    else:
        waste_bags(sc, 372, rng)
    if i == 6:
        env.containment(sc, 304, 70)
        dim_emissive(sc, 304, 70, 324, 162, 0.55)
    props.vent(sc, 140 if i < 4 else 290, 24 if i < 4 else 30, tier=tier_like)
    props.waste_bin(sc, 148, tier_like)
    # ------------------------------------------------------------ storytelling
    if i <= 3:
        props.blood(sc, cx - 6, FLOOR + 14, 10 - min(i, 3) * 2, 2, rng)
        props.blood(sc, cx + 22, FLOOR + 24, 4, 1, rng)
    props.blood(sc, cx + 10, FLOOR + 8 + i, 2, 1, rng, fresh=True)
    for k in range(4 - min(i, 3)):
        props.discarded_implant(sc, 120 + k * 9, FLOOR + 10 + (k % 2) * 3, rng, glow=(k == 0))
    props.drain(sc, cx + 40, FLOOR + 40)
    if i >= 1:
        props.tool_cart(sc, cx + 54, FLOOR + 2, tier_like)
    props.floor_cables(sc, [(110, FLOOR), (130, FLOOR + 12), (cx - 10, FLOOR + 14), (cx, FLOOR)])
    props.floor_cables(sc, [(300, FLOOR), (280, FLOOR + 16), (cx + 20, FLOOR + 18)])
    if i <= 3:
        props.floor_cables(sc, [(66, 56), (70, 120), (64, FLOOR), (90, FLOOR + 30), (150, FLOOR + 34)])
    if i <= 1:
        props.hidden_compartment(sc, 228, 112, "panel")
        props.box_stack(sc, 360, FLOOR + 22, rng)
        props.tape(sc, 86, 93)
        env.puddle(sc, 60, FLOOR + 46, 40, rng, [GLOW("amber", 2), GLOW("red", 1)])
        mop(sc, 50)
    else:
        props.hidden_compartment(sc, 300, FLOOR + 44, "hatch")
        props.equipment_case(sc, 356, FLOOR + 36, "cyan" if i < 6 else "magenta")
    # Graffiti and posters (old city / undercity walls carry history).
    if i <= 1:
        props.graffiti(sc, 82, 66, "NO DOC" if i == 0 else "R4T", "magenta" if i == 0 else "cyan", rng)
        props.graffiti(sc, 300, 56, "SUMP", "red", rng)
    elif i == 2:
        props.graffiti(sc, 96, 112, "XX", "amber", rng)
    elif i == 3:
        poster(sc, 300, 40, 22, 30, rng, "5a3a4a", "LOST")
        props.graffiti(sc, 96, 66, "UNDR", "magenta", rng)
    elif i == 4:
        poster(sc, 300, 44, 22, 28, rng, "5a5448", "QUIET")
        props.warning_label(sc, 352, 40, "BIO")
    else:
        props.warning_label(sc, 352, 40, "BIO")
        security_camera(sc, 380, 22, -1)
    if i <= 2:
        props.steam(70 + i * 40, 10)
        props.steam(330, 10)
    grime_pass(sc, spec["grime"], rng)
    # Cold floor strip only in the corporate / restricted clinics (and dimmed).
    if i >= 5:
        for x in range(0, W):
            if x % 4 == 0:
                sc.emissive.set(x, FLOOR + 1, GLOW("blue", 3))
    return sc


# =============================================================================
# Upgrade overlays (props per category and level)
# =============================================================================

def _upgrade_props(sc, cat, level, cid, rng):
    a = sc.albedo
    lv = level
    if cat == "surgery":
        # 1 instrument tray, 2 anaesthesia cart, 3 cautery arm from the ceiling
        a.rect(152, FLOOR - 26, 12, 2, C(MAT["steel"], 5))
        a.vline(157, FLOOR - 24, FLOOR - 1, C(MAT["steel"], 3))
        a.hline(153, 162, FLOOR - 1, C(MAT["steel"], 2))
        for k in range(3):
            a.set(154 + k * 3, FLOOR - 27, C(MAT["white"], 7))
        if lv >= 2:
            g = R("4a6a7a", 0.06)
            a.shaded_poly([(236, FLOOR - 30), (250, FLOOR - 30), (250, FLOOR - 2), (236, FLOOR - 2)], g, 4.4, 2.2, 1, 1)
            a.cylinder(238, FLOOR - 46, 4, 16, R("3a6a4a", 0.06), 1.2, 5)  # gas bottles
            a.cylinder(244, FLOOR - 44, 4, 14, R("6a6a7a", 0.06), 1.2, 5)
            sc.emissive.rect(239, FLOOR - 24, 8, 4, (8, 20, 18, 255))
            sc.emissive.hline(239, 246, FLOOR - 22, GLOW("green", 4))
            props.fx("ecg", 239, FLOOR - 24, 8, 4, color="green")
            a.polyline([(243, FLOOR - 30), (232, FLOOR - 40), (222, FLOOR - 40)], (20, 20, 26, 255))
        if lv >= 3:
            a.hline(150, 190, 18, C(MAT["steel"], 4))
            a.capsule(176, 18, 172, 36, 2, MAT["steel"], 1.5, 5.5)
            a.capsule(172, 36, 184, 50, 1.6, MAT["steel"], 1.5, 5.5)
            a.set(185, 51, C(MAT["white"], 7))
            sc.emissive.set(185, 52, GLOW("amber", 6))
            props.fx("laser", 185, 52, color="amber")
    elif cat == "diagnostics":
        # 1 handheld scanner + chart, 2 wall vitals monitor, 3 imaging panel
        a.rect(118, 74, 8, 11, C(R("b8b0a0", 0.05), 4))  # clipboard
        for k in range(4):
            a.hline(119, 124, 76 + k * 2, C(MAT["dark"], 3))
        a.rect(128, 76, 3, 8, C(MAT["dark"], 4))
        sc.emissive.set(129, 77, GLOW("cyan", 6))
        props.fx("led", 129, 77, color="cyan", rate=0.6)
        if lv >= 2:
            a.rect(84, 50, 28, 2, C(MAT["dark"], 3))  # wall bracket
            a.shaded_poly([(86, 52), (110, 52), (110, 70), (86, 70)], MAT["dark"], 4.4, 2.2, 1, 1)
            for yy in range(54, 68):
                for xx in range(88, 108):
                    sc.emissive.set(xx, yy, (6, 16, 18, 255))
            props.fx("ecg", 88, 54, 20, 7, color="green")
            text(sc.emissive, 89, 62, "84", GLOW("cyan", 5))
            text(sc.emissive, 100, 62, "31", GLOW("amber", 5))
            sc.light(98, 61, pal.ACCENT["cyan"], 24, 0.25)
        if lv >= 3:
            a.shaded_poly([(226, 46), (250, 46), (250, 84), (226, 84)], MAT["dark"], 4.2, 2, 1, 1)
            for yy in range(48, 82):
                for xx in range(228, 248):
                    sc.emissive.set(xx, yy, (14, 18, 24, 255))
            # skull x-ray with an implant lattice
            sc.emissive.ellipse(238, 60, 6, 7, (60, 70, 80, 255))
            sc.emissive.ellipse(238, 60, 4, 5, (24, 30, 36, 255))
            for k in range(5):
                sc.emissive.set(235 + k, 60 + (k % 2), GLOW("cyan", 5))
            a.vline(238, 68, 80, (40, 46, 54, 255))
            props.fx("holo", 228, 48, 20, 34, color="white")
            sc.light(238, 64, "c8dce0", 26, 0.3)
    elif cat == "security":
        # 1 camera on the door, 2 bars + maglock + second camera, 3 CCTV bank
        security_camera(sc, 52, 18, -1)
        if lv >= 2:
            door_bars(sc)
            a.rect(44, 126, 4, 8, C(MAT["dark"], 2))
            sc.emissive.set(45, 128, GLOW("red", 6))
            props.fx("led", 45, 128, color="red", rate=0.3)
            security_camera(sc, 318, 18, 1)
        if lv >= 3:
            a.rect(6, 46, 40, 34, C(MAT["dark"], 1))
            for k in range(4):
                mx, my = 8 + (k % 2) * 19, 48 + (k // 2) * 16
                a.rect(mx, my, 17, 14, C(MAT["dark"], 3))
                for yy in range(my + 1, my + 13):
                    for xx in range(mx + 1, mx + 16):
                        sc.emissive.set(xx, yy, (18, 24, 20, 255) if (yy + k) % 2 else (10, 14, 12, 255))
                sc.emissive.set(mx + 3 + k * 2, my + 8, (90, 100, 90, 255))  # someone in frame
                props.fx("monitor", mx + 1, my + 1, 15, 12, color="green")
            sc.light(26, 63, "a8c8b0", 30, 0.3)
    elif cat == "black_market":
        # 1 stacked contraband crates, 2 organ cooler, 3 encrypted relay
        rng2 = random.Random(41)
        for k, (x, y, w, h) in enumerate(((296, FLOOR + 30, 26, 16), (300, FLOOR + 20, 18, 10), (322, FLOOR + 34, 16, 12))):
            a.shaded_poly([(x, y), (x + w, y), (x + w, y + h), (x, y + h)], R("3a3a30", 0.05), 4.4, 2.2, 1, 1)
            a.line(x, y, x + w, y + h, C(R("3a3a30"), 2))
            a.rect(x + 2, y + 2, 4, 2, C(R("8a3a2a", 0.06), 4))  # stencil
        a.set(318, FLOOR + 29, C(MAT["steel"], 6))  # padlock
        if lv >= 2:
            cool = R("c8ccd2", 0.05)
            a.shaded_poly([(114, FLOOR - 18), (138, FLOOR - 18), (138, FLOOR), (114, FLOOR)], cool, 4.6, 2.4, 1, 1)
            a.rect(114, FLOOR - 13, 24, 2, (120, 20, 30, 255))
            text(a, 118, FLOOR - 9, "BIO", (60, 14, 20, 255))
            for k in range(6):
                a.set(115 + rng2.randrange(22), FLOOR - 18 - (k % 2), (220, 240, 250, 255))  # frost
            sc.emissive.set(135, FLOOR - 16, GLOW("blue", 6))
            props.fx("led", 135, FLOOR - 16, color="blue", rate=0.7)
        if lv >= 3:
            encrypted_terminal(sc, 256, 44)
            a.vline(266, 26, 44, C(MAT["steel"], 4))  # antenna
            a.hline(262, 270, 26, C(MAT["steel"], 5))
            sc.emissive.set(266, 25, GLOW("magenta", 5))
            props.fx("led", 266, 25, color="magenta", rate=0.35)
    elif cat == "staff":
        # 1 coat hooks + lab coat, 2 rota board, 3 second workstation stool + lamp
        a.hline(294, 306, 58, C(MAT["steel"], 4))
        coat = R("c8c4b8", 0.05)
        a.shaded_poly([(295, 60), (302, 60), (304, 92), (293, 92)], coat, 4.4, 2.4, 1, 1)
        a.vline(298, 62, 90, C(coat, 2))
        a.set(300, 80, (90, 20, 28, 255))  # blood on the sleeve
        if lv >= 2:
            a.rect(310, 44, 22, 18, C(R("b8b0a0", 0.05), 3))
            for k in range(4):
                a.hline(312, 312 + 6 + (k * 5) % 12, 47 + k * 3, C(MAT["dark"], 2))
            a.rect(326, 46, 3, 3, (120, 30, 30, 255))
            a.rect(313, 56, 3, 3, (40, 90, 50, 255))
        if lv >= 3:
            a.cylinder(232, FLOOR - 14, 10, 3, MAT["dark"], 1.2, 4, vertical=False)  # stool seat
            a.vline(237, FLOOR - 11, FLOOR - 1, C(MAT["steel"], 3))
            a.hline(233, 241, FLOOR - 1, C(MAT["steel"], 3))
            a.vline(288, 104, 132, C(MAT["dark"], 3))  # task lamp
            a.line(288, 104, 296, 98, C(MAT["dark"], 3))
            sc.emissive.rect(295, 99, 3, 2, (255, 220, 160, 255))
            sc.light(296, 104, "ffd090", 30, 0.45, cone=(100, 50))
    elif cat == "customer":
        # 1 plastic waiting chairs, 2 water/stim dispenser, 3 recovery cot
        for k in range(2):
            x = 52 + k * 13
            pc = R("4a5a6a" if k else "6a4a3a", 0.06)
            a.shaded_poly([(x, FLOOR - 12), (x + 10, FLOOR - 12), (x + 10, FLOOR - 9), (x, FLOOR - 9)], pc, 4.6, 2.4, 1, 1)
            a.shaded_poly([(x + 1, FLOOR - 24), (x + 9, FLOOR - 24), (x + 9, FLOOR - 12), (x + 1, FLOOR - 12)], pc, 4.2, 2.2, 1, 1)
            a.vline(x + 1, FLOOR - 9, FLOOR, C(MAT["steel"], 3))
            a.vline(x + 9, FLOOR - 9, FLOOR, C(MAT["steel"], 3))
        if lv >= 2:
            a.shaded_poly([(140, 92), (150, 92), (150, 130), (140, 130)], R("2a3a4a", 0.05), 4.4, 2.2, 1, 1)
            a.cylinder(141, 82, 8, 10, R("6a8a9a", 0.05), 1.5, 5.5)
            sc.emissive.rect(142, 100, 6, 4, GLOW("cyan", 3))
            sc.emissive.set(145, 110, GLOW("green", 6))
            props.fx("led", 145, 110, color="green", rate=0.4)
            sc.light(145, 102, pal.ACCENT["cyan"], 18, 0.2)
        if lv >= 3:
            cot = R("3a4a4a", 0.06)
            a.shaded_poly([(64, FLOOR + 34), (130, FLOOR + 34), (130, FLOOR + 40), (64, FLOOR + 40)], cot, 4.6, 2.4, 1, 1)
            a.shaded_poly([(66, FLOOR + 30), (82, FLOOR + 30), (82, FLOOR + 34), (66, FLOOR + 34)], MAT["white"], 4.6, 3, 1, 1)
            for lx in (66, 126):
                a.vline(lx, FLOOR + 40, FLOOR + 50, C(MAT["steel"], 3))
            a.shaded_poly([(84, FLOOR + 31), (128, FLOOR + 31), (128, FLOOR + 34), (84, FLOOR + 34)], R("5a5a6a", 0.06), 4.4, 3, 1, 1)


def _copy_scene(sc: LitScene) -> LitScene:
    n = LitScene(sc.w, sc.h, ambient=sc.ambient, bands=sc.bands)
    n.albedo.px = [row[:] for row in sc.albedo.px]
    n.emissive.px = [row[:] for row in sc.emissive.px]
    n.unlit.px = [row[:] for row in sc.unlit.px]
    n.lights = list(sc.lights)
    return n


def _changed_bbox(base: LitScene, sc: LitScene):
    x0, y0, x1, y1 = W, H, -1, -1
    for y in range(H):
        ra, rb = base.albedo.px[y], sc.albedo.px[y]
        ea, eb = base.emissive.px[y], sc.emissive.px[y]
        for x in range(W):
            if ra[x] != rb[x] or ea[x] != eb[x]:
                x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
    for l in sc.lights[len(base.lights):]:
        x0, y0 = min(x0, int(l.x - l.radius)), min(y0, int(l.y - l.radius))
        x1, y1 = max(x1, int(l.x + l.radius)), max(y1, int(l.y + l.radius))
    return max(0, x0), max(0, y0), min(W, x1 + 1), min(H, y1 + 1)


def overlay(cid: int, base_sc: LitScene, base_img, cat: str, level: int):
    """Returns (canvas_crop, x, y, fx_list) for one upgrade level."""
    props.reset_fx()
    sc = _copy_scene(base_sc)
    _upgrade_props(sc, cat, level, cid, random.Random(cid * 31 + level))
    fx = list(props.FX)
    box = _changed_bbox(base_sc, sc)
    if box[2] <= box[0]:
        return None, 0, 0, fx
    img = sc.render(box)
    from .lib import Canvas
    x0, y0, x1, y1 = box
    out = Canvas(x1 - x0, y1 - y0, fill=None)
    for y in range(y0, y1):
        for x in range(x0, x1):
            if img.px[y][x] != base_img.px[y][x]:
                out.px[y - y0][x - x0] = img.px[y][x]
    return out, x0, y0, fx


def generate(with_overlays=True):
    fx_all = {}
    overlays = {}
    for cid, spec in enumerate(CLINICS):
        props.reset_fx()
        with env._Size(W, H, FLOOR):
            sc = _base(cid)
            fx_all[spec["id"]] = list(props.FX)
            img = sc.render()
            img.save(f"clinic/clinic_{spec['id']}.png")
            if not with_overlays:
                continue
            for cat in UPGRADE_CATEGORIES:
                for lv in (1, 2, 3):
                    cv, x, y, fx = overlay(cid, sc, img, cat, lv)
                    if cv is None:
                        continue
                    rel = f"clinic/upgrades/{spec['id']}_{cat}_{lv}.png"
                    cv.save(rel)
                    overlays[f"{spec['id']}/{cat}/{lv}"] = {"path": "res://assets/sprites/" + rel, "x": x, "y": y, "fx": fx}
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data")
    with open(os.path.join(root, "clinic_fx.json"), "w") as f:
        json.dump({"_doc": "Animation anchors per clinic (art px), generated by tools/art/clinics.py",
                   "clinics": fx_all}, f, indent=1)
    if with_overlays:
        with open(os.path.join(root, "clinic_overlays.json"), "w") as f:
            json.dump({"_doc": "Upgrade overlay sprites per clinic/category/level (art px offsets), generated by tools/art/clinics.py",
                       "overlays": overlays}, f, indent=1)
    print("clinics: %d rooms, %d upgrade overlays" % (len(CLINICS), len(overlays)))
