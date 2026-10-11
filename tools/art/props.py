"""Set dressing and environmental storytelling for the clinic tiers:
power systems, ventilation, graffiti, warning labels, medical waste, blood,
discarded implants, tool carts, cables, drains, hidden compartments and
field repairs. Each prop can register animation anchors (FX) that the game
animates at runtime (scripts/components/clinic_view.gd reads
data/clinic_fx.json): blinking LEDs, monitor scanlines, vent fans, steam,
sparks and drips. Coordinates are art pixels of the 180x250 backdrop.
"""
from __future__ import annotations

import math

from . import palette as pal
from .lib import bayer

FX: list[dict] = []


def reset_fx():
    FX.clear()


def fx(kind, x, y, w=1, h=1, color="cyan", **extra):
    entry = {"type": kind, "x": int(x), "y": int(y), "w": int(w), "h": int(h), "color": color}
    entry.update(extra)
    FX.append(entry)


def _env():
    # Late import: environments imports this module.
    from . import environments as env
    return env


def power_box(sc, x, y, tier, sparks=False):
    """Breaker box with conduit to the ceiling, status LEDs and an HV label."""
    env = _env()
    a = sc.albedo
    a.vline(x + 4, 12, y, env.C(env.MAT["dark"], 2))
    a.vline(x + 5, 12, y, env.C(env.MAT["steel"], 3))
    a.vline(x + 14, 12, y, env.C(env.MAT["dark"], 1))
    m = env.MAT["rust"] if tier == 0 else env.MAT["panel"]
    a.shaded_poly([(x, y), (x + 20, y), (x + 20, y + 16), (x, y + 16)], m, 4.2, 2.2, 1, 1)
    a.rect(x + 2, y + 2, 16, 12, env.C(env.MAT["dark"], 1))
    for k in range(4):  # breaker switches
        a.rect(x + 3 + k * 4, y + 4, 2, 5, env.C(env.MAT["steel"], 5 if k != 2 else 2))
    for k, col in enumerate(("green", "green", "amber")):
        sc.emissive.set(x + 4 + k * 5, y + 11, env.GLOW(col, 6))
        fx("led", x + 4 + k * 5, y + 11, color=col, rate=0.4 + k * 0.37)
    warning_label(sc, x + 4, y + 18, "HV")
    if sparks:
        # Exposed, half-repaired wire hanging out of the box.
        a.polyline([(x + 18, y + 14), (x + 22, y + 22), (x + 21, y + 28)], (12, 12, 16, 255))
        a.set(x + 21, y + 29, env.C(env.MAT["plastic"], 6))
        fx("spark", x + 21, y + 29, color="amber")


