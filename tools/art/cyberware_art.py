"""Cyberware art, drawn once as a design and rasterised at two densities:

* the item icon, 48x48 (shown at GameConfig.ART_SCALE, the same 96-unit
  footprint the old 32 px icons had at PIXEL_SCALE), and
* the surgical-field implant, 64x64 (the field is 320 px wide, so the
  implant keeps the share of the field the old 32 px art had of 160).

Designs are written on a 32-unit grid and every primitive is evaluated per
output pixel, so the larger rasters get real extra detail (panel seams,
screw slots, pistons, finger joints) rather than an upscale. The look
follows modern character pixel art: flat cel bands lit from the upper
left, a 1 px near-black ink contour, 1 px speculars and hard emissive
cores. Engineered, not magical: housings, screws, connectors, cables and
synthetic muscle; glow is reserved for status LEDs, optics and active
cores. Tier changes the material language.
"""
from __future__ import annotations

import math

from . import palette as pal
from .lib import Canvas, LIGHT, clamp, poly_pixels

CATEGORIES = ["eyes", "arms", "legs", "spine", "neural", "dermal", "respiratory", "internal"]
ICON_SIZE = 48
FIELD_SIZE = 64
INK = (14, 12, 20, 255)

# Tier material language
TIER_STYLE = {
    1: dict(body="c2bba9", trim="6e6a62", metal="8e9aa8", led="amber", accent="7a5a3a"),   # civilian: beige polymer
    2: dict(body="8e9aa8", trim="2f3c56", metal="b6c0cc", led="cyan", accent="2a3f5c"),    # professional chrome
    3: dict(body="4f5864", trim="4a4f2e", metal="6a7380", led="red", accent="3a3f28"),     # military gunmetal/olive
    4: dict(body="d6dade", trim="8aa0b8", metal="c8ccd2", led="blue", accent="3a8cff"),    # experimental ceramic
    5: dict(body="2e3138", trim="5a3424", metal="58606b", led="magenta", accent="ff3d81"),  # black-market prototype
}


def R(hexc, shift=0.06, contrast=1.1):
    return pal.ramp(hexc, shift, contrast)


class Style:
    def __init__(self, tier):
        st = TIER_STYLE[tier]
        self.tier = tier
        self.body = R(st["body"])
        self.trim = R(st["trim"])
        self.metal = R(st["metal"])
        self.glow = pal.glow_ramp(pal.GLOWS[st["led"]])
        self.accent = R(st["accent"])
        self.cable = R("2a2a32")
        self.muscle = R("7a2030", 0.1)
        self.gold = R("a8843a", 0.05)
        self.glass = R("12161e")
        self.pcb = R("1f4a3a" if tier < 5 else "2a1f30")
        self.tape = R("b0965c", 0.04)


def rgb(ramp, i):
    c = ramp[int(clamp(i, 0, 7))]
    return (c[0], c[1], c[2], 255)


def band(v: float) -> int:
    """Cel bands: deep shadow, shadow, base, light."""
    if v < 1.6:
        return 1
    if v < 2.9:
        return 2
    if v < 4.4:
        return 4
    return 5


