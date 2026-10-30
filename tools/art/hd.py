"""HD scene kit (art v3): dense, lit pixel-art scenes at 2 canvas units per
art pixel (1.5x the old resolution). numpy buffers, so big scenes with
many lights render in seconds.

Look (see the reference boards in docs/ART_BIBLE.md): deep blue-grey tech
interiors and wet neon alleys; lots of small light sources (screens, LED
strips, indicator dots, tubes); panel seams, rivets, vents, cable runs;
neon halos (bloom); glossy floors that mirror the lights; a little haze.
Light is banded and dithered (Bayer 4x4), and the final image is
posterised with an ordered dither so it stays pixel art, never smooth.

Scene buffers (H, W, 3) floats in 0..1:
  albedo   - surface colour
  emissive - light-emitting pixels (screens, neon, LEDs), unaffected by light
  gloss    - (H, W) 0..1, how much the floor mirrors what's above it
"""
from __future__ import annotations

import math
import os
import random

import numpy as np
from PIL import Image

from .lib import SPRITES

BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16.0 + 1 / 32.0


def hexc(h: str) -> np.ndarray:
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def mix(a, b, t):
    return np.asarray(a, dtype=np.float32) * (1 - t) + np.asarray(b, dtype=np.float32) * t


def shade(c, k):
    """k > 0 lightens towards white, k < 0 darkens."""
    c = np.asarray(c, dtype=np.float32)
    return c + (1 - c) * k if k >= 0 else c * (1 + k)


# Named colours (the HD palette). Kept small so scenes read as one world.
PAL = {
    "void": hexc("06080d"), "night": hexc("0b111b"), "steel0": hexc("121a26"), "steel1": hexc("1b2535"),
    "steel2": hexc("27344a"), "steel3": hexc("3a4a63"), "steel4": hexc("5a6c86"), "steel5": hexc("8a9bb3"),
    "concrete0": hexc("17181c"), "concrete1": hexc("24252b"), "concrete2": hexc("34353d"), "concrete3": hexc("4a4b55"),
    "rust0": hexc("2a160e"), "rust1": hexc("51281a"), "rust2": hexc("7a3f22"), "rust3": hexc("a5602e"),
    "tile0": hexc("1a2230"), "tile1": hexc("243042"), "tile2": hexc("314157"), "white": hexc("e8f2f7"),
    "bone": hexc("c9c2b0"), "skin": hexc("b0806a"), "blood": hexc("6a0f1c"), "grime": hexc("2a2418"),
    "cyan": hexc("2ee6c8"), "teal": hexc("1a9e94"), "blue": hexc("3a8cff"), "ice": hexc("9fe8ff"),
    "pink": hexc("ff3d8b"), "magenta": hexc("d0309a"), "violet": hexc("8a4dff"), "yellow": hexc("ffd23d"),
    "amber": hexc("ffa93d"), "orange": hexc("ff6a2a"), "red": hexc("ff3a3a"), "green": hexc("5dff7a"),
    "lime": hexc("b6ff4a"), "sodium": hexc("ffb35a"), "tungsten": hexc("ffd9a0"), "fluoro": hexc("d8f4ff"),
}


RES = 2  # hi-res pixels per design pixel (art v4: 2x the v3 pixel count)


