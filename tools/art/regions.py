"""Surgical-field anatomy textures (160x160, palette-indexed).

Each region is defined as a height field (muscle masses, bones, tendons,
veins). Normals from the height field are lit by the global key light plus
the overhead surgical lamp, then mapped onto the customer's skin ramp with
dithering. Hair uses the hair ramp; surgical drape uses cloth ramp A.
"""
from __future__ import annotations

import math
import random

from .lib import Canvas, LIGHT, bayer, clamp

SK, HR, CA, CB, MT, GL, IR, FX = range(8)
DR, IO = 12, 13  # fixed material ramps: sterile drape, iodine prep wash
SIZE = 160


def gauss(x, y, cx, cy, sx, sy, a):
    return a * math.exp(-(((x - cx) / sx) ** 2 + ((y - cy) / sy) ** 2))


def ridge_x(x, cx, s, a):
    return a * math.exp(-((x - cx) / s) ** 2)


def lamp(x, y):
    """Overhead surgical lamp: brighter centre."""
    d = math.hypot(x - 80, y - 76) / 110
    return clamp(1.0 - d * d, 0.0, 1.0)


def render_height(cv, hfn, mask_fn, ramp=SK, lo=1.0, hi=6.6, scale=1.0, detail=None):
    eps = 1.0
    for y in range(SIZE):
        for x in range(SIZE):
            r = mask_fn(x, y)
            if r is None:
                continue
            hx = (hfn(x + eps, y) - hfn(x - eps, y)) / (2 * eps) * scale
            hy = (hfn(x, y + eps) - hfn(x, y - eps)) / (2 * eps) * scale
            n = (-hx, -hy, 1.0)
            ln = math.sqrt(n[0] ** 2 + n[1] ** 2 + 1.0)
            i = clamp((n[0] * LIGHT[0] + n[1] * LIGHT[1] + n[2] * LIGHT[2]) / ln, 0, 1)
            i = 0.55 * i + 0.45 * lamp(x, y) * (n[2] / ln)
            v = lo + (hi - lo) * i
            if detail:
                v += detail(x, y)
            cv.shade_px(x, y, r, v)


def skin_details(cv, rng, area, count=40):
    """Pores, freckles, moles: tiny 1px variations so skin isn't plastic."""
    x0, y0, x1, y1 = area
    for _ in range(count):
        x, y = rng.randrange(x0, x1), rng.randrange(y0, y1)
        c = cv.get(x, y)
        if c and c[0] == SK:
            cv.set(x, y, (SK, max(0, c[1] - 1)))
    for _ in range(3):
        x, y = rng.randrange(x0 + 10, x1 - 10), rng.randrange(y0 + 10, y1 - 10)
        c = cv.get(x, y)
        if c and c[0] == SK:
            cv.set(x, y, (SK, 0))
            cv.set(x + 1, y, (SK, 1))


def drape_height(x, y):
    """Broad, irregular cloth folds."""
    return 7 * math.sin(x * 0.045 + 2.2 * math.sin(y * 0.021)) + 3 * math.sin(y * 0.07 + x * 0.013 + 1.3) + 1.2 * math.sin(x * 0.13 - y * 0.05)


