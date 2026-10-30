"""Full-screen cutscene illustrations (art v4).

The cutscene stage is the screen between the letterbox bars: 1920x840 at
1080p. Each illustration is laid out on a 960x420 design grid and painted
at 2 px per design px, so it fills the stage at one texel per screen pixel,
the sharpest the game shows anything. Same kit (hd.Scene) and palette as
the rooms and streets, so a scene cut between a street view and an
illustration still reads as one world.

assets/sprites/cutscenes/<id>.png, used by data/cutscenes.json shots as
"backdrop": "scene:<id>".
"""
from __future__ import annotations

import math
import random

from .hd import PAL, Scene, hexc, mix, shade

W, H = 960, 420


def C(name, k=0.0):
    return shade(PAL[name], k) if k else PAL[name]


def rain(s: Scene, rng, n=900, color="ice", strength=0.16, slant=0.18, y1=H):
    """Fine rain streaks (one hi-res px wide) in the emissive buffer."""
    col = C(color) * strength
    for _ in range(n):
        x, y = rng.uniform(-40, W), rng.uniform(-10, y1)
        ln = rng.uniform(4, 11)
        s.fline(x, y, x + ln * slant, y + ln, col * rng.uniform(0.5, 1.0), "emissive")


def windows(s: Scene, rng, x, top, w, bottom, lit_from, p, cols=("amber", "tungsten", "cyan", "fluoro"), dim=-0.35):
    """Window grid of a tower: lit only above `lit_from` (the waterline
    city has its lights up high), with frames and the odd silhouette."""
    for wy in range(int(top) + 6, int(bottom) - 3, 7):
        for wx in range(int(x) + 3, int(x + w) - 4, 6):
            if wy < lit_from and rng.random() < p:
                c = shade(C(rng.choice(cols)), dim + rng.uniform(-0.15, 0.1))
                s.glow(wx, wy, 3.5, 3, c, 0.8)
                s.fhline(wx, wx + 3.5, wy, shade(c, 0.3), "emissive")
                if rng.random() < 0.08:
                    s.scale_buf(wx + 1, wy + 1, 1.5, 2, 0.15)
            else:
                Y, X = min(s.rh - 1, int(wy * s.res)), min(s.rw - 1, max(0, int(wx * s.res)))
                s.rect(wx, wy, 3.5, 3, shade(s.albedo[Y, X], -0.35))


def tower(s: Scene, rng, x, top, w, base_y, col, lit_from, p):
    s.occlude(x, top, w, base_y - top)
    s.rect(x, top, w, base_y - top, col)
    s.noise(x, top, w, base_y - top, 0.05, seed=int(x))
    s.fvline(x, top, base_y, shade(col, 0.25))
    s.fvline(x + w - 0.5, top, base_y, shade(col, -0.4))
    windows(s, rng, x, top, w, base_y, lit_from, p)
    # Crown: setbacks, antennas, an aviation light.
    s.rect(x + w * 0.2, top - 6, w * 0.6, 6, shade(col, 0.05))
    s.fhline(x + w * 0.2, x + w * 0.8, top - 6, shade(col, 0.35))
    ax = x + w * rng.uniform(0.3, 0.7)
    s.vline(ax, top - 26, top - 6, shade(col, 0.2), t=0.5)
    s.gpx(ax, top - 27, C("red"), 1.0)
    s.light(ax, top - 27, C("red") * 0.6, 18, 0.4)


# =============================================================================
# The flooded city: towers lit above the waterline, the Sump dark below.
# =============================================================================

