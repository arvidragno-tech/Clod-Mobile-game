"""Cyberware icons (32x32). Engineered, not magical: housings, screws,
connectors, cables and synthetic muscle; glow is reserved for status LEDs,
optics and active cores. Tier changes the material language."""
from __future__ import annotations

import math

from . import palette as pal
from .lib import Canvas, clamp

CATEGORIES = ["eyes", "arms", "legs", "spine", "neural", "dermal", "respiratory", "internal"]

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
        self.pcb = R("1f4a3a" if tier < 5 else "2a1f30")


def rgb(ramp, i):
    c = ramp[int(clamp(i, 0, 7))]
    return (c[0], c[1], c[2], 255)


def screw(cv, x, y, st):
    cv.set(x, y, rgb(st.metal, 6))
    cv.set(x + 1, y, rgb(st.metal, 3))
    cv.set(x, y + 1, rgb(st.metal, 2))
    cv.set(x + 1, y + 1, rgb(st.metal, 1))


def led(cv, x, y, st, big=False):
    cv.set(x, y, rgb(st.glow, 7))
    if big:
        for dx, dy in ((1, 0), (0, 1), (1, 1)):
            cv.set(x + dx, y + dy, rgb(st.glow, 5))


def cable(cv, pts, st, w=1):
    for a, b in zip(pts, pts[1:]):
        steps = int(max(abs(b[0] - a[0]), abs(b[1] - a[1]))) + 1
        for k in range(steps + 1):
            t = k / max(1, steps)
            x = a[0] + (b[0] - a[0]) * t
            y = a[1] + (b[1] - a[1]) * t
            cv.set(int(x), int(y), rgb(st.cable, 3))
            if w > 1:
                cv.set(int(x) + 1, int(y), rgb(st.cable, 1))
            cv.set(int(x), int(y) - 1, rgb(st.cable, 5)) if k % 3 == 0 else None


def tape(cv, x, y, w, h):
    """Improvised repair tape (black-market tier)."""
    for yy in range(y, y + h):
        for xx in range(x, x + w):
            cv.set(xx, yy, (176, 150, 92, 255) if (xx + yy) % 4 else (140, 118, 70, 255))


def draw_eyes(cv, st):
    cable(cv, [(30, 26), (24, 22), (20, 19)], st, 2)
    cv.cylinder(19, 13, 6, 10, st.trim, 1, 5, vertical=False)
    cv.sphere(14, 16, 11, 11, st.body, 1.2, 6.4)
    # Front optic: dark glass with aperture ring
    cv.sphere(12, 15, 7, 7, st.metal, 0.8, 5.5)
    cv.sphere(12, 15, 5, 5, R("12161e"), 0.5, 3.5)
    for a in range(0, 360, 45):  # aperture blades
        x = 12 + round(3.5 * math.cos(math.radians(a)))
        y = 15 + round(3.5 * math.sin(math.radians(a)))
        cv.set(x, y, rgb(st.metal, 2))
    cv.sphere(12, 15, 2, 2, st.glow, 2.5, 7)
    cv.set(10, 12, (240, 250, 255, 255))
    cv.set(11, 12, (180, 200, 220, 255))
    screw(cv, 21, 9, st)
    screw(cv, 21, 21, st)
    led(cv, 5, 22, st)


def draw_arms(cv, st):
    # Forearm housing (diagonal), synthetic muscle visible through a slot.
    cv.capsule(7, 27, 23, 9, 6.0, st.body, 1.0, 6.2, r2=5.0)
    for k in range(10):  # muscle slot
        t = k / 9
        x = 10 + (19 - 10) * t
        y = 22 + (12 - 22) * t
        for d in (-1, 0, 1):
            cv.set(int(x + d), int(y + d), rgb(st.muscle, 2 + (k + d) % 3))
    cv.capsule(5, 22, 18, 7, 1.0, st.metal, 2, 6.5)  # piston
    cv.capsule(12, 30, 26, 14, 1.0, st.metal, 1, 5)
    cv.sphere(25, 7, 4, 4, st.trim, 1, 5.5)  # wrist joint
    for p in ((8, 26), (15, 18), (21, 12)):
        screw(cv, *p, st)
    led(cv, 18, 19, st)
    if st.tier >= 3:  # armour plate
        cv.shaded_poly([(10, 27), (17, 20), (20, 23), (13, 30)], st.trim, 5, 2.5, 1, 1)


def draw_legs(cv, st):
    cv.capsule(10, 3, 14, 15, 5.5, st.body, 1.0, 6.0, r2=5.0)  # thigh
    cv.capsule(16, 18, 20, 30, 4.0, st.body, 1.0, 5.5, r2=3.2)  # shin
    cv.capsule(21, 17, 24, 29, 1.0, st.metal, 2, 7)  # shock piston
    cv.capsule(22, 17, 25, 22, 1.6, st.trim, 1, 5)
    cv.sphere(15, 16, 4.5, 4.5, st.metal, 1.0, 6.5)  # knee
    cv.sphere(15, 16, 1.8, 1.8, st.trim, 1, 4)
    screw(cv, 8, 6, st)
    screw(cv, 18, 26, st)
    led(cv, 12, 9, st)


