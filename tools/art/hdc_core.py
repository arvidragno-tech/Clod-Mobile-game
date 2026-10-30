"""HD character core: palette-indexed canvases at 1.5x the v2 resolution.

The v2 characters were designed on a 96x112 portrait and a 40x80 body. The
HD set keeps those proportions as *logical* coordinates (so faces, builds
and outfits still line up) but rasterises everything at 1.5x: a 144x168
portrait and a 60x120 body. Two kinds of drawing exist side by side:

* logical drawing (lower-case coordinates, continuous units of the old
  grid): shaded primitives (sphere, capsule, cylinder, polygon) and area
  loops via `grid()` are evaluated per HD pixel, so contours and light
  ramps get the extra resolution for free; `f/hl/vl` fill whole logical
  cells (1-2 HD px) for blocky details that should keep their weight.
* HD drawing (upper-case coordinates, integer HD pixels): `P/HL/VL/LN/DOT`
  for the fine detail the old grid could not hold: lashes, irises with two
  catch-lights, lip lines, stitching, zipper teeth, screw heads, strands.

Encoding is unchanged (R = ramp*16, G = shade*32), so the runtime recolours
HD parts exactly like v2 parts.
"""
from __future__ import annotations

import math

from .lib import Canvas, LIGHT, poly_pixels, clamp, bayer

S = 1.5

SK, HR, CA, CB, MT, GL, IR, FX, CC, LT, GR, BL = range(12)
F_OUT, F_EYEW, F_PUPIL, F_HI, F_BLOOD, F_INK, F_LENS, F_RIM = range(8)


def H(v: float) -> int:
    """Logical continuous coordinate -> HD pixel index containing it."""
    return int(math.floor(v * S + 1e-6))


def cell(i: float) -> tuple[int, int]:
    """HD pixel span [a, b) covering logical cell i (pixel centres inside)."""
    i = int(i)
    return int(math.ceil(i * S - 0.5)), int(math.ceil((i + 1) * S - 0.5))


def span(a: float, b: float) -> range:
    """HD pixels whose centres fall in the logical continuous range [a, b)."""
    return range(int(math.ceil(a * S - 0.5)), int(math.ceil(b * S - 0.5)))


class HDCanvas(Canvas):
    """Indexed HD canvas. Integer methods inherited from Canvas (set, get,
    shade_px, rect...) work in HD pixels; the l* methods take logical
    coordinates."""

    def __init__(self, lw: int, lh: int, dither: float = 0.0):
        super().__init__(int(round(lw * S)), int(round(lh * S)), indexed=True)
        self.dither_band = dither

    # --- logical shaded primitives ------------------------------------------------------------
    def lsphere(self, cx, cy, rx, ry, ramp, lo=1.0, hi=6.0, light=LIGHT, rim=None, clip=None):
        cl = None
        if clip is not None:
            cl = lambda X, Y: clip((X + 0.5) / S - 0.5, (Y + 0.5) / S - 0.5)  # noqa: E731
        self.sphere(cx * S, cy * S, rx * S, ry * S, ramp, lo, hi, light, rim, cl)

    def lcapsule(self, ax, ay, bx, by, r, ramp, lo=1.0, hi=6.0, light=LIGHT, r2=None):
        self.capsule(ax * S, ay * S, bx * S, by * S, r * S, ramp, lo, hi, light, None if r2 is None else r2 * S)

    def lcylinder(self, x, y, w, h, ramp, lo=1.0, hi=6.0, vertical=True, light=LIGHT):
        self.cylinder(x * S, y * S, w * S, h * S, ramp, lo, hi, vertical, light)

    def lshaded_poly(self, pts, ramp, top=5.0, bottom=2.0, left_bias=0.8, edge_dark=1.0):
        self.shaded_poly([(x * S, y * S) for x, y in pts], ramp, top, bottom, left_bias, edge_dark)

    def lpoly_pixels(self, pts):
        return poly_pixels([(x * S, y * S) for x, y in pts])

    def lellipse(self, cx, cy, rx, ry, c):
        self.ellipse(cx * S, cy * S, rx * S, ry * S, c)

    def lline(self, x0, y0, x1, y1, c):
        """Thin (1 HD px) line between logical cell centres."""
        self.line((x0 + 0.5) * S - 0.5, (y0 + 0.5) * S - 0.5, (x1 + 0.5) * S - 0.5, (y1 + 0.5) * S - 0.5, c)

    def shade_px(self, x, y, ramp, value):
        """Cel quantisation: shaded primitives land on four flat bands
        (deep shadow, shadow, base, light) instead of a smooth ramp."""
        v = float(value)
        s = 1 if v < 1.6 else (2 if v < 2.9 else (4 if v < 4.4 else 5))
        if v < 0.6:
            s = 0
        self.set(x, y, self.resolve(ramp, s))

    def has(self, X, Y, ramp=None) -> bool:
        p = self.get(X, Y)
        return p is not None and (ramp is None or p[0] == ramp)


