"""Surgical-field anatomy textures (320x320, palette-indexed).

The field is 160 field px wide (SurgicalSiteView.FIELD_SIZE) and every
rule in the game works on that grid; the art is drawn at RES = 4 art px per
field px, so a region shows twice the detail of the old 160 px textures.
Designs are written in field coordinates (0..160) and evaluated at the
centre of every art pixel.

Each region is defined as a height field (muscle masses, bones, tendons,
veins). Normals from the height field are lit by the key light plus the
overhead surgical lamp and land on flat cel bands of the customer's skin
ramp (no dither), with a hard highlight on the lit peaks. The sterile drape
is cel-shaded too, its folds closed by dark crease lines, and an ink line
runs where it meets the skin. Hair uses the hair ramp.
"""
from __future__ import annotations

import math
import random

from .lib import Canvas, LIGHT, bayer, clamp

SK, HR, CA, CB, MT, GL, IR, FX = range(8)
DR, IO = 12, 13  # fixed material ramps: sterile drape, iodine prep wash
SIZE = 160       # field px (design coordinates)
RES = 4          # art px per field px
N = SIZE * RES   # texture size
INK = (FX, 0)


def gauss(x, y, cx, cy, sx, sy, a):
    return a * math.exp(-(((x - cx) / sx) ** 2 + ((y - cy) / sy) ** 2))


def ridge_x(x, cx, s, a):
    return a * math.exp(-((x - cx) / s) ** 2)


def lamp(x, y):
    """Overhead surgical lamp: brighter centre."""
    d = math.hypot(x - 80, y - 76) / 110
    return clamp(1.0 - d * d, 0.0, 1.0)


def pixels():
    """Every art pixel with the field coordinate of its centre."""
    for Y in range(N):
        y = (Y + 0.5) / RES - 0.5
        for X in range(N):
            yield X, Y, (X + 0.5) / RES - 0.5, y


def new_canvas() -> Canvas:
    return Canvas(N, N, indexed=True)


def skin_band(v: float) -> int:
    """Cel bands for skin: deep shadow, shadow, base, lit, highlight."""
    if v < 2.0:
        return 2
    if v < 3.2:
        return 3
    if v < 4.5:
        return 4
    if v < 5.8:
        return 5
    return 6


def cloth_band(v: float) -> int:
    if v < 1.8:
        return 1
    if v < 3.0:
        return 2
    if v < 4.2:
        return 3
    return 4


def render_height(cv, hfn, mask_fn, lo=1.0, hi=6.6, scale=1.0, detail=None):
    eps = 0.75
    for X, Y, x, y in pixels():
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
        cv.set(X, Y, (r, skin_band(v) if r == SK else cloth_band(v)))


