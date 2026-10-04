"""Pixel-art drawing library.

A Canvas holds either RGBA colours or palette indices (ramp, shade). All
shading primitives work on 8-step ramps and dither between shades with a
4x4 Bayer matrix, which produces the "gradients made of pixel clusters" look
without any smooth blending. LitScene adds a per-pixel lighting pass with
banded, dithered falloff for environments.
"""
from __future__ import annotations

import math
import os
from PIL import Image

from . import palette as pal

BAYER4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
# Key light from top-left-front, used everywhere for consistency.
LIGHT = (-0.55, -0.62, 0.56)
_ln = math.sqrt(sum(c * c for c in LIGHT))
LIGHT = tuple(c / _ln for c in LIGHT)

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SPRITES = os.path.join(ROOT, "assets", "sprites")


def bayer(x: int, y: int) -> float:
    return (BAYER4[y & 3][x & 3] + 0.5) / 16.0


def clamp(v, lo, hi):
    return lo if v < lo else hi if v > hi else v


class Canvas:
    """Pixel buffer. In indexed mode a colour is (ramp_id, shade); in RGB mode
    it is (r, g, b, a). `ramp` arguments are a ramp id (indexed) or a list of
    8 RGB tuples (RGB)."""

    def __init__(self, w: int, h: int, indexed: bool = False, fill=None):
        self.w, self.h = w, h
        self.indexed = indexed
        self.px = [[fill] * w for _ in range(h)]
        self.ox = 0
        self.oy = 0

    # --- basic access ---
    def resolve(self, ramp, shade):
        s = int(clamp(shade, 0, 7))
        if self.indexed:
            return (ramp, s)
        c = ramp[s]
        return (c[0], c[1], c[2], 255)

    def inside(self, x: int, y: int) -> bool:
        return 0 <= x < self.w and 0 <= y < self.h

    def set(self, x: int, y: int, c) -> None:
        x += self.ox
        y += self.oy
        if 0 <= x < self.w and 0 <= y < self.h:
            if c is not None and not self.indexed and len(c) == 4 and c[3] < 255:
                base = self.px[y][x]
                if base is None:
                    self.px[y][x] = c
                    return
                a = c[3] / 255.0
                self.px[y][x] = (round(base[0] + (c[0] - base[0]) * a), round(base[1] + (c[1] - base[1]) * a),
                                 round(base[2] + (c[2] - base[2]) * a), max(base[3], c[3]))
                return
            self.px[y][x] = c

    def get(self, x: int, y: int):
        x += self.ox
        y += self.oy
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[y][x]
        return None

    # Width of the fractional band that gets dithered (1.0 = always dither,
    # smaller = cleaner clusters with dithering only at shade transitions).
    dither_band = 0.5

    def shade_px(self, x: int, y: int, ramp, value: float) -> None:
        """Set a pixel to a fractional shade, dithering between neighbours."""
        base = math.floor(value)
        frac = value - base
        t = 0.5 + (bayer(x + self.ox, y + self.oy) - 0.5) * self.dither_band
        s = base + (1 if frac > t else 0)
        self.set(x, y, self.resolve(ramp, s))

    # --- shapes (flat colour) ---
    def rect(self, x, y, w, h, c):
        for yy in range(int(y), int(y + h)):
            for xx in range(int(x), int(x + w)):
                self.set(xx, yy, c)

    def hline(self, x0, x1, y, c):
        for x in range(int(min(x0, x1)), int(max(x0, x1)) + 1):
            self.set(x, int(y), c)

    def vline(self, x, y0, y1, c):
        for y in range(int(min(y0, y1)), int(max(y0, y1)) + 1):
            self.set(int(x), y, c)

    def line(self, x0, y0, x1, y1, c):
        x0, y0, x1, y1 = int(round(x0)), int(round(y0)), int(round(x1)), int(round(y1))
        dx, dy = abs(x1 - x0), -abs(y1 - y0)
        sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
        err = dx + dy
        while True:
            self.set(x0, y0, c)
            if x0 == x1 and y0 == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x0 += sx
            if e2 <= dx:
                err += dx
                y0 += sy

    def polyline(self, pts, c):
        for a, b in zip(pts, pts[1:]):
            self.line(a[0], a[1], b[0], b[1], c)

    def ellipse(self, cx, cy, rx, ry, c):
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                    self.set(x, y, c)

    def poly(self, pts, c):
        for x, y in poly_pixels(pts):
            self.set(x, y, c)

    def dither_rect(self, x, y, w, h, c, density=0.5):
        for yy in range(int(y), int(y + h)):
            for xx in range(int(x), int(x + w)):
                if bayer(xx, yy) < density:
                    self.set(xx, yy, c)

    # --- shaded primitives ---
    def sphere(self, cx, cy, rx, ry, ramp, lo=1.0, hi=6.0, light=LIGHT, rim=None, clip=None):
        """Ellipsoid shading. rim=(ramp, shade) paints a 1px rim on the side
        facing away from the key light (fake bounce / screen glow)."""
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                nx = (x + 0.5 - cx) / rx
                ny = (y + 0.5 - cy) / ry
                d = nx * nx + ny * ny
                if d > 1.0 or (clip and not clip(x, y)):
                    continue
                nz = math.sqrt(1.0 - d)
                i = clamp(nx * light[0] + ny * light[1] + nz * light[2], 0.0, 1.0)
                self.shade_px(x, y, ramp, lo + (hi - lo) * i)
                if rim and d > 0.78 and nx > 0.35:
                    self.set(x, y, self.resolve(*rim))

    def cylinder(self, x, y, w, h, ramp, lo=1.0, hi=6.0, vertical=True, light=LIGHT):
        """Axis-aligned cylinder (vertical = axis along y)."""
        for yy in range(int(y), int(y + h)):
            for xx in range(int(x), int(x + w)):
                t = ((xx + 0.5 - x) / w) * 2 - 1 if vertical else ((yy + 0.5 - y) / h) * 2 - 1
                nz = math.sqrt(max(0.0, 1 - t * t))
                n = (t, 0.0, nz) if vertical else (0.0, t, nz)
                i = clamp(n[0] * light[0] + n[1] * light[1] + n[2] * light[2], 0, 1)
                self.shade_px(xx, yy, ramp, lo + (hi - lo) * i)

    def capsule(self, ax, ay, bx, by, r, ramp, lo=1.0, hi=6.0, light=LIGHT, r2=None):
        """Rounded limb between two points, radius tapering r -> r2."""
        r2 = r if r2 is None else r2
        minx, maxx = int(min(ax, bx) - max(r, r2) - 1), int(max(ax, bx) + max(r, r2) + 2)
        miny, maxy = int(min(ay, by) - max(r, r2) - 1), int(max(ay, by) + max(r, r2) + 2)
        vx, vy = bx - ax, by - ay
        ll = vx * vx + vy * vy or 1.0
        for y in range(miny, maxy):
            for x in range(minx, maxx):
                px, py = x + 0.5 - ax, y + 0.5 - ay
                t = clamp((px * vx + py * vy) / ll, 0.0, 1.0)
                rr = r + (r2 - r) * t
                dx, dy = px - vx * t, py - vy * t
                d = math.sqrt(dx * dx + dy * dy)
                if d > rr:
                    continue
                nx, ny = dx / rr, dy / rr
                nz = math.sqrt(max(0.0, 1 - nx * nx - ny * ny))
                i = clamp(nx * light[0] + ny * light[1] + nz * light[2], 0, 1)
                self.shade_px(x, y, ramp, lo + (hi - lo) * i)

    def shaded_poly(self, pts, ramp, top=5.0, bottom=2.0, left_bias=0.8, edge_dark=1.0):
        """Flat-ish panel (cloth, plates): vertical gradient, lit from the
        left, edges darkened for a soft ambient-occlusion read."""
        pix = poly_pixels(pts)
        if not pix:
            return
        s = set(pix)
        ys = [p[1] for p in pix]
        xs = [p[0] for p in pix]
        y0, y1 = min(ys), max(ys)
        x0, x1 = min(xs), max(xs)
        for x, y in pix:
            ty = (y - y0) / max(1, y1 - y0)
            tx = (x - x0) / max(1, x1 - x0)
            v = top + (bottom - top) * ty + (0.5 - tx) * left_bias
            edge = sum(1 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if (x + dx, y + dy) not in s)
            if edge:
                v -= edge_dark
            self.shade_px(x, y, ramp, v)

    def selective_outline(self, darken_lit_side=True, only_ramp=None):
        """Sel-out: outline each opaque region with the darkest shade of the
        neighbouring colour instead of pure black (avoids heavy outlines).
        The lit (top/left) side gets a lighter outline."""
        src = [row[:] for row in self.px]
        for y in range(self.h):
            for x in range(self.w):
                if src[y][x] is not None:
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < self.w and 0 <= ny < self.h and src[ny][nx] is not None:
                        n = src[ny][nx]
                        lit = dx > 0 or dy > 0  # neighbour is right/below -> we are on its top/left (lit) side
                        if self.indexed:
                            if only_ramp is not None and n[0] != only_ramp:
                                break
                            shade = 1 if (lit and darken_lit_side) else 0
                            self.px[y][x] = (n[0], shade) if n[0] != pal.RAMP_FIXED else (pal.RAMP_FIXED, 0)
                        else:
                            k = 0.55 if lit else 0.35
                            self.px[y][x] = (int(n[0] * k), int(n[1] * k), int(n[2] * k), 255)
                        break

    def noise(self, x, y, w, h, c, chance, rng, mask=None):
        for yy in range(int(y), int(y + h)):
            for xx in range(int(x), int(x + w)):
                if rng.random() < chance and (mask is None or self.get(xx, yy) is not None):
                    self.set(xx, yy, c)

    def paste(self, other: "Canvas", x: int, y: int) -> None:
        for yy in range(other.h):
            for xx in range(other.w):
                c = other.px[yy][xx]
                if c is not None:
                    self.set(x + xx, y + yy, c)

    def flipped(self) -> "Canvas":
        c = Canvas(self.w, self.h, self.indexed)
        c.px = [row[::-1] for row in self.px]
        return c

    # --- output ---
    def to_image(self, palette_map=None) -> Image.Image:
        img = Image.new("RGBA", (self.w, self.h), (0, 0, 0, 0))
        out = img.load()
        for y in range(self.h):
            for x in range(self.w):
                c = self.px[y][x]
                if c is None:
                    continue
                if self.indexed:
                    if palette_map is None:
                        # Encoded form read by the game: R = ramp*16 (16 ramps),
                        # G = shade*32 (8 shades).
                        out[x, y] = (c[0] * 16, c[1] * 32, 0, 255)
                    else:
                        rgb = palette_map[c[0]][c[1]]
                        out[x, y] = (rgb[0], rgb[1], rgb[2], 255)
                else:
                    out[x, y] = tuple(int(v) for v in c)
        return img

    def save(self, rel_path: str, scale: int = 1, palette_map=None, opaque=False) -> str:
        path = os.path.join(SPRITES, rel_path)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        img = self.to_image(palette_map)
        if scale != 1:
            img = img.resize((self.w * scale, self.h * scale), Image.NEAREST)
        if opaque:
            img = img.convert("RGB")
        img.save(path, optimize=True)
        return path