class Pen:
    """Draws a 32-unit design onto a canvas of any size. Shapes take design
    units; `px` is output pixels per design unit."""

    def __init__(self, size: int):
        self.cv = Canvas(size, size)
        self.px = size / 32.0

    # -- coordinates ----------------------------------------------------------------------------
    def P(self, v):
        return v * self.px

    def cells(self, x0, y0, x1, y1):
        """Output pixels whose centres fall in the design box, with the
        design coordinate of each centre."""
        k = self.px
        for Y in range(int(math.floor(y0 * k)), int(math.ceil(y1 * k))):
            y = (Y + 0.5) / k
            if not (y0 <= y < y1):
                continue
            for X in range(int(math.floor(x0 * k)), int(math.ceil(x1 * k))):
                x = (X + 0.5) / k
                if x0 <= x < x1:
                    yield X, Y, x, y

    def put(self, X, Y, c):
        self.cv.set(int(X), int(Y), c)

    def shade(self, X, Y, ramp, v):
        self.put(X, Y, rgb(ramp, band(v)))

    # -- shaded primitives ----------------------------------------------------------------------
    def sphere(self, cx, cy, rx, ry, ramp, lo=1.0, hi=6.0, clip=None):
        for X, Y, x, y in self.cells(cx - rx, cy - ry, cx + rx, cy + ry):
            nx, ny = (x - cx) / rx, (y - cy) / ry
            d = nx * nx + ny * ny
            if d > 1.0 or (clip and not clip(x, y)):
                continue
            nz = math.sqrt(1 - d)
            i = clamp(nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2], 0, 1)
            self.shade(X, Y, ramp, lo + (hi - lo) * i)

    def capsule(self, ax, ay, bx, by, r, ramp, lo=1.0, hi=6.0, r2=None, mask=None):
        r2 = r if r2 is None else r2
        m = max(r, r2)
        vx, vy = bx - ax, by - ay
        ll = vx * vx + vy * vy or 1.0
        for X, Y, x, y in self.cells(min(ax, bx) - m, min(ay, by) - m, max(ax, bx) + m, max(ay, by) + m):
            px, py = x - ax, y - ay
            t = clamp((px * vx + py * vy) / ll, 0.0, 1.0)
            rr = r + (r2 - r) * t
            dx, dy = px - vx * t, py - vy * t
            d = math.hypot(dx, dy)
            if d > rr:
                continue
            if mask is not None:
                mask.add((X, Y))
            nx, ny = dx / rr, dy / rr
            nz = math.sqrt(max(0.0, 1 - nx * nx - ny * ny))
            i = clamp(nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2], 0, 1)
            self.shade(X, Y, ramp, lo + (hi - lo) * i)

    def cylinder(self, x0, y0, w, h, ramp, lo=1.0, hi=6.0, vertical=True):
        for X, Y, x, y in self.cells(x0, y0, x0 + w, y0 + h):
            t = ((x - x0) / w) * 2 - 1 if vertical else ((y - y0) / h) * 2 - 1
            nz = math.sqrt(max(0.0, 1 - t * t))
            i = clamp((t * LIGHT[0] if vertical else t * LIGHT[1]) + nz * LIGHT[2], 0, 1)
            self.shade(X, Y, ramp, lo + (hi - lo) * i)

    def panel(self, pts, ramp, top=5.0, bottom=2.4, bevel=True):
        """A flat plate: cel bands top to bottom, a lit top/left bevel and a
        dark bottom/right lip one output pixel wide."""
        pix = set(poly_pixels([(x * self.px, y * self.px) for x, y in pts]))
        if not pix:
            return pix
        ys = [p[1] for p in pix]
        y0, y1 = min(ys), max(ys)
        for X, Y in pix:
            t = (Y - y0) / max(1, y1 - y0)
            self.shade(X, Y, ramp, top + (bottom - top) * t)
        if bevel:
            for X, Y in pix:
                if (X, Y - 1) not in pix or (X - 1, Y) not in pix:
                    self.put(X, Y, rgb(ramp, 6))
                elif (X, Y + 1) not in pix or (X + 1, Y) not in pix:
                    self.put(X, Y, rgb(ramp, 1))
        return pix

    # -- line work ------------------------------------------------------------------------------
    def line(self, x0, y0, x1, y1, c):
        self.cv.line(x0 * self.px, y0 * self.px, x1 * self.px, y1 * self.px, c)

    def seam(self, x0, y0, x1, y1, ramp, lit=True):
        """Panel seam: a dark 1 px groove with a lit edge under it."""
        self.line(x0, y0, x1, y1, rgb(ramp, 0))
        if lit:
            d = 1.0 / self.px
            self.line(x0, y0 + d, x1, y1 + d, rgb(ramp, 5))

    def screw(self, x, y, ramp):
        X, Y = int(x * self.px), int(y * self.px)
        if self.px >= 1.9:
            for dx, dy, s in ((0, 0, 6), (1, 0, 5), (2, 0, 4), (0, 1, 5), (1, 1, 1), (2, 1, 3), (0, 2, 3), (1, 2, 3), (2, 2, 1)):
                self.put(X + dx, Y + dy, rgb(ramp, s))
        else:
            for dx, dy, s in ((0, 0, 6), (1, 0, 3), (0, 1, 2), (1, 1, 1)):
                self.put(X + dx, Y + dy, rgb(ramp, s))

    def led(self, x, y, st, big=False):
        X, Y = int(x * self.px), int(y * self.px)
        n = 2 if (big or self.px >= 1.9) else 1
        for dy in range(n):
            for dx in range(n):
                self.put(X + dx, Y + dy, rgb(st.glow, 7 if dx == 0 and dy == 0 else 5))
        if big:
            for dx in range(-1, n + 1):
                for dy in (-1, n):
                    if self.cv.get(X + dx, Y + dy) is not None:
                        self.put(X + dx, Y + dy, rgb(st.glow, 3))

    def cable(self, pts, st, w=1.2):
        """A sheathed cable: dark core, a lit stripe, ribbing every few px."""
        for a, b in zip(pts, pts[1:]):
            self.capsule(a[0], a[1], b[0], b[1], w, st.cable, 1.0, 5.6)
        step = max(3, int(3 * self.px))
        for a, b in zip(pts, pts[1:]):
            n = int(math.hypot(b[0] - a[0], b[1] - a[1]) * self.px)
            for k in range(0, n, step):
                t = k / max(1, n)
                x, y = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
                self.put(x * self.px, y * self.px, rgb(st.cable, 0))

    def spec(self, x, y, n=1):
        X, Y = int(x * self.px), int(y * self.px)
        for k in range(n):
            self.put(X + k, Y, (246, 248, 251, 255))

    def ink(self):
        """1 px near-black contour just outside the silhouette."""
        cv = self.cv
        src = [row[:] for row in cv.px]
        for y in range(cv.h):
            for x in range(cv.w):
                if src[y][x] is not None:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < cv.w and 0 <= ny < cv.h and src[ny][nx] is not None:
                        cv.px[y][x] = INK
                        break


