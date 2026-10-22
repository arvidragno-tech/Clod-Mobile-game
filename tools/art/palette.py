"""Palette system for UNDERCITY: RIPPER.

All art is built from hue-shifted 8-step ramps: shadows rotate toward cool
blue/violet, highlights toward warm yellow, which is what gives pixel art
depth without flat colours. The same ramps are exported to
data/palettes.json so the game can recolour characters at runtime.
"""
from __future__ import annotations

import colorsys
import json
import os

SHADES = 8
COOL_HUE = 0.70   # blue-violet
WARM_HUE = 0.13   # warm yellow


def hex_to_rgb(h: str) -> tuple[int, int, int]:
    h = h.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def rgb_to_hex(c) -> str:
    return "%02x%02x%02x" % (int(c[0]), int(c[1]), int(c[2]))


def _toward(h: float, target: float, amount: float) -> float:
    d = (target - h + 0.5) % 1.0 - 0.5
    return (h + d * amount) % 1.0


def ramp(base_hex: str, hue_shift: float = 0.08, contrast: float = 1.0, sat_boost: float = 0.0) -> list[tuple[int, int, int]]:
    """8 shades, index 0 = darkest, 7 = lightest. base sits at index 4."""
    r, g, b = [x / 255.0 for x in hex_to_rgb(base_hex)]
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    out = []
    for i in range(SHADES):
        t = (i - 4) / 4.0  # -1 .. 0.75
        if t < 0:
            hh = _toward(h, COOL_HUE, -t * hue_shift * 2.5)
            vv = v * (1.0 + t * 0.78 * contrast)
            ss = min(1.0, s * (1.0 - t * 0.12) + sat_boost)
        else:
            hh = _toward(h, WARM_HUE, t * hue_shift * 2.0)
            vv = min(1.0, v + (1.0 - v) * t * 0.85 * contrast + t * 0.08)
            ss = max(0.0, s * (1.0 - t * 0.45) + sat_boost)
        rr, gg, bb = colorsys.hsv_to_rgb(hh, max(0.0, min(1.0, ss)), max(0.0, min(1.0, vv)))
        out.append((round(rr * 255), round(gg * 255), round(bb * 255)))
    return out


# --- Global scene palette (environment, UI) ---------------------------------
# Very dark blacks / dark blue / dark purple / steel, plus semantic accents.
ENV = {
    "void": "06070b",
    "night": "0b0e16",
    "navy": "121a2a",
    "steel": "2a3444",
    "steel_light": "566477",
    "purple": "1d1426",
    "concrete": "2b2d33",
    "rust": "5a3424",
}
ACCENT = {
    "cyan": "2ee6c8",      # technology / information
    "blue": "3a8cff",      # electric blue (experimental)
    "green": "6dff8a",     # stable / success / medical
    "amber": "ffb43d",     # warning
    "red": "ff4d4d",       # danger
    "magenta": "ff3d81",   # black market / experimental
    "white": "e8fff8",     # surgical light
}