class Scene:
    """A scene laid out in *design* pixels (w x h, the units ClinicView,
    hotspots and fx anchors use) and rasterised at `res` times that, so a
    600x336 room is a 1200x672 image. Rectangles, polygons, gradients and
    lights are evaluated per hi-res pixel (smooth diagonals, fine light
    bands, fine grain); px/hline/vline keep the weight of one design pixel
    unless given a thinner `t`; bevels, glints and `fpx` are one hi-res
    pixel, the fine detail the old grid could not hold."""

    def __init__(self, w: int, h: int, ambient=(0.16, 0.18, 0.24), seed: int = 1, res: int = RES):
        self.w, self.h = w, h
        self.res = res
        self.rw, self.rh = w * res, h * res
        H, W = self.rh, self.rw
        self.albedo = np.zeros((H, W, 3), dtype=np.float32)
        self.albedo[:] = PAL["night"]
        self.emissive = np.zeros((H, W, 3), dtype=np.float32)
        self.gloss = np.zeros((H, W), dtype=np.float32)
        self.lights: list[dict] = []
        self.ambient = np.array(ambient, dtype=np.float32)
        self.haze = 0.0
        self.haze_color = PAL["steel2"]
        self.floor_y = h  # reflections mirror about this line (design px)
        self.grade = None  # optional colour grade (see neon_grade)
        self.rng = random.Random(seed)
        self.fx: list[dict] = []  # animation anchors for the game (design px)
        yy, xx = np.mgrid[0:H, 0:W]
        self._xx = (xx.astype(np.float32) + 0.5) / res
        self._yy = (yy.astype(np.float32) + 0.5) / res
        self._bayer = np.tile(BAYER, (H // 4 + 1, W // 4 + 1))[:H, :W]

    # --- copies (upgrade overlays are diffs against the base) ---------------------------------
    def copy(self) -> "Scene":
        n = Scene.__new__(Scene)
        n.__dict__.update(self.__dict__)
        n.albedo = self.albedo.copy()
        n.emissive = self.emissive.copy()
        n.gloss = self.gloss.copy()
        n.lights = [dict(l) for l in self.lights]
        n.fx = []
        n.rng = random.Random(1234)
        return n

    # --- basic drawing (design coordinates) ---------------------------------------------------
    def _clip(self, x0, y0, x1, y1):
        """Design box -> hi-res pixel box (pixel centres inside)."""
        r = self.res
        x0, y0 = max(0, int(round(x0 * r))), max(0, int(round(y0 * r)))
        x1, y1 = min(self.rw, int(round(x1 * r))), min(self.rh, int(round(y1 * r)))
        return x0, y0, x1, y1

    def rect(self, x, y, w, h, c, buf="albedo"):
        x0, y0, x1, y1 = self._clip(x, y, x + w, y + h)
        if x1 > x0 and y1 > y0:
            getattr(self, buf)[y0:y1, x0:x1] = c

    def occlude(self, x, y, w, h):
        """Solid foreground: hide any glow drawn behind this box."""
        x0, y0, x1, y1 = self._clip(x, y, x + w, y + h)
        self.emissive[y0:y1, x0:x1] = 0

    def px(self, x, y, c, buf="albedo", t=1.0):
        """One design pixel (or a t x t design-unit dot)."""
        self.rect(int(x) if t >= 1 else x, int(y) if t >= 1 else y, t, t, c, buf)

    def fpx(self, X, Y, c, buf="albedo"):
        """One hi-res pixel at hi-res coordinates."""
        X, Y = int(X), int(Y)
        if 0 <= X < self.rw and 0 <= Y < self.rh:
            getattr(self, buf)[Y, X] = c

    def hline(self, x0, x1, y, c, buf="albedo", t=1.0):
        self.rect(min(x0, x1), y, abs(x1 - x0) + 1, t, c, buf)

    def vline(self, x, y0, y1, c, buf="albedo", t=1.0):
        self.rect(x, min(y0, y1), t, abs(y1 - y0) + 1, c, buf)

    def line(self, x0, y0, x1, y1, c, buf="albedo", t=1.0):
        """Line between design pixel centres, stepped per hi-res pixel with
        a brush t design px wide (smooth diagonals)."""
        r = self.res
        b = max(1, int(round(t * r)))
        X0, Y0 = (x0 + 0.5) * r - b / 2, (y0 + 0.5) * r - b / 2
        X1, Y1 = (x1 + 0.5) * r - b / 2, (y1 + 0.5) * r - b / 2
        n = int(max(abs(X1 - X0), abs(Y1 - Y0))) + 1
        arr = getattr(self, buf)
        for i in range(n + 1):
            u = i / max(1, n)
            X, Y = int(round(X0 + (X1 - X0) * u)), int(round(Y0 + (Y1 - Y0) * u))
            xa, ya = max(0, X), max(0, Y)
            xb, yb = min(self.rw, X + b), min(self.rh, Y + b)
            if xb > xa and yb > ya:
                arr[ya:yb, xa:xb] = c

    def vgrad(self, x, y, w, h, top, bottom, buf="albedo", dither=True):
        """Vertical gradient, dithered between two colours."""
        x0, y0, x1, y1 = self._clip(x, y, x + w, y + h)
        if x1 <= x0 or y1 <= y0:
            return
        t = ((self._yy[y0:y1, x0:x1] - y) / max(1, h))
        if dither:
            t = np.floor(t * 8 + self._bayer[y0:y1, x0:x1]) / 8
        t = np.clip(t, 0, 1)[..., None]
        getattr(self, buf)[y0:y1, x0:x1] = np.asarray(top) * (1 - t) + np.asarray(bottom) * t

    def noise(self, x, y, w, h, amount, buf="albedo", seed=0, scale=1):
        """Grain: per-pixel brightness jitter; `scale` 1 = fine (one hi-res
        pixel), 2 = one design pixel."""
        x0, y0, x1, y1 = self._clip(x, y, x + w, y + h)
        if x1 <= x0 or y1 <= y0:
            return
        scale = max(1, int(round(scale * self.res / 2)))
        r = np.random.default_rng(seed + x0 * 7 + y0 * 13)
        hh, ww = (y1 - y0 + scale - 1) // scale, (x1 - x0 + scale - 1) // scale
        n = r.uniform(-amount, amount, (hh, ww)).astype(np.float32)
        n = np.kron(n, np.ones((scale, scale), dtype=np.float32))[: y1 - y0, : x1 - x0]
        b = getattr(self, buf)
        b[y0:y1, x0:x1] = np.clip(b[y0:y1, x0:x1] * (1 + n[..., None]), 0, 1)

    def darken(self, x, y, w, h, f, buf="albedo"):
        x0, y0, x1, y1 = self._clip(x, y, x + w, y + h)
        if x1 > x0 and y1 > y0:
            getattr(self, buf)[y0:y1, x0:x1] *= f

    def scale_buf(self, x, y, w, h, f, buf="emissive"):
        self.darken(x, y, w, h, f, buf)

    def set_gloss(self, x, y, w, h, v):
        x0, y0, x1, y1 = self._clip(x, y, x + w, y + h)
        if x1 > x0 and y1 > y0:
            self.gloss[y0:y1, x0:x1] = v

    def _edge(self, x, y, w, h, c):
        """A one-hi-res-pixel edge of a design box: side is t/b/l/r."""
        x0, y0, x1, y1 = self._clip(x, y, x + w, y + h)
        if x1 > x0 and y1 > y0:
            self.albedo[y0:y1, x0:x1] = c

    def box(self, x, y, w, h, c, edge=0.18, bevel=True, shadow=0.35):
        """A lit box face: a fine bright top bevel, a softer second row,
        darker bottom/right lips and a dark ink rim."""
        c = np.asarray(c, dtype=np.float32)
        self.rect(x, y, w, h, c)
        if bevel and w > 2 and h > 2:
            f = 1.0 / self.res
            self._edge(x, y, w, f, shade(c, edge * 1.9))
            self._edge(x, y + f, w, f, shade(c, edge * 0.9))
            self._edge(x, y, f, h, shade(c, edge))
            self._edge(x, y + h - 2 * f, w, f, shade(c, -shadow * 0.6))
            self._edge(x, y + h - f, w, f, shade(c, -shadow - 0.25))
            self._edge(x + w - f, y, f, h, shade(c, -shadow * 0.8))

    def panel(self, x, y, w, h, c, seams=True, rivets=True, vent=False):
        """Riveted metal panel with seams (the tech-interior wall unit)."""
        self.box(x, y, w, h, c, 0.12, True, 0.3)
        self.noise(x + 1, y + 1, w - 2, h - 2, 0.05, seed=x * 3 + y)
        f = 1.0 / self.res
        if seams and h > 12:
            for sy in range(y + 10, y + h - 4, 18):
                self.hline(x + 1, x + w - 2, sy, shade(c, -0.35), t=f)
                self.hline(x + 1, x + w - 2, sy + f, shade(c, -0.15), t=f)
                self.hline(x + 1, x + w - 2, sy + 2 * f, shade(c, 0.12), t=f)
        if rivets and w > 8 and h > 8:
            for rx, ry in ((x + 2, y + 2), (x + w - 3, y + 2), (x + 2, y + h - 3), (x + w - 3, y + h - 3)):
                self.rivet(rx, ry, c)
        if vent and w > 10 and h > 10:
            vx, vy = x + 3, y + h - 12
            for k in range(4):
                self.hline(vx, x + w - 4, vy + k * 2, shade(c, -0.5))
                self.hline(vx, x + w - 4, vy + k * 2 + 1, shade(c, 0.1), t=f)

    def rivet(self, x, y, c):
        """A domed rivet: dark rim, lit top-left hi-res pixel."""
        r = self.res
        self.rect(x, y, 1, 1, shade(c, -0.35))
        X, Y = int(x * r), int(y * r)
        self.fpx(X, Y, shade(c, 0.5))
        if r > 2:
            self.fpx(X + 1, Y, shade(c, 0.25))

    def poly(self, pts, c, buf="albedo"):
        """Scanline polygon fill (design points, hi-res scanlines)."""
        r = self.res
        P = [(px * r, py * r) for px, py in pts]
        ys = [p[1] for p in P]
        arr = getattr(self, buf)
        n = len(P)
        for Y in range(max(0, int(math.floor(min(ys)))), min(self.rh, int(math.ceil(max(ys))) + 1)):
            cy = Y + 0.5
            xs = []
            for i in range(n):
                (x0, y0), (x1, y1) = P[i], P[(i + 1) % n]
                if (y0 <= cy < y1) or (y1 <= cy < y0):
                    xs.append(x0 + (cy - y0) * (x1 - x0) / (y1 - y0))
            xs.sort()
            for a, b in zip(xs[::2], xs[1::2]):
                xa, xb = max(0, int(round(a))), min(self.rw, int(round(b)))
                if xb > xa:
                    arr[Y, xa:xb] = c

    def disc(self, cx, cy, rad, c, buf="albedo"):
        """Filled circle (design centre and radius)."""
        x0, y0, x1, y1 = self._clip(cx - rad - 1, cy - rad - 1, cx + rad + 1, cy + rad + 1)
        if x1 <= x0 or y1 <= y0:
            return
        d = (self._xx[y0:y1, x0:x1] - cx) ** 2 + (self._yy[y0:y1, x0:x1] - cy) ** 2
        m = d <= rad * rad
        getattr(self, buf)[y0:y1, x0:x1][m] = c

    def cable(self, x0, y0, x1, y1, sag, c, thick=1, hl=None):
        """Sagging cable (parabola) traced per hi-res pixel, `thick` design
        px, with a fine highlight line along its top."""
        r = self.res
        n = int((abs(x1 - x0) + abs(y1 - y0)) * r) + 2
        prev = None
        b = max(1, int(thick * r))
        for i in range(n + 1):
            u = i / n
            X = (x0 + (x1 - x0) * u) * r
            Y = (y0 + (y1 - y0) * u + sag * 4 * u * (1 - u)) * r
            p = (int(round(X)), int(round(Y)))
            if p == prev:
                continue
            prev = p
            for k in range(b):
                self.fpx(p[0], p[1] + k, c)
                self.fpx(p[0] + 1, p[1] + k, c)
            if hl is not None and (i // r) % 3 == 0:
                self.fpx(p[0], p[1], hl)
            elif hl is not None:
                self.fpx(p[0], p[1], shade(np.asarray(c, dtype=np.float32), 0.18))

    # --- light and emission --------------------------------------------------------------------
    def light(self, x, y, color, radius, intensity=1.0, cone=None, falloff=1.6):
        """Point light (design coords); cone = (dir_x, dir_y, half_angle_deg)."""
        self.lights.append({"x": x, "y": y, "c": np.asarray(color, dtype=np.float32), "r": radius, "i": intensity,
                            "cone": cone, "f": falloff})

    def glow(self, x, y, w, h, color, strength=1.0):
        """Emissive rectangle (screen, LED strip, sign face)."""
        self.rect(x, y, w, h, np.asarray(color, dtype=np.float32) * strength, "emissive")

    def gpx(self, x, y, color, strength=1.0, t=1.0):
        self.px(x, y, np.asarray(color, dtype=np.float32) * strength, "emissive", t)

    def tube(self, x0, y0, x1, y1, color, strength=1.0, t=1.0):
        """A neon tube: saturated glass with a hot white-ish core line."""
        col = np.asarray(color, dtype=np.float32)
        self.line(x0, y0, x1, y1, col * strength, "emissive", t)
        core = np.minimum(1.0, col * 0.85 + 0.25) * strength
        self.line(x0, y0, x1, y1, core, "emissive", t * 0.5)

    # --- fine detail (hi-res strokes inside design pixels) ------------------------------------
    def fline(self, x0, y0, x1, y1, c, buf="albedo"):
        """A one-hi-res-pixel line between design points (not cell centres)."""
        r = self.res
        X0, Y0, X1, Y1 = x0 * r, y0 * r, x1 * r, y1 * r
        n = int(max(abs(X1 - X0), abs(Y1 - Y0))) + 1
        for i in range(n + 1):
            u = i / max(1, n)
            self.fpx(X0 + (X1 - X0) * u, Y0 + (Y1 - Y0) * u, c, buf)

    def fhline(self, x0, x1, y, c, buf="albedo"):
        self.rect(min(x0, x1), y, abs(x1 - x0), 1.0 / self.res, c, buf)

    def fvline(self, x, y0, y1, c, buf="albedo"):
        self.rect(x, min(y0, y1), 1.0 / self.res, abs(y1 - y0), c, buf)

    def ftext(self, x, y, s, color, buf="emissive", spacing=1):
        """Micro lettering: the 3x5 font at one hi-res pixel per dot (screen
        readouts, labels, serial plates). Returns the width in design px."""
        r = self.res
        X, Y = int(round(x * r)), int(round(y * r))
        cx = X
        for ch in s.upper():
            g = FONT3.get(ch)
            if g is None:
                cx += 3
                continue
            for rr, row in enumerate(g):
                for cidx, v in enumerate(row):
                    if v == "1":
                        self.fpx(cx + cidx, Y + rr, color, buf)
            cx += len(g[0]) + spacing
        return (cx - X) / r

    def label(self, x, y, w, h, c, ink=None, text=None):
        """A printed sticker / tag: paper with a fine border and micro text."""
        c = np.asarray(c, dtype=np.float32)
        self.rect(x, y, w, h, c)
        self.fhline(x, x + w, y, shade(c, 0.25))
        self.fhline(x, x + w, y + h - 1.0 / self.res, shade(c, -0.35))
        ink = shade(c, -0.6) if ink is None else ink
        if text:
            self.ftext(x + 1, y + (h - 2.5) / 2, text, ink, "albedo")
        else:
            for k in range(int(h * self.res) // 2 - 1):
                ln = self.rng.uniform(0.4, 0.9) * (w - 2)
                self.fhline(x + 1, x + 1 + ln, y + 0.5 + k * 2.0 / self.res + 0.5, ink)

    def bottle(self, x, y, h, c, w=3, cap=None):
        """Glass bottle / vial: body, shoulder, cap, a fine glass glint."""
        c = np.asarray(c, dtype=np.float32)
        self.rect(x, y + 2, w, h - 2, c)
        self.rect(x + w * 0.25, y + 0.5, w * 0.5, 1.5, shade(c, -0.2))
        self.rect(x + w * 0.25, y, w * 0.5, 0.5 + 0.5, PAL["steel4"] if cap is None else cap)
        self.fvline(x + 0.5, y + 2.5, y + h - 1, shade(c, 0.55))
        self.fvline(x + w - 0.5, y + 2, y + h, shade(c, -0.4))
        self.rect(x + 0.5, y + h * 0.55, w - 1, h * 0.25, shade(c, 0.15))  # label band

    def bezel(self, x, y, w, h, c):
        """Screen bezel: a dark frame with a fine lit edge and corner screws."""
        c = np.asarray(c, dtype=np.float32)
        self.box(x, y, w, h, c, 0.25)
        f = 1.0 / self.res
        for sx, sy in ((x + 0.5, y + 0.5), (x + w - 1, y + 0.5), (x + 0.5, y + h - 1), (x + w - 1, y + h - 1)):
            self.rect(sx, sy, f, f, shade(c, 0.6))

    def glass(self, x, y, w, h, strength=0.12):
        """Diagonal glare streaks across a screen or window (emissive)."""
        r = self.res
        for k, off in enumerate((0.18, 0.3)):
            x0 = x + w * off
            for i in range(int(min(w, h) * r * 0.5)):
                X = int(x0 * r) + i - k
                Y = int((y + h) * r) - 1 - i * 2
                for j in range(1 + (k == 0)):
                    if x * r <= X + j < (x + w) * r and y * r <= Y < (y + h) * r:
                        self.emissive[Y, X + j] += strength

    # --- text (sign glyphs) --------------------------------------------------------------------
    def text(self, x, y, s, color, buf="emissive", big=False, spacing=1, neon=False):
        """Sign lettering in design px. neon=True draws each stroke as a
        tube: a hot core hi-res line inside the coloured glyph."""
        font = FONT5 if big else FONT3
        cx = x
        col = np.asarray(color, dtype=np.float32)
        core = np.minimum(1.0, col * 0.85 + 0.25)
        r = self.res
        for ch in s.upper():
            g = font.get(ch)
            if g is None:
                cx += 3 if not big else 4
                continue
            for rr, row in enumerate(g):
                for cidx, v in enumerate(row):
                    if v == "1":
                        self.px(cx + cidx, y + rr, col, buf)
                        if neon:
                            X, Y = int((cx + cidx) * r), int((y + rr) * r)
                            self.fpx(X + r // 2 - 1 + (r % 2), Y + r // 2 - 1 + (r % 2), core, buf)
            cx += len(g[0]) + spacing
        return cx - x

    # --- render ----------------------------------------------------------------------------------
    def lightmap(self) -> np.ndarray:
        L = np.zeros((self.rh, self.rw, 3), dtype=np.float32)
        L[:] = self.ambient
        for l in self.lights:
            dx = self._xx - l["x"]
            dy = self._yy - l["y"]
            d = np.sqrt(dx * dx + dy * dy)
            i = np.clip(1 - d / l["r"], 0, 1) ** l["f"] * l["i"]
            if l["cone"] is not None:
                cx, cy, ang = l["cone"]
                nrm = math.hypot(cx, cy) or 1
                cosang = (dx * cx + dy * cy) / (d * nrm + 1e-6)
                lim = math.cos(math.radians(ang))
                i = i * np.clip((cosang - lim) / (1 - lim + 1e-6) * 3, 0, 1)
            # banded + dithered falloff (pixel-art light pools, fine bands)
            q = np.floor(i * 14 + 0.25 + self._bayer * 0.5) / 14
            L += q[..., None] * l["c"]
        return L

    def render(self, posterize=40) -> np.ndarray:
        r = self.res
        L = self.lightmap()
        img = self.albedo * L
        # Haze: distant light scattering, stronger higher up.
        if self.haze > 0:
            t = np.clip(1 - self._yy / self.h, 0, 1)[..., None] * self.haze
            img = img * (1 - t) + self.haze_color * t * (0.4 + 0.6 * np.clip(L.mean(axis=2, keepdims=True), 0, 1.5))
        if self.grade is not None:
            img = self.grade(img, self)
        img = np.maximum(img, self.emissive)
        # Bloom: emissive light spills as a soft halo (blurred, then banded).
        em = self.emissive
        if em.max() > 0:
            b = _blur(em, 2 * r)
            b = _blur(b, 2 * r) * 0.5 + _blur(b, 5 * r) * 0.5
            q = np.floor(b * 14 + self._bayer[..., None] * 0.999) / 14
            img = img + q * 0.85
        # Wet floor: mirror the scene above the floor line, fading with distance.
        if self.gloss.max() > 0:
            fy = int(self.floor_y * r)
            for Y in range(fy, self.rh):
                src = 2 * fy - Y - 1
                if src < 0:
                    continue
                g = self.gloss[Y][:, None] * max(0.0, 1 - (Y - fy) / (95.0 * r))
                row = img[src] * 0.7
                if (Y - fy) // r % 2 == 1:  # broken, rippled reflection
                    row = np.roll(row, r if (Y // (2 * r)) % 2 else -r, axis=0)
                img[Y] = img[Y] + row * g
        img = np.clip(img, 0, 1)
        # Posterise with an ordered dither: cohesive pixel colours.
        img = np.floor(img * posterize + 0.2 + self._bayer[..., None] * 0.6) / posterize
        return np.clip(img, 0, 1)

    def save(self, rel: str, img: np.ndarray | None = None) -> str:
        if img is None:
            img = self.render()
        path = os.path.join(SPRITES, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        Image.fromarray((img * 255).astype(np.uint8), "RGB").save(path, optimize=True)
        return path

    def anchor(self, kind, x, y, w=1, h=1, color="cyan", **kw):
        e = {"type": kind, "x": int(x), "y": int(y), "w": int(w), "h": int(h), "color": color}
        e.update(kw)
        self.fx.append(e)


def neon_grade(shadow="140a2e", mid="3a1f5c", strength=0.55, pink=0.10, cyan=0.06):
    """The neon reference's colour script: shadows sink into indigo-violet,
    mid tones lean purple, lit areas keep their light colour. Returned as a
    Scene.grade callable."""
    sh, md = hexc(shadow), hexc(mid)

    def g(img, sc):
        lum = img.mean(axis=2, keepdims=True)
        t = np.clip(1 - lum * 2.2, 0, 1) * strength  # how much of a shadow this is
        out = img * (1 - t) + (sh + img * 0.6) * t
        m = np.clip(1 - np.abs(lum - 0.32) * 3.5, 0, 1) * strength * 0.5
        out = out * (1 - m) + (out * 0.7 + md * 0.45) * m
        # Faint magenta lift along the top and cyan along the floor (the room
        # is lit by signs on both sides, like the reference).
        y = (sc._yy / sc.h)[..., None]
        out = out + hexc("ff3d9a") * pink * np.clip(0.5 - y, 0, 0.5) * (1 - lum)
        out = out + hexc("2ee6ff") * cyan * np.clip(y - 0.6, 0, 0.4) * (1 - lum)
        return out

    return g


def _blur(a: np.ndarray, r: int) -> np.ndarray:
    """Box blur (separable), radius r."""
    k = 2 * r + 1
    pad = np.pad(a, ((r, r), (0, 0), (0, 0)), mode="edge")
    c = np.cumsum(pad, axis=0)
    c = np.concatenate([np.zeros_like(c[:1]), c], axis=0)
    v = (c[k:] - c[:-k]) / k
    pad = np.pad(v, ((0, 0), (r, r), (0, 0)), mode="edge")
    c = np.cumsum(pad, axis=1)
    c = np.concatenate([np.zeros_like(c[:, :1]), c], axis=1)
    return (c[:, k:] - c[:, :-k]) / k


def save_rgba(rel: str, rgb: np.ndarray, alpha: np.ndarray) -> str:
    path = os.path.join(SPRITES, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    a = (np.clip(alpha, 0, 1) * 255).astype(np.uint8)[..., None]
    Image.fromarray(np.concatenate([(rgb * 255).astype(np.uint8), a], axis=2), "RGBA").save(path, optimize=True)
    return path


# --- Sign fonts: 3x5 (small labels) and 5x7 (big neon) ----------------------------------------------

def _font(spec: str, w: int) -> dict:
    out = {}
    for line in spec.strip().splitlines():
        ch, bits = line.split(":")
        rows = bits.split(",")
        out[ch if ch != "SP" else " "] = [r.ljust(w, "0") for r in rows]
    return out


FONT3 = _font("""
A:010,101,111,101,101
B:110,101,110,101,110
C:011,100,100,100,011
D:110,101,101,101,110
E:111,100,110,100,111
F:111,100,110,100,100
G:011,100,101,101,011
H:101,101,111,101,101
I:111,010,010,010,111
J:001,001,001,101,010
K:101,101,110,101,101
L:100,100,100,100,111
M:101,111,111,101,101
N:110,101,101,101,101
O:010,101,101,101,010
P:110,101,110,100,100
Q:010,101,101,110,011
R:110,101,110,101,101
S:011,100,010,001,110
T:111,010,010,010,010
U:101,101,101,101,111
V:101,101,101,101,010
W:101,101,111,111,101
X:101,101,010,101,101
Y:101,101,010,010,010
Z:111,001,010,100,111
0:111,101,101,101,111
1:010,110,010,010,111
2:110,001,010,100,111
3:110,001,010,001,110
4:101,101,111,001,001
5:111,100,110,001,110
6:011,100,111,101,111
7:111,001,010,010,010
8:111,101,111,101,111
9:111,101,111,001,110
-:000,000,111,000,000
+:000,010,111,010,000
.:000,000,000,000,010
/:001,001,010,100,100
%:101,001,010,100,101
""", 3)
FONT3[":"] = ["000", "010", "000", "010", "000"]

FONT5 = _font("""
A:01110,10001,10001,11111,10001,10001,10001
B:11110,10001,11110,10001,10001,10001,11110
C:01111,10000,10000,10000,10000,10000,01111
D:11110,10001,10001,10001,10001,10001,11110
E:11111,10000,11110,10000,10000,10000,11111
F:11111,10000,11110,10000,10000,10000,10000
G:01111,10000,10000,10011,10001,10001,01111
H:10001,10001,11111,10001,10001,10001,10001
I:11111,00100,00100,00100,00100,00100,11111
K:10001,10010,11100,10010,10001,10001,10001
L:10000,10000,10000,10000,10000,10000,11111
M:10001,11011,10101,10001,10001,10001,10001
N:10001,11001,10101,10011,10001,10001,10001
O:01110,10001,10001,10001,10001,10001,01110
P:11110,10001,10001,11110,10000,10000,10000
R:11110,10001,10001,11110,10010,10001,10001
S:01111,10000,01110,00001,00001,00001,11110
T:11111,00100,00100,00100,00100,00100,00100
U:10001,10001,10001,10001,10001,10001,01110
V:10001,10001,10001,10001,10001,01010,00100
W:10001,10001,10001,10101,10101,11011,10001
X:10001,01010,00100,01010,10001,10001,10001
Y:10001,01010,00100,00100,00100,00100,00100
Z:11111,00010,00100,01000,10000,10000,11111
0:01110,10011,10101,11001,10001,10001,01110
1:00100,01100,00100,00100,00100,00100,01110
2:01110,10001,00010,00100,01000,10000,11111
3:11110,00001,01110,00001,00001,00001,11110
4:10010,10010,10010,11111,00010,00010,00010
5:11111,10000,11110,00001,00001,00001,11110
7:11111,00001,00010,00100,01000,01000,01000
8:01110,10001,01110,10001,10001,10001,01110
9:01110,10001,10001,01111,00001,00001,01110
+:00000,00100,00100,11111,00100,00100,00000
-:00000,00000,00000,11111,00000,00000,00000
""", 5)
