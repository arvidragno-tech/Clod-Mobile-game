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


class Scene:
    def __init__(self, w: int, h: int, ambient=(0.16, 0.18, 0.24), seed: int = 1):
        self.w, self.h = w, h
        self.albedo = np.zeros((h, w, 3), dtype=np.float32)
        self.albedo[:] = PAL["night"]
        self.emissive = np.zeros((h, w, 3), dtype=np.float32)
        self.gloss = np.zeros((h, w), dtype=np.float32)
        self.lights: list[dict] = []
        self.ambient = np.array(ambient, dtype=np.float32)
        self.haze = 0.0
        self.haze_color = PAL["steel2"]
        self.floor_y = h  # reflections mirror about this line
        self.rng = random.Random(seed)
        self.fx: list[dict] = []  # animation anchors for the game
        yy, xx = np.mgrid[0:h, 0:w]
        self._xx = xx.astype(np.float32) + 0.5
        self._yy = yy.astype(np.float32) + 0.5
        self._bayer = np.tile(BAYER, (h // 4 + 1, w // 4 + 1))[:h, :w]

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

    # --- basic drawing -------------------------------------------------------------------------
    def _clip(self, x0, y0, x1, y1):
        x0, y0 = max(0, int(x0)), max(0, int(y0))
        x1, y1 = min(self.w, int(x1)), min(self.h, int(y1))
        return x0, y0, x1, y1

    def rect(self, x, y, w, h, c, buf="albedo"):
        x0, y0, x1, y1 = self._clip(x, y, x + w, y + h)
        if x1 > x0 and y1 > y0:
            getattr(self, buf)[y0:y1, x0:x1] = c

    def px(self, x, y, c, buf="albedo"):
        x, y = int(x), int(y)
        if 0 <= x < self.w and 0 <= y < self.h:
            getattr(self, buf)[y, x] = c

    def hline(self, x0, x1, y, c, buf="albedo"):
        self.rect(min(x0, x1), y, abs(x1 - x0) + 1, 1, c, buf)

    def vline(self, x, y0, y1, c, buf="albedo"):
        self.rect(x, min(y0, y1), 1, abs(y1 - y0) + 1, c, buf)

    def line(self, x0, y0, x1, y1, c, buf="albedo"):
        n = int(max(abs(x1 - x0), abs(y1 - y0))) + 1
        for i in range(n + 1):
            t = i / max(1, n)
            self.px(round(x0 + (x1 - x0) * t), round(y0 + (y1 - y0) * t), c, buf)

    def vgrad(self, x, y, w, h, top, bottom, buf="albedo", dither=True):
        """Vertical gradient, dithered between two colours."""
        x0, y0, x1, y1 = self._clip(x, y, x + w, y + h)
        if x1 <= x0 or y1 <= y0:
            return
        t = ((self._yy[y0:y1, x0:x1] - y) / max(1, h))
        if dither:
            t = np.floor(t * 6 + self._bayer[y0:y1, x0:x1]) / 6
        t = np.clip(t, 0, 1)[..., None]
        getattr(self, buf)[y0:y1, x0:x1] = np.asarray(top) * (1 - t) + np.asarray(bottom) * t

    def noise(self, x, y, w, h, amount, buf="albedo", seed=0, scale=1):
        """Grain: per-pixel brightness jitter (or blocks of `scale`)."""
        x0, y0, x1, y1 = self._clip(x, y, x + w, y + h)
        if x1 <= x0 or y1 <= y0:
            return
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

    def box(self, x, y, w, h, c, edge=0.18, bevel=True, shadow=0.35):
        """A lit box face: lighter top edge, darker bottom/right, outline."""
        c = np.asarray(c, dtype=np.float32)
        self.rect(x, y, w, h, c)
        if bevel and w > 2 and h > 2:
            self.hline(x, x + w - 1, y, shade(c, edge * 1.6))
            self.vline(x, y, y + h - 1, shade(c, edge))
            self.hline(x, x + w - 1, y + h - 1, shade(c, -shadow))
            self.vline(x + w - 1, y, y + h - 1, shade(c, -shadow * 0.7))

    def panel(self, x, y, w, h, c, seams=True, rivets=True, vent=False):
        """Riveted metal panel with seams (the tech-interior wall unit)."""
        self.box(x, y, w, h, c, 0.12, True, 0.3)
        self.noise(x + 1, y + 1, w - 2, h - 2, 0.05, seed=x * 3 + y)
        if seams and h > 12:
            for sy in range(y + 10, y + h - 4, 18):
                self.hline(x + 1, x + w - 2, sy, shade(c, -0.35))
                self.hline(x + 1, x + w - 2, sy + 1, shade(c, 0.08))
        if rivets and w > 8 and h > 8:
            for rx, ry in ((x + 2, y + 2), (x + w - 3, y + 2), (x + 2, y + h - 3), (x + w - 3, y + h - 3)):
                self.px(rx, ry, shade(c, 0.35))
        if vent and w > 10 and h > 10:
            vx, vy = x + 3, y + h - 12
            for k in range(4):
                self.hline(vx, x + w - 4, vy + k * 2, shade(c, -0.5))

    def poly(self, pts, c, buf="albedo"):
        """Scanline polygon fill."""
        ys = [p[1] for p in pts]
        for y in range(max(0, int(math.floor(min(ys)))), min(self.h, int(math.ceil(max(ys))) + 1)):
            cy = y + 0.5
            xs = []
            n = len(pts)
            for i in range(n):
                (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
                if (y0 <= cy < y1) or (y1 <= cy < y0):
                    xs.append(x0 + (cy - y0) * (x1 - x0) / (y1 - y0))
            xs.sort()
            for a, b in zip(xs[::2], xs[1::2]):
                self.rect(round(a), y, round(b) - round(a), 1, c, buf)

    def cable(self, x0, y0, x1, y1, sag, c, thick=1, hl=None):
        """Sagging cable (parabola), with an optional highlight pixel line."""
        n = int(abs(x1 - x0) + abs(y1 - y0)) + 2
        prev = None
        for i in range(n + 1):
            t = i / n
            x = x0 + (x1 - x0) * t
            y = y0 + (y1 - y0) * t + sag * 4 * t * (1 - t)
            p = (round(x), round(y))
            if p != prev:
                for k in range(thick):
                    self.px(p[0], p[1] + k, c)
                if hl is not None and i % 3 == 0:
                    self.px(p[0], p[1], hl)
            prev = p

    # --- light and emission --------------------------------------------------------------------
    def light(self, x, y, color, radius, intensity=1.0, cone=None, falloff=1.6):
        """Point light; cone = (dir_x, dir_y, half_angle_deg) for spots."""
        self.lights.append({"x": x, "y": y, "c": np.asarray(color, dtype=np.float32), "r": radius, "i": intensity,
                            "cone": cone, "f": falloff})

    def glow(self, x, y, w, h, color, strength=1.0):
        """Emissive rectangle (screen, LED strip, sign face)."""
        self.rect(x, y, w, h, np.asarray(color, dtype=np.float32) * strength, "emissive")

    def gpx(self, x, y, color, strength=1.0):
        self.px(x, y, np.asarray(color, dtype=np.float32) * strength, "emissive")

    # --- text (sign glyphs) --------------------------------------------------------------------
    def text(self, x, y, s, color, buf="emissive", big=False, spacing=1):
        font = FONT5 if big else FONT3
        gh = 7 if big else 5
        cx = x
        for ch in s.upper():
            g = font.get(ch)
            if g is None:
                cx += 3 if not big else 4
                continue
            for r, row in enumerate(g):
                for cidx, v in enumerate(row):
                    if v == "1":
                        self.px(cx + cidx, y + r, color, buf)
            cx += len(g[0]) + spacing
        return cx - x

    # --- render ----------------------------------------------------------------------------------
    def lightmap(self) -> np.ndarray:
        L = np.zeros((self.h, self.w, 3), dtype=np.float32)
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
            # banded + dithered falloff (pixel-art light pools)
            q = np.floor(i * 10 + 0.25 + self._bayer * 0.5) / 10
            L += q[..., None] * l["c"]
        return L

    def render(self, posterize=32) -> np.ndarray:
        L = self.lightmap()
        img = self.albedo * L
        # Haze: distant light scattering, stronger higher up.
        if self.haze > 0:
            t = np.clip(1 - self._yy / self.h, 0, 1)[..., None] * self.haze
            img = img * (1 - t) + self.haze_color * t * (0.4 + 0.6 * np.clip(L.mean(axis=2, keepdims=True), 0, 1.5))
        img = np.maximum(img, self.emissive)
        # Bloom: emissive light spills as a soft halo (blurred, then banded).
        em = self.emissive
        if em.max() > 0:
            b = _blur(em, 3)
            b = _blur(b, 3) * 0.55 + _blur(b, 7) * 0.45
            q = np.floor(b * 10 + self._bayer[..., None] * 0.999) / 10
            img = img + q * 0.75
        # Wet floor: mirror the scene above the floor line, fading with distance.
        if self.gloss.max() > 0:
            fy = int(self.floor_y)
            for y in range(fy, self.h):
                src = 2 * fy - y - 1
                if src < 0:
                    continue
                g = self.gloss[y][:, None] * max(0.0, 1 - (y - fy) / 95.0)
                row = img[src] * 0.7
                if (y - fy) % 2 == 1:  # broken, rippled reflection
                    row = np.roll(row, 1 if (y // 2) % 2 else -1, axis=0)
                img[y] = img[y] + row * g
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