def towers() -> Scene:
    rng = random.Random(901)
    s = Scene(W, H, ambient=(0.30, 0.30, 0.42), seed=901)
    water = 318
    s.haze, s.haze_color = 0.35, hexc("261a3c")
    s.vgrad(0, 0, W, water, hexc("04040a"), hexc("2a1c40"))
    for k in range(140):  # a few stars through the smog
        s.gpx(rng.uniform(0, W), rng.uniform(0, 140), C("fluoro"), rng.uniform(0.15, 0.4), t=0.5)
    # Far row, mid row, near row of towers.
    for depth, (n, hmin, hmax, wmin, wmax, k, p) in enumerate(((26, 120, 240, 16, 34, -0.15, 0.25),
                                                                (16, 60, 200, 26, 52, -0.35, 0.35),
                                                                (7, 20, 120, 46, 80, -0.55, 0.45))):
        xs = sorted(rng.uniform(-30, W) for _ in range(n))
        for x in xs:
            w = rng.uniform(wmin, wmax)
            top = rng.uniform(hmin, hmax)
            col = shade(hexc("3a2a48"), k + rng.uniform(-0.08, 0.06))
            tower(s, rng, x, top, w, water, col, water - 70 + depth * 10, p)
    # Holo ads on the near towers.
    for (hx, hy, txt, c) in ((120, 150, "LYRA", "cyan"), (700, 110, "MERIDIAN", "pink"), (430, 190, "CREDIT", "amber")):
        s.box(hx - 4, hy - 4, len(txt) * 6 + 6, 13, C("void"), 0.1)
        s.glow(hx - 2, hy - 2, len(txt) * 6 + 2, 9, shade(C(c), -0.7), 1.0)
        s.text(hx, hy, txt, C(c), big=True, neon=True)
        s.light(hx + len(txt) * 3, hy + 4, C(c), 140, 0.55)
    # The waterline: half-drowned lower floors, a dark wall of the Sump.
    s.rect(0, water - 8, W, 8, hexc("0c0a12"))
    for x in range(0, W, 9):
        if rng.random() < 0.3:
            s.gpx(x + rng.uniform(0, 6), water - 4, C(rng.choice(["amber", "sodium"])), 0.5)
    # Black water mirroring the lit towers, with ripples and a boat light.
    s.vgrad(0, water, W, H - water, hexc("0a0a14"), hexc("05050a"))
    s.noise(0, water, W, H - water, 0.12, seed=7, scale=1)
    s.set_gloss(0, water, W, H - water, 0.75)
    s.floor_y = water
    for k in range(60):
        y = rng.uniform(water + 4, H - 2)
        x = rng.uniform(0, W)
        s.set_gloss(x, y, rng.uniform(20, 90), 0.5, 0.2)
    s.box(560, 360, 46, 6, hexc("12121a"), 0.15)
    s.poly([(560, 360), (606, 360), (612, 356), (556, 356)], hexc("1a1a24"))
    s.glow(600, 352, 2, 2, C("tungsten"), 1.0)
    s.light(601, 353, C("tungsten"), 90, 0.6)
    s.vline(601, 344, 352, C("steel2"), t=0.5)
    rain(s, rng, 1200, "ice", 0.12, 0.12)
    return s


# =============================================================================
# The stairs down to the clinic door: someone already on them.
# =============================================================================

