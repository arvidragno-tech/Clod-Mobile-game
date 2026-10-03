#!/usr/bin/env python3
"""Generates the placeholder pixel art for UNDERCITY: RIPPER.

All sprites are drawn at native pixel resolution from simple shapes so the
game already has a coherent look. Godot displays them with nearest-neighbour
filtering. Re-run after tweaking:  python3 tools/generate_placeholder_art.py

Final art can replace any output file 1:1 (same path, same pixel size).
Requires Pillow.
"""
from __future__ import annotations

import os
import random
from PIL import Image

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "sprites")


def hexc(h: str, a: int = 255) -> tuple:
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def mix(c1: tuple, c2: tuple, t: float) -> tuple:
    return tuple(int(round(c1[i] + (c2[i] - c1[i]) * t)) for i in range(4))


def shade(c: tuple, amount: float) -> tuple:
    """amount < 0 darkens, > 0 lightens."""
    target = (0, 0, 0, c[3]) if amount < 0 else (255, 255, 255, c[3])
    return mix(c, target, abs(amount))


# Palette (mirrors scripts/core/palette.gd)
BG_0 = hexc("07080c")
BG_1 = hexc("0d1017")
PANEL = hexc("121821")
PANEL_HI = hexc("1a2230")
LINE = hexc("2a3646")
LINE_HI = hexc("3b4b60")
TEXT = hexc("c9d6df")
TEXT_DIM = hexc("6b7c8c")
ACCENT = hexc("2ee6c8")
ACCENT_DIM = hexc("1a7d70")
BRAND = hexc("ff3d81")
BRAND_DIM = hexc("7a1f42")
WARN = hexc("ffb43d")
DANGER = hexc("ff4d4d")
OK = hexc("6dff8a")
METAL = hexc("8e9aa8")
METAL_DARK = hexc("3d4652")
BLOOD = hexc("b3122e")
CLEAR = (0, 0, 0, 0)