def tape(p: Pen, x, y, w, h, st):
    """Improvised repair tape (black-market tier)."""
    p.panel([(x, y), (x + w, y), (x + w, y + h), (x, y + h)], st.tape, 5.2, 4.2, bevel=False)
    for X, Y, xx, yy in p.cells(x, y, x + w, y + h):
        if (X + Y) % 5 == 0:
            p.put(X, Y, rgb(st.tape, 2))


# --- designs ----------------------------------------------------------------------------------------

def draw_eyes(p: Pen, st):
    p.cable([(31, 27), (26, 23), (21, 19)], st, 1.6)
    p.cable([(30, 30), (24, 27)], st, 0.9)
    # Mounting bracket behind the optic.
    p.panel([(17, 9), (25, 9), (27, 11), (27, 21), (25, 23), (17, 23)], st.trim, 5.0, 2.0)
    p.seam(19, 12, 25, 12, st.trim)
    p.seam(19, 20, 25, 20, st.trim)
    p.screw(24, 10, st.metal)
    p.screw(24, 21, st.metal)
    # Housing, front bezel ring, glass, aperture blades and the core.
    p.sphere(13.5, 16, 11.5, 11.5, st.body, 1.0, 6.2)
    p.sphere(12.5, 15.5, 8.2, 8.2, st.metal, 1.2, 6.4)
    p.sphere(12.5, 15.5, 6.4, 6.4, st.glass, 0.6, 3.6)
    for a in range(0, 360, 40):
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        p.line(12.5 + 2.4 * ca, 15.5 + 2.4 * sa, 12.5 + 5.4 * math.cos(math.radians(a + 32)),
               15.5 + 5.4 * math.sin(math.radians(a + 32)), rgb(st.metal, 2))
    p.sphere(12.5, 15.5, 2.3, 2.3, st.glow, 3.0, 7.2)
    p.spec(9.5, 11.5, 2)
    p.spec(15.5, 18.5)
    # Housing seam and the focus ring knurl.
    for k in range(9):
        a = math.radians(200 + k * 14)
        p.put((13.5 + 10.6 * math.cos(a)) * p.px, (16 + 10.6 * math.sin(a)) * p.px, rgb(st.body, 1))
    p.led(4.5, 24, st)