def stairs() -> Scene:
    rng = random.Random(902)
    s = Scene(W, H, ambient=(0.26, 0.25, 0.34), seed=902)
    s.haze, s.haze_color = 0.25, hexc("1a1426")
    s.vgrad(0, 0, W, H, hexc("0a0a10"), hexc("15131c"))
    # Looking down the flight: the door small and far at the bottom of the
    # stairs (top of the frame), the steps widening towards the viewer.
    dx, dy, dw, dh = 444, 62, 72, 104
    top_y = dy + dh
    n = 16
    for i in range(n):
        u0, u1 = i / n, (i + 1) / n
        y0 = top_y + (H - top_y) * u0 ** 1.6
        y1 = top_y + (H - top_y) * u1 ** 1.6
        hw0 = 50 + 190 * u0 ** 1.2
        x0, x1 = 480 - hw0, 480 + hw0
        s.rect(x0, y0, x1 - x0, y1 - y0 + 0.5, shade(C("concrete1"), -0.3 + u0 * 0.2))
        nose = max(0.5, (y1 - y0) * 0.18)
        s.rect(x0, y0, x1 - x0, nose, shade(C("concrete2"), 0.05 + u0 * 0.15))
        s.fhline(x0, x1, y0 + nose, C("concrete0", -0.4))
        s.noise(x0, y0, x1 - x0, y1 - y0, 0.1, seed=i, scale=1)
        if rng.random() < 0.45 and y1 - y0 > 4:  # litter on the treads
            lx = rng.uniform(x0 + 10, x1 - 20)
            s.rect(lx, y0 + nose + 1, rng.uniform(3, 8) * (0.5 + u0), 1.2 + u0,
                   shade(C(rng.choice(["bone", "rust2", "steel3"])), -0.3))
    # Side walls close in on the flight.
    s.poly([(0, 0), (300, 0), (430, top_y), (240, H), (0, H)], shade(C("concrete1"), -0.12))
    s.poly([(660, 0), (W, 0), (W, H), (720, H), (530, top_y)], shade(C("concrete1"), -0.22))
    s.noise(0, 0, 440, H, 0.08, seed=11, scale=1)
    s.noise(520, 0, 440, H, 0.08, seed=12, scale=1)
    for (px_, py_, c, txt) in ((60, 120, "pink", "CHROME"), (180, 70, "cyan", "LINK"), (760, 140, "amber", "WORK"),
                               (850, 50, "pink", "FIX")):
        s.box(px_, py_, 70, 96, shade(C(c), -0.65), 0.1)
        s.disc(px_ + 35, py_ + 34, 18, shade(C(c), -0.4))
        s.text(px_ + 6, py_ + 66, txt, shade(C(c), 0.05), "albedo", big=True)
        for j in range(4):
            s.fhline(px_ + 6, px_ + 60 - j * 8, py_ + 80 + j * 3, shade(C(c), -0.3))
        s.poly([(px_ + 52, py_ + 96), (px_ + 70, py_ + 78), (px_ + 70, py_ + 96)], shade(C("concrete1"), -0.12))
    for _ in range(16):  # wet streaks down the walls
        sx = rng.choice((rng.uniform(10, 300), rng.uniform(680, 950)))
        for k in range(rng.randint(40, 200)):
            s.fpx(int(sx * s.res + math.sin(k * 0.2) * 2), int((10 + k) * s.res), shade(C("concrete0"), -0.3))
    # Handrail down the left wall, converging on the door.
    s.line(250, H, 436, top_y - 30, C("steel3"), t=1.5)
    s.fline(250, H - 1, 436, top_y - 31, C("steel5"))
    # The clinic door: steel, cyan cross over it, red work light, light under it.
    s.rect(dx - 6, dy - 8, dw + 12, dh + 8, C("steel0"))
    s.box(dx, dy, dw, dh, C("steel2"), 0.2)
    s.panel(dx + 5, dy + 6, dw - 10, 40, C("steel2", -0.05), seams=False)
    s.panel(dx + 5, dy + 54, dw - 10, 44, C("steel2", -0.05), seams=False)
    s.box(dx + dw - 14, dy + 48, 7, 4, C("steel4"), 0.3)
    s.label(dx + 16, dy + 18, 40, 10, C("bone", -0.2), text="CLINIC")
    s.glow(dx + 2, dy + dh - 1.5, dw - 4, 1.5, C("tungsten"), 0.9)
    s.light(dx + dw / 2, dy + dh, C("tungsten"), 80, 0.6, cone=(0, 1, 70))
    s.box(dx + dw / 2 - 10, dy - 34, 20, 20, C("void"), 0.1)
    s.glow(dx + dw / 2 - 3, dy - 31, 6, 14, C("cyan"), 1.0)
    s.glow(dx + dw / 2 - 7, dy - 27, 14, 6, C("cyan"), 1.0)
    s.light(dx + dw / 2, dy - 24, C("cyan"), 300, 0.95)
    s.glow(dx + 4, dy - 6, dw - 8, 2, C("red"), 0.9)
    s.light(dx + dw / 2, dy - 4, C("red"), 170, 0.6)
    # The figure halfway down: hooded, backlit by the cross, one red optic.
    fx, fb = 486, 318  # feet line
    hgt = 150
    body = hexc("08080c")
    hy = fb - hgt
    s.disc(fx, hy + 10, 11, body)
    s.poly([(fx - 13, hy + 18), (fx + 13, hy + 18), (fx + 28, hy + 60), (fx + 32, fb - 58), (fx - 32, fb - 58),
            (fx - 28, hy + 60)], body)
    s.rect(fx - 22, fb - 60, 16, 56, body)
    s.rect(fx + 6, fb - 60, 16, 52, body)
    s.poly([(fx - 24, fb - 4), (fx - 4, fb - 4), (fx - 2, fb + 2), (fx - 26, fb + 2)], body)
    s.poly([(fx + 4, fb - 8), (fx + 24, fb - 8), (fx + 26, fb - 2), (fx + 2, fb - 2)], body)
    for k in range(5):  # coat folds
        s.fline(fx - 20 + k * 10, hy + 40, fx - 26 + k * 13, fb - 60, hexc("161824"))
    for sx, side in ((fx + 12, 1), (fx - 12, -1)):  # rim light down both shoulders
        s.fline(sx, hy + 18, sx + side * 16, hy + 60, C("cyan", -0.1))
        s.fline(sx + side * 16, hy + 60, sx + side * 20, fb - 58, C("cyan", -0.4))
        s.fline(sx + side * 8, fb - 58, sx + side * 10, fb - 6, C("cyan", -0.55))
    for k in range(16):  # hood rim
        a = math.pi * (1.1 + 0.8 * k / 15)
        s.fpx(int((fx + math.cos(a) * 11) * s.res), int((hy + 10 + math.sin(a) * 11) * s.res), C("cyan", -0.1))
    s.gpx(fx + 4, hy + 12, C("red"), 1.0, t=1.5)
    s.light(fx + 4, hy + 12, C("red"), 26, 0.6)
    # The figure's shadow falls towards the viewer.
    s.poly([(fx - 24, fb + 2), (fx + 26, fb + 2), (fx + 60, H), (fx - 50, H)], C("void"))
    s.darken(fx - 50, fb + 2, 110, H - fb, 0.85)
    # Overhead: a caged bulb above the viewer, just in frame.
    s.vline(600, 0, 12, C("steel1"), t=0.5)
    s.disc(600, 16, 4, C("tungsten"), "emissive")
    for k in range(-4, 5, 2):
        s.fline(600 + k, 12, 600 + k * 1.2, 20, C("steel2"))
    s.light(600, 20, C("tungsten"), 260, 0.55)
    rain(s, rng, 260, "ice", 0.08, 0.1, 140)
    return s


# =============================================================================
# Cars at the kerb in the rain.
# =============================================================================

