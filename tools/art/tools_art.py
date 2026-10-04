"""Surgical tool sprites (24x24), quick-action icons (12x12), UI icons (12x12)
and faction emblems (16x16)."""
from __future__ import annotations

import math

from . import palette as pal
from .lib import Canvas, clamp

STEEL = pal.ramp("9aa6b4", 0.06, 1.15)
DARK = pal.ramp("3a404c", 0.06, 1.1)
GRIP = pal.ramp("2c2f38", 0.05)
RUST = pal.ramp("7a4a2a", 0.08)
ORANGE = pal.ramp("c46a28", 0.06)
GOLD = pal.ramp("a8843a", 0.05)
WHITE = pal.ramp("d6dade", 0.05)
GREEN_P = pal.ramp("3a6a4a", 0.06)
G = {k: pal.glow_ramp(v) for k, v in pal.GLOWS.items()}


def c(ramp, i):
    r = ramp[int(clamp(i, 0, 7))]
    return (r[0], r[1], r[2], 255)


def blade(cv, x0, y0, x1, y1, ramp, width=2):
    """Diagonal blade with bright cutting edge."""
    steps = int(max(abs(x1 - x0), abs(y1 - y0)))
    for k in range(steps + 1):
        t = k / max(1, steps)
        x = round(x0 + (x1 - x0) * t)
        y = round(y0 + (y1 - y0) * t)
        w = max(1, round(width * (1 - t * 0.6)))
        for d in range(w):
            cv.set(x + d, y, c(ramp, 4 - d))
        cv.set(x - 1, y + 1, c(ramp, 7))  # edge glint


def handle(cv, x0, y0, x1, y1, ramp, r=1.6):
    cv.capsule(x0, y0, x1, y1, r, ramp, 1, 5.5)