def operating_field(cv, rng, window, edge_dist, clips):
    """Dresses a region as a prepped operating field: everything outside
    `window(x, y)` is a sterile drape (its own folds, lit by the lamp, with
    a contact shadow and a hem where it meets skin); the skin just inside
    the window carries the iodine prep wash in brush-streaked bands that
    fade toward the middle; towel clamps pin the drape at `clips`; and wet
    skin catches a few lamp glints. `edge_dist(x, y)` is the distance in
    pixels from the window's edge (inside > 0)."""
    phase = rng.random() * 6.0
    for y in range(SIZE):
        for x in range(SIZE):
            if window(x, y):
                continue
            hx = drape_height(x + 1, y + phase) - drape_height(x - 1, y + phase)
            hy = drape_height(x, y + 1 + phase) - drape_height(x, y - 1 + phase)
            i = clamp(0.42 - hx * 0.14 - hy * 0.14 + lamp(x, y) * 0.5, 0, 1)
            d = -edge_dist(x, y)
            v = 1.2 + i * 4.2
            if d < 3:
                v -= 1.4 - d * 0.35  # tucked under: shadow on the skin side
            elif d < 5:
                v += 0.9  # folded hem catches the lamp
            if (x * 5 + y * 3) % 23 == 0:
                v -= 0.6  # weave
            cv.shade_px(x, y, DR, v)
    # Iodine: a band inside the window, painted in strokes, thinning inward.
    strokes = [(rng.uniform(0, math.tau), rng.uniform(6, 14)) for _ in range(14)]
    for y in range(SIZE):
        for x in range(SIZE):
            if not window(x, y):
                continue
            c = cv.get(x, y)
            if not c or c[0] != SK:
                continue
            d = edge_dist(x, y)
            ang = math.atan2(y - 80, x - 80)
            reach = 10.0
            for a, r in strokes:
                da = abs((ang - a + math.pi) % math.tau - math.pi)
                if da < 0.22:
                    reach = max(reach, r + 8.0 * (1 - da / 0.22))
            fade = clamp(1.15 - d / reach, 0.0, 1.0)
            if d < reach and (bayer(x, y) * 0.6 + rng.random() * 0.4) < fade:
                cv.set(x, y, (IO, clamp(c[1] - 1 + (1 if d < 2 else 0), 0, 7)))
            elif c[1] >= 6 and rng.random() < 0.006:
                cv.set(x, y, (FX, 3))  # wet glint under the lamp
    # Towel clamps: a ring handle and the jaw biting the drape edge.
    for cx, cy in clips:
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                rr = math.hypot(dx, dy)
                if 1.6 <= rr <= 2.9:
                    cv.set(cx + dx, cy + dy, (MT, 5 if dx + dy < 0 else 3))
        cv.set(cx, cy + 3, (MT, 2))
        cv.set(cx, cy + 4, (MT, 1))
        cv.set(cx + 1, cy - 2, (MT, 7))


def ellipse_window(cx, cy, rx, ry, wobble=0.04, seed=0.0):
    """An irregular elliptical opening in the drape, and its edge distance."""
    def r(x, y):
        a = math.atan2(y - cy, x - cx)
        k = 1.0 + wobble * math.sin(a * 5 + seed) + wobble * 0.5 * math.sin(a * 11 + seed * 2)
        return math.hypot((x - cx) / (rx * k), (y - cy) / (ry * k))

    def window(x, y):
        return r(x, y) < 1.0

    def dist(x, y):
        return (1.0 - r(x, y)) * min(rx, ry)

    return window, dist


def limb_window(half_w, cy, ry, frac=0.8):
    """An oval opening in the drape along a limb: it follows the limb's
    taper (frac of its half width) and closes in a curve at both ends."""
    def r(x, y):
        return math.hypot((x - 80) / max(1.0, half_w(y) * frac), (y - cy) / ry)

    def window(x, y):
        return r(x, y) < 1.0

    def dist(x, y):
        return (1.0 - r(x, y)) * min(half_w(y) * frac, ry)

    return window, dist


# --- Regions -----------------------------------------------------------------