# --- Character ramps -----------------------------------------------------------
SKIN_TONES = ["f1c9a5", "e2ad86", "c98e66", "a86c49", "8a5236", "6a3d24", "4b2a19"]
HAIR_COLORS = {
    "black": "1e1a20", "dark_brown": "3d2a20", "brown": "6b4429", "auburn": "7a3420",
    "blond": "c7a061", "gray": "8b8d92", "white": "d6d8de",
    "dye_cyan": "2a9ea0", "dye_magenta": "a8327a", "dye_green": "5b8f2b", "dye_blue": "34509e", "dye_red": "9e2a2a",
}
IRIS_COLORS = {"brown": "5a3a22", "dark": "2c2220", "hazel": "6e5a2c", "green": "3f6b3a", "blue": "3d6286", "gray": "6a7680"}
CLOTH = {
    "black": "24242c", "charcoal": "363a44", "navy": "1f2a44", "olive": "4a4f2e", "khaki": "6e6146",
    "brown": "5a3c28", "tan": "8c7050", "maroon": "5a1e28", "red": "8e2626", "teal": "1f4f52",
    "slate": "4a5668", "white": "c9cdd4", "gray": "70757e", "hivis": "c99a26", "purple": "3e2a52",
    "denim": "2f4566", "leather": "3a2a24", "green": "2f4a34", "drape": "2c4a4e",
    # v2 occupational palettes (restrained, mostly desaturated)
    "corp_white": "b9bfc8", "corp_gray": "5c626c", "cold_blue": "3a4c66", "gang_red": "6e1a1e",
    "dirty_orange": "8a4a1e", "work_brown": "4e3a2a", "work_blue": "26324a", "safety": "b88a1e",
    "scrub_green": "3e5a4a", "dirty_white": "a9a690", "bm_purple": "35223f", "dark_red": "4a1418",
    "military_olive": "434a30", "muted_red": "6a2c2a", "rubber": "1e2024", "bone": "c8bea4",
}
METALS = {
    "chrome": "8e9aa8",      # tier 1-2 civilian/professional
    "gunmetal": "4f5864",    # tier 3 military
    "ceramic": "c8ccd2",     # tier 4 experimental
    "brass": "8a6e3c",       # cheap / improvised
    "blackened": "2e3138",   # black-market
}
GLOWS = {k: ACCENT[k] for k in ("cyan", "blue", "green", "amber", "red", "magenta")}
# Fixed ramp (index 7): outline, eye white, pupil, highlight, blood, ink, lens, rim light
FIXED = ["0b0a10", "d9dee4", "15131a", "f6f8fb", "7c0f1e", "1c2534", "a9e9ff", "3b9da0"]

RAMP_SKIN, RAMP_HAIR, RAMP_CLOTH_A, RAMP_CLOTH_B, RAMP_METAL, RAMP_GLOW, RAMP_IRIS, RAMP_FIXED = range(8)
# v2 character ramps (encoding R = ramp * 16 allows up to 16 ramps):
RAMP_CLOTH_C, RAMP_LEATHER, RAMP_GRIME, RAMP_BLOOD, RAMP_DRAPE, RAMP_IODINE = range(8, 14)
# Fixed material ramps shared by every character (not recoloured).
MATERIALS = {
    "leather": "3b2a24",   # worn dark leather, warm
    "grime": "4a3f2c",     # dirt, grease, oil stains
    "blood": "6e1018",     # dried to fresh blood
    "drape": "2f6b66",     # sterile surgical drape, washed teal
    "iodine": "8a4a1c",    # skin prep wash, burnt amber
}


def glow_ramp(base_hex: str) -> list:
    """Emissive ramp: dark falloff to hot near-white core."""
    return ramp(base_hex, hue_shift=0.02, contrast=1.15, sat_boost=0.05)


def export_json(path: str) -> None:
    data = {
        "shades": SHADES,
        "skin": [[rgb_to_hex(c) for c in ramp(h, 0.06)] for h in SKIN_TONES],
        "hair": {k: [rgb_to_hex(c) for c in ramp(v, 0.09)] for k, v in HAIR_COLORS.items()},
        "iris": {k: [rgb_to_hex(c) for c in ramp(v, 0.05)] for k, v in IRIS_COLORS.items()},
        "cloth": {k: [rgb_to_hex(c) for c in ramp(v, 0.10)] for k, v in CLOTH.items()},
        "metal": {k: [rgb_to_hex(c) for c in ramp(v, 0.06, 1.1)] for k, v in METALS.items()},
        "glow": {k: [rgb_to_hex(c) for c in glow_ramp(v)] for k, v in GLOWS.items()},
        "fixed": FIXED,
        "material": {k: [rgb_to_hex(c) for c in ramp(v, 0.07, 1.05)] for k, v in MATERIALS.items()},
    }
    with open(path, "w") as f:
        json.dump(data, f, indent=1)
        f.write("\n")
    print("wrote", os.path.relpath(path))