def poly_pixels(pts):
    """Scanline polygon fill; returns covered pixel coordinates."""
    out = []
    if len(pts) < 3:
        return out
    ys = [p[1] for p in pts]
    for y in range(int(math.floor(min(ys))), int(math.ceil(max(ys))) + 1):
        cy = y + 0.5
        xs = []
        n = len(pts)
        for i in range(n):
            x0, y0 = pts[i]
            x1, y1 = pts[(i + 1) % n]
            if (y0 <= cy < y1) or (y1 <= cy < y0):
                xs.append(x0 + (cy - y0) * (x1 - x0) / (y1 - y0))
        xs.sort()
        for i in range(0, len(xs) - 1, 2):
            for x in range(int(math.ceil(xs[i] - 0.5)), int(math.floor(xs[i + 1] - 0.5)) + 1):
                out.append((x, y))
    return out


# --- Lighting ------------------------------------------------------------------

class Light:
    def __init__(self, x, y, color_hex, radius, intensity=1.0, cone=None, falloff=2.0):
        self.x, self.y = x, y
        r, g, b = pal.hex_to_rgb(color_hex)
        self.color = (r / 255.0, g / 255.0, b / 255.0)
        self.radius = radius
        self.intensity = intensity
        self.cone = cone  # (direction_deg, half_angle_deg)
        self.falloff = falloff

    def at(self, x, y) -> float:
        dx, dy = x - self.x, y - self.y
        d = math.sqrt(dx * dx + dy * dy)
        if d >= self.radius:
            return 0.0
        i = (1.0 - d / self.radius) ** self.falloff * self.intensity
        if self.cone and d > 0.5:
            ang = math.degrees(math.atan2(dy, dx))
            diff = abs((ang - self.cone[0] + 180) % 360 - 180)
            if diff > self.cone[1]:
                return 0.0
            i *= 1.0 - (diff / self.cone[1]) ** 3
        return i