def draw_arms(p: Pen, st):
    """Forearm and fist: segmented plates over a synthetic-muscle core,
    a piston along the ulna, an articulated hand."""
    # Forearm core, muscle showing through the plate gaps.
    p.capsule(6, 29, 20, 13, 5.6, st.muscle, 1.0, 5.0, r2=4.8)
    for k, (t0, t1) in enumerate(((0.0, 0.28), (0.33, 0.6), (0.65, 0.94))):
        ax, ay = 6 + 14 * t0, 29 - 16 * t0
        bx, by = 6 + 14 * t1, 29 - 16 * t1
        p.capsule(ax, ay, bx, by, 5.4 - k * 0.3, st.body, 1.0, 6.2)
        mx, my = (ax + bx) / 2, (ay + by) / 2
        p.seam(mx - 3.2, my - 2.8, mx + 2.8, my + 3.2, st.body)
    p.capsule(3.5, 25, 16.5, 10, 0.9, st.metal, 2.0, 7.0)   # piston rod
    p.capsule(3.0, 26, 8.5, 19.5, 1.5, st.trim, 1.0, 5.2)   # piston sleeve
    # Wrist joint and the hand: palm block, four fingers curled into a fist, thumb.
    p.sphere(21, 12, 3.4, 3.4, st.trim, 1.0, 5.6)
    p.panel([(21, 5), (28, 4), (30, 7), (29, 13), (23, 14), (20, 10)], st.body, 5.4, 2.2)
    for k in range(4):
        fy = 4.6 + k * 2.3
        p.capsule(27.2, fy, 30.0, fy + 0.4, 1.0, st.metal, 1.2, 6.2)
        p.put(30.2 * p.px, (fy + 0.3) * p.px, rgb(st.metal, 1))
    p.capsule(22, 13.5, 26, 11.5, 1.1, st.metal, 1.2, 6.0)  # thumb
    p.screw(9, 25, st.metal)
    p.screw(15.5, 17.5, st.metal)
    p.screw(23.5, 7.5, st.metal)
    p.led(12, 21, st)
    p.spec(8, 22, 2)
    if st.tier >= 3:  # armour plate
        p.panel([(9, 27), (16, 20), (19, 23), (12, 30)], st.trim, 5.0, 2.4)
        p.seam(11, 27, 16, 22, st.trim)


def draw_legs(p: Pen, st):
    p.capsule(10.5, 6.5, 14, 15, 5.4, st.body, 1.0, 6.0, r2=5.0)      # thigh
    p.seam(7, 10, 14.5, 8.5, st.body)
    p.capsule(16, 18, 19.5, 28.5, 4.2, st.body, 1.0, 5.8, r2=3.4)     # shin
    p.seam(13.5, 23, 20, 21.5, st.body)
    p.capsule(21.5, 16.5, 24, 28, 0.9, st.metal, 2.0, 7.0)            # shock piston
    p.capsule(22, 16.5, 23.6, 21.5, 1.7, st.trim, 1.0, 5.2)
    p.panel([(14, 28), (22, 28), (26, 30), (26, 31.5), (13, 31.5)], st.trim, 5.0, 2.0)   # foot
    p.sphere(15, 16, 4.8, 4.8, st.metal, 1.0, 6.6)                    # knee
    p.sphere(15, 16, 2.0, 2.0, st.trim, 1.0, 4.4)
    p.spec(13, 13.5, 2)
    p.screw(8, 7.5, st.metal)
    p.screw(18, 25, st.metal)
    p.led(11.5, 12, st)