def car(s: Scene, x, y, w, col, stripe=None, plates=True, face="right"):
    """A long, low sedan seen side-on (design px, y = ground line)."""
    h = w * 0.22
    body = col
    s.poly([(x, y - h * 0.3), (x + w * 0.06, y - h * 0.62), (x + w * 0.3, y - h * 0.68), (x + w * 0.4, y - h),
            (x + w * 0.72, y - h), (x + w * 0.82, y - h * 0.66), (x + w * 0.98, y - h * 0.6), (x + w, y - h * 0.3),
            (x + w, y - h * 0.12), (x, y - h * 0.12)], body)
    # Glass: dark, with a lit reflection band.
    s.poly([(x + w * 0.42, y - h * 0.94), (x + w * 0.7, y - h * 0.94), (x + w * 0.78, y - h * 0.68),
            (x + w * 0.34, y - h * 0.68)], hexc("06070c"))
    s.fline(x + w * 0.44, y - h * 0.9, x + w * 0.68, y - h * 0.9, C("steel4"))
    s.vline(x + w * 0.56, y - h * 0.94, y - h * 0.68, shade(body, -0.2), t=1.5)
    # Body line, door seams, chrome trim.
    s.fhline(x + w * 0.03, x + w * 0.98, y - h * 0.55, shade(body, 0.35))
    s.fline(x + w * 0.4, y - h, x + w * 0.72, y - h, shade(body, 0.6))  # roof highlight
    s.fline(x + w * 0.06, y - h * 0.62, x + w * 0.3, y - h * 0.68, shade(body, 0.45))  # bonnet
    s.fline(x + w * 0.82, y - h * 0.66, x + w * 0.98, y - h * 0.6, shade(body, 0.45))
    s.fhline(x + w * 0.02, x + w * 0.99, y - h * 0.32, shade(body, -0.35))
    for dxx in (0.36, 0.56, 0.76):
        s.fvline(x + w * dxx, y - h * 0.66, y - h * 0.16, shade(body, -0.45))
    if stripe is not None:
        s.rect(x + w * 0.04, y - h * 0.47, w * 0.92, 2, stripe)
        s.fhline(x + w * 0.04, x + w * 0.96, y - h * 0.47, shade(stripe, 0.4))
    # Wheels.
    for wx in (x + w * 0.2, x + w * 0.82):
        s.disc(wx, y - h * 0.14, h * 0.26, hexc("050507"))
        s.disc(wx, y - h * 0.14, h * 0.15, C("steel2"))
        s.disc(wx, y - h * 0.14, h * 0.05, C("steel4"))
        s.fpx(int((wx - h * 0.1) * s.res), int((y - h * 0.24) * s.res), C("steel5"))
    # Lights: headlights forward, tail lights behind, both onto the wet road.
    fx_, bx_ = (x + w, x) if face == "right" else (x, x + w)
    sgn = 1 if face == "right" else -1
    s.glow(fx_ - sgn * 6 - (3 if sgn > 0 else 0), y - h * 0.5, 4, 3, C("fluoro"), 1.0)
    s.light(fx_ + sgn * 30, y - h * 0.45, C("fluoro"), 180, 0.9, cone=(sgn, 0.12, 22), falloff=1.1)
    s.glow(bx_ + (0 if sgn > 0 else -4), y - h * 0.46, 4, 3, C("red"), 1.0)
    s.light(bx_ - sgn * 10, y - h * 0.46, C("red"), 70, 0.6)
    s.disc(x + w * 0.5, y + 1, 0.1, body)


def cars() -> Scene:
    rng = random.Random(903)
    s = Scene(W, H, ambient=(0.24, 0.23, 0.32), seed=903)
    ground = 300
    s.haze, s.haze_color = 0.3, hexc("1c1428")
    s.vgrad(0, 0, W, ground, hexc("07060c"), hexc("1c1426"))
    # Tenement front behind: lit windows, a stair door, signs.
    for bx in range(-20, W, 140):
        col = shade(C("concrete1"), rng.uniform(-0.25, 0.0))
        top = rng.uniform(0, 60)
        tower(s, rng, bx, top, 136, ground - 40, col, ground, 0.14)
    s.rect(0, ground - 40, W, 40, C("concrete0"))
    s.noise(0, ground - 40, W, 40, 0.1, seed=3)
    s.rect(400, ground - 96, 60, 56, C("void"))
    s.glow(406, ground - 94, 48, 2, C("tungsten"), 0.7)
    s.box(420, ground - 130, 20, 20, C("void"), 0.1)
    s.glow(427, ground - 127, 6, 14, C("cyan"), 1.0)
    s.glow(423, ground - 123, 14, 6, C("cyan"), 1.0)
    s.light(430, ground - 120, C("cyan"), 200, 0.7)
    # Kerb and wet road.
    s.rect(0, ground, W, 5, C("concrete2"))
    s.fhline(0, W, ground, C("concrete3"))
    s.vgrad(0, ground + 5, W, H - ground - 5, hexc("0e0c14"), hexc("16131c"))
    s.noise(0, ground + 5, W, H - ground - 5, 0.12, seed=5, scale=1)
    s.set_gloss(0, ground + 5, W, H, 0.85)
    s.floor_y = ground + 5
    # Three cars in Rustline colours, nose to tail.
    rust = shade(C("rust2"), 0.1)
    for k, cx in enumerate((40, 330, 620)):
        car(s, cx, ground + 70, 290, shade(hexc("262a34"), k * 0.03), stripe=rust, face="left")
    # Street lamps: highlights on the roofs and a pool on the road.
    for lx in (180, 760):
        s.rect(lx, 40, 3, ground - 40, C("steel1"))
        s.hline(lx, lx + 24, 40, C("steel2"))
        s.glow(lx + 14, 42, 10, 2, C("sodium"), 1.0)
        s.light(lx + 18, 50, C("sodium"), 320, 1.0, cone=(0, 1, 50), falloff=1.2)
    # Crew members by the cars: still silhouettes, one with a light.
    for k, (px_, h) in enumerate(((300, 62), (590, 66), (900, 60))):
        b = hexc("07070a")
        s.disc(px_, ground + 70 - h, 5, b)
        s.poly([(px_ - 8, ground + 70 - h + 4), (px_ + 8, ground + 70 - h + 4), (px_ + 11, ground + 70 - 22),
                (px_ - 11, ground + 70 - 22)], b)
        s.rect(px_ - 8, ground + 48, 6, 22, b)
        s.rect(px_ + 2, ground + 48, 6, 22, b)
        s.fline(px_ + 8, ground + 70 - h + 4, px_ + 11, ground + 48, shade(rust, 0.2))
    s.gpx(588, ground + 18, C("amber"), 1.0, t=1)  # a cigarette
    rain(s, rng, 1500, "ice", 0.13, 0.15)
    return s


