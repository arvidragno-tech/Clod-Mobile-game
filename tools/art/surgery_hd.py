"""HD operating-table backdrops (art v4): the surround of the surgical field.

Laid out in field units (340x270, the 160x160 field sits at 90..250 x
55..215) and rendered at 4 px per unit, the same density as the anatomy
and implant art, so at the default zoom every texel is one screen pixel.

Three levels follow the clinic: 0 a wooden kitchen table under a work lamp
(back-alley), 1 a steel table with a vitals monitor, 2 a surgical suite
with robotic arms. Everything around the field is detail the player sees
at the edges while operating: the drape and its clamps, rails, trays of
instruments, gauze, vials, cables and the floor.
"""
from __future__ import annotations

import math

from .hd import Scene, PAL, shade, mix
from .rooms_hd import C

W, H = 340, 270
RES = 4
FX0, FY0, FX1, FY1 = 90, 55, 250, 215  # the field (covered by anatomy)
TX0, TX1 = 66, 274  # the table


def floor(s: Scene, level):
    base = C("concrete1") if level == 0 else C("tile0") if level == 1 else C("steel1")
    s.rect(0, 0, W, H, base)
    s.noise(0, 0, W, H, 0.07, seed=11, scale=1)
    s.noise(0, 0, W, H, 0.05, seed=12, scale=2)
    f = 1.0 / s.res
    if level == 0:
        # Cracked concrete with stains and a drain.
        for k in range(9):
            x, y = s.rng.uniform(0, W), s.rng.uniform(0, H)
            for _ in range(14):
                nx, ny = x + s.rng.uniform(-6, 6), y + s.rng.uniform(-2, 7)
                s.fline(x, y, nx, ny, C("concrete0", -0.3))
                x, y = nx, ny
        for k in range(7):
            cx, cy = s.rng.uniform(0, W), s.rng.uniform(0, H)
            s.disc(cx, cy, s.rng.uniform(5, 14), mix(base, C("grime"), 0.35))
        s.disc(310, 250, 9, C("concrete0", -0.2))
        for k in range(5):
            s.rect(302, 245 + k * 2.2, 16, 1, C("void"))
    else:
        step = 20 if level == 1 else 30
        for y in range(0, H, step):
            s.rect(0, y, W, 2 * f, shade(base, -0.45))
            s.rect(0, y + 2 * f, W, f, shade(base, 0.18))
        for x in range(0, W, step):
            s.rect(x, 0, 2 * f, H, shade(base, -0.45))
            s.rect(x + 2 * f, 0, f, H, shade(base, 0.18))
        for y in range(0, H, step):  # per-tile tone
            for x in range(0, W, step):
                s.darken(x + 1, y + 1, step - 2, step - 2, s.rng.uniform(0.9, 1.05))
        if level == 2:  # anti-static floor: fine tread dots
            for y in range(4, H, 6):
                for x in range(3 + (y // 6 % 2) * 3, W, 6):
                    s.fpx(x * s.res, y * s.res, shade(base, 0.25))
        s.disc(312, 248, 6, C("steel0"))
        for k in range(4):
            s.fhline(307, 317, 245.5 + k * 2, C("void"))
    s.set_gloss(0, 0, W, H, 0.0)
    # Blood drips on the floor by the table edge.
    for k in range(10 if level == 0 else 4):
        x = s.rng.choice((s.rng.uniform(TX0 - 16, TX0 - 2), s.rng.uniform(TX1 + 2, TX1 + 16)))
        y = s.rng.uniform(30, H - 10)
        s.disc(x, y, s.rng.uniform(0.4, 1.2), C("blood", -0.35))
        s.fpx(int(x * s.res), int(y * s.res) - 1, C("blood", 0.2))


def table(s: Scene, level):
    f = 1.0 / s.res
    if level == 0:
        wood = C("rust1", 0.08)
        s.rect(TX0, 0, TX1 - TX0, H, wood)
        for k in range(int((TX1 - TX0) * s.res)):  # wood grain
            X = TX0 * s.res + k
            if k % 3 == 0:
                ph = math.sin(k * 0.37) * 2.5
                for Y in range(0, H * s.res, 2):
                    if math.sin((Y + ph * 30) * 0.045 + k * 0.11) > 0.86:
                        s.fpx(X, Y, shade(wood, -0.28))
        for x in range(TX0 + 26, TX1, 26):  # plank seams
            s.rect(x, 0, 2 * f, H, shade(wood, -0.55))
            s.rect(x + 2 * f, 0, f, H, shade(wood, 0.2))
        for x0 in (TX0, TX1 - 6):  # edge boards with nails
            s.box(x0, 0, 6, H, shade(wood, -0.1), 0.2)
            for y in range(10, H, 34):
                s.rivet(x0 + 2.5, y, C("steel3"))
    else:
        steel = C("steel3")
        s.box(TX0, 0, TX1 - TX0, H, steel, 0.15)
        s.noise(TX0, 0, TX1 - TX0, H, 0.03, seed=4)
        for x0 in (TX0, TX1 - 7):  # accessory rails with slots
            s.box(x0, 0, 7, H, C("steel4"), 0.25)
            s.fvline(x0 + 1.5, 0, H, C("steel5"))
            s.fvline(x0 + 1.75, 0, H, C("white"))
            for y in range(6, H, 16):
                s.rect(x0 + 2.5, y, 2, 7, C("void"))
                s.fhline(x0 + 2.5, x0 + 4.5, y + 7 - f, C("steel5"))
            for y in range(14, H, 48):
                s.rivet(x0 + 3, y, C("steel4"))
        if level == 2:  # control strip down the left rail
            for k in range(8):
                s.glow(TX0 + 2.25, 70 + k * 18, 2.5, 1.0, C("cyan" if k % 3 else "amber"), 0.8)
    # Sterile drape over the table, folds running down from the field.
    drape = C("teal", -0.62) if level else C("teal", -0.5)
    dx0, dx1 = TX0 + 8, TX1 - 8
    s.rect(dx0, 4, dx1 - dx0, H - 8, drape)
    for i in range(int((dx1 - dx0) * s.res)):
        x = dx0 + i * f
        for Y in range(4 * s.res, (H - 4) * s.res):
            y = Y / s.res
            v = 0.07 * math.sin(x * 0.11 + 1.7 * math.sin(y * 0.031)) + 0.05 * math.sin(x * 0.29 + y * 0.013)
            if abs(v) > 0.03:
                s.albedo[Y, int(x * s.res)] = shade(drape, v * 1.1)
    s.noise(dx0, 4, dx1 - dx0, H - 8, 0.05, seed=9)
    # Hem and selvedge stitching.
    for X in range(dx0 * s.res, dx1 * s.res, 3):
        s.fpx(X, 5 * s.res, shade(drape, 0.35))
        s.fpx(X, (H - 5) * s.res, shade(drape, 0.35))
    for Y in range(4 * s.res, (H - 4) * s.res, 3):
        s.fpx(dx0 * s.res + 2, Y, shade(drape, 0.3))
        s.fpx(dx1 * s.res - 3, Y, shade(drape, 0.3))
    s.rect(dx0, 4, f * 2, H - 8, shade(drape, -0.5))
    s.rect(dx1 - 2 * f, 4, f * 2, H - 8, shade(drape, -0.5))
    # Fenestration: the drape folds up around the field opening.
    for k in range(6):
        g = 0.55 - k * 0.08
        s.rect(FX0 - 1 - k, FY0 - 1 - k, FX1 - FX0 + 2 + 2 * k, 1, shade(drape, -g))
        s.rect(FX0 - 1 - k, FY1 + k, FX1 - FX0 + 2 + 2 * k, 1, shade(drape, -g * 0.8))
        s.rect(FX0 - 1 - k, FY0 - k, 1, FY1 - FY0 + 2 * k, shade(drape, -g))
        s.rect(FX1 + k, FY0 - k, 1, FY1 - FY0 + 2 * k, shade(drape, -g * 0.8))
    s.fhline(FX0 - 7, FX1 + 7, FY0 - 7, shade(drape, 0.3))
    s.fvline(FX0 - 7, FY0 - 7, FY1 + 7, shade(drape, 0.25))
    # Towel clips at the corners of the opening.
    for cx, cy in ((FX0 - 4, FY0 - 4), (FX1 + 3, FY0 - 4), (FX0 - 4, FY1 + 3), (FX1 + 3, FY1 + 3)):
        s.disc(cx, cy, 2.2, C("steel4"))
        s.disc(cx, cy, 1.1, C("steel1"))
        s.fpx(int((cx - 1.2) * s.res), int((cy - 1.4) * s.res), C("white"))
        s.line(cx, cy, cx + (6 if cx < W / 2 else -6), cy + (5 if cy < H / 2 else -5), C("steel4"), t=0.75)
    # Used gauze on the drape near the field: crumpled, soaked unevenly.
    gauze = C("bone", -0.08)
    for gx, gy, gw, gh in ((FX1 + 3, FY0 + 24, 8, 6), (FX0 - 11, FY1 - 30, 7, 8)):
        pts = [(gx + gw * (0.5 + 0.5 * math.cos(a)) + s.rng.uniform(-1, 1),
                gy + gh * (0.5 + 0.5 * math.sin(a)) + s.rng.uniform(-1, 1))
               for a in [k / 9 * 2 * math.pi for k in range(9)]]
        s.poly(pts, gauze)
        for k in range(1, int(gw * s.res), 3):
            s.fvline(gx + k * f, gy + 1, gy + gh - 1, shade(gauze, -0.15))
        for k in range(1, int(gh * s.res), 3):
            s.fhline(gx + 1, gx + gw - 1, gy + k * f, shade(gauze, -0.15))
        for j in range(7):
            s.disc(gx + gw * s.rng.uniform(0.3, 0.8), gy + gh * s.rng.uniform(0.3, 0.8), s.rng.uniform(0.5, 1.6),
                   C("blood", s.rng.uniform(-0.4, 0.0)))
    # Drips and smears near the opening (small, uneven).
    for k in range(12 if level == 0 else 6):
        a = s.rng.uniform(0, 2 * math.pi)
        rx = (FX1 - FX0) / 2 + s.rng.uniform(4, 14)
        ry = (FY1 - FY0) / 2 + s.rng.uniform(4, 14)
        x, y = (FX0 + FX1) / 2 + math.cos(a) * rx, (FY0 + FY1) / 2 + math.sin(a) * ry
        for j in range(3):
            s.disc(x + s.rng.uniform(-0.8, 0.8), y + s.rng.uniform(-0.8, 0.8), s.rng.uniform(0.3, 0.8),
                   C("blood", -0.2))
    # Patient strap across top and bottom of the table.
    for sy in (18, H - 26):
        s.box(TX0 + 2, sy, TX1 - TX0 - 4, 7, C("concrete1") if level == 0 else C("steel0"), 0.2)
        for X in range((TX0 + 3) * s.res, (TX1 - 3) * s.res, 4):
            s.fpx(X, sy * s.res + 2, C("steel2"))
            s.fpx(X, (sy + 7) * s.res - 3, C("steel2"))
        bx = (FX0 + FX1) / 2 - 5
        s.box(bx, sy - 1, 10, 9, C("steel4"), 0.3)
        s.rect(bx + 2, sy + 2, 6, 3, C("void"))
        s.fhline(bx + 2, bx + 8, sy + 2, C("steel5"))


def instrument(s: Scene, x, y, kind, ang=0.0):
    """A single steel instrument laid on a tray."""
    f = 1.0 / s.res
    ca, sa = math.cos(ang), math.sin(ang)

    def P(u, v):
        return x + u * ca - v * sa, y + u * sa + v * ca

    st, hi, lo = C("steel4"), C("white"), C("steel1")
    if kind == "scalpel":
        s.line(*P(0, 0), *P(20, 0), st, t=1.25)
        s.fline(*P(0, -0.4), *P(20, -0.4), C("steel5"))
        for k in range(4):
            s.fline(*P(3 + k * 1.2, 0.5), *P(3 + k * 1.2, -0.5), lo)
        s.poly([P(20, -0.8), P(27, -0.2), P(25, 0.9), P(20, 0.8)], C("steel5"))
        s.fline(*P(20.5, -0.6), *P(26.5, -0.2), hi)
    elif kind == "forceps":
        s.line(*P(0, -1.5), *P(22, -0.2), st, t=0.75)
        s.line(*P(0, 1.5), *P(22, 0.2), st, t=0.75)
        s.fline(*P(0, -1.8), *P(22, -0.4), hi)
        for k in range(5):
            s.fline(*P(4 + k, -1.6), *P(4 + k, -0.9), lo)
            s.fline(*P(4 + k, 1.6), *P(4 + k, 0.9), lo)
    elif kind == "clamp":
        s.disc(*P(2, -2), 1.8, st)
        s.disc(*P(2, 2), 1.8, st)
        s.disc(*P(2, -2), 0.9, lo)
        s.disc(*P(2, 2), 0.9, lo)
        s.line(*P(3.5, -1.5), *P(18, 0), st, t=0.75)
        s.line(*P(3.5, 1.5), *P(18, 0), st, t=0.75)
        s.fline(*P(3.5, -1.8), *P(18, -0.3), hi)
        s.disc(*P(11, 0), 0.8, C("steel5"))
    elif kind == "needle":
        for k in range(16):
            a0, a1 = math.pi * k / 16, math.pi * (k + 1) / 16
            s.fline(*P(4 + 4 * math.cos(a0), -4 * math.sin(a0)), *P(4 + 4 * math.cos(a1), -4 * math.sin(a1)), hi)
        for k in range(40):  # suture thread
            u = k * 0.6
            s.fpx(int(P(8 + u, math.sin(u * 0.5) * 2)[0] * s.res), int(P(8 + u, math.sin(u * 0.5) * 2)[1] * s.res),
                  C("blue", -0.2))
    elif kind == "syringe":
        s.box(*P(0, -1.5), 14, 3, C("ice", -0.35), 0.2)
        s.rect(*P(2, -1), 8, 2, C("amber", -0.2))
        for k in range(5):
            s.fvline(P(2 + k * 2, 0)[0], P(0, -1.5)[1], P(0, -0.6)[1], C("white"))
        s.rect(*P(-4, -0.5), 4, 1, C("steel3"))
        s.rect(*P(-5, -2), 1, 4, C("steel3"))
        s.fline(*P(14, 0), *P(20, 0), C("steel5"))
    elif kind == "retractor":
        s.line(*P(0, 0), *P(16, 0), st, t=1.0)
        s.line(*P(16, 0), *P(16, 5), st, t=1.0)
        for k in range(3):
            s.line(*P(16 + k * 1.5, 5), *P(16 + k * 1.5, 7), st, t=0.5)
        s.fline(*P(0, -0.5), *P(16, -0.5), hi)
    # Specular glint and a contact shadow.
    gx, gy = P(6, -0.6)
    s.fpx(int(gx * s.res), int(gy * s.res), hi)


def tray(s: Scene, x, y, w, h, level, seed):
    """Stainless instrument tray on a stand, with a towel and tools."""
    rng = s.rng
    s.rect(x + 2, y + 3, w, h, C("void"))  # drop shadow
    s.box(x, y, w, h, C("steel3"), 0.3)
    s.box(x + 2, y + 2, w - 4, h - 4, C("steel2"), -0.15, True, -0.2)
    for X in range(int((x + 3) * s.res), int((x + w - 3) * s.res), 5):  # brushed steel
        s.fvline(X / s.res, y + 3, y + h - 3, C("steel2", 0.08))
    towel = C("teal", -0.45) if level else C("bone", -0.1)
    s.rect(x + 4, y + 5, w - 8, h - 10, towel)
    s.noise(x + 4, y + 5, w - 8, h - 10, 0.06, seed=seed)
    for k in range(2, int((h - 10) * s.res), 6):
        s.fhline(x + 4, x + w - 4, y + 5 + k / s.res, shade(towel, -0.15))
    kinds = ["scalpel", "forceps", "clamp", "syringe", "retractor", "needle", "clamp"]
    rng.shuffle(kinds)
    for k, kind in enumerate(kinds[: int((h - 14) // 11)]):
        instrument(s, x + 7, y + 10 + k * 11, kind, rng.uniform(-0.12, 0.08))
    # Vials in a rack on the tray edge.
    for k in range(4):
        s.bottle(x + 6 + k * 5, y - 9, 8, C(["amber", "ice", "red", "lime"][k], -0.35), 3, C("steel4"))
        s.gpx(x + 7 + k * 5, y - 3, C(["amber", "ice", "red", "lime"][k]), 0.25)
    s.box(x + 4, y - 2, 22, 2, C("steel4"), 0.2)


def monitor(s: Scene, x, y, w, h, level):
    s.box(x - 3, y - 3, w + 6, h + 9, C("steel1"), 0.2)
    s.bezel(x - 1, y - 1, w + 2, h + 2, C("steel0"))
    s.glow(x, y, w, h, shade(C("green"), -0.88), 1.0)
    f = 1.0 / s.res
    prev = None
    for i in range(int(w * s.res)):  # ECG trace at one hi-res px
        xx = x + i * f
        k = (i // 2) % 28
        dy = {12: -1.5, 13: 4, 14: -6.5, 15: 5, 16: -1}.get(k, 0)
        yy = y + h * 0.45 + dy
        if prev is not None:
            for t in range(int(min(prev, yy) * s.res), int(max(prev, yy) * s.res) + 1):
                s.fpx(int(xx * s.res), t, C("green"), "emissive")
        prev = yy
    s.ftext(x + 1, y + 1, "HR 72", C("green"), "emissive")
    s.ftext(x + w - 12, y + 1, "SPO2 98", C("ice"), "emissive")
    s.ftext(x + 1, y + h - 3, "BP 118/76", C("amber"), "emissive")
    s.ftext(x + w - 9, y + h - 3, "RR 14", C("ice"), "emissive")
    for k in range(int(h * s.res)):
        if k % 2:
            s.scale_buf(x, y + k * f, w, f, 0.72)
    s.glass(x, y, w, h, 0.07)
    for k in range(4):  # buttons under the screen
        s.rect(x + 2 + k * 6, y + h + 2, 4, 2, C("steel3"))
        s.fhline(x + 2 + k * 6, x + 6 + k * 6, y + h + 2, C("steel5"))
    s.gpx(x + w - 3, y + h + 2.5, C("green"), 0.9, t=1)
    s.light(x + w / 2, y + h / 2, C("green") * 0.7, 70, 0.4)


def drip(s: Scene, x, y):
    """IV bag on a pole hook with a drip chamber and tube to the table."""
    s.vline(x + 5, 0, y, C("steel4"), t=0.75)
    s.fvline(x + 5.25, 0, y, C("white"))
    bag = C("ice", -0.15)
    s.poly([(x, y + 2), (x + 11, y + 2), (x + 11, y + 15), (x + 8, y + 19), (x + 3, y + 19), (x, y + 15)], bag)
    s.rect(x + 1, y + 8, 9, 9, C("amber", -0.25))  # fluid level
    s.fvline(x + 1, y + 3, y + 15, C("white"))
    s.label(x + 2.5, y + 4, 6, 3, C("white", -0.1), text="NS")
    s.rect(x + 4, y + 19, 3, 5, C("ice", -0.4))
    s.fpx(int((x + 5.5) * s.res), int((y + 21) * s.res), C("white"))
    s.cable(x + 5.5, y + 24, TX1 - 3, 80, 14, C("ice", -0.45), 0.5, hl=C("white", -0.2))
    s.light(x + 5, y + 10, C("ice") * 0.5, 40, 0.25)


def cables(s: Scene, level):
    for k in range(3 + level):
        y0 = 70 + k * 36
        s.cable(W + 2, y0, TX1 - 2, y0 + 30 + k * 6, 10 + k * 3, C("void"), 1.25, hl=C("steel2"))
    if level >= 1:
        s.cable(46, 66, TX0 + 4, 96, 16, C("void"), 1.0, hl=C("steel2"))
        s.cable(40, 66, TX0 + 4, 118, 22, C("steel0"), 0.75, hl=C("green", -0.6))


def robot_arm(s: Scene, bx, side):
    """Ceiling-mounted manipulator: white shells, black joints, LEDs."""
    j1 = (bx + side * 28, 30)
    j2 = (bx + side * 34, 58)
    s.box(bx - 7, 0, 14, 6, C("steel2"), 0.2)
    for a, b, r in ((( bx, 4), j1, 4.5), (j1, j2, 3.2)):
        s.line(*a, *b, C("white", -0.12), t=r * 2)
        s.line(a[0] - 1.2, a[1] - 0.6, b[0] - 1.2, b[1] - 0.6, C("white", 0.05), t=r * 0.6)
        s.line(a[0] + r * 0.6, a[1] + 0.8, b[0] + r * 0.6, b[1] + 0.8, C("steel4"), t=0.5)
    for (jx, jy), r in ((j1, 4.5), (j2, 3.2)):
        s.disc(jx, jy, r, C("steel0"))
        s.disc(jx, jy, r * 0.5, C("steel2"))
        s.fpx(int((jx - r * 0.4) * s.res), int((jy - r * 0.5) * s.res), C("steel5"))
    s.gpx(j1[0] - 0.5, j1[1] - 0.5, C("cyan"), 1.0)
    # Tool head with a red laser aperture.
    tx, ty = j2[0] + side * 2, j2[1] + 6
    s.poly([(j2[0] - 2.5, j2[1]), (j2[0] + 2.5, j2[1]), (tx + 1.2, ty), (tx - 1.2, ty)], C("steel3"))
    s.gpx(tx - 0.5, ty, C("red"), 1.0)
    s.light(tx, ty, C("red") * 0.6, 20, 0.35)


def backdrop(level: int) -> Scene:
    s = Scene(W, H, ambient=(0.20, 0.21, 0.28) if level else (0.17, 0.15, 0.15), seed=320 + level, res=RES)
    floor(s, level)
    table(s, level)
    tray(s, 8, 150, 50, 86, level, 1)
    tray(s, 282, 150, 50, 86, level, 2)
    cables(s, level)
    if level >= 1:
        monitor(s, 10, 22, 46, 30, level)
    else:
        # A clip-on work lamp and an ashtray on an upturned crate.
        s.box(6, 30, 40, 30, C("rust1", -0.1), 0.2)
        for k in range(3):
            s.fhline(6, 46, 38 + k * 8, C("rust0"))
        s.disc(26, 44, 6, C("steel2"))
        s.disc(26, 44, 4.5, C("concrete0"))
        for k in range(4):
            s.line(22 + k * 2.2, 43 + (k % 2), 25 + k * 2.2, 41 + k % 2, C("bone", -0.2), t=0.5)
        s.gpx(25 + 3 * 2.2, 41.5, C("orange"), 1.0, t=0.5)
        s.line(48, 0, 54, 18, C("steel3"), t=1.0)
        s.poly([(48, 18), (60, 18), (64, 28), (44, 28)], C("steel2"))
        s.glow(46, 27, 16, 1.5, C("tungsten"), 1.0)
        s.light(56, 40, C("tungsten") * 1.1, 230, 0.75, cone=(1.2, 1, 70), falloff=1.1)
    drip(s, 298, 12)
    if level >= 2:
        robot_arm(s, 62, 1)
        robot_arm(s, 278, -1)
    # The operating light: a big white pool over the field.
    s.light(170, 130, PAL["white"], 200, 1.0, falloff=1.3)
    if level == 0:
        s.light(170, 120, C("tungsten"), 150, 0.4)
    else:
        s.light(W + 10, 90, C("cyan") * 0.8, 120, 0.35)
    return s


def generate():
    for lv in range(3):
        backdrop(lv).save(f"surgery/backdrop_{lv}.png")
    print("surgery: HD backdrops x3 (1360x1080)")