def tool_scalpel(cv, tier):
    hr = {1: RUST, 2: DARK, 3: GRIP}[tier]
    handle(cv, 3, 21, 12, 12, hr, 1.8)
    if tier == 1:
        for k in range(0, 9, 3):
            cv.set(5 + k, 19 - k, c(RUST, 1))  # tape wraps
    if tier == 2:
        for k in range(0, 8, 2):
            cv.set(5 + k, 18 - k, c(STEEL, 6))  # knurling
    cv.rect(11, 11, 3, 3, c(STEEL, 3))
    if tier == 3:
        # Laser cutter: emitter head + beam
        cv.sphere(15, 9, 3.2, 3.2, DARK, 1, 5)
        cv.set(16, 8, c(G["red"], 7))
        for k in range(6):
            cv.set(18 + k, 5 - k // 1 if k < 5 else 0, c(G["red"], 6 - k // 2))
        cv.set(9, 15, c(G["red"], 5))
    else:
        blade(cv, 13, 10, 21, 2, STEEL, 3 if tier == 1 else 2)


def tool_retractor(cv, tier):
    for x in (6, 16):
        cv.capsule(x, 3, x - 1, 17, 1.4, STEEL, 1.5, 6)
        cv.set(x - 3, 19, c(STEEL, 5))
        cv.set(x - 2, 20, c(STEEL, 4))
        cv.set(x - 1, 19, c(STEEL, 3))
    cv.capsule(5, 10, 17, 10, 1.6, DARK, 1, 5)
    cv.sphere(11, 10, 2.5, 2.5, STEEL if tier == 1 else GOLD, 1, 6)
    if tier >= 2:  # micro clamp: fine teeth + LED
        for x in range(3, 20, 2):
            cv.set(x, 21, c(STEEL, 6))
        cv.set(20, 4, c(G["cyan"], 7))


def tool_cautery(cv, tier):
    body = DARK if tier == 1 else pal.ramp("4a3a5a", 0.06)
    cv.capsule(3, 19, 14, 9, 2.6, body, 1, 5.5)
    cv.capsule(14, 9, 18, 5, 1.2, STEEL, 2, 6.5)
    tipc = G["amber"] if tier == 1 else G["blue"]
    cv.set(19, 4, c(tipc, 7))
    cv.set(20, 3, c(tipc, 5))
    cv.set(19, 3, c(tipc, 4))
    cv.set(8, 15, c(tipc, 5))
    cv.set(6, 17, c(STEEL, 6))
    for k in range(3):
        cv.set(10 - k, 14 + k, c(body, 7))


def tool_forceps(cv, tier):
    cv.capsule(4, 20, 17, 5, 1.1, STEEL, 2, 6.5)
    cv.capsule(8, 21, 19, 7, 1.1, STEEL, 1, 5)
    cv.sphere(5, 20, 2.4, 2.4, DARK if tier == 1 else GOLD, 1, 6)
    if tier >= 2:  # magnetic tips
        cv.set(17, 5, c(G["cyan"], 6))
        cv.set(19, 7, c(G["cyan"], 6))


def tool_splicer(cv, tier):
    cv.shaded_poly([(3, 12), (11, 9), (13, 15), (5, 19)], DARK, 5, 2, 1, 1)
    cv.capsule(12, 12, 19, 8, 1.2, STEEL, 2, 6)
    cv.line(19, 8, 22, 5, c(G["cyan"], 6))
    cv.line(19, 9, 22, 12, c(G["amber"], 6))
    cv.set(6, 14, c(G["cyan"], 7))
    cv.set(8, 13, c(G["magenta"], 6))
    if tier >= 2:  # neural probe: fine needle + readout
        cv.line(14, 15, 21, 20, c(STEEL, 6))
        cv.rect(4, 4, 6, 4, c(DARK, 2))
        cv.line(5, 6, 8, 5, c(G["green"], 6))


def tool_suture(cv, tier):
    body = DARK if tier == 1 else WHITE
    cv.shaded_poly([(3, 7), (15, 7), (16, 15), (3, 15)], body, 5.5, 2.5, 1, 1)
    cv.rect(5, 15, 4, 6, c(DARK, 2))
    cv.capsule(15, 10, 21, 10, 1.4, STEEL, 2, 6.5)
    if tier == 1:
        for k in range(3):
            cv.set(18 + k * 2, 13, c(STEEL, 6))
    else:
        cv.set(21, 10, c(G["green"], 7))
        cv.set(10, 9, c(G["green"], 5))


def tool_drill(cv, tier):
    body = ORANGE if tier == 1 else DARK
    cv.shaded_poly([(3, 6), (13, 6), (14, 13), (4, 13)], body, 5.5, 2.5, 1, 1)
    cv.shaded_poly([(6, 13), (11, 13), (12, 22), (7, 22)], GRIP, 4, 1.5, 1, 1)
    cv.capsule(14, 9, 17, 9, 2, STEEL, 2, 6)
    for x in range(17, 23):  # spiral bit
        cv.set(x, 9 + (1 if x % 2 else -1) * (0 if x % 3 else 1), c(STEEL if tier == 1 else pal.ramp("d8e4f0"), 6 - (x % 2) * 3))
        cv.set(x, 9, c(STEEL, 5))
    if tier >= 2:
        cv.set(22, 9, c(G["cyan"], 7))
    cv.set(8, 8, c(G["amber"] if tier == 1 else G["cyan"], 6))


def tool_scanner(cv, tier):
    shell = {1: DARK, 2: pal.ramp("2f3c56"), 3: pal.ramp("4a3a5a")}[tier]
    cv.shaded_poly([(3, 3), (16, 3), (16, 21), (3, 21)], shell, 5, 2, 1, 1)
    cv.rect(5, 5, 9, 9, c(pal.ramp("0a1416"), 3))
    glow = G["cyan"] if tier < 3 else G["blue"]
    for x in range(5, 14):  # waveform on screen
        y = 9 + round(math.sin(x * 1.3) * (2 if tier > 1 else 1))
        cv.set(x, y, c(glow, 6))
    cv.set(6, 17, c(G["green"], 6))
    cv.set(9, 17, c(G["amber"], 5))
    if tier >= 2:
        cv.sphere(19, 12, 3.5, 6, STEEL, 1.5, 6)  # emitter dish
        cv.set(20, 11, c(glow, 7))
    if tier == 3:
        for a in (0, 1, 2):
            cv.set(21 + a, 8 - a, c(glow, 5 - a))
            cv.set(21 + a, 16 + a, c(glow, 5 - a))


def tool_calibrator(cv, tier):
    cv.shaded_poly([(2, 6), (21, 6), (21, 18), (2, 18)], DARK if tier == 1 else pal.ramp("2f3c56"), 5, 2, 1, 1)
    for k, x in enumerate((5, 9, 13)):
        cv.sphere(x, 14, 1.6, 1.6, STEEL, 1, 6)
        cv.set(x, 13, c(G["amber"] if k == 0 else STEEL, 6))
    cv.rect(4, 8, 15, 3, c(pal.ramp("0a1416"), 3))
    glow = G["green"] if tier == 1 else G["cyan"]
    for x in range(4, 19):
        cv.set(x, 9 + (1 if (x // 2) % 2 else 0) * (1 if tier == 1 else 0), c(glow, 6))
    cv.line(18, 13, 21, 2, c(STEEL, 5))


def tool_injector(cv, tier):
    cv.capsule(3, 19, 16, 6, 2.6, WHITE, 2, 6)
    for k in range(4):
        x, y = 7 + k * 2, 15 - k * 2
        cv.set(x, y, c(G["blue"], 6))
        cv.set(x + 1, y, c(G["blue"], 4))
    cv.capsule(16, 6, 21, 2, 0.8, STEEL, 3, 7)
    cv.rect(2, 19, 3, 3, c(DARK, 3))


DRAW = {
    "scalpel": tool_scalpel, "retractor": tool_retractor, "cautery": tool_cautery, "forceps": tool_forceps,
    "splicer": tool_splicer, "suture": tool_suture, "drill": tool_drill, "scanner": tool_scanner,
    "calibrator": tool_calibrator, "injector": tool_injector,
}


def make_tool(category, tier) -> Canvas:
    cv = Canvas(24, 24)
    DRAW[category](cv, tier)
    cv.selective_outline()
    return cv


# --- 12x12 UI / quick-action icons -------------------------------------------

def icon(draw) -> Canvas:
    cv = Canvas(12, 12)
    draw(cv)
    return cv


def i_coag(cv):
    for y in range(1, 11):
        w = 0 if y < 3 else min(4, (y - 1) // 2 + 1)
        for x in range(6 - w, 6 + w + 1):
            cv.set(x, y, c(pal.ramp("b3122e"), 3 + (1 if x < 6 else 0)))
    cv.set(6, 2, c(pal.ramp("b3122e"), 4))
    cv.set(4, 6, c(pal.ramp("b3122e"), 7))
    cv.rect(5, 7, 3, 1, (240, 240, 240, 255))
    cv.rect(6, 6, 1, 3, (240, 240, 240, 255))


def i_sedate(cv):
    cv.line(1, 10, 8, 3, c(STEEL, 6))
    cv.line(2, 10, 9, 3, c(STEEL, 4))
    cv.line(3, 8, 6, 5, c(G["cyan"], 6))
    cv.line(9, 3, 11, 1, c(WHITE, 7))
    cv.line(0, 9, 2, 11, c(DARK, 4))


def i_stabilize(cv):
    pts = [(0, 6), (3, 6), (4, 3), (6, 10), (8, 4), (9, 6), (11, 6)]
    for a, b in zip(pts, pts[1:]):
        cv.line(a[0], a[1], b[0], b[1], c(G["cyan"], 6))


def i_supply(cv):
    cv.shaded_poly([(1, 4), (11, 4), (11, 11), (1, 11)], pal.ramp("6e6146"), 5, 2.5, 1, 1)
    cv.rect(1, 4, 10, 1, c(pal.ramp("6e6146"), 6))
    cv.rect(5, 6, 2, 4, c(G["red"], 5))
    cv.rect(4, 7, 4, 2, c(G["red"], 5))
    cv.line(2, 3, 5, 1, c(STEEL, 5))


def i_skills(cv):
    cv.sphere(6, 6, 5, 5, pal.ramp("4a3a5a"), 1.5, 5.5)
    for p in ((4, 4), (7, 3), (8, 6), (5, 8), (3, 6)):
        cv.set(*p, c(G["cyan"], 6))
    cv.line(4, 4, 7, 3, c(G["cyan"], 4))
    cv.line(8, 6, 5, 8, c(G["cyan"], 4))


def i_upgrade(cv):
    cv.shaded_poly([(1, 6), (6, 1), (11, 6), (10, 6), (10, 11), (2, 11), (2, 6)], DARK, 5, 2, 1, 1)
    cv.rect(5, 7, 2, 4, c(G["amber"], 5))
    cv.line(6, 3, 6, 5, c(G["green"], 7))
    cv.set(5, 4, c(G["green"], 7))
    cv.set(7, 4, c(G["green"], 7))


def i_dossier(cv):
    cv.shaded_poly([(1, 2), (5, 2), (6, 3), (11, 3), (11, 11), (1, 11)], pal.ramp("8c7050"), 5.5, 3, 1, 1)
    cv.rect(3, 6, 6, 1, c(DARK, 2))
    cv.rect(3, 8, 4, 1, c(DARK, 2))
    cv.set(9, 8, c(G["red"], 6))


def i_blackmarket(cv):
    cv.sphere(6, 6, 5, 5, pal.ramp("2e3138"), 1, 4.5)
    cv.ellipse(6, 6, 3.5, 2, c(G["magenta"], 4))
    cv.ellipse(6, 6, 1.4, 1.6, c(G["magenta"], 7))
    cv.set(6, 6, (10, 8, 12, 255))


def i_menu(cv):
    for y in (3, 6, 9):
        cv.rect(2, y, 8, 1, c(STEEL, 5))


def i_money(cv):
    cv.sphere(6, 6, 5, 5, GOLD, 1.5, 6.5)
    cv.rect(4, 4, 4, 1, c(GOLD, 2))
    cv.rect(4, 7, 4, 1, c(GOLD, 2))
    cv.rect(5, 3, 1, 6, c(GOLD, 2))


def i_xp(cv):
    pts = [(6, 0), (8, 4), (12, 5), (9, 8), (10, 12), (6, 10), (2, 12), (3, 8), (0, 5), (4, 4)]
    cv.shaded_poly(pts, pal.ramp("2ee6c8", 0.04), 6, 3, 1, 0.5)


def i_rep(cv):
    cv.shaded_poly([(1, 1), (11, 1), (11, 6), (6, 11), (1, 6)], pal.ramp("ff3d81", 0.04), 5.5, 2.5, 1, 1)
    cv.set(4, 3, c(pal.ramp("ff3d81"), 7))


def i_supplies(cv):
    cv.shaded_poly([(2, 2), (10, 2), (10, 11), (2, 11)], WHITE, 6, 3.5, 1, 1)
    cv.rect(5, 4, 2, 5, c(G["green"], 5))
    cv.rect(4, 5, 4, 2, c(G["green"], 5))


def i_parts(cv):
    cv.sphere(6, 6, 5, 5, STEEL, 1.5, 6)
    cv.sphere(6, 6, 2, 2, DARK, 0.5, 2)
    for a in range(0, 360, 60):
        cv.set(6 + round(5.4 * math.cos(math.radians(a))), 6 + round(5.4 * math.sin(math.radians(a))), c(STEEL, 3))


def i_tokens(cv):
    cv.shaded_poly([(6, 0), (11, 6), (6, 11), (1, 6)], pal.ramp("a8327a"), 6, 2.5, 1, 1)
    cv.set(6, 5, c(G["magenta"], 7))
    cv.set(5, 4, c(G["magenta"], 6))


def i_heat(cv):
    cv.ellipse(6, 7, 4.5, 4.5, c(G["red"], 4))
    cv.ellipse(6, 5, 2.5, 4, c(G["amber"], 5))
    cv.ellipse(6, 8, 1.5, 2, c(G["amber"], 7))


def i_neural(cv):
    cv.sphere(6, 6, 5.2, 5, pal.ramp("4a3a5a"), 1.5, 5.5)
    for x in range(2, 11):
        cv.set(x, 6 + round(math.sin(x * 1.4) * 2), c(G["cyan"], 6))


def i_lock(cv):
    cv.rect(2, 5, 8, 7, c(DARK, 4))
    cv.rect(3, 2, 1, 4, c(STEEL, 5))
    cv.rect(8, 2, 1, 4, c(STEEL, 4))
    cv.rect(4, 1, 4, 1, c(STEEL, 6))
    cv.rect(5, 7, 2, 3, c(G["amber"], 5))


def i_warning(cv):
    for y in range(1, 11):
        w = y // 2
        for x in range(6 - w, 6 + w + 1):
            cv.set(x, y, c(G["amber"], 5))
    cv.rect(6, 4, 1, 4, (20, 16, 10, 255))
    cv.set(6, 9, (20, 16, 10, 255))


UI_ICONS = {
    "coag": i_coag, "sedate": i_sedate, "stabilize": i_stabilize, "supply": i_supply, "skills": i_skills,
    "upgrade": i_upgrade, "dossier": i_dossier, "blackmarket": i_blackmarket, "menu": i_menu, "money": i_money,
    "xp": i_xp, "rep": i_rep, "supplies": i_supplies, "parts": i_parts, "tokens": i_tokens, "heat": i_heat,
    "neural": i_neural, "lock": i_lock, "warning": i_warning,
}


# --- Faction emblems (16x16) -----------------------------------------------------

def emblem(fid) -> Canvas:
    cv = Canvas(16, 16)
    if fid == "street_gangs":  # crossed rebar + rust red
        col = pal.ramp("c0452a")
        cv.shaded_poly([(1, 2), (15, 2), (15, 9), (8, 15), (1, 9)], pal.ramp("2a1a1a"), 4, 2, 1, 1)
        cv.line(4, 4, 12, 12, c(col, 6))
        cv.line(12, 4, 4, 12, c(col, 5))
        cv.set(8, 8, c(col, 7))
    elif fid == "corporate_security":  # shield + cyan bar
        cv.shaded_poly([(2, 1), (14, 1), (14, 8), (8, 15), (2, 8)], pal.ramp("2f3c56"), 5, 2, 1, 1)
        cv.rect(5, 5, 6, 2, c(G["blue"], 6))
        cv.rect(7, 4, 2, 6, c(G["blue"], 5))
    elif fid == "independent_mercs":  # crosshair, steel/amber
        cv.ellipse(8, 8, 6.5, 6.5, c(DARK, 3))
        cv.ellipse(8, 8, 5, 5, c(DARK, 1))
        cv.rect(8, 1, 1, 14, c(G["amber"], 5))
        cv.rect(1, 8, 14, 1, c(G["amber"], 5))
        cv.set(8, 8, c(G["amber"], 7))
    elif fid == "black_market":  # eye
        cv.shaded_poly([(0, 8), (5, 3), (11, 3), (16, 8), (11, 13), (5, 13)], pal.ramp("2e2030"), 4, 2, 1, 1)
        cv.ellipse(8, 8, 3, 3, c(G["magenta"], 5))
        cv.ellipse(8, 8, 1.4, 1.4, c(G["magenta"], 7))
        cv.set(8, 8, (8, 6, 10, 255))
    elif fid == "medical_authorities":  # green cross on white disc
        cv.sphere(8, 8, 7, 7, WHITE, 2.5, 6.5)
        cv.rect(6, 3, 4, 10, c(G["green"], 4))
        cv.rect(3, 6, 10, 4, c(G["green"], 4))
    cv.selective_outline()
    return cv


FACTIONS = ["street_gangs", "corporate_security", "independent_mercs", "black_market", "medical_authorities"]

TOOLS = {
    # id: (category, tier)
    "scalpel_rust": ("scalpel", 1), "scalpel_precision": ("scalpel", 2), "laser_cutter": ("scalpel", 3),
    "retractor_basic": ("retractor", 1), "micro_clamp": ("retractor", 2),
    "cautery_basic": ("cautery", 1), "plasma_cauterizer": ("cautery", 2),
    "forceps_basic": ("forceps", 1), "maglock_forceps": ("forceps", 2),
    "splicer_basic": ("splicer", 1), "neural_probe": ("splicer", 2),
    "suture_basic": ("suture", 1), "dermal_sealer": ("suture", 2),
    "cyber_drill": ("drill", 1), "diamond_drill": ("drill", 2),
    "scanner_basic": ("scanner", 1), "diagnostic_scanner": ("scanner", 2), "deep_scanner": ("scanner", 3),
    "tuning_deck": ("calibrator", 1), "neural_calibrator": ("calibrator", 2),
    "nanite_injector": ("injector", 1),
}


def generate():
    for tid, (cat, tier) in TOOLS.items():
        make_tool(cat, tier).save(f"tools/{tid}.png")
    for name, fn in UI_ICONS.items():
        cv = icon(fn)
        cv.selective_outline()
        cv.save(f"ui/icons/{name}.png")
    for fid in FACTIONS:
        emblem(fid).save(f"factions/{fid}.png")
    app_icon()
    print("tools:", len(TOOLS), "ui icons:", len(UI_ICONS), "emblems:", len(FACTIONS))


def app_icon():
    """App icon on a 60x60 grid (iOS sizes 120/180 are exact 2x/3x; 1024 is
    17x plus a 2 px bleed). Big, high-contrast shapes so it reads at 40 px:
    a cyan neural implant under a magenta-edged scalpel, a blood drop, on a
    dark underground backdrop with a magenta key light."""
    import os
    from PIL import Image
    from .lib import SPRITES, bayer
    S = 60
    img = Image.new("RGB", (S, S))
    bg0, bg1, key = (9, 8, 14), (22, 17, 34), (110, 26, 84)
    for y in range(S):
        for x in range(S):
            d = math.hypot(x - 24, y - 22) / 42.0
            t = clamp(1.0 - d, 0.0, 1.0)
            base = bg1 if (y / S) < 0.62 + 0.25 * bayer(x, y) else bg0
            band = 0.0
            if t > 0.5 or (t > 0.38 and bayer(x, y) < (t - 0.38) / 0.12):
                band = 0.32
            if t > 0.78 or (t > 0.68 and bayer(x, y) < (t - 0.68) / 0.1):
                band = 0.55
            img.putpixel((x, y), tuple(int(base[i] + (key[i] - base[i]) * band) for i in range(3)))
    px = img.load()

    def rect(x, y, w, h, c):
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                if 0 <= xx < S and 0 <= yy < S:
                    px[xx, yy] = c

    # Neural implant: chunky chip with pins and a glowing core.
    cyan, cyan_d, cyan_l = (46, 230, 200), (20, 110, 100), (180, 255, 240)
    metal, metal_d, metal_l = (60, 70, 86), (28, 33, 42), (120, 134, 152)
    rect(13, 13, 26, 26, metal_d)
    rect(14, 14, 24, 24, metal)
    rect(14, 14, 24, 2, metal_l)
    for k in range(5):  # pins
        rect(16 + k * 5, 10, 2, 3, metal_l)
        rect(16 + k * 5, 39, 2, 3, metal_l)
        rect(10, 16 + k * 5, 3, 2, metal_l)
        rect(39, 16 + k * 5, 3, 2, metal_l)
    rect(19, 19, 14, 14, cyan_d)
    rect(21, 21, 10, 10, cyan)
    rect(23, 23, 6, 6, cyan_l)
    for k in range(3):  # traces
        rect(15, 18 + k * 6, 4, 1, cyan_d)
        rect(33, 20 + k * 6, 4, 1, cyan_d)
    # Scalpel: diagonal blade crossing the chip, magenta cutting edge.
    steel, steel_l, edge = (170, 182, 196), (236, 242, 248), (255, 61, 129)
    handle, handle_l = (40, 44, 54), (80, 88, 104)
    for t in range(0, 36):
        x, y = 15 + t, 54 - t
        if t < 14:  # handle with cyan grip rings
            rect(x - 2, y - 2, 5, 5, (10, 10, 14))
        else:
            w = 5 if t < 31 else 3
            rect(x - 2, y - 2, w + 1, w + 1, (10, 10, 14))
    for t in range(0, 36):
        x, y = 15 + t, 54 - t
        if t < 14:
            rect(x - 1, y - 1, 3, 3, handle)
            px[x, y - 1] = handle_l
            if t % 4 == 1:
                rect(x - 1, y - 1, 3, 3, cyan_d)
        else:  # blade: silver body, bright spine, magenta cutting edge
            w = 4 if t < 31 else 2
            rect(x - 1, y - 1, w, w, steel)
            px[x, y - 1] = steel_l
            px[min(S - 1, x + 1), y - 1] = steel_l
            ex, ey = x + w - 2, y + w - 2
            if 0 <= ex < S and 0 <= ey < S:
                px[ex, ey] = edge
    # Outline the blade for small-size contrast.
    rect(30, 38, 2, 2, (10, 10, 14))
    # Blood drop under the tip.
    red, red_l = (196, 22, 48), (255, 110, 120)
    rect(49, 25, 3, 4, red)
    rect(48, 27, 5, 3, red)
    px[50, 26] = red_l
    # Frame: thin cyan bracket corners (reads as a medical HUD).
    for (cx, cy, sx, sy) in ((2, 2, 1, 1), (57, 2, -1, 1), (2, 57, 1, -1), (57, 57, -1, -1)):
        for k in range(6):
            px[cx + sx * k, cy] = cyan_d
            px[cx, cy + sy * k] = cyan_d
    out = os.path.join(SPRITES, "ui")
    img.resize((240, 240), Image.NEAREST).save(os.path.join(out, "app_icon.png"), optimize=True)
    big = Image.new("RGB", (1024, 1024), bg0)
    big.paste(img.resize((1020, 1020), Image.NEAREST), (2, 2))
    big.save(os.path.join(out, "app_icon_1024.png"), optimize=True)
    # iOS icon set (iPhone): exact 2x/3x where possible, nearest elsewhere.
    ios = os.path.join(SPRITES, "..", "ios")
    os.makedirs(ios, exist_ok=True)
    for size in (40, 58, 60, 76, 80, 87, 120, 152, 167, 180):
        img.resize((size, size), Image.NEAREST).save(os.path.join(ios, f"icon_{size}.png"), optimize=True)
    # Launch screen: the clinic mark + wordmark, integer-scaled per density.
    logo = Image.new("RGBA", (64, 40), (0, 0, 0, 0))
    lp = logo.load()
    small = img.crop((10, 9, 44, 45)).resize((34, 36), Image.NEAREST)
    logo.paste(small, (15, 0))
    for scale, name in ((4, "launch@2x.png"), (6, "launch@3x.png")):
        logo.resize((64 * scale, 40 * scale), Image.NEAREST).save(os.path.join(ios, name), optimize=True)