# =============================================================================
# The table, the lamp, the tray of tools.
# =============================================================================

def tool_tray(s: Scene, x, y, w, h, rng):
    s.rect(x + 3, y + 4, w, h, C("void"))
    s.box(x, y, w, h, C("steel3"), 0.3)
    s.box(x + 3, y + 3, w - 6, h - 6, C("steel2"), -0.1, True, -0.2)
    for X in range(int((x + 4) * s.res), int((x + w - 4) * s.res), 3):
        s.fvline(X / s.res, y + 4, y + h - 4, C("steel2", 0.07))
    ty = y + 8
    while ty < y + h - 8:
        kind = rng.choice(("scalpel", "forceps", "clamp", "probe"))
        tx = x + 10 + rng.uniform(0, 8)
        ln = rng.uniform(w * 0.5, w * 0.75)
        if kind == "scalpel":
            s.line(tx, ty, tx + ln * 0.75, ty, C("steel4"), t=2)
            s.fline(tx, ty - 0.5, tx + ln * 0.75, ty - 0.5, C("white"))
            s.poly([(tx + ln * 0.75, ty - 1), (tx + ln, ty), (tx + ln * 0.95, ty + 1.6), (tx + ln * 0.75, ty + 1.4)],
                   C("steel5"))
        elif kind == "forceps":
            s.line(tx, ty - 2, tx + ln, ty, C("steel4"), t=1.2)
            s.line(tx, ty + 2, tx + ln, ty, C("steel4"), t=1.2)
            s.fline(tx, ty - 2.5, tx + ln, ty - 0.5, C("white"))
        elif kind == "clamp":
            s.disc(tx + 3, ty - 3, 3, C("steel4"))
            s.disc(tx + 3, ty + 3, 3, C("steel4"))
            s.disc(tx + 3, ty - 3, 1.6, C("steel1"))
            s.disc(tx + 3, ty + 3, 1.6, C("steel1"))
            s.line(tx + 6, ty - 2, tx + ln, ty, C("steel4"), t=1.2)
            s.line(tx + 6, ty + 2, tx + ln, ty, C("steel4"), t=1.2)
        else:
            s.line(tx, ty, tx + ln, ty, C("steel4"), t=1.0)
            s.disc(tx + ln, ty, 1.5, C("steel5"))
        s.fpx(int((tx + ln * 0.3) * s.res), int((ty - 1) * s.res), C("white"))
        ty += rng.uniform(10, 14)


