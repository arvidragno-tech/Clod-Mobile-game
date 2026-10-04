"""9-slice UI frames and buttons. Drawn in art pixels and saved at 2x so
borders share the game's pixel density (1 art px = 2 UI units)."""
from __future__ import annotations

from . import palette as pal
from .lib import Canvas, clamp

SCALE = 3


def rgba(h, a=255):
    r, g, b = pal.hex_to_rgb(h)
    return (r, g, b, a)


def frame(fill, border, bracket, size=16, bracket_len=4, alpha=225, chamfer=2, rivet=None, tape=False, notch=False):
    cv = Canvas(size, size)
    for y in range(size):
        for x in range(size):
            # chamfered corners
            if min(x, size - 1 - x) + min(y, size - 1 - y) < chamfer:
                continue
            cv.set(x, y, rgba(fill, alpha))
    for y in range(size):
        for x in range(size):
            if cv.get(x, y) is None:
                continue
            edge = x == 0 or y == 0 or x == size - 1 or y == size - 1
            diag = min(x, size - 1 - x) + min(y, size - 1 - y) == chamfer
            if edge or diag:
                cv.set(x, y, rgba(border))
    # Inner top highlight line (bevel)
    for x in range(chamfer + 1, size - chamfer - 1):
        cv.set(x, 1, rgba(border, 120))
    # Corner brackets
    b = rgba(bracket)
    for (cx, cy, sx, sy) in ((0, 0, 1, 1), (size - 1, 0, -1, 1), (0, size - 1, 1, -1), (size - 1, size - 1, -1, -1)):
        for k in range(chamfer, chamfer + bracket_len):
            cv.set(cx + sx * k, cy, b)
            cv.set(cx, cy + sy * k, b)
        for k in range(chamfer + 1):
            cv.set(cx + sx * k, cy + sy * (chamfer - k), b)
    if rivet:
        cv.set(3, 3, rgba(rivet))
        cv.set(size - 4, 3, rgba(rivet))
    if tape:
        for y in range(0, 4):
            for x in range(size - 6, size - 1):
                if (x + y) % 5 != 0:
                    cv.set(x, y, (170, 140, 80, 235))
    if notch:
        for x in range(6, 9):
            cv.set(x, size - 1, None)
            cv.set(x, size - 2, rgba(bracket))
    return cv