class LitScene:
    """Albedo + emissive buffers with point/cone lights. Light intensity is
    quantised into bands and dithered at band edges, the classic pixel-art
    way of drawing light falloff."""

    def __init__(self, w, h, ambient=(0.30, 0.31, 0.40), bands=7):
        self.w, self.h = w, h
        self.albedo = Canvas(w, h, fill=(10, 12, 18, 255))
        self.emissive = Canvas(w, h, fill=None)
        self.lights: list[Light] = []
        self.ambient = ambient
        self.bands = bands
        # Pixels marked here ignore lighting (UI-ish signage already lit).
        self.unlit = Canvas(w, h, fill=None)

    def light(self, *args, **kw) -> Light:
        l = Light(*args, **kw)
        self.lights.append(l)
        return l

    def render(self, region=None) -> Canvas:
        """Lit image. region=(x0, y0, x1, y1) limits the work to a box
        (pixels outside stay black), used to diff overlays cheaply."""
        out = Canvas(self.w, self.h, fill=(0, 0, 0, 255))
        x0, y0, x1, y1 = region if region else (0, 0, self.w, self.h)
        for y in range(max(0, y0), min(self.h, y1)):
            for x in range(max(0, x0), min(self.w, x1)):
                a = self.albedo.px[y][x]
                e = self.emissive.px[y][x]
                if self.unlit.px[y][x] is not None:
                    out.px[y][x] = a
                    continue
                lr, lg, lb = self.ambient
                for l in self.lights:
                    i = l.at(x + 0.5, y + 0.5)
                    if i <= 0.0:
                        continue
                    q = math.floor(i * self.bands + bayer(x, y) * 0.999) / self.bands
                    lr += l.color[0] * q
                    lg += l.color[1] * q
                    lb += l.color[2] * q
                r = min(255, a[0] * lr)
                g = min(255, a[1] * lg)
                b = min(255, a[2] * lb)
                if e is not None:
                    r, g, b = max(r, e[0]), max(g, e[1]), max(b, e[2])
                out.px[y][x] = (int(r), int(g), int(b), 255)
        return out


def ramp_of(hex_color: str, shift=0.08, contrast=1.0):
    return pal.ramp(hex_color, shift, contrast)


def save_preview_sheet(images: list[Image.Image], path: str, scale: int = 3, bg=(14, 16, 24, 255), cols=8):
    """Debug contact sheet (not shipped)."""
    if not images:
        return
    cw = max(i.width for i in images) * scale + 4
    ch = max(i.height for i in images) * scale + 4
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGBA", (cw * min(cols, len(images)), ch * rows), bg)
    for k, im in enumerate(images):
        r, c = divmod(k, cols)
        big = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
        sheet.paste(big, (c * cw + 2, r * ch + 2), big)
    sheet.save(path)