def grid(x0, y0, x1, y1):
    """Iterate the HD pixels of the logical box [x0, x1) x [y0, y1).

    Yields (X, Y, x, y): HD indices plus the logical *cell-equivalent*
    coordinates, so formulas written for the old grid as `x + 0.5` still
    land on the pixel centre."""
    for Y in span(y0, y1):
        y = (Y + 0.5) / S - 0.5
        for X in span(x0, x1):
            yield X, Y, (X + 0.5) / S - 0.5, y


# --- logical cell drawing (keeps the weight of the old pixels) ------------------------------------

def f(c: HDCanvas, x, y, ramp, shade):
    xa, xb = cell(x)
    ya, yb = cell(y)
    col = (ramp, int(clamp(shade, 0, 7)))
    for Y in range(ya, yb):
        for X in range(xa, xb):
            c.set(X, Y, col)


def hl(c, x0, x1, y, ramp, shade):
    a, b = int(round(x0)), int(round(x1))
    xa, _ = cell(min(a, b))
    _, xb = cell(max(a, b))
    ya, yb = cell(y)
    col = (ramp, int(clamp(shade, 0, 7)))
    for Y in range(ya, yb):
        for X in range(xa, xb):
            c.set(X, Y, col)


def vl(c, x, y0, y1, ramp, shade):
    a, b = int(round(y0)), int(round(y1))
    ya, _ = cell(min(a, b))
    _, yb = cell(max(a, b))
    xa, xb = cell(x)
    col = (ramp, int(clamp(shade, 0, 7)))
    for Y in range(ya, yb):
        for X in range(xa, xb):
            c.set(X, Y, col)


def hl1(c, x0, x1, y, ramp, shade):
    """Thin horizontal line (1 HD px tall) across logical cells x0..x1."""
    a, b = int(round(x0)), int(round(x1))
    xa, _ = cell(min(a, b))
    _, xb = cell(max(a, b))
    HL(c, xa, xb - 1, H(y + 0.5), ramp, shade)


def vl1(c, x, y0, y1, ramp, shade):
    a, b = int(round(y0)), int(round(y1))
    ya, _ = cell(min(a, b))
    _, yb = cell(max(a, b))
    VL(c, H(x + 0.5), ya, yb - 1, ramp, shade)


def shade_cell(c, x, y, ramp, value):
    xa, xb = cell(x)
    ya, yb = cell(y)
    for Y in range(ya, yb):
        for X in range(xa, xb):
            c.shade_px(X, Y, ramp, value)


# --- HD pixel drawing ---------------------------------------------------------------------------

def P(c, X, Y, ramp, shade):
    c.set(int(X), int(Y), (ramp, int(clamp(shade, 0, 7))))


def HL(c, X0, X1, Y, ramp, shade):
    for X in range(int(min(X0, X1)), int(max(X0, X1)) + 1):
        P(c, X, Y, ramp, shade)


def VL(c, X, Y0, Y1, ramp, shade):
    for Y in range(int(min(Y0, Y1)), int(max(Y0, Y1)) + 1):
        P(c, X, Y, ramp, shade)