def draw_spine(cv, st):
    cable(cv, [(23, 2), (24, 10), (23, 18), (24, 30)], st, 2)
    for k in range(5):
        y = 3 + k * 6
        cv.shaded_poly([(9, y), (21, y), (22, y + 2), (21, y + 4), (9, y + 4), (8, y + 2)], st.body, 6, 2.5, 1.4, 1)
        cv.set(6, y + 2, rgb(st.metal, 5))
        cv.set(7, y + 2, rgb(st.metal, 3))
        cv.set(23, y + 2, rgb(st.metal, 4))
        led(cv, 15, y + 2, st) if k % 2 == 0 else cv.set(15, y + 2, rgb(st.trim, 2))
    cv.rect(14, 2, 2, 28, rgb(st.trim, 2))


def draw_neural(cv, st):
    cv.shaded_poly([(5, 7), (27, 7), (27, 25), (5, 25)], st.pcb, 4.5, 2.5, 1.0, 1)
    for x in range(6, 27, 2):  # gold contact pins
        cv.set(x, 5, rgb(st.gold, 6))
        cv.set(x, 6, rgb(st.gold, 4))
        cv.set(x, 26, rgb(st.gold, 3))
        cv.set(x, 27, rgb(st.gold, 2))
    for y in (10, 14, 18, 22):  # traces
        for x in range(7, 11):
            cv.set(x, y, rgb(st.gold, 3))
    cv.shaded_poly([(12, 10), (24, 10), (24, 22), (12, 22)], st.body, 5.5, 2, 1, 1)  # die / heat spreader
    for x in range(13, 24, 2):  # heat sink fins
        cv.rect(x, 11, 1, 10, rgb(st.metal, 5 if x < 18 else 3))
    led(cv, 8, 21, st, big=True)
    screw(cv, 25, 8, st)
    if st.tier == 5:
        tape(cv, 4, 14, 6, 3)


def draw_dermal(cv, st):
    cx, cy = 16, 16
    for y in range(3, 30):
        for x in range(3, 30):
            dx, dy = (x + 0.5 - cx) / 13, (y + 0.5 - cy) / 13
            d = dx * dx + dy * dy
            if d > 1:
                continue
            nz = math.sqrt(1 - d)
            i = clamp(dx * -0.55 + dy * -0.62 + nz * 0.56, 0, 1)
            # hex tile seams
            q = (x + (y // 4 % 2) * 2) % 5
            seam = (y % 4 == 0) or q == 0
            cv.shade_px(x, y, st.trim if seam else st.body, (1.2 + 4.8 * i) - (1.2 if seam else 0))
    for p in ((9, 9), (22, 10), (16, 23)):
        screw(cv, *p, st)
    led(cv, 16, 15, st)


def draw_respiratory(cv, st):
    cv.cylinder(8, 6, 16, 22, st.body, 1.0, 6.0)
    for y in range(9, 26, 3):  # vents
        cv.rect(10, y, 12, 1, rgb(st.trim, 1))
    cv.sphere(16, 6, 8, 2.5, st.metal, 2, 6.5)
    cv.sphere(16, 28, 8, 2.5, st.metal, 1, 4.5)
    cable(cv, [(16, 3), (16, 1), (24, 1), (29, 4)], st, 2)
    cv.sphere(16, 17, 3.2, 3.2, st.metal, 1, 6)  # intake fan hub
    for a in range(0, 360, 60):
        cv.set(16 + round(2.2 * math.cos(math.radians(a))), 17 + round(2.2 * math.sin(math.radians(a))), rgb(st.trim, 2))
    led(cv, 21, 25, st)


def draw_internal(cv, st):
    cv.capsule(9, 16, 23, 16, 8.0, st.body, 1.0, 6.0)
    # Glass window with bio-fluid
    for y in range(12, 21):
        for x in range(11, 22):
            v = 2.5 + (21 - y) * 0.35
            cv.shade_px(x, y, st.glow if st.tier >= 2 else R("4a8a3a"), v)
    cv.rect(11, 12, 11, 1, rgb(st.metal, 6))
    cv.rect(11, 20, 11, 1, rgb(st.metal, 2))
    cv.set(13, 14, (230, 255, 250, 255))
    cable(cv, [(2, 10), (5, 13)], st, 2)
    cable(cv, [(30, 22), (27, 19)], st, 2)
    for p in ((7, 11), (24, 20)):
        screw(cv, *p, st)
    led(cv, 25, 11, st)


DRAW = {"eyes": draw_eyes, "arms": draw_arms, "legs": draw_legs, "spine": draw_spine, "neural": draw_neural,
        "dermal": draw_dermal, "respiratory": draw_respiratory, "internal": draw_internal}


def make_icon(category: str, tier: int) -> Canvas:
    cv = Canvas(32, 32)
    st = Style(tier)
    DRAW[category](cv, st)
    if tier == 5 and category != "neural":
        tape(cv, 3, 3, 4, 2)
        cv.line(2, 29, 9, 25, (255, 61, 129, 255))  # exposed live wire
    cv.selective_outline()
    return cv


def generate():
    n = 0
    for cat in CATEGORIES:
        for tier in range(1, 6):
            make_icon(cat, tier).save(f"cyberware/{cat}_t{tier}.png")
            n += 1
    print("cyberware icons:", n)