def warning_label(sc, x, y, label):
    """Hazard-striped plate with a 3x5 label (albedo, not emissive)."""
    env = _env()
    a = sc.albedo
    w = env.text_width(label) + 4
    a.rect(x - 1, y - 1, w + 2, 11, (16, 14, 12, 255))  # dark mount
    a.rect(x, y, w, 9, (178, 142, 44, 255))
    for xx in range(x, x + w):  # hazard stripes top and bottom only
        if (xx // 2) % 2 == 0:
            a.set(xx, y, (30, 26, 18, 255))
            a.set(xx, y + 8, (30, 26, 18, 255))
    env.text(a, x + 2, y + 2, label, (22, 18, 12, 255))


def vent(sc, x, y, w=20, h=12, tier=0):
    """Wall vent with louvres; the fan behind it spins at runtime."""
    env = _env()
    a = sc.albedo
    a.shaded_poly([(x, y), (x + w, y), (x + w, y + h), (x, y + h)], env.MAT["steel"] if tier >= 2 else env.MAT["rust"], 4.5, 2.4, 1, 1)
    a.rect(x + 2, y + 2, w - 4, h - 4, (10, 11, 14, 255))
    fx("fan", x + 2, y + 2, w - 4, h - 4, color="dark")
    for yy in range(y + 3, y + h - 2, 2):
        a.hline(x + 2, x + w - 3, yy, env.C(env.MAT["steel"], 2))
    if tier <= 1:  # grime streak under the vent
        for yy in range(y + h, y + h + 18):
            for xx in range(x + 4, x + w - 4):
                if bayer(xx, yy) < 0.35 * (1 - (yy - y - h) / 18):
                    c = a.px[yy][xx]
                    if c:
                        a.px[yy][xx] = (int(c[0] * 0.75), int(c[1] * 0.75), int(c[2] * 0.72), 255)


def graffiti(sc, x, y, tag, color, rng):
    """Old spray tag: 2x-scaled letters, overspray and drips (faded paint)."""
    env = _env()
    a = sc.albedo
    r, g, b = pal.hex_to_rgb(pal.ACCENT[color])
    paint = (int(r * 0.45), int(g * 0.45), int(b * 0.45), 255)
    dark = (int(r * 0.25), int(g * 0.25), int(b * 0.25), 255)
    cx = x
    for ch in tag:
        glyph = env.FONT3x5.get(ch, env.FONT3x5[" "])
        for gy, row in enumerate(glyph):
            for gx, bit in enumerate(row):
                if bit == "1":
                    for dy in (0, 1):
                        for dx in (0, 1):
                            a.set(cx + gx * 2 + dx, y + gy * 2 + dy, paint)
                    a.set(cx + gx * 2 + 2, y + gy * 2 + 2, dark)
        cx += (len(glyph[0]) + 1) * 2
    width = cx - x
    for _ in range(width // 4):  # drips
        dx = x + rng.randrange(width)
        for k in range(rng.randrange(2, 7)):
            a.set(dx, y + 10 + k, paint if k < 3 else dark)
    for _ in range(width):  # overspray
        if rng.random() < 0.6:
            a.set(x + rng.randrange(-2, width + 2), y + rng.randrange(-3, 13), dark)


def waste_bin(sc, x, tier):
    """Biohazard bin; overflowing in the cheap clinics."""
    env = _env()
    a = sc.albedo
    col = env.R("b8902c", 0.06) if tier < 3 else env.R("8e2626", 0.06)
    a.cylinder(x, env.FLOOR_Y - 13, 11, 13, col, 1.2, 5)
    a.rect(x - 1, env.FLOOR_Y - 14, 13, 2, env.C(col, 2))
    # Biohazard mark (tiny trefoil)
    for px, py in ((x + 5, env.FLOOR_Y - 9), (x + 4, env.FLOOR_Y - 7), (x + 6, env.FLOOR_Y - 7), (x + 5, env.FLOOR_Y - 8)):
        a.set(px, py, (20, 16, 12, 255))
    if tier <= 1:
        for k, (dx, dy) in enumerate(((2, -16), (6, -17), (9, -15))):
            a.set(x + dx, env.FLOOR_Y + dy, env.C(env.MAT["white"], 4 + k % 2))  # gauze
        a.set(x + 4, env.FLOOR_Y - 16, (120, 20, 32, 255))


def blood(sc, x, y, w, h, rng, fresh=False):
    """Dithered stain (old = brown-red, fresh = bright)."""
    a = sc.albedo
    base = (92, 14, 24, 255) if fresh else (54, 16, 20, 255)
    edge = (70, 20, 24, 255) if fresh else (44, 20, 22, 255)
    for yy in range(y - h, y + h + 1):
        for xx in range(x - w, x + w + 1):
            d = ((xx - x) / max(w, 1)) ** 2 + ((yy - y) / max(h, 1)) ** 2
            if d <= 1.0 and (d < 0.55 or bayer(xx, yy) < 0.5):
                a.set(xx, yy, base if d < 0.55 else edge)
    for _ in range(w):  # satellite droplets
        a.set(x + rng.randrange(-w * 2, w * 2), y + rng.randrange(-h * 2, h * 2 + 1), edge)


def discarded_implant(sc, x, y, rng, glow=False):
    """Pulled chrome lying around: a capsule body and a (dead) LED."""
    env = _env()
    a = sc.albedo
    a.rect(x, y, 4, 2, env.C(env.MAT["steel"], 5))
    a.set(x, y + 1, env.C(env.MAT["steel"], 3))
    a.set(x + 4, y + 1, (14, 14, 18, 255))  # torn wire
    a.set(x + 5, y + 2, (14, 14, 18, 255))
    if glow:
        sc.emissive.set(x + 1, y, env.GLOW("red", 3))
        fx("led", x + 1, y, color="red", rate=0.15)


def tool_cart(sc, x, y, tier):
    """Rolling instrument cart in the foreground with laid-out tools."""
    env = _env()
    a = sc.albedo
    m = env.MAT["steel"]
    a.shaded_poly([(x, y), (x + 26, y), (x + 26, y + 3), (x, y + 3)], m, 5.5, 2.5, 1, 1)
    for lx in (x + 2, x + 23):
        a.vline(lx, y + 3, y + 22, env.C(m, 3))
        a.set(lx, y + 23, env.C(env.MAT["dark"], 1))
        a.set(lx + 1, y + 23, env.C(env.MAT["dark"], 2))
    a.hline(x + 2, x + 23, y + 14, env.C(m, 4))  # lower shelf
    a.rect(x + 5, y + 11, 6, 3, env.C(env.MAT["cloth"], 4))  # folded drape
    for k in range(4):  # instruments with a glint
        tx = x + 3 + k * 6
        a.line(tx, y - 1, tx + 4, y - 2, env.C(m, 6))
        a.set(tx + 4, y - 2, env.C(env.MAT["white"], 7))
    if tier >= 3:
        sc.emissive.set(x + 13, y + 1, env.GLOW("cyan", 6))
        fx("led", x + 13, y + 1, color="cyan", rate=0.8)
    else:
        a.rect(x + 16, y - 3, 4, 3, env.C(env.MAT["plastic"], 4))  # tape roll


def floor_cables(sc, points, color=(10, 10, 14, 255)):
    sc.albedo.polyline(points, color)
    sc.albedo.polyline([(px, py + 1) for px, py in points], (26, 26, 32, 255))


def drain(sc, x, y):
    env = _env()
    a = sc.albedo
    a.rect(x, y, 14, 5, env.C(env.MAT["dark"], 2))
    for xx in range(x + 1, x + 13, 2):
        a.vline(xx, y + 1, y + 3, (8, 8, 10, 255))
    fx("drip", x + 7, 12, h=y - 12, color="cyan")


def hidden_compartment(sc, x, y, kind="panel"):
    """Smuggler's stash: a wall panel left ajar or a floor hatch, magenta
    light leaking out (the black market is never far away)."""
    env = _env()
    a = sc.albedo
    if kind == "panel":
        a.rect(x, y, 14, 18, (8, 6, 10, 255))
        for yy in range(y + 10, y + 17):  # faint glow pooled at the bottom
            for xx in range(x + 1, x + 4):
                if bayer(xx, yy) < 0.25:
                    sc.emissive.set(xx, yy, env.GLOW("magenta", 1))
        a.shaded_poly([(x + 3, y - 1), (x + 17, y + 1), (x + 17, y + 19), (x + 3, y + 17)], env.MAT["panel"], 4.4, 2.2, 1, 1)
        sc.emissive.set(x + 2, y + 9, env.GLOW("magenta", 6))
        fx("led", x + 2, y + 9, color="magenta", rate=0.25)
        sc.light(x + 6, y + 9, pal.ACCENT["magenta"], 16, 0.3)
    else:
        a.rect(x - 1, y - 1, 24, 8, env.C(env.MAT["steel"], 4))  # frame
        a.rect(x, y, 22, 6, env.C(env.MAT["dark"], 3))
        a.hline(x, x + 21, y, env.C(env.MAT["steel"], 5))
        for xx in range(x + 3, x + 20, 4):  # vent slots with a magenta leak
            a.set(xx, y + 3, (6, 4, 8, 255))
            sc.emissive.set(xx, y + 3, env.GLOW("magenta", 2))
        sc.light(x + 11, y + 2, pal.ACCENT["magenta"], 14, 0.25)
        a.set(x + 20, y + 3, env.C(env.MAT["steel"], 6))  # pull ring


def tape(sc, x, y, w=5, vertical=False):
    env = _env()
    col = env.C(env.R("8a8a7a", 0.04), 4)
    if vertical:
        sc.albedo.rect(x, y, 2, w, col)
    else:
        sc.albedo.rect(x, y, w, 2, col)


def ecg_cart(sc, x, tier):
    """Diagnostic cart: vitals monitor on a pole with a cable to the bed."""
    env = _env()
    a = sc.albedo
    a.vline(x + 7, 118, env.FLOOR_Y - 2, env.C(env.MAT["steel"], 4))
    a.hline(x + 2, x + 12, env.FLOOR_Y - 1, env.C(env.MAT["steel"], 3))
    a.shaded_poly([(x, 104), (x + 15, 104), (x + 15, 118), (x, 118)], env.MAT["dark"], 4.5, 2, 1, 1)
    for yy in range(106, 116):
        for xx in range(x + 2, x + 13):
            sc.emissive.set(xx, yy, (6, 18, 14, 255))
    fx("ecg", x + 2, 106, 11, 10, color="green")
    sc.light(x + 7, 111, pal.ACCENT["green"], 26, 0.35)


def steam(x, y):
    fx("steam", x, y, color="white")


def box_stack(sc, x, y, rng, spill=True):
    """Foreground cardboard boxes; the top one spills salvaged chrome."""
    env = _env()
    a = sc.albedo
    card = env.R("6e5638", 0.07)
    a.shaded_poly([(x, y + 12), (x + 26, y + 12), (x + 26, y + 30), (x, y + 30)], card, 4.4, 2.4, 1, 1)
    a.shaded_poly([(x + 4, y), (x + 22, y), (x + 22, y + 12), (x + 4, y + 12)], card, 4.8, 2.4, 1, 1)
    a.hline(x + 4, x + 21, y + 1, env.C(card, 6))
    a.rect(x + 10, y + 14, 6, 3, env.C(env.R("c8c8b8", 0.03), 4))  # shipping label
    a.vline(x + 13, y, y + 11, env.C(env.R("8a8a7a", 0.04), 4))  # tape seam
    if spill:
        for k in range(4):
            discarded_implant(sc, x + 6 + k * 4, y - 2 - (k % 2), rng, glow=(k == 2))


def equipment_case(sc, x, y, color="cyan"):
    """Hard-shell transport case for chrome (cleaner clinics)."""
    env = _env()
    a = sc.albedo
    a.shaded_poly([(x, y), (x + 30, y), (x + 30, y + 16), (x, y + 16)], env.MAT["dark"], 4.6, 2.4, 1, 1)
    a.hline(x, x + 29, y + 5, env.C(env.MAT["steel"], 3))
    a.rect(x + 12, y + 3, 6, 4, env.C(env.MAT["steel"], 5))  # latch
    sc.emissive.rect(x + 3, y + 10, 5, 2, env.GLOW(color, 5))
    fx("led", x + 3, y + 10, 5, 1, color=color, rate=0.5)


def desk(sc, x, w, tier, rng):
    """Computer desk: keyboard, monitors (CRT -> flat -> holo), clutter."""
    env = _env()
    a = sc.albedo
    top = env.FLOOR_Y - 26
    m = env.MAT["wood"] if tier <= 1 else env.MAT["dark"]
    a.shaded_poly([(x, top), (x + w, top), (x + w, top + 4), (x, top + 4)], m, 4.6, 2.4, 1, 1)
    for lx in (x + 2, x + w - 4):
        a.rect(lx, top + 4, 2, env.FLOOR_Y - top - 4, env.C(m, 2))
    a.rect(x + 6, top - 2, 20, 2, env.C(env.MAT["dark"], 3))  # keyboard
    for k in range(6):
        a.set(x + 8 + k * 3, top - 2, env.C(env.MAT["steel"], 4))
    if tier <= 1:
        env.monitor(sc, x + w - 30, top - 22, 24, 20, "crt", "green", stand=False)
        tape(sc, x + w - 29, top - 21, 4)
        a.rect(x + 30, top - 5, 6, 5, env.C(env.R("6a3c26"), 4))  # cup
    elif tier <= 3:
        env.monitor(sc, x + 4, top - 24, 26, 18, "flat", "cyan", stand=False)
        env.monitor(sc, x + 34, top - 26, 28, 20, "flat", "green" if tier == 2 else "cyan", stand=False)
    else:
        env.holo(sc, x + 8, top - 40, w - 16, 34, "blue" if tier == 4 else "cyan")
    # Cable bundle down to the floor
    a.polyline([(x + w - 6, top + 4), (x + w - 4, env.FLOOR_Y - 2), (x + w + 6, env.FLOOR_Y + 4)], (12, 12, 16, 255))


def server_rack(sc, x, h=70):
    """Rack of blinking compute (the clinic's diagnostics brain)."""
    env = _env()
    a = sc.albedo
    y = env.FLOOR_Y - h
    a.shaded_poly([(x, y), (x + 18, y), (x + 18, env.FLOOR_Y), (x, env.FLOOR_Y)], env.MAT["dark"], 4.2, 2.2, 1, 1)
    for k, yy in enumerate(range(y + 4, env.FLOOR_Y - 4, 6)):
        a.hline(x + 2, x + 15, yy, env.C(env.MAT["steel"], 3))
        col = ["green", "cyan", "amber", "green"][k % 4]
        sc.emissive.set(x + 3, yy + 2, env.GLOW(col, 6))
        fx("led", x + 3, yy + 2, color=col, rate=0.6 + 0.37 * k)
        for b in range(3):
            sc.emissive.set(x + 7 + b * 2, yy + 2, env.GLOW("cyan", 2))
    sc.light(x + 9, y + h / 2, pal.ACCENT["cyan"], 30, 0.3)


def workbench(sc, x, w, rng):
    """Cheap clinics: a bench covered in salvaged chrome being rebuilt."""
    env = _env()
    a = sc.albedo
    top = env.FLOOR_Y - 22
    a.shaded_poly([(x, top), (x + w, top), (x + w, top + 4), (x, top + 4)], env.MAT["wood"], 4.4, 2.4, 1, 1)
    for lx in (x + 3, x + w - 5):
        a.line(lx, top + 4, lx - 2, env.FLOOR_Y, env.C(env.MAT["wood"], 2))
    for k in range(4):
        discarded_implant(sc, x + 6 + k * 8, top - 2, rng, glow=(k == 1))
    a.rect(x + w - 14, top - 8, 8, 8, env.C(env.MAT["steel"], 3))  # vise
    sc.light(x + w / 2, top - 10, "ffcf8a", 26, 0.35)