def draw_spine(p: Pen, st):
    p.cable([(24, 1.5), (25, 10), (23.5, 18), (25, 30.5)], st, 1.3)
    p.cylinder(13.6, 1.5, 3.2, 29, st.trim, 1.0, 4.8)                 # central conduit
    for k in range(5):
        y = 2.5 + k * 6
        p.panel([(8.5, y), (21.5, y), (23, y + 2.2), (21.5, y + 4.4), (8.5, y + 4.4), (7, y + 2.2)], st.body, 5.6, 2.4)
        p.capsule(5.0, y + 2.2, 8.0, y + 2.2, 0.8, st.metal, 1.5, 6.0)   # transverse pins
        p.capsule(22, y + 2.2, 24.5, y + 2.2, 0.8, st.metal, 1.5, 6.0)
        if k % 2 == 0:
            p.led(14.5, y + 1.6, st)
        else:
            p.screw(14.3, y + 1.4, st.metal)


def draw_neural(p: Pen, st):
    p.panel([(4.5, 6.5), (27.5, 6.5), (27.5, 25.5), (4.5, 25.5)], st.pcb, 4.6, 2.6)
    for x in range(6, 27, 2):  # gold contact pins
        p.panel([(x, 4.2), (x + 1.1, 4.2), (x + 1.1, 6.5), (x, 6.5)], st.gold, 6.0, 4.0, bevel=False)
        p.panel([(x, 25.5), (x + 1.1, 25.5), (x + 1.1, 27.8), (x, 27.8)], st.gold, 4.2, 2.2, bevel=False)
    for k, y in enumerate((9.5, 13, 16.5, 20, 23)):  # traces into the die
        p.line(6, y, 10 + (k % 2), y, rgb(st.gold, 4))
        p.line(10 + (k % 2), y, 11.5, y - 1.5 + k * 0.6, rgb(st.gold, 4))
    p.panel([(12, 9.5), (25, 9.5), (25, 23), (12, 23)], st.body, 5.8, 2.2)   # heat spreader
    for k in range(7):  # fins
        x = 13 + k * 1.75
        p.panel([(x, 10.6), (x + 0.9, 10.6), (x + 0.9, 21.8), (x, 21.8)], st.metal, 6.2 if k < 4 else 4.2, 2.4, bevel=False)
    p.spec(13, 10.6, 3)
    p.led(7.5, 21, st, big=True)
    p.screw(25.5, 7.6, st.metal)
    p.screw(5.4, 7.6, st.metal)
    if st.tier == 5:
        tape(p, 3.5, 14, 6.5, 3, st)


def draw_dermal(p: Pen, st):
    """A curved hex-weave mesh plate."""
    cx, cy, r = 16, 16, 13.2
    for X, Y, x, y in p.cells(cx - r, cy - r, cx + r, cy + r):
        dx, dy = (x - cx) / r, (y - cy) / r
        d = dx * dx + dy * dy
        if d > 1:
            continue
        nz = math.sqrt(1 - d)
        i = clamp(dx * LIGHT[0] + dy * LIGHT[1] + nz * LIGHT[2], 0, 1)
        # Hex cells 4 units across.
        hy = y / 3.4
        row = math.floor(hy)
        hx = (x + (row % 2) * 2.0) / 4.0
        fx, fy = hx - math.floor(hx), hy - row
        seam = fy < 0.18 or fx < 0.12 or fx > 0.94
        if seam:
            p.put(X, Y, rgb(st.trim, max(0, band(1.0 + 4.0 * i) - 1)))
        else:
            p.shade(X, Y, st.body, 1.2 + 5.2 * i - (0.8 if fy > 0.8 else 0))
    p.spec(9, 7.5, 3)
    for q in ((8.5, 9.5), (22, 10), (15.5, 23.5)):
        p.screw(*q, st.metal)
    p.led(15.5, 15, st)