def skin_details(cv, rng, area, count=40):
    """Freckles and moles: a few 2x1 marks one band darker, so the skin
    isn't plastic without becoming noise."""
    x0, y0, x1, y1 = area
    for _ in range(count // 3):
        X, Y = rng.randrange(x0 * RES, x1 * RES), rng.randrange(y0 * RES, y1 * RES)
        c = cv.get(X, Y)
        if c and c[0] == SK and c[1] >= 4:
            cv.set(X, Y, (SK, c[1] - 1))
            cv.set(X + 1, Y, (SK, c[1] - 1))
    for _ in range(2):
        X, Y = rng.randrange((x0 + 10) * RES, (x1 - 10) * RES), rng.randrange((y0 + 10) * RES, (y1 - 10) * RES)
        c = cv.get(X, Y)
        if c and c[0] == SK:
            for dx, dy, s in ((0, 0, 1), (1, 0, 2), (0, 1, 2), (1, 1, 2)):
                cv.set(X + dx, Y + dy, (SK, s))


def drape_height(x, y):
    """Broad, irregular cloth folds."""
    return 7 * math.sin(x * 0.045 + 2.2 * math.sin(y * 0.021)) + 3 * math.sin(y * 0.07 + x * 0.013 + 1.3) + 1.2 * math.sin(x * 0.13 - y * 0.05)


def drape_px(cv, X, Y, x, y, phase=0.0, ramp=DR, extra=0.0):
    """One art pixel of cel-shaded drape: lit fold planes and a shadow band
    on the far side of each fold."""
    hx = drape_height(x + 0.5, y + phase) - drape_height(x - 0.5, y + phase)
    hy = drape_height(x, y + 0.5 + phase) - drape_height(x, y - 0.5 + phase)
    i = clamp(0.42 - hx * 0.28 - hy * 0.28 + lamp(x, y) * 0.5, 0, 1)
    v = 1.2 + i * 4.2 + extra
    cv.set(X, Y, (ramp, cloth_band(v)))


def operating_field(cv, rng, window, edge_dist, clips):
    """Dresses a region as a prepped operating field: everything outside
    `window(x, y)` is a sterile drape (cel-shaded folds lit by the lamp, a
    contact shadow and a lit hem where it meets skin, an ink line on the
    edge); the skin just inside the window carries the iodine prep wash in
    brush strokes that fade toward the middle; towel clamps pin the drape
    at `clips`; and wet skin catches a few lamp glints. `edge_dist(x, y)`
    is the distance in field px from the window's edge (inside > 0)."""
    phase = rng.random() * 6.0
    for X, Y, x, y in pixels():
        if window(x, y):
            continue
        d = -edge_dist(x, y)
        extra = 0.0
        if d < 2.5:
            extra = -1.6           # tucked under: shadow on the skin side
        elif d < 4.5:
            extra = 1.1            # folded hem catches the lamp
        drape_px(cv, X, Y, x, y, phase, DR, extra)
        if d < 0.5:
            cv.set(X, Y, INK)
        elif (X * 5 + Y * 3) % 37 == 0 and d > 6:
            cv.set(X, Y, (DR, max(0, cv.get(X, Y)[1] - 1)))   # weave
    # Iodine: a band inside the window, painted in strokes, thinning inward.
    strokes = [(rng.uniform(0, math.tau), rng.uniform(6, 14)) for _ in range(14)]
    waves = [(rng.uniform(5, 13), rng.uniform(0, math.tau)) for _ in range(3)]
    for X, Y, x, y in pixels():
        if not window(x, y):
            continue
        c = cv.get(X, Y)
        if not c or c[0] != SK:
            continue
        d = edge_dist(x, y)
        ang = math.atan2(y - 80, x - 80)
        reach = 7.0
        for a, r in strokes:
            da = abs((ang - a + math.pi) % math.tau - math.pi)
            reach = max(reach, 7.0 + (r - 5.0) * math.exp(-(da / 0.32) ** 2))
        # Brush edge: a soft wavy line along the stroke direction, not noise.
        edge = reach * (0.9 + 0.035 * sum(math.sin(ang * f + ph) for f, ph in waves))
        if d < edge:
            cv.set(X, Y, (IO, clamp(c[1] - 1 + (1 if d < 1.5 else 0), 1, 6)))
            if abs(d - edge) < 0.5:
                cv.set(X, Y, (IO, max(1, c[1] - 2)))
        elif c[1] >= 6 and rng.random() < 0.004:
            cv.set(X, Y, (FX, 3))  # wet glint under the lamp
            cv.set(X + 1, Y, (FX, 3))
    # Towel clamps: a ring handle, its shadow and the jaw biting the drape edge.
    for cx, cy in clips:
        CX, CY = cx * RES, cy * RES
        for dy in range(-7, 9):
            for dx in range(-7, 9):
                rr = math.hypot(dx, dy)
                if 3.4 <= rr <= 5.9:
                    cv.set(CX + dx + 2, CY + dy + 2, (DR, 0))
        for dy in range(-7, 8):
            for dx in range(-7, 8):
                rr = math.hypot(dx, dy)
                if 3.2 <= rr <= 5.8:
                    edge = rr > 5.1 or rr < 3.7
                    cv.set(CX + dx, CY + dy, INK if edge else (MT, 6 if dx + dy < -2 else (4 if dx + dy < 3 else 2)))
        for k in range(4):
            cv.set(CX - 1, CY + 6 + k, INK)
            cv.set(CX, CY + 6 + k, (MT, 3))
            cv.set(CX + 1, CY + 6 + k, (MT, 2))
            cv.set(CX + 2, CY + 6 + k, INK)
        cv.set(CX - 3, CY - 4, (MT, 7))
        cv.set(CX - 2, CY - 4, (MT, 7))


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


def ink_edges(cv, ramp_a, ramp_b):
    """Ink line on the ramp_a side wherever ramp_a meets ramp_b."""
    src = [row[:] for row in cv.px]
    for Y in range(N):
        for X in range(N):
            c = src[Y][X]
            if c is None or c[0] != ramp_a:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if 0 <= X + dx < N and 0 <= Y + dy < N:
                    n = src[Y + dy][X + dx]
                    if n is not None and n[0] == ramp_b:
                        cv.px[Y][X] = INK
                        break


# --- Regions -----------------------------------------------------------------

def neck():
    """Back of the neck / upper back, patient prone. Spine runs vertically."""
    rng = random.Random(11)
    cv = new_canvas()

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

    render_height(cv, h, lambda x, y: SK if y >= hairline(x) else None, scale=0.9)
    # Hair: clumps combed down, split by dark strand lines, a lit band where
    # the lamp catches the crown; darker toward the neck line.
    for X, Y, x, y in pixels():
        hl = hairline(x)
        if y < hl:
            v = 3.6 - (y / hl) * 1.6 + 1.2 * lamp(x, y)
            s = 4 if v >= 4.0 else (3 if v >= 3.0 else 2)
            f = (x / 3.2 + math.sin(y * 0.15) * 0.6) % 1.0
            if f < 0.16:
                s = 1
            elif f > 0.55 and f < 0.75 and v > 3.8:
                s = 5
            cv.set(X, Y, (HR, s))
        elif y < hl + 1.0:
            cv.set(X, Y, (SK, 2))        # the hair's shadow on the nape
    ink_edges(cv, HR, SK)
    skin_details(cv, rng, (0, 30, SIZE, SIZE), 70)
    win, dist = ellipse_window(80, 92, 64, 76, seed=1.0)
    operating_field(cv, rng, win, dist, [(30, 60), (130, 60), (34, 140), (126, 140)])
    return cv


def _limb_drape(cv, half_w):
    """Drape on both sides of a limb, with the contact shadow beside it."""
    for X, Y, x, y in pixels():
        if abs(x - 80) < half_w(y):
            continue
        d = abs(abs(x - 80) - half_w(y))
        drape_px(cv, X, Y, x, y, 0.0, CA, -1.4 if d < 4 else 0.0)


def forearm():
    """Forearm laid vertically (elbow top, wrist bottom) on a drape."""
    rng = random.Random(12)
    cv = new_canvas()

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

    _limb_drape(cv, half_w)
    render_height(cv, h, lambda x, y: SK if inside(x, y) else None, scale=0.6)
    # Veins: faint, cool, a single art px wide.
    for k in range(2):
        x = (70 + k * 16) * RES
        for Y in range(60 * RES, 150 * RES):
            x += rng.choice((-1, 0, 0, 0, 1)) * 0.5
            c = cv.get(int(x), Y)
            if c and c[0] == SK:
                cv.set(int(x), Y, (SK, max(0, c[1] - 1)))
    ink_edges(cv, SK, CA)
    skin_details(cv, rng, (45, 0, 115, SIZE), 60)
    win, dist = limb_window(half_w, 80, 84, 1.0)
    operating_field(cv, rng, win, dist, [(80, 6), (80, 154)])
    return cv


def chest():
    rng = random.Random(13)
    cv = new_canvas()

    def h(x, y):
        v = gauss(x, y, 80, 90, 140, 110, 24)
        v += gauss(x, y, 48, 60, 28, 22, 9) + gauss(x, y, 112, 60, 28, 22, 9)  # pectorals
        v -= ridge_x(x, 80, 4, 3) * clamp((y - 20) / 30, 0, 1)  # sternum
        for ry in (100, 116, 132):  # lower ribs
            v += ridge_x(y, ry + abs(x - 80) * 0.25, 2.5, 1.0) * clamp((abs(x - 80) - 18) / 30, 0, 1)
        return v

    for X, Y, x, y in pixels():
        if y > 150 or y < 6:
            v = 2.0 + lamp(x, y) * 2 + (0.6 if (x // 6) % 2 else 0)
            cv.set(X, Y, (CA, cloth_band(v)))
    render_height(cv, h, lambda x, y: SK if 6 <= y <= 150 else None, scale=0.8)
    ink_edges(cv, SK, CA)
    skin_details(cv, rng, (0, 10, SIZE, 148), 70)
    win, dist = ellipse_window(80, 80, 66, 64, seed=2.0)
    operating_field(cv, rng, win, dist, [(24, 40), (136, 40), (24, 122), (136, 122)])
    return cv


def thigh():
    rng = random.Random(14)
    cv = new_canvas()

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

    _limb_drape(cv, half_w)
    render_height(cv, h, lambda x, y: SK if inside(x, y) else None, scale=0.6)
    ink_edges(cv, SK, CA)
    skin_details(cv, rng, (24, 0, 136, SIZE), 70)
    win, dist = limb_window(half_w, 82, 84, 1.0)
    operating_field(cv, rng, win, dist, [(80, 4)])
    return cv


def orbital():
    """Face close-up around the left eye: brow, socket, cheekbone."""
    rng = random.Random(15)
    cv = new_canvas()

    def h(x, y):
        v = gauss(x, y, 80, 80, 150, 150, 30)
        v += gauss(x, y, 80, 40, 48, 12, 8)  # brow ridge
        v -= gauss(x, y, 80, 80, 26, 18, 9)  # eye socket
        v += gauss(x, y, 84, 82, 18, 12, 6)  # eyeball under lid
        v += gauss(x, y, 92, 122, 40, 16, 8)  # cheekbone
        v += ridge_x(x, 6, 8, 10) * clamp((y - 60) / 60, 0, 1)  # nose bridge at left edge
        return v

    render_height(cv, h, lambda x, y: SK, scale=0.9)
    # Brow: a tapered mass of hair, dark core, strands flicking outward.
    for X, Y, x, y in pixels():
        if not 44 <= x < 120:
            continue
        yb = 32 + ((x - 80) / 40) ** 2 * 5
        th = 6.0 * (1.0 - max(0.0, (x - 96) / 30)) if x > 96 else 6.0 - max(0.0, (52 - x) / 4)
        if yb <= y < yb + th:
            f = (x * 0.55 - (y - yb) * 0.9) % 1.0
            s = 1 if f < 0.22 else (3 if y < yb + th * 0.4 and x < 84 else 2)
            cv.set(X, Y, (HR, s))
    # Closed eyelid: an ink lash line, lashes, the lid crease above.
    for X in range(58 * RES, 104 * RES):
        x = (X + 0.5) / RES
        y = 88 - ((x - 81) / 23) ** 2 * 4
        Y = int(y * RES)
        cv.set(X, Y, INK)
        cv.set(X, Y + 1, INK)
        if X % 5 == 0:
            cv.set(X, Y + 2, INK)
            cv.set(X - 1, Y + 3, INK)
        cv.set(X, Y - 1, (SK, 3))
        cv.set(X, int((y - 7 + ((x - 81) / 23) ** 2 * 1.5) * RES), (SK, 3))
    skin_details(cv, rng, (0, 0, SIZE, SIZE), 80)
    win, dist = ellipse_window(84, 84, 68, 60, wobble=0.03, seed=3.0)
    operating_field(cv, rng, win, dist, [(26, 46), (142, 46), (40, 142), (130, 142)])
    return cv


REGIONS = {"neck": neck, "forearm": forearm, "chest": chest, "thigh": thigh, "orbital": orbital}


def generate():
    for name, fn in REGIONS.items():
        fn().save(f"surgery/regions/{name}.png")
    scan_hologram().save("surgery/scan_hologram.png")
    print("regions:", len(REGIONS), "at", N, "px")


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