class Canvas:
    def __init__(self, w: int, h: int, fill: tuple = CLEAR):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w, h), fill)
        self.px = self.img.load()
        # Drawing offset, so props can be laid out in local coordinates.
        self.ox = 0
        self.oy = 0

    def set(self, x: int, y: int, c: tuple) -> None:
        x += self.ox
        y += self.oy
        if 0 <= x < self.w and 0 <= y < self.h:
            if c[3] == 255 or c[3] == 0:
                self.px[x, y] = c
            else:
                base = self.px[x, y]
                a = c[3] / 255.0
                self.px[x, y] = (
                    int(base[0] + (c[0] - base[0]) * a),
                    int(base[1] + (c[1] - base[1]) * a),
                    int(base[2] + (c[2] - base[2]) * a),
                    max(base[3], c[3]),
                )

    def get(self, x: int, y: int) -> tuple:
        return self.px[x, y]

    def rect(self, x: int, y: int, w: int, h: int, c: tuple) -> None:
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.set(xx, yy, c)

    def outline(self, x: int, y: int, w: int, h: int, c: tuple) -> None:
        for xx in range(x, x + w):
            self.set(xx, y, c)
            self.set(xx, y + h - 1, c)
        for yy in range(y, y + h):
            self.set(x, yy, c)
            self.set(x + w - 1, yy, c)

    def hline(self, x0: int, x1: int, y: int, c: tuple) -> None:
        for x in range(min(x0, x1), max(x0, x1) + 1):
            self.set(x, y, c)

    def vline(self, x: int, y0: int, y1: int, c: tuple) -> None:
        for y in range(min(y0, y1), max(y0, y1) + 1):
            self.set(x, y, c)

    def line(self, x0: int, y0: int, x1: int, y1: int, c: tuple) -> None:
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

    def disc(self, cx: float, cy: float, r: float, c: tuple) -> None:
        for y in range(int(cy - r - 1), int(cy + r + 2)):
            for x in range(int(cx - r - 1), int(cx + r + 2)):
                if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                    self.set(x, y, c)

    def ellipse(self, cx: float, cy: float, rx: float, ry: float, c: tuple) -> None:
        for y in range(int(cy - ry - 1), int(cy + ry + 2)):
            for x in range(int(cx - rx - 1), int(cx + rx + 2)):
                if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0:
                    self.set(x, y, c)

    def dither(self, x: int, y: int, w: int, h: int, c: tuple, density: float = 0.5, seed: int = 0) -> None:
        """Ordered (Bayer 4x4) dither of colour c over a region."""
        bayer = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                if (bayer[(yy + seed) % 4][(xx + seed) % 4] + 0.5) / 16.0 < density:
                    self.set(xx, yy, c)

    def noise(self, x: int, y: int, w: int, h: int, c: tuple, chance: float, rng: random.Random) -> None:
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                if rng.random() < chance:
                    self.set(xx, yy, c)

    def glow(self, cx: float, cy: float, r: float, c: tuple, strength: float = 0.35) -> None:
        for y in range(int(cy - r), int(cy + r + 1)):
            for x in range(int(cx - r), int(cx + r + 1)):
                d = ((x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2) ** 0.5
                if d < r:
                    a = int(255 * strength * (1.0 - d / r) ** 2)
                    # quantise alpha into bands for a pixel-art look
                    a = (a // 24) * 24
                    if a > 0:
                        self.set(x, y, (c[0], c[1], c[2], a))

    def save(self, rel_path: str, scale: int = 1, opaque: bool = False) -> None:
        path = os.path.join(ROOT, rel_path)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        img = self.img
        if scale != 1:
            img = img.resize((self.w * scale, self.h * scale), Image.NEAREST)
        if opaque:
            img = img.convert("RGB")  # App Store icons must not have alpha
        img.save(path)
        print("wrote", os.path.relpath(path, os.path.join(ROOT, "..", "..")))


# --- Tiny 3x5 pixel font for signage ----------------------------------------
FONT3x5 = {
    "A": ["010", "101", "111", "101", "101"],
    "C": ["011", "100", "100", "100", "011"],
    "L": ["100", "100", "100", "100", "111"],
    "D": ["110", "101", "101", "101", "110"],
    "E": ["111", "100", "110", "100", "111"],
    "H": ["101", "101", "111", "101", "101"],
    "I": ["111", "010", "010", "010", "111"],
    "N": ["1001", "1101", "1011", "1001", "1001"],
    "O": ["010", "101", "101", "101", "010"],
    "P": ["110", "101", "110", "100", "100"],
    "R": ["110", "101", "110", "101", "101"],
    "2": ["110", "001", "010", "100", "111"],
    "4": ["101", "101", "111", "001", "001"],
    " ": ["000", "000", "000", "000", "000"],
}


def text3x5(cv: Canvas, x: int, y: int, text: str, c: tuple) -> int:
    for ch in text:
        glyph = FONT3x5.get(ch, FONT3x5[" "])
        for gy, row in enumerate(glyph):
            for gx, bit in enumerate(row):
                if bit == "1":
                    cv.set(x + gx, y + gy, c)
        x += len(glyph[0]) + 1
    return x


# --- Clinic background -------------------------------------------------------
def clinic_background() -> None:
    W, H = 160, 200
    PROPS_X = 20  # props are laid out on a 120px-wide stage centred in W
    rng = random.Random(7)
    cv = Canvas(W, H, BG_1)
    wall = hexc("10141c")
    wall_hi = hexc("161c27")
    floor_y = 150

    # Wall: concrete panels
    cv.rect(0, 0, W, floor_y, wall)
    for py in range(14, floor_y, 22):
        cv.hline(0, W - 1, py, hexc("0b0e14"))
        cv.hline(0, W - 1, py + 1, wall_hi)
    for px_ in range(0, W, 30):
        off = 0 if (px_ // 30) % 2 == 0 else 11
        for py in range(14 + off, floor_y, 44):
            cv.vline(px_, py, min(py + 21, floor_y), hexc("0b0e14"))
    cv.noise(0, 0, W, floor_y, hexc("0a0d12"), 0.08, rng)
    # Grime running down from the ceiling
    for _ in range(14):
        gx = rng.randrange(0, W)
        length = rng.randrange(8, 40)
        cv.vline(gx, 14, 14 + length, hexc("0a0c11"))
    cv.dither(0, floor_y - 18, W, 18, hexc("090b10"), 0.5)

    # Ceiling + pipes
    cv.rect(0, 0, W, 12, hexc("0a0c11"))
    cv.rect(0, 6, W, 4, METAL_DARK)
    cv.hline(0, W - 1, 6, shade(METAL_DARK, 0.25))
    for x in range(10, W, 26):
        cv.rect(x, 5, 2, 6, hexc("2a313b"))
    cv.rect(W - 12, 10, 4, floor_y - 10, hexc("1e242d"))
    cv.vline(W - 12, 10, floor_y, hexc("2a313b"))
    # Hanging cables
    for cx_, sag in ((6, 8), (46, 10), (98, 7), (118, 12)):
        for x in range(cx_, cx_ + 14):
            t = (x - cx_) / 13.0
            y = 12 + int(sag * 4 * t * (1 - t))
            cv.set(x, y, hexc("05060a"))

    # Edge props: faded poster (left), crates (right)
    cv.rect(5, 44, 12, 18, hexc("1a1520"))
    cv.dither(5, 44, 12, 18, BRAND_DIM, 0.3)
    cv.line(7, 59, 14, 47, shade(BRAND, -0.4))
    cv.hline(6, 15, 53, shade(ACCENT, -0.5))
    cv.rect(137, 128, 20, 22, hexc("1a1f27"))
    cv.outline(137, 128, 20, 22, hexc("262d38"))
    cv.line(137, 128, 156, 149, hexc("232a34"))
    cv.rect(140, 112, 14, 16, hexc("161b22"))
    cv.outline(140, 112, 14, 16, hexc("262d38"))
    cv.rect(144, 117, 6, 3, shade(WARN, -0.5))

    cv.ox = PROPS_X
    # Neon sign: OPEN CLINIC + emblem
    cv.rect(38, 18, 44, 22, hexc("0a0c12"))
    cv.outline(38, 18, 44, 22, hexc("1c222c"))
    cv.outline(37, 17, 46, 24, BRAND_DIM)
    cv.dither(34, 14, 52, 3, BRAND_DIM, 0.25)
    cv.dither(34, 41, 52, 3, BRAND_DIM, 0.25)
    # Emblem: a blade crossing a pulse line
    cv.line(44, 36, 54, 22, BRAND)
    cv.line(45, 36, 55, 22, shade(BRAND, 0.3))
    cv.hline(42, 47, 30, ACCENT)
    cv.line(47, 30, 49, 26, ACCENT)
    cv.line(49, 26, 51, 33, ACCENT)
    cv.line(51, 33, 53, 30, ACCENT)
    cv.hline(53, 56, 30, ACCENT)
    text3x5(cv, 59, 22, "OPEN", BRAND)
    text3x5(cv, 56, 31, "CLINIC", ACCENT)

    # Door (left)
    cv.rect(4, 92, 26, floor_y - 92, hexc("0a0c10"))
    cv.outline(4, 92, 26, floor_y - 92, hexc("232a35"))
    cv.rect(7, 95, 20, floor_y - 95, hexc("141922"))
    cv.rect(10, 100, 14, 10, hexc("0c1a1d"))
    cv.dither(10, 100, 14, 10, ACCENT_DIM, 0.25)
    cv.rect(23, 122, 2, 5, METAL)
    cv.rect(4, 90, 26, 2, WARN)  # warning light strip over the door
    cv.dither(4, 92, 26, 4, shade(WARN, -0.6), 0.5)
    cv.dither(2, 86, 30, 4, shade(WARN, -0.7), 0.25)

    # Monitor on a stand
    cv.rect(39, 104, 2, floor_y - 104, METAL_DARK)
    cv.rect(35, floor_y - 2, 10, 2, METAL_DARK)
    cv.rect(32, 82, 18, 22, hexc("1b2029"))
    cv.outline(32, 82, 18, 22, hexc("2c3440"))
    cv.rect(34, 84, 14, 14, hexc("041311"))
    ecg = [0, 0, 0, -1, 0, 1, -4, 3, 0, 0, -1, 0, 0, 0]
    prev = None
    for i, dy in enumerate(ecg):
        if prev is not None:
            cv.line(34 + i - 1, 91 + prev, 34 + i, 91 + dy, ACCENT)
        prev = dy
    cv.dither(30, 80, 22, 2, ACCENT_DIM, 0.2)
    cv.rect(35, 100, 3, 2, OK)
    cv.rect(39, 100, 3, 2, WARN)

    # Surgical lamp (centre), hanging in front of the sign's right edge
    cv.vline(88, 10, 50, hexc("1e242d"))
    cv.line(88, 50, 74, 54, hexc("1e242d"))
    cv.rect(66, 54, 17, 5, METAL_DARK)
    cv.hline(66, 82, 54, METAL)
    cv.rect(68, 59, 13, 2, hexc("e8fff9"))
    # Light cone onto the chair
    for y in range(61, 114):
        spread = (y - 61) * 0.4
        for x in range(int(74 - 6 - spread), int(74 + 7 + spread)):
            if (x + y) % 2 == 0 and y % 3 != 0:
                cv.set(x, y, (200, 255, 245, 12))

    # Operating chair (reclined)
    chair = hexc("1f2631")
    chair_hi = hexc("2c3644")
    cv.rect(54, 116, 44, 7, chair)               # seat/back bed
    cv.rect(58, 113, 34, 3, hexc("27303d"))     # cushion
    cv.hline(54, 97, 116, chair_hi)
    cv.rect(50, 108, 8, 10, chair)              # headrest
    cv.hline(50, 57, 108, chair_hi)
    cv.rect(92, 112, 8, 6, chair)               # leg rest
    cv.rect(72, 123, 6, 18, METAL_DARK)         # pillar
    cv.rect(64, 141, 22, 4, METAL_DARK)         # base
    cv.hline(64, 85, 141, METAL)
    cv.hline(55, 96, 122, ACCENT_DIM)           # trim light
    cv.dither(54, 123, 44, 2, ACCENT_DIM, 0.3)
    # Tool tray next to the chair
    cv.rect(86, 100, 14, 2, METAL)
    cv.vline(93, 102, 140, METAL_DARK)
    cv.set(88, 99, TEXT)
    cv.set(91, 99, ACCENT)
    cv.set(95, 99, TEXT_DIM)

    # Cabinet (right)
    cv.rect(98, 70, 14, floor_y - 70, hexc("161b23"))
    cv.outline(98, 70, 14, floor_y - 70, hexc("252d38"))
    for shelf_y in (84, 100, 116):
        cv.hline(99, 110, shelf_y, hexc("2b3440"))
    jars = [(100, 79, OK), (104, 80, ACCENT), (107, 78, WARN), (101, 95, BRAND), (105, 94, ACCENT),
            (100, 111, OK), (106, 110, WARN)]
    for jx, jy, col in jars:
        cv.rect(jx, jy, 3, 5, shade(col, -0.55))
        cv.rect(jx, jy + 2, 3, 3, shade(col, -0.2))
        cv.set(jx, jy, shade(col, 0.2))


    # Floor
    cv.ox = 0
    cv.rect(0, floor_y, W, H - floor_y, hexc("0b0e13"))
    cv.hline(0, W - 1, floor_y, hexc("222a35"))
    for i, fy in enumerate((154, 160, 168, 178, 190)):
        cv.hline(0, W - 1, fy, hexc("0f131a"))
    for fx in range(-W // 2, W + W // 2, 16):
        cv.line(W // 2 + (fx - W // 2) // 3, floor_y, fx, H - 1, hexc("0f131a"))
    cv.noise(0, floor_y + 1, W, H - floor_y - 1, hexc("080a0e"), 0.15, rng)
    cv.ox = PROPS_X
    # Puddle with neon reflection
    cv.ellipse(48, 176, 18, 4, hexc("0a1418"))
    cv.dither(32, 173, 32, 7, ACCENT_DIM, 0.12)
    cv.dither(40, 175, 14, 3, BRAND_DIM, 0.2, 1)
    # Drain
    cv.rect(84, 184, 10, 4, hexc("05070a"))
    for x in range(85, 94, 2):
        cv.vline(x, 184, 187, hexc("1a1f27"))
    cv.save("clinic/clinic_bg.png")


# --- Customers ---------------------------------------------------------------
CUSTOMERS = {
    "mara_quill": dict(skin="b07a5a", hair="1d1a2b", hair_style="bob", jacket="2a3b4f", accent="2ee6c8",
                       pants="1a1f29", eye="2ee6c8", seed=1),
    "dez_okafor": dict(skin="6b4532", hair="0d0d10", hair_style="mohawk", jacket="3a2340", accent="ff3d81",
                       pants="15151c", eye="ff3d81", seed=2),
    "hollis_brandt": dict(skin="d9a585", hair="8b8b8b", hair_style="cap", jacket="4a3a22", accent="ffb43d",
                          pants="262a30", eye="", seed=3),
    "juno_reyes": dict(skin="c48a64", hair="5a1830", hair_style="long", jacket="1f3a33", accent="6dff8a",
                       pants="1a1a22", eye="6dff8a", seed=4),
}


def draw_hair(cv: Canvas, style: str, hx: int, hy: int, hw: int, hair: tuple, accent: tuple, scale: int = 1) -> None:
    """Hair over a head whose top-left is (hx, hy) and width hw."""
    s = scale
    if style == "bob":
        cv.rect(hx - s, hy - s, hw + 2 * s, 3 * s, hair)
        cv.rect(hx - s, hy, 2 * s, 7 * s, hair)
        cv.rect(hx + hw - s, hy, 2 * s, 7 * s, hair)
    elif style == "mohawk":
        cv.rect(hx + hw // 2 - s, hy - 3 * s, 2 * s, 4 * s, accent)
        cv.rect(hx + 1 * s, hy - s, hw - 2 * s, s, hair)
    elif style == "cap":
        cv.rect(hx - s, hy - s, hw + 2 * s, 3 * s, hexc("2b3138"))
        cv.rect(hx + hw - s, hy + s, 3 * s, s, hexc("2b3138"))
        cv.rect(hx - s, hy + 2 * s, s, 2 * s, hair)
    elif style == "long":
        cv.rect(hx - s, hy - s, hw + 2 * s, 3 * s, hair)
        cv.rect(hx - 2 * s, hy, 2 * s, 12 * s, hair)
        cv.rect(hx + hw, hy, 2 * s, 12 * s, hair)


def customer_full(cid: str, p: dict) -> None:
    W, H = 24, 48
    cv = Canvas(W, H)
    skin, hair, jacket = hexc(p["skin"]), hexc(p["hair"]), hexc(p["jacket"])
    accent, pants = hexc(p["accent"]), hexc(p["pants"])
    outline = hexc("05060a")
    # Shadow
    cv.ellipse(12, 46, 9, 2, (0, 0, 0, 140))
    # Legs + boots
    cv.rect(8, 30, 4, 14, pants)
    cv.rect(13, 30, 4, 14, pants)
    cv.rect(7, 43, 5, 3, outline)
    cv.rect(13, 43, 5, 3, outline)
    # Torso / jacket
    cv.rect(6, 15, 13, 16, jacket)
    cv.rect(6, 15, 13, 2, shade(jacket, 0.2))
    cv.vline(12, 17, 30, shade(jacket, -0.35))
    cv.rect(13, 20, 2, 2, accent)  # badge / LED
    cv.rect(6, 29, 13, 2, shade(jacket, -0.3))
    # Arms
    cv.rect(4, 16, 3, 13, shade(jacket, -0.15))
    cv.rect(18, 16, 3, 13, shade(jacket, -0.15))
    cv.rect(4, 29, 3, 2, skin)
    cv.rect(18, 29, 3, 2, skin)
    # Neck + head
    cv.rect(10, 12, 5, 3, shade(skin, -0.2))
    cv.rect(8, 4, 9, 9, skin)
    cv.rect(8, 11, 9, 2, shade(skin, -0.15))
    # Eyes
    eye = hexc(p["eye"]) if p["eye"] else hexc("1a1a1a")
    cv.set(10, 8, eye)
    cv.set(14, 8, hexc("1a1a1a"))
    draw_hair(cv, p["hair_style"], 8, 4, 9, hair, accent)
    # Outline pass
    src = cv.img.copy().load()
    for y in range(H):
        for x in range(W):
            if src[x, y][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < W and 0 <= ny < H and src[nx, ny][3] == 255 and ny < 44:
                        cv.set(x, y, outline)
                        break
    cv.save(f"customers/{cid}_full.png")


def customer_portrait(cid: str, p: dict) -> None:
    W = H = 40
    rng = random.Random(p["seed"])
    cv = Canvas(W, H, hexc("0b0f16"))
    skin, hair, jacket = hexc(p["skin"]), hexc(p["hair"]), hexc(p["jacket"])
    accent = hexc(p["accent"])
    # Background: scan grid + accent glow
    for y in range(0, H, 4):
        cv.hline(0, W - 1, y, hexc("0e141d"))
    cv.glow(30, 8, 22, accent, 0.18)
    # Shoulders / jacket
    cv.ellipse(20, 42, 17, 10, jacket)
    cv.ellipse(20, 40, 15, 6, shade(jacket, 0.12))
    cv.rect(18, 32, 4, 8, shade(jacket, -0.35))
    cv.rect(26, 35, 2, 2, accent)
    # Neck
    cv.rect(16, 26, 8, 8, shade(skin, -0.25))
    # Head
    cv.ellipse(20, 18, 8, 10, skin)
    cv.rect(13, 22, 14, 3, shade(skin, -0.1))
    cv.dither(12, 8, 6, 20, shade(skin, -0.25), 0.4)  # side shading
    # Eyes
    eye = hexc(p["eye"]) if p["eye"] else hexc("15151a")
    cv.rect(15, 17, 3, 1, hexc("15151a"))
    cv.rect(22, 17, 3, 1, hexc("15151a"))
    cv.set(16, 17, eye)
    if p["eye"]:
        cv.glow(16, 17, 4, eye, 0.5)
    cv.set(23, 17, hexc("cfd8dc"))
    # Brows, nose, mouth
    cv.hline(14, 17, 15, shade(hair, 0.1))
    cv.hline(22, 25, 15, shade(hair, 0.1))
    cv.vline(20, 18, 21, shade(skin, -0.3))
    cv.hline(18, 22, 24, shade(skin, -0.45))
    # Cyber scar line on cheek
    cv.line(25, 20, 27, 24, shade(accent, -0.3))
    # Hair
    draw_hair(cv, p["hair_style"], 12, 9, 16, hair, accent, 1)
    if p["hair_style"] in ("bob", "long"):
        cv.ellipse(20, 10, 9, 4, hair)
    elif p["hair_style"] == "cap":
        cv.ellipse(20, 9, 9, 4, hexc("2b3138"))
        cv.rect(20, 10, 11, 2, hexc("2b3138"))
        cv.hline(12, 28, 12, hexc("3a424b"))
    elif p["hair_style"] == "mohawk":
        cv.rect(19, 3, 3, 8, accent)
        cv.rect(19, 3, 3, 1, shade(accent, 0.3))
    # Grain
    cv.noise(0, 0, W, H, (0, 0, 0, 60), 0.05, rng)
    # Frame
    cv.outline(0, 0, W, H, LINE_HI)
    cv.save(f"customers/{cid}_portrait.png")


# --- Diagnosis scan body -----------------------------------------------------
def scan_body() -> None:
    W, H = 48, 96
    cv = Canvas(W, H)
    body = hexc("12312d")
    edge = ACCENT_DIM
    # Head
    cv.ellipse(24, 11, 7, 9, body)
    # Neck
    cv.rect(21, 19, 6, 6, body)
    # Torso
    cv.rect(13, 25, 22, 30, body)
    cv.ellipse(24, 27, 12, 4, body)
    # Arms
    cv.rect(7, 27, 6, 28, body)
    cv.rect(35, 27, 6, 28, body)
    cv.rect(6, 55, 6, 6, body)
    cv.rect(36, 55, 6, 6, body)
    # Legs
    cv.rect(14, 55, 9, 38, body)
    cv.rect(25, 55, 9, 38, body)
    # Edge detection outline
    src = cv.img.copy().load()
    for y in range(H):
        for x in range(W):
            if src[x, y][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < W and 0 <= ny < H and src[nx, ny][3] > 0:
                        cv.set(x, y, edge)
                        break
    # Spine
    for y in range(20, 56, 2):
        cv.set(24, y, ACCENT)
    # Brain hint
    cv.ellipse(24, 9, 4, 5, hexc("1a5048"))
    # Port site marker
    cv.rect(23, 20, 3, 3, BRAND)
    cv.save("surgery/scan_body.png")


# --- Implant -----------------------------------------------------------------
def implant() -> None:
    W = H = 16
    cv = Canvas(W, H)
    # Octagonal housing
    cv.rect(4, 2, 8, 12, METAL)
    cv.rect(2, 4, 12, 8, METAL)
    cv.rect(3, 3, 10, 10, METAL)
    cv.outline(3, 3, 10, 10, METAL_DARK)
    cv.hline(4, 11, 2, METAL_DARK)
    cv.hline(4, 11, 13, METAL_DARK)
    cv.vline(2, 4, 11, METAL_DARK)
    cv.vline(13, 4, 11, METAL_DARK)
    cv.hline(4, 11, 3, shade(METAL, 0.35))
    # Core
    cv.rect(6, 6, 4, 4, hexc("0a2a26"))
    cv.rect(7, 7, 2, 2, ACCENT)
    # Alignment key notch at the top
    cv.rect(7, 1, 2, 3, WARN)
    cv.save("surgery/implant_nx1.png")


# --- Tool icons (16x16) --------------------------------------------------------
def icon_canvas() -> Canvas:
    return Canvas(16, 16)


def tool_scalpel(mono: bool = False) -> Canvas:
    cv = icon_canvas()
    handle = hexc("4b5563") if not mono else hexc("2b2f3a")
    blade = METAL if not mono else ACCENT
    cv.line(2, 13, 8, 7, handle)
    cv.line(3, 13, 9, 7, handle)
    cv.line(2, 14, 8, 8, shade(handle, -0.3))
    cv.line(9, 6, 13, 2, blade)
    cv.line(9, 7, 14, 2, shade(blade, -0.2))
    cv.line(10, 7, 14, 3, shade(blade, 0.3))
    if mono:
        cv.set(14, 1, hexc("ffffff"))
    return cv


def tool_retractor() -> Canvas:
    cv = icon_canvas()
    cv.rect(3, 2, 2, 10, METAL)
    cv.rect(11, 2, 2, 10, METAL)
    cv.rect(3, 7, 10, 2, METAL_DARK)
    cv.rect(1, 11, 4, 2, METAL)
    cv.rect(11, 11, 4, 2, METAL)
    cv.set(1, 13, METAL)
    cv.set(14, 13, METAL)
    return cv


def tool_cautery() -> Canvas:
    cv = icon_canvas()
    cv.rect(2, 9, 8, 4, hexc("3b4452"))
    cv.rect(2, 9, 8, 1, METAL)
    cv.rect(10, 10, 2, 2, METAL)
    cv.hline(12, 15, 10, DANGER)
    cv.hline(12, 15, 11, WARN)
    cv.set(4, 11, DANGER)
    return cv


def tool_forceps() -> Canvas:
    cv = icon_canvas()
    cv.line(2, 2, 9, 9, METAL)
    cv.line(2, 6, 9, 10, METAL)
    cv.line(9, 9, 14, 13, shade(METAL, 0.2))
    cv.line(9, 10, 13, 14, shade(METAL, 0.2))
    cv.rect(2, 2, 2, 5, METAL_DARK)
    return cv


def tool_splicer() -> Canvas:
    cv = icon_canvas()
    cv.rect(2, 5, 6, 6, hexc("2b2f3a"))
    cv.outline(2, 5, 6, 6, METAL)
    cv.hline(8, 11, 7, METAL)
    cv.hline(8, 11, 8, METAL)
    cv.line(11, 7, 14, 4, ACCENT)
    cv.line(11, 8, 14, 11, WARN)
    cv.set(4, 7, ACCENT)
    cv.set(5, 8, BRAND)
    return cv


def tool_suture() -> Canvas:
    cv = icon_canvas()
    cv.rect(2, 4, 9, 7, hexc("3b4452"))
    cv.outline(2, 4, 9, 7, METAL)
    cv.rect(4, 11, 3, 3, METAL_DARK)
    cv.rect(11, 6, 3, 3, METAL)
    cv.hline(11, 14, 9, TEXT)
    cv.set(14, 10, TEXT)
    return cv


def quick_coag() -> Canvas:
    cv = icon_canvas()
    cv.disc(8, 10, 4, BLOOD)
    cv.line(8, 2, 5, 8, BLOOD)
    cv.line(8, 2, 11, 8, BLOOD)
    cv.rect(5, 6, 7, 3, BLOOD)
    cv.hline(5, 11, 10, TEXT)
    cv.vline(8, 7, 13, TEXT)
    return cv


def quick_sedate() -> Canvas:
    cv = icon_canvas()
    cv.line(3, 12, 10, 5, METAL)
    cv.line(4, 12, 11, 5, METAL)
    cv.line(5, 10, 9, 6, ACCENT)
    cv.line(11, 4, 14, 1, TEXT)
    cv.line(2, 11, 5, 14, METAL_DARK)
    return cv


def quick_stabilize() -> Canvas:
    cv = icon_canvas()
    cv.hline(1, 4, 8, ACCENT)
    cv.line(4, 8, 6, 3, ACCENT)
    cv.line(6, 3, 9, 13, ACCENT)
    cv.line(9, 13, 11, 8, ACCENT)
    cv.hline(11, 14, 8, ACCENT)
    return cv


# --- App icon ----------------------------------------------------------------
def app_icon() -> None:
    S = 32
    cv = Canvas(S, S, BG_0)
    cv.rect(2, 2, 28, 28, PANEL)
    cv.outline(2, 2, 28, 28, LINE_HI)
    cv.glow(16, 16, 16, BRAND, 0.25)
    cv.line(7, 25, 22, 8, BRAND)
    cv.line(8, 25, 23, 8, shade(BRAND, 0.3))
    cv.line(22, 8, 26, 4, METAL)
    cv.hline(4, 9, 17, ACCENT)
    cv.line(9, 17, 12, 11, ACCENT)
    cv.line(12, 11, 15, 22, ACCENT)
    cv.line(15, 22, 18, 17, ACCENT)
    cv.hline(18, 27, 17, ACCENT)
    cv.save("ui/app_icon.png", scale=8)        # 256x256 (project icon)
    cv.save("ui/app_icon_1024.png", scale=32, opaque=True)  # App Store icon


def main() -> None:
    clinic_background()
    for cid, p in CUSTOMERS.items():
        customer_full(cid, p)
        customer_portrait(cid, p)
    scan_body()
    implant()
    tools = {
        "scalpel": tool_scalpel(),
        "scalpel_mono": tool_scalpel(mono=True),
        "retractor": tool_retractor(),
        "cautery": tool_cautery(),
        "forceps": tool_forceps(),
        "splicer": tool_splicer(),
        "suture": tool_suture(),
        "quick_coag": quick_coag(),
        "quick_sedate": quick_sedate(),
        "quick_stabilize": quick_stabilize(),
    }
    for name, cv in tools.items():
        cv.save(f"tools/{name}.png")
    app_icon()


if __name__ == "__main__":
    main()