def table() -> Scene:
    rng = random.Random(904)
    s = Scene(W, H, ambient=(0.34, 0.32, 0.38), seed=904)
    s.haze, s.haze_color = 0.2, hexc("201a24")
    # Tiled back wall, half the tiles cracked, a drain in the floor.
    s.rect(0, 0, W, 250, C("tile1", -0.2))
    for ty in range(0, 250, 16):
        for tx in range(0, W, 16):
            off = (ty // 16 % 2) * 8
            s.darken(tx + off + 0.5, ty + 0.5, 15, 15, rng.uniform(0.85, 1.05))
            s.fhline(tx + off, tx + off + 16, ty, C("tile0", -0.4))
            s.fvline(tx + off, ty, ty + 16, C("tile0", -0.4))
            s.fpx(int((tx + off + 2) * s.res), int((ty + 2) * s.res), C("tile2", 0.2))
            if rng.random() < 0.06:
                cx, cy = tx + off + rng.uniform(2, 14), ty + rng.uniform(2, 14)
                for _ in range(4):
                    nx, ny = cx + rng.uniform(-5, 5), cy + rng.uniform(-5, 5)
                    s.fline(cx, cy, nx, ny, C("tile0", -0.5))
                    cx, cy = nx, ny
    s.noise(0, 0, W, 250, 0.06, seed=1)
    for _ in range(14):  # grime streaks under the grout
        sx = rng.uniform(0, W)
        s.darken(sx, rng.uniform(40, 120), rng.uniform(1, 3), rng.uniform(40, 130), 0.75)
    s.vgrad(0, 250, W, H - 250, C("concrete1", -0.3), C("concrete0", -0.3))
    s.noise(0, 250, W, H - 250, 0.1, seed=2, scale=1)
    s.disc(140, 380, 14, C("void"))
    for k in range(6):
        s.fhline(128, 152, 372 + k * 3, C("steel2"))
    s.set_gloss(0, 251, W, H, 0.2)
    s.floor_y = 251
    # The table: steel top with a worn pad, the lamp hanging over it.
    tx0, tx1, ty = 260, 700, 236
    s.box(tx0, ty, tx1 - tx0, 14, C("steel3"), 0.25)
    s.box(tx0 + 12, ty - 10, tx1 - tx0 - 24, 11, C("rust1", -0.15), 0.2)
    s.noise(tx0 + 12, ty - 10, tx1 - tx0 - 24, 11, 0.12, seed=3)
    for X in range(int((tx0 + 14) * s.res), int((tx1 - 14) * s.res), 4):
        s.fpx(X, int((ty - 9) * s.res), shade(C("rust1"), 0.25))
    for k in range(8):  # old stains on the pad
        s.disc(rng.uniform(tx0 + 40, tx1 - 40), ty - rng.uniform(3, 8), rng.uniform(1, 4), C("blood", -0.4))
    for lx in (tx0 + 20, tx1 - 30):
        s.box(lx, ty + 14, 10, 120, C("steel2"), 0.2)
        s.box(lx - 6, ty + 130, 22, 5, C("steel1"), 0.2)
    for sx in (tx0 + 110, tx1 - 130):  # straps
        s.rect(sx, ty - 11, 12, 13, C("void"))
        s.box(sx + 2, ty - 7, 8, 5, C("steel4"), 0.3)
    # The tray of tools on a stand to the right.
    s.box(740, 238, 8, 120, C("steel2"), 0.2)
    s.box(722, 352, 44, 5, C("steel1"), 0.2)
    tool_tray(s, 700, 186, 160, 56, rng)
    # Bottles and a bin on the left.
    for k in range(5):
        s.bottle(150 + k * 14, 204, 30, shade(C(["amber", "ice", "teal", "amber", "red"][k]), -0.45), 9, C("steel4"))
    s.box(140, 236, 90, 8, C("steel2"), 0.2)
    s.box(178, 244, 8, 110, C("steel1"), 0.2)
    s.box(40, 300, 50, 70, C("rust1", -0.2), 0.2)
    s.label(52, 320, 26, 12, C("yellow", -0.4), text="SHARP")
    # The lamp: a cone of hard light, the brightest thing in the room.
    lx, ly = 480, 92
    s.vline(lx, 0, ly - 22, C("steel2"), t=1)
    s.cable(lx + 2, 0, lx + 160, 0, 30, C("void"), 1)
    s.poly([(lx - 50, ly), (lx + 50, ly), (lx + 26, ly - 24), (lx - 26, ly - 24)], C("steel2"))
    s.poly([(lx - 26, ly - 24), (lx + 26, ly - 24), (lx + 22, ly - 20), (lx - 22, ly - 20)], C("steel4"))
    s.fline(lx - 50, ly, lx - 26, ly - 24, C("steel5"))
    s.glow(lx - 46, ly, 92, 3, C("white"), 1.0)
    s.glow(lx - 40, ly + 3, 80, 1, C("tungsten"), 0.8)
    s.light(lx, ly + 10, C("tungsten") * 1.15, 320, 1.5, cone=(0, 1, 42), falloff=1.0)
    s.light(lx, ly + 150, C("tungsten") * 0.8, 380, 0.5)
    for k in range(40):  # dust in the beam
        u = rng.random()
        yy = ly + 10 + u * 140
        xx = lx + rng.uniform(-1, 1) * (20 + u * 90)
        s.gpx(xx, yy, C("tungsten"), rng.uniform(0.1, 0.3), t=0.5)
    s.light(780, 140, C("cyan") * 0.6, 260, 0.3)
    return s


# =============================================================================
# The lattice in a steel tray: a nest of grey hair, still warm.
# =============================================================================

def lattice() -> Scene:
    rng = random.Random(905)
    s = Scene(W, H, ambient=(0.26, 0.26, 0.32), seed=905)
    s.rect(0, 0, W, H, C("steel1", -0.3))
    s.noise(0, 0, W, H, 0.08, seed=1, scale=1)
    # A big kidney tray seen from above, brushed steel with a rolled lip.
    cx, cy = 480, 220
    for r_, c in ((230, C("steel0")), (224, C("steel4")), (218, C("steel3")), (204, C("steel2"))):
        s.poly([(cx + math.cos(a / 40 * 2 * math.pi) * r_ * (1.15 - 0.25 * math.cos(a / 40 * 2 * math.pi) ** 2),
                 cy + math.sin(a / 40 * 2 * math.pi) * r_ * 0.62
                 - 30 * math.cos(a / 40 * 2 * math.pi) ** 2 * (r_ / 230)) for a in range(40)], c)
    # The lattice: hundreds of fine grey filaments curling out from a node.
    nx, ny = 470, 230
    s.disc(nx, ny, 16, C("steel1"))
    s.disc(nx, ny, 12, C("steel3"))
    s.disc(nx - 4, ny - 4, 4, C("steel5"))
    for k in range(260):
        a = rng.uniform(0, 2 * math.pi)
        ln = rng.uniform(40, 170)
        curl = rng.uniform(-0.03, 0.03)
        x, y = nx + math.cos(a) * 10, ny + math.sin(a) * 6
        col = shade(C("steel4"), rng.uniform(-0.3, 0.25))
        for t in range(int(ln)):
            a += curl + math.sin(t * 0.15 + k) * 0.03
            nx2, ny2 = x + math.cos(a) * 1.0, y + math.sin(a) * 0.62
            s.fline(x, y, nx2, ny2, col)
            x, y = nx2, ny2
        if rng.random() < 0.3:  # tiny contact beads at the tips
            s.disc(x, y, 0.8, C("steel5"))
    for k in range(18):  # a few still glowing faintly
        a = rng.uniform(0, 2 * math.pi)
        r_ = rng.uniform(20, 120)
        s.gpx(nx + math.cos(a) * r_, ny + math.sin(a) * r_ * 0.6, C("cyan"), rng.uniform(0.3, 0.7), t=0.5)
    # Blood and saline pooled in the tray, a pair of forceps resting on the lip.
    for k in range(5):
        bx, by, br = rng.uniform(340, 620), rng.uniform(180, 290), rng.uniform(3, 8)
        for j in range(5):
            s.disc(bx + rng.uniform(-br, br), by + rng.uniform(-br, br) * 0.6, br * rng.uniform(0.4, 0.8),
                   shade(C("blood"), -0.2))
        s.fpx(int((bx - br * 0.3) * s.res), int((by - br * 0.3) * s.res), C("blood", 0.5))
    s.line(600, 90, 760, 160, C("steel4"), t=2)
    s.line(606, 86, 764, 156, C("steel4"), t=2)
    s.fline(600, 89, 760, 159, C("white"))
    s.light(380, 60, C("tungsten") * 1.1, 420, 1.2, falloff=1.1)
    s.light(780, 360, C("cyan") * 0.5, 300, 0.4)
    return s


# =============================================================================
# The notes wall: names, dates, the same scar behind the same left ear.
# =============================================================================

def wall_notes() -> Scene:
    rng = random.Random(906)
    s = Scene(W, H, ambient=(0.26, 0.25, 0.3), seed=906)
    s.rect(0, 0, W, H, C("concrete1", -0.1))
    s.noise(0, 0, W, H, 0.08, seed=1, scale=1)
    s.noise(0, 0, W, H, 0.06, seed=2, scale=2)
    pins = []
    for _ in range(70):
        w, h = rng.choice(((34, 24), (40, 30), (28, 36), (50, 34), (24, 24)))
        x, y = rng.uniform(20, W - 70), rng.uniform(18, H - 60)
        kind = rng.random()
        if kind < 0.3:  # photo: a face crop with a circled scar
            s.rect(x + 2, y + 2, w, h, C("void"))
            s.box(x, y, w, h, C("bone", 0.1), 0.05)
            s.rect(x + 2, y + 2, w - 4, h - 8, shade(C("skin"), rng.uniform(-0.6, -0.3)))
            s.disc(x + w * 0.45, y + h * 0.38, min(w, h) * 0.22, shade(C("skin"), -0.2))
            s.disc(x + w * 0.7, y + h * 0.35, 3, C("red"), "albedo")
            s.disc(x + w * 0.7, y + h * 0.35, 2.2, shade(C("skin"), -0.2))
            s.ftext(x + 2, y + h - 5, rng.choice(["#14", "#07", "#22", "#31", "#09"]), C("void"), "albedo")
        else:  # handwritten note, index card or printout
            paper = shade(C(rng.choice(["bone", "bone", "yellow", "white"])), rng.uniform(-0.35, -0.1))
            s.rect(x + 1.5, y + 2, w, h, C("void"))
            s.box(x, y, w, h, paper, 0.05)
            for k in range(3, int(h) - 3, 3):
                ln = rng.uniform(0.35, 0.9) * (w - 6)
                for j in range(int(ln * s.res)):
                    if rng.random() < 0.8:
                        s.fpx(int((x + 3) * s.res) + j, int((y + k) * s.res + math.sin(j * 0.9) * 0.6),
                              shade(C("blue" if rng.random() < 0.7 else "red"), -0.65))
        px_, py_ = x + w / 2, y + 2
        s.disc(px_, py_, 1.3, C(rng.choice(["red", "yellow", "cyan"])))
        s.fpx(int((px_ - 0.6) * s.res), int((py_ - 0.6) * s.res), C("white"))
        pins.append((px_, py_))
    # Red string between pins (sagging).
    for _ in range(26):
        a, b = rng.sample(pins, 2)
        s.cable(a[0], a[1], b[0], b[1], rng.uniform(2, 10), shade(C("red"), -0.3), 0.5)
    # A big printed part number at the centre, circled three times.
    s.box(380, 160, 200, 80, C("white", -0.2), 0.05)
    s.text(396, 182, "LTC-7", C("void"), "albedo", big=True)
    s.ftext(396, 206, "LATTICE PN 0447-K", C("void"), "albedo")
    s.ftext(396, 214, "LYRA ANNEX TRIAL", C("void"), "albedo")
    for k in range(3):
        for t in range(220):
            a = t / 220 * 2 * math.pi
            s.fpx(int((478 + math.cos(a) * (112 + k * 3)) * s.res), int((200 + math.sin(a) * (50 + k * 2)) * s.res),
                  shade(C("red"), -0.1))
    # A desk lamp from below-left and the room dark beyond.
    s.light(160, 460, C("tungsten") * 1.1, 620, 1.2, cone=(0.6, -1, 50), falloff=1.0)
    s.light(900, -40, C("cyan") * 0.5, 400, 0.3)
    return s


# =============================================================================
# Cash in a drawer under the lamp.
# =============================================================================

def money() -> Scene:
    rng = random.Random(907)
    s = Scene(W, H, ambient=(0.3, 0.27, 0.3), seed=907)
    s.rect(0, 0, W, H, C("rust0", -0.2))
    for k in range(int(W * s.res)):  # desk wood grain
        if k % 2 == 0:
            for Y in range(0, H * s.res):
                if math.sin(Y * 0.31 + math.sin(k * 0.004 + Y * 0.002) * 4) > 0.93:
                    s.fpx(k, Y, C("rust1", -0.1))
    # The open drawer.
    dx0, dy0, dx1, dy1 = 230, 120, 730, 380
    s.box(dx0 - 14, dy0 - 14, dx1 - dx0 + 28, dy1 - dy0 + 28, C("rust1"), 0.25)
    s.rect(dx0, dy0, dx1 - dx0, dy1 - dy0, C("rust0", -0.5))
    s.box(dx0 + (dx1 - dx0) / 2 - 30, dy1 + 2, 60, 8, C("steel3"), 0.3)
    # Bundles of cash, banded, a few loose notes.
    note = hexc("5a7a5a")
    for k in range(14):
        bx = dx0 + 20 + (k % 5) * 92 + rng.uniform(-6, 6)
        by = dy0 + 20 + (k // 5) * 80 + rng.uniform(-6, 6)
        for j in range(4):  # stack edges
            s.box(bx, by - j * 2, 80, 40, shade(note, -0.2 + j * 0.06), 0.1)
        s.rect(bx, by - 6, 80, 40, shade(note, 0.05))
        s.rect(bx + 4, by - 2, 72, 32, shade(note, -0.05))
        s.disc(bx + 40, by + 14, 9, shade(note, 0.15))
        s.ftext(bx + 6, by + 1, "100", shade(note, -0.5), "albedo")
        s.ftext(bx + 62, by + 24, "100", shade(note, -0.5), "albedo")
        s.rect(bx + 34, by - 6, 12, 40, C("bone", -0.1))  # band
        s.fvline(bx + 34, by - 6, by + 34, C("bone", 0.2))
    # A pistol and a pack of cigarettes on the desk beside the drawer.
    s.poly([(780, 300), (880, 300), (884, 312), (820, 314), (812, 344), (794, 344), (796, 314), (780, 312)],
           C("steel2"))
    s.fhline(782, 880, 301, C("steel4"))
    s.box(60, 300, 60, 34, C("red", -0.55), 0.2)
    s.label(66, 306, 48, 10, C("white", -0.2), text="KOBE")
    s.light(420, 120, C("tungsten") * 1.15, 520, 1.3, falloff=1.1)
    return s


SCENES = {"towers": towers, "stairs": stairs, "cars": cars, "table": table, "lattice": lattice,
          "wall_notes": wall_notes, "money": money}


def generate(only=None):
    for name, fn in SCENES.items():
        if only and name not in only:
            continue
        fn().save(f"cutscenes/{name}.png")
    print("cutscenes: %d HD illustrations (%dx%d)" % (len(SCENES), W * 2, H * 2))