def draw_respiratory(p: Pen, st):
    p.cylinder(8, 6, 16, 22, st.body, 1.0, 6.0)
    for y in range(9, 26, 3):  # vents
        p.panel([(10, y), (22, y), (22, y + 1.1), (10, y + 1.1)], st.trim, 1.6, 1.0, bevel=False)
    p.sphere(16, 6, 8.2, 2.6, st.metal, 2.0, 6.6)
    p.sphere(16, 28, 8.2, 2.6, st.metal, 1.0, 4.6)
    p.cable([(16, 3), (16, 1.2), (24, 1.2), (29.5, 4)], st, 1.1)
    p.sphere(16, 17, 3.6, 3.6, st.metal, 1.0, 6.2)  # intake fan
    for a in range(0, 360, 60):
        ca, sa = math.cos(math.radians(a)), math.sin(math.radians(a))
        p.line(16 + 0.8 * ca, 17 + 0.8 * sa, 16 + 3.2 * math.cos(math.radians(a + 25)), 17 + 3.2 * math.sin(math.radians(a + 25)),
               rgb(st.trim, 1))
    p.sphere(16, 17, 1.0, 1.0, st.trim, 3.0, 5.0)
    p.spec(10, 8.5, 2)
    p.led(21, 25, st)


def draw_internal(p: Pen, st):
    p.capsule(9, 16, 23, 16, 8.0, st.body, 1.0, 6.0)
    fluid = st.glow if st.tier >= 2 else R("4a8a3a")
    window = [(11, 12), (22, 12), (22, 20.5), (11, 20.5)]
    p.panel(window, st.glass, 3.0, 2.0, bevel=False)
    for X, Y, x, y in p.cells(11, 14, 22, 20.5):   # bio-fluid with a meniscus
        if y > 14.2 + 0.6 * math.sin(x * 0.9):
            p.shade(X, Y, fluid, 2.4 + (20.5 - y) * 0.42)
    for X, Y, x, y in p.cells(12, 15.5, 21, 20):    # bubbles
        if (X * 7 + Y * 13) % 41 == 0:
            p.put(X, Y, rgb(fluid, 7))
    p.line(11, 12, 22, 12, rgb(st.metal, 6))
    p.line(11, 20.5, 22, 20.5, rgb(st.metal, 1))
    p.spec(12.5, 13, 2)
    p.cable([(1.5, 9.5), (5.5, 13)], st, 1.2)
    p.cable([(30.5, 22.5), (26.5, 19)], st, 1.2)
    p.screw(6.5, 11, st.metal)
    p.screw(24, 20, st.metal)
    p.led(25, 11, st)


DRAW = {"eyes": draw_eyes, "arms": draw_arms, "legs": draw_legs, "spine": draw_spine, "neural": draw_neural,
        "dermal": draw_dermal, "respiratory": draw_respiratory, "internal": draw_internal}


def make_icon(category: str, tier: int, size: int = ICON_SIZE) -> Canvas:
    p = Pen(size)
    st = Style(tier)
    DRAW[category](p, st)
    if tier == 5 and category != "neural":
        tape(p, 2.5, 2.5, 4.5, 2.2, st)
        p.line(1.5, 29.5, 9, 25, (255, 61, 129, 255))  # exposed live wire
    p.ink()
    return p.cv


def generate():
    """Renders only the category/tier icons that data/cyberware.json uses
    (plus neural_t1, the surgical field's default implant), each as the
    48 px item icon and the 64 px surgical-field implant."""
    import json
    import os
    data = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "cyberware.json")
    wanted = {"neural_t1"}
    for item in json.load(open(data))["cyberware"]:
        wanted.add(os.path.splitext(os.path.basename(item["icon"]))[0])
    n = 0
    for cat in CATEGORIES:
        for tier in range(1, 6):
            if f"{cat}_t{tier}" in wanted:
                make_icon(cat, tier, ICON_SIZE).save(f"cyberware/{cat}_t{tier}.png")
                make_icon(cat, tier, FIELD_SIZE).save(f"cyberware/field/{cat}_t{tier}.png")
                n += 1
    print("cyberware icons:", n, "(48 px icons + 64 px field implants)")