def button(top, bottom, border, highlight, size=12, chamfer=2, pressed=False, hazard=False, outline_only=False):
    cv = Canvas(size, size)
    for y in range(size):
        for x in range(size):
            if min(x, size - 1 - x) + min(y, size - 1 - y) < chamfer:
                continue
            t = y / (size - 1)
            r1, g1, b1 = pal.hex_to_rgb(top)
            r2, g2, b2 = pal.hex_to_rgb(bottom)
            c = (int(r1 + (r2 - r1) * t), int(g1 + (g2 - g1) * t), int(b1 + (b2 - b1) * t), 235 if outline_only else 255)
            if outline_only:
                c = (c[0], c[1], c[2], 170)
            cv.set(x, y, c)
    for y in range(size):
        for x in range(size):
            if cv.get(x, y) is None:
                continue
            edge = x == 0 or y == 0 or x == size - 1 or y == size - 1
            diag = min(x, size - 1 - x) + min(y, size - 1 - y) == chamfer
            if edge or diag:
                cv.set(x, y, rgba(border))
    hl = rgba(highlight)
    if not pressed:
        for x in range(chamfer + 1, size - chamfer - 1):
            cv.set(x, 1, hl)  # bevel highlight
        for x in range(chamfer, size - chamfer):
            cv.set(x, size - 2, rgba(border, 200))  # bottom shadow lip
    else:
        for x in range(chamfer + 1, size - chamfer - 1):
            cv.set(x, size - 2, hl)
    if hazard:
        for x in range(1, size - 1):
            c = (255, 180, 61, 255) if ((x // 2) % 2 == 0) else (30, 24, 14, 255)
            cv.set(x, size - 1, c) if chamfer <= x < size - chamfer else None
    return cv


PANELS = {
    # name: (fill, border, bracket, extras)
    "panel": ("121821", "2a3646", "566477", {}),
    "panel_accent": ("0f171d", "1a7d70", "2ee6c8", {}),
    "panel_danger": ("2a0e12", "8a2a2a", "ff4d4d", {}),
    "panel_card": ("1a2230", "2a3646", "3b4b60", {"bracket_len": 2}),
    "panel_hud": ("0b0e16", "2a3646", "3b4b60", {"bracket_len": 3, "alpha": 235}),
    "panel_toast": ("0b0e16", "1a7d70", "2ee6c8", {"alpha": 240}),
    "panel_bm": ("140a14", "5a1f42", "ff3d81", {"tape": True, "notch": True, "alpha": 235}),
    "panel_bm_card": ("1c0f1c", "3e1a33", "a8327a", {"bracket_len": 2}),
    "panel_green": ("0c1a12", "2a6a3a", "6dff8a", {}),
}

BUTTONS = {
    # name: states -> (top, bottom, border, highlight, opts)
    "btn": {"normal": ("232d3c", "1a2230", "3b4b60", "566477"), "hover": ("2a3646", "1d2633", "566477", "7c8796"),
            "pressed": ("12302c", "0f2420", "2ee6c8", "1a7d70"), "disabled": ("141a22", "121821", "2a3646", "1a2230")},
    "btn_accent": {"normal": ("5ff5dc", "1fb39b", "a8fff0", "c8fff6"), "hover": ("7ffbe6", "2ac9ae", "c8fff6", "e0fffa"),
                   "pressed": ("1a7d70", "136058", "2ee6c8", "2ee6c8"), "disabled": ("141a22", "121821", "2a3646", "1a2230")},
    "btn_brand": {"normal": ("ff6aa0", "c42a62", "ffb0cc", "ffc8dc"), "hover": ("ff85b3", "d63a72", "ffc8dc", "ffe0ec"),
                  "pressed": ("7a1f42", "5a1630", "ff3d81", "ff3d81"), "disabled": ("141a22", "121821", "2a3646", "1a2230")},
    "btn_danger": {"normal": ("6e1c1c", "4a1212", "ff4d4d", "a83a3a"), "hover": ("7e2424", "561616", "ff6a6a", "c04848"),
                   "pressed": ("ff4d4d", "c43a3a", "ffa0a0", "ff8080"), "disabled": ("141a22", "121821", "2a3646", "1a2230")},
    "btn_ghost": {"normal": ("0d1017", "0b0e16", "2a3646", "1a2230"), "hover": ("121821", "0d1017", "3b4b60", "2a3646"),
                  "pressed": ("1a2230", "121821", "1a7d70", "2ee6c8"), "disabled": ("0d1017", "0b0e16", "1a2230", "121821")},
    "btn_tool": {"normal": ("121821", "0d1017", "2a3646", "1a2230"), "hover": ("1a2230", "121821", "3b4b60", "2a3646"),
                 "pressed": ("12302c", "0d211e", "2ee6c8", "1a7d70"), "disabled": ("0b0e16", "0b0e16", "1a2230", "121821")},
    "btn_quick": {"normal": ("1a1610", "0f0d0a", "7a5a24", "3a2e18"), "hover": ("241e14", "14110c", "a87a2a", "4a3a1c"),
                  "pressed": ("5a4218", "3a2c12", "ffb43d", "ffb43d"), "disabled": ("0d0d0e", "0b0b0c", "2a2620", "1a1814")},
    "btn_bm": {"normal": ("3a1030", "220a1c", "a8327a", "5a1f42"), "hover": ("4a1440", "2a0c22", "ff3d81", "7a1f42"),
               "pressed": ("ff3d81", "a8327a", "ffb0cc", "ff85b3"), "disabled": ("140a14", "100810", "3e1a33", "1c0f1c")},
}


def generate():
    n = 0
    for name, (fill, border, bracket, extra) in PANELS.items():
        frame(fill, border, bracket, **extra).save(f"ui/frames/{name}.png", scale=SCALE)
        n += 1
    for name, states in BUTTONS.items():
        for state, (top, bottom, border, hl) in states.items():
            cv = button(top, bottom, border, hl, pressed=(state == "pressed"), hazard=(name == "btn_quick" and state != "disabled"),
                        outline_only=(name == "btn_ghost"))
            cv.save(f"ui/frames/{name}_{state}.png", scale=SCALE)
            n += 1
    for state, (body, edge, core) in {"normal": ("4c5868", "1b222c", "2ee6c8"), "hover": ("6c7a8c", "1b222c", "8ff5e4")}.items():
        grabber(body, edge, core).save(f"ui/frames/grabber_{state}.png", scale=SCALE)
        n += 1
    track(False).save("ui/frames/slider_track.png", scale=SCALE)
    track(True).save("ui/frames/slider_fill.png", scale=SCALE)
    print("ui frames:", n + 2)


def grabber(body, edge, core):
    """8x12 slider knob: bevelled metal with a cyan status LED."""
    cv = Canvas(8, 12)
    for y in range(12):
        for x in range(8):
            if (x in (0, 7) and y in (0, 11)):
                continue
            border = x in (0, 7) or y in (0, 11)
            cv.set(x, y, rgba(edge if border else body))
    for y in range(1, 11):
        cv.set(1, y, rgba("bcc6d2"))
    for x in range(2, 6):
        cv.set(x, 10, rgba("232a34"))
    cv.set(3, 4, rgba(core)); cv.set(4, 4, rgba(core))
    cv.set(3, 5, rgba(core)); cv.set(4, 5, rgba(core))
    for y in (7, 8):
        for x in (2, 5):
            cv.set(x, y, rgba("232a34"))
    return cv


def track(filled):
    """6x4 9-slice slider track; the filled part glows cyan."""
    cv = Canvas(6, 4)
    for y in range(4):
        for x in range(6):
            if filled:
                c = "2ee6c8" if y in (1, 2) else "1a7d70"
            else:
                c = "0d1017" if y in (1, 2) else "2a3646"
            cv.set(x, y, rgba(c))
    return cv