def neck():
    """Back of the neck / upper back, patient prone. Spine runs vertically."""
    rng = random.Random(11)
    cv = Canvas(SIZE, SIZE, indexed=True)
    cv.dither_band = 0.45

    def hairline(x):
        return 26 + 7 * math.sin(x / 11.0) * math.exp(-((x - 80) / 70) ** 2) + (x - 80) ** 2 / 260

    def h(x, y):
        v = gauss(x, y, 80, 130, 120, 120, 30)  # broad back dome
        v += gauss(x, y, 48, 92, 26, 50, 9) + gauss(x, y, 112, 92, 26, 50, 9)  # trapezius
        v -= ridge_x(x, 80, 5, 5) * clamp((y - 30) / 40, 0, 1)  # spine groove
        for vy, a in ((70, 2.0), (88, 2.6), (106, 4.2), (124, 3.0), (142, 2.6)):
            v += gauss(x, y, 80, vy, 4.5, 4, a)  # vertebrae (C7 prominent)
        v += gauss(x, y, 22, 150, 16, 26, 6) + gauss(x, y, 138, 150, 16, 26, 6)  # scapula
        return v

    def mask(x, y):
        return HR if y < hairline(x) else SK

    def hair_detail(x, y):
        return 0.0

    render_height(cv, h, lambda x, y: SK if y >= hairline(x) else None, scale=0.9)
    # Hair: short strands combed down, darker toward the neck line.
    for y in range(0, SIZE):
        for x in range(SIZE):
            hl = hairline(x)
            if y < hl:
                v = 3.6 - (y / hl) * 1.4 + 1.1 * lamp(x, y) + (0.9 if (x * 3 + y // 3) % 7 == 0 else 0) - (0.8 if (x + y * 2) % 5 == 0 else 0)
                cv.shade_px(x, y, HR, v)
            elif y < hl + 3 and (x + y) % 3 == 0:
                cv.set(x, y, (HR, 1))
    skin_details(cv, rng, (0, 30, SIZE, SIZE), 70)
    win, dist = ellipse_window(80, 92, 64, 76, seed=1.0)
    operating_field(cv, rng, win, dist, [(30, 60), (130, 60), (34, 140), (126, 140)])
    return cv


def forearm():
    """Forearm laid vertically (elbow top, wrist bottom) on a drape."""
    rng = random.Random(12)
    cv = Canvas(SIZE, SIZE, indexed=True)
    cv.dither_band = 0.45

    def half_w(y):
        return 40 - (y / SIZE) * 12 + 3 * math.sin(y / 30)

    def inside(x, y):
        return abs(x - 80) < half_w(y)

    def h(x, y):
        hw = half_w(y)
        t = clamp((x - 80) / hw, -1, 1)
        v = math.sqrt(max(0.0, 1 - t * t)) * 30
        v += gauss(x, y, 66, 40, 12, 40, 4) + gauss(x, y, 96, 52, 12, 40, 3)  # flexor / brachioradialis
        for k, tx in enumerate((72, 80, 88)):
            v += ridge_x(x, tx + (y - 120) * 0.05, 1.6, 1.2) * clamp((y - 100) / 40, 0, 1)  # tendons near wrist
        return v

    for y in range(SIZE):
        for x in range(SIZE):
            if not inside(x, y):
                hh = drape_height(x, y)
                hx = drape_height(x + 1, y) - drape_height(x - 1, y)
                hy = drape_height(x, y + 1) - drape_height(x, y - 1)
                i = clamp(0.45 - hx * 0.09 - hy * 0.09 + lamp(x, y) * 0.5, 0, 1)
                d = abs(abs(x - 80) - half_w(y))
                shadow = 1.2 if d < 4 else 0.0  # contact shadow next to the arm
                cv.shade_px(x, y, CA, 1.0 + i * 4.0 - shadow)
    render_height(cv, h, lambda x, y: SK if inside(x, y) else None, scale=0.6)
    # Veins: faint, cool, 1px
    for k in range(2):
        x = 70 + k * 16
        for y in range(60, 150):
            x += rng.choice((-1, 0, 0, 1)) * 0.5
            c = cv.get(int(x), y)
            if c and c[0] == SK:
                cv.set(int(x), y, (SK, max(0, c[1] - 1)))
    skin_details(cv, rng, (45, 0, 115, SIZE), 60)

    win, dist = limb_window(half_w, 80, 84, 1.0)

    operating_field(cv, rng, win, dist, [(80, 6), (80, 154)])
    return cv


def chest():
    rng = random.Random(13)
    cv = Canvas(SIZE, SIZE, indexed=True)
    cv.dither_band = 0.45

    def h(x, y):
        v = gauss(x, y, 80, 90, 140, 110, 24)
        v += gauss(x, y, 48, 60, 28, 22, 9) + gauss(x, y, 112, 60, 28, 22, 9)  # pectorals
        v -= ridge_x(x, 80, 4, 3) * clamp((y - 20) / 30, 0, 1)  # sternum
        for ry in (100, 116, 132):  # lower ribs
            v += ridge_x(y, ry + abs(x - 80) * 0.25, 2.5, 1.0) * clamp((abs(x - 80) - 18) / 30, 0, 1)
        return v

    for y in range(SIZE):
        for x in range(SIZE):
            if y > 150 or y < 6:
                cv.shade_px(x, y, CA, 2.0 + lamp(x, y) * 2 + (0.5 if (x // 6) % 2 else 0))
    render_height(cv, h, lambda x, y: SK if 6 <= y <= 150 else None, scale=0.8)
    skin_details(cv, rng, (0, 10, SIZE, 148), 70)
    win, dist = ellipse_window(80, 80, 66, 64, seed=2.0)
    operating_field(cv, rng, win, dist, [(24, 40), (136, 40), (24, 122), (136, 122)])
    return cv


def thigh():
    rng = random.Random(14)
    cv = Canvas(SIZE, SIZE, indexed=True)
    cv.dither_band = 0.45

    def half_w(y):
        return 58 - (y / SIZE) * 16

    def inside(x, y):
        return abs(x - 80) < half_w(y)

    def h(x, y):
        hw = half_w(y)
        t = clamp((x - 80) / hw, -1, 1)
        v = math.sqrt(max(0.0, 1 - t * t)) * 34
        v += gauss(x, y, 60, 60, 18, 50, 5) + gauss(x, y, 98, 70, 16, 45, 5)  # quads
        v += gauss(x, y, 80, 150, 16, 12, 7)  # kneecap
        return v

    for y in range(SIZE):
        for x in range(SIZE):
            if not inside(x, y):
                hx = drape_height(x + 1, y) - drape_height(x - 1, y)
                hy = drape_height(x, y + 1) - drape_height(x, y - 1)
                i = clamp(0.45 - hx * 0.09 - hy * 0.09 + lamp(x, y) * 0.5, 0, 1)
                cv.shade_px(x, y, CA, 1.0 + i * 4.0 - (1.2 if abs(abs(x - 80) - half_w(y)) < 4 else 0))
    render_height(cv, h, lambda x, y: SK if inside(x, y) else None, scale=0.6)
    skin_details(cv, rng, (24, 0, 136, SIZE), 70)

    win, dist = limb_window(half_w, 82, 84, 1.0)

    operating_field(cv, rng, win, dist, [(80, 4)])
    return cv


def orbital():
    """Face close-up around the left eye: brow, socket, cheekbone."""
    rng = random.Random(15)
    cv = Canvas(SIZE, SIZE, indexed=True)
    cv.dither_band = 0.45

    def h(x, y):
        v = gauss(x, y, 80, 80, 150, 150, 30)
        v += gauss(x, y, 80, 40, 48, 12, 8)  # brow ridge
        v -= gauss(x, y, 80, 80, 26, 18, 9)  # eye socket
        v += gauss(x, y, 84, 82, 18, 12, 6)  # eyeball under lid
        v += gauss(x, y, 92, 122, 40, 16, 8)  # cheekbone
        v += ridge_x(x, 6, 8, 10) * clamp((y - 60) / 60, 0, 1)  # nose bridge at left edge
        return v

    render_height(cv, h, lambda x, y: SK, scale=0.9)
    # Brow hair
    for x in range(44, 120):
        yb = 32 + int(((x - 80) / 40) ** 2 * 5)
        for y in range(yb, yb + 6):
            if (x * 7 + y * 3) % 5 not in (0, 3) or y == yb + 2:
                cv.shade_px(x, y, HR, 2.4 + lamp(x, y) - abs(y - yb - 2) * 0.35 + (0.8 if (x // 3) % 3 == 0 else 0))
    # Closed eyelid line + lashes
    for x in range(58, 104):
        y = 84 + int(((x - 81) / 23) ** 2 * -4) + 4
        cv.set(x, y, (SK, 0))
        if x % 3 == 0:
            cv.set(x, y + 1, (HR, 1))
        cv.set(x, y - 1, (SK, 2))
    skin_details(cv, rng, (0, 0, SIZE, SIZE), 80)
    win, dist = ellipse_window(84, 84, 68, 60, wobble=0.03, seed=3.0)
    operating_field(cv, rng, win, dist, [(26, 46), (142, 46), (40, 142), (130, 142)])
    return cv


REGIONS = {"neck": neck, "forearm": forearm, "chest": chest, "thigh": thigh, "orbital": orbital}


def generate():
    for name, fn in REGIONS.items():
        fn().save(f"surgery/regions/{name}.png")
    scan_hologram().save("surgery/scan_hologram.png")
    print("regions:", len(REGIONS))


def scan_hologram():
    """Holographic full-body scan (RGB, 60x124) for the diagnosis screen.
    The silhouette (and so ScanView.REGIONS) is fixed; anatomy() draws the
    skeleton, organs and nerve trunks inside it."""
    from . import palette as pal
    from .lib import poly_pixels
    W2, H2 = 60, 124
    mask = Canvas(W2, H2, indexed=True)
    mk = (0, 1)
    mask.ellipse(30, 11, 7.5, 9, mk)
    mask.rect(27, 19, 6, 6, mk)
    for x, y in poly_pixels([(15, 25), (45, 25), (43, 52), (40, 66), (20, 66), (17, 52)]):
        mask.set(x, y, mk)
    for (ax, ay, bx, by, r) in ((16, 27, 10, 50, 3.2), (10, 50, 8, 70, 2.6), (44, 27, 50, 50, 3.2), (50, 50, 52, 70, 2.6),
                                (24, 64, 22, 92, 4.2), (22, 92, 22, 118, 3.2), (36, 64, 38, 92, 4.2), (38, 92, 38, 118, 3.2)):
        mask.capsule(ax, ay, bx, by, r, 0, 1, 1)
    out = Canvas(W2, H2)
    cyan = pal.glow_ramp(pal.GLOWS["cyan"])
    for y in range(H2):
        for x in range(W2):
            if mask.px[y][x] is None:
                continue
            edge = any(not (0 <= x + dx < W2 and 0 <= y + dy < H2) or mask.px[y + dy][x + dx] is None
                       for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
            if edge:
                c = cyan[5]
            elif y % 3 == 0 and bayer(x, y) < 0.5:
                c = cyan[1]
            else:
                c = (8, 40, 38) if (x + y) % 2 else (10, 48, 44)
            out.set(x, y, (c[0], c[1], c[2], 255 if edge else 200))
    anatomy(out, mask, cyan)
    return out


def anatomy(out, mask, cyan):
    """Skeleton, organs and nerve trunks for the scan hologram, in the
    cyan glow ramp (bone brightest, soft tissue dim, the heart warm)."""
    W2, H2 = out.w, out.h

    def inside(x, y):
        return 0 <= x < W2 and 0 <= y < H2 and mask.px[y][x] is not None

    def put(x, y, c, a=255):
        x, y = int(round(x)), int(round(y))
        if inside(x, y):
            out.set(x, y, (c[0], c[1], c[2], a))

    def seg(ax, ay, bx, by, c, a=255):
        n = int(max(abs(bx - ax), abs(by - ay))) + 1
        for i in range(n + 1):
            t = i / max(1, n)
            put(ax + (bx - ax) * t, ay + (by - ay) * t, c, a)

    # Bone sits between the fill and the bright silhouette edge, so the
    # outline still reads as the body's edge.
    bone, bone_dim, tissue, nerve = (70, 185, 166), (44, 132, 120), (24, 100, 90), (34, 150, 132)
    # Organs first, so bone draws over them.
    for side in (-1, 1):  # lungs: two lobes behind the ribs
        for y in range(28, 46):
            half = 6 if y < 42 else 6 - (y - 42)
            for d in range(2, 2 + half):
                if (d + y) % 2 == 0:
                    put(30 + side * (d + 1), y, tissue, 170)
    for y in range(46, 53):  # liver (right of the body = left of the image)
        for x in range(21, 30 - (y - 46) // 2):
            if (x + y) % 2:
                put(x, y, tissue, 190)
    for y in range(47, 52):  # stomach
        for x in range(32, 37):
            if (x * 3 + y) % 4 == 0:
                put(x, y, tissue, 190)
    for y in range(53, 61, 2):  # gut coils
        for x in range(25 + (y % 4), 36, 3):
            put(x, y, tissue, 170)
    # Brain: rounded mass with folds.
    for y in range(4, 14):
        for x in range(24, 37):
            if (x - 30) ** 2 / 36.0 + (y - 9) ** 2 / 25.0 <= 1.0:
                fold = (x * 2 + y * 3) % 5 == 0 or (x + y * 2) % 7 == 0
                put(x, y, cyan[5] if fold else cyan[2], 230)
    seg(30, 4, 30, 13, cyan[1], 230)  # the fissure between hemispheres
    # Jaw and orbits (the silhouette edge is the skull).
    seg(26, 16, 30, 19, bone_dim)
    seg(34, 16, 30, 19, bone_dim)
    put(28, 14, cyan[6])
    put(32, 14, cyan[6])  # optic sockets glint
    # Spine: vertebrae as short bars, sacrum at the bottom.
    for y in range(19, 62, 2):
        put(30, y, bone)
        if y % 4 == 1:
            put(29, y, bone_dim)
            put(31, y, bone_dim)
    # Clavicles, sternum, ribs (curving down and out).
    seg(29, 26, 21, 25, bone)
    seg(31, 26, 39, 25, bone)
    seg(30, 27, 30, 40, bone_dim)
    for k, y in enumerate(range(28, 46, 3)):
        span = 11 - abs(k - 2)
        for d in range(2, span):
            dy = (d * d) // 28
            put(30 - d, y + dy, bone_dim, 240)
            put(30 + d, y + dy, bone_dim, 240)
    # Pelvis.
    for d in range(2, 11):
        put(30 - d, 60 + (d * d) // 30, bone)
        put(30 + d, 60 + (d * d) // 30, bone)
    seg(20, 61, 23, 65, bone_dim)
    seg(40, 61, 37, 65, bone_dim)
    # Limb bones follow the same capsules as the silhouette.
    for (ax, ay, bx, by) in ((17, 27, 11, 50), (43, 27, 49, 50), (11, 51, 9, 69), (49, 51, 51, 69),
                             (24, 65, 22, 91), (36, 65, 38, 91), (22, 93, 22, 117), (38, 93, 38, 117)):
        seg(ax, ay, bx, by, bone)
    for (x, y) in ((11, 50), (49, 50), (22, 92), (38, 92), (17, 27), (43, 27)):  # joints
        put(x - 1, y, bone_dim)
        put(x + 1, y, bone_dim)
    for (x, y) in ((9, 70), (51, 70), (22, 118), (38, 118)):  # hands, feet
        for d in (-1, 0, 1):
            put(x + d, y + 1, bone_dim)
    # Nerve trunks: a faint dotted line beside each long bone.
    for (ax, ay, bx, by) in ((15, 30, 10, 49), (45, 30, 50, 49), (26, 66, 24, 90), (34, 66, 36, 90)):
        n = 12
        for i in range(0, n + 1, 2):
            t = i / n
            put(ax + (bx - ax) * t, ay + (by - ay) * t, nerve, 200)
    # Heart last: it is the only warm colour on the scan.
    for (x, y) in ((32, 36), (33, 36), (34, 36), (32, 37), (33, 37), (34, 37), (35, 37), (33, 38), (34, 38), (33, 39)):
        put(x, y, (200, 60, 90))
    put(32, 36, (240, 120, 140))