def LN(c, X0, Y0, X1, Y1, ramp, shade):
    c.line(X0, Y0, X1, Y1, (ramp, int(clamp(shade, 0, 7))))


def DOT(c, X, Y, ramp, shade, n=1):
    for dy in range(n):
        for dx in range(n):
            P(c, X + dx, Y + dy, ramp, shade)


def RECT(c, X, Y, W, Hh, ramp, shade):
    for yy in range(int(Y), int(Y + Hh)):
        for xx in range(int(X), int(X + W)):
            P(c, xx, yy, ramp, shade)


def plate(c, x0, y0, x1, y1, ramp=MT, lo=2.0, hi=5.6, screws=False):
    """Bevelled plate over the logical cells x0..x1, y0..y1 (inclusive),
    drawn at HD: chamfered corners, a bright top bevel, a dark lip, and
    optional screw heads."""
    X0, _ = cell(x0)
    _, X1 = cell(x1)
    Y0, _ = cell(y0)
    _, Y1 = cell(y1)
    X1 -= 1
    Y1 -= 1
    pts = [(X0 + 1, Y0), (X1, Y0), (X1 + 1, Y0 + 1), (X1 + 1, Y1), (X1, Y1 + 1), (X0 + 1, Y1 + 1), (X0, Y1), (X0, Y0 + 1)]
    c.shaded_poly(pts, ramp, top=hi, bottom=lo, left_bias=2.0, edge_dark=0.5)
    HL(c, X0 + 1, X1 - 1, Y0, ramp, 7)
    HL(c, X0 + 1, X1 - 1, Y1, ramp, 0)
    if screws and X1 - X0 >= 6 and Y1 - Y0 >= 5:
        for sx, sy in ((X0 + 2, Y0 + 2), (X1 - 2, Y0 + 2), (X0 + 2, Y1 - 2), (X1 - 2, Y1 - 2)):
            P(c, sx, sy, ramp, 6)
            P(c, sx + 1, sy + 1, ramp, 1)


def stitch_h(c, X0, X1, Y, ramp, shade, gap=2):
    """Dashed stitching along a seam."""
    for X in range(int(X0), int(X1) + 1, gap + 1):
        P(c, X, Y, ramp, shade)


def stitch_v(c, X, Y0, Y1, ramp, shade, gap=2):
    for Y in range(int(Y0), int(Y1) + 1, gap + 1):
        P(c, X, Y, ramp, shade)


def zipper(c, X, Y0, Y1, ramp=MT):
    """Zip teeth: alternating bright/dark HD pixels either side of a line."""
    for Y in range(int(Y0), int(Y1) + 1):
        P(c, X, Y, ramp, 2)
        P(c, X - 1 + (Y % 2) * 2, Y, ramp, 6 if Y % 2 else 4)


def screw(c, X, Y, ramp=MT):
    P(c, X, Y, ramp, 6)
    P(c, X + 1, Y, ramp, 3)
    P(c, X, Y + 1, ramp, 3)
    P(c, X + 1, Y + 1, ramp, 1)


def stipple(X, Y, density: float) -> bool:
    """Ordered (Bayer) stipple: regular fine texture instead of noise."""
    return bayer(X, Y) < density


def bbox(cv: HDCanvas):
    xs, ys = [], []
    for y in range(cv.h):
        row = cv.px[y]
        for x in range(cv.w):
            if row[x] is not None:
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return min(xs), min(ys), max(xs) - min(xs) + 1, max(ys) - min(ys) + 1


def ink_outline(cv: HDCanvas, ramp=FX, shade=F_OUT):
    """Closes a part with a 1 px ink line just outside its silhouette
    (4-neighbour), the clean dark contour of modern character pixel art."""
    src = [row[:] for row in cv.px]
    for y in range(cv.h):
        for x in range(cv.w):
            if src[y][x] is not None:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < cv.w and 0 <= ny < cv.h and src[ny][nx] is not None and src[ny][nx] != (ramp, shade):
                    cv.px[y][x] = (ramp, shade)
                    break
