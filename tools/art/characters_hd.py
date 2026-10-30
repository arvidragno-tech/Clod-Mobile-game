"""Character art, HD: 288x336 portraits and 120x240 in-room bodies.

Parts are designed on the 1.5x grid (144x168 / 60x120, tools/art/hdc_*)
and rasterised at UPSCALE x that with an edge-directed pixel-art scaler
(EPX / Scale2x on the palette-indexed values, so ramps and shades stay
exact and the runtime still recolours every pixel): contours, ink lines,
cel-band edges and highlights come out as smooth hi-res curves instead of
doubled stair steps, and a hi-res finishing pass adds the fine work the
1.5x grid cannot hold (lit-edge rim pixels, catch-lights).

Builds every part (tools/art/hdc_face, hdc_hair, hdc_outfit, hdc_gear,
hdc_body), packs each slot into an atlas under
assets/sprites/characters_hd/ and writes data/character_parts.json with
the same layout as v2 (so CharacterArt composes and recolours HD parts the
same way): {sizes, layer_order, atlases, parts: {view: {slot: {id: [ax, ay,
w, h, ox, oy]}}}}.
"""
from __future__ import annotations

import json
import os
import random

import numpy as np
from PIL import Image

from .lib import ROOT
from .hdc_core import bbox, ink_outline, FX, F_OUT, F_HI, SK, HR
from . import hdc_face as face, hdc_hair as hair, hdc_outfit as outfit, hdc_gear as gear, hdc_body as body

PORTRAIT_ORDER = ["hair_back", "body", "outfit", "head", "age", "nose", "mouth", "brows", "eyes", "facial_hair",
                  "scar", "tattoo", "makeup", "cyber_low", "piercing", "hair", "cyber", "accessory"]
BODY_ORDER = ["body", "outfit", "cyber", "hair", "acc"]
# Slots whose parts get the ink contour (the reference look: every shape
# that reads as its own form is closed by a near-black line).
OUTLINED = {"portrait": ("hair_back", "body", "outfit", "head", "cyber", "cyber_low", "hair", "accessory"),
            "body": ("body", "outfit", "cyber", "hair", "acc")}
# Marks drawn flat on the skin: no contour.
FLAT_PARTS = {"skin_seam", "serial_marks", "cheek_leds", "temple_ports", "cigarette"}
OUT_DIR = os.path.join(ROOT, "assets", "sprites", "characters_hd")
UPSCALE = 2


class Part:
    """A finished part at the output resolution: codes[y, x] = ramp*8 +
    shade + 1 (0 = transparent)."""

    def __init__(self, codes: np.ndarray):
        self.codes = codes
        self.h, self.w = codes.shape


def _codes(cv) -> np.ndarray:
    out = np.zeros((cv.h, cv.w), dtype=np.int16)
    for y, row in enumerate(cv.px):
        for x, c in enumerate(row):
            if c is not None:
                out[y, x] = c[0] * 8 + c[1] + 1
    return out


def epx(a: np.ndarray) -> np.ndarray:
    """Scale2x / EPX: each pixel becomes 2x2; a corner takes a neighbour's
    value where two neighbours agree across it (smooth diagonals), so no new
    values are ever invented."""
    p = np.pad(a, 1, mode="edge")
    P = p[1:-1, 1:-1]
    A, D = p[:-2, 1:-1], p[2:, 1:-1]   # up, down
    C, B = p[1:-1, :-2], p[1:-1, 2:]   # left, right
    o = np.empty((a.shape[0] * 2, a.shape[1] * 2), dtype=a.dtype)
    o[0::2, 0::2] = np.where((C == A) & (C != D) & (A != B), A, P)
    o[0::2, 1::2] = np.where((A == B) & (A != C) & (B != D), B, P)
    o[1::2, 0::2] = np.where((D == C) & (D != B) & (C != A), C, P)
    o[1::2, 1::2] = np.where((B == D) & (B != A) & (D != C), D, P)
    return o


def finish(codes: np.ndarray, slot: str) -> np.ndarray:
    """Hi-res finishing: a one-pixel lit rim inside the ink contour on the
    upper-left (key light) side of skin and hair, the fine edge light the
    1.5x grid could only fake with whole pixels."""
    if slot not in ("head", "hair", "hair_back", "body"):
        return codes
    ink = FX * 8 + F_OUT + 1
    ramp = (codes - 1) // 8
    shade = (codes - 1) % 8
    solid = (codes > 0) & (codes != ink)
    up = np.zeros_like(solid)
    up[1:] = (codes[:-1] == ink) | (codes[:-1] == 0)
    left = np.zeros_like(solid)
    left[:, 1:] = (codes[:, :-1] == ink) | (codes[:, :-1] == 0)
    rim = solid & (up | left) & ((ramp == SK) | (ramp == HR)) & (shade >= 2) & (shade < 6)
    out = codes.copy()
    out[rim] = (ramp[rim] * 8 + np.minimum(shade[rim] + 1, 6) + 1).astype(codes.dtype)
    return out


def build_parts():
    parts = {"portrait": {}, "body": {}}

    def put(view, slot, pid, fn, *args):
        cv = face.portrait() if view == "portrait" else body.body_canvas()
        fn(cv, *args)
        if slot in OUTLINED.get(view, ()) and pid not in FLAT_PARTS:
            ink_outline(cv)
        codes = _codes(cv)
        for _ in range(UPSCALE // 2):
            codes = epx(codes)
        parts[view].setdefault(slot, {})[pid] = Part(finish(codes, slot))

    # --- portrait ---
    for build in outfit.BUILDS:
        put("portrait", "body", build, outfit.draw_bust_base, build)
        for o in outfit.OUTFITS:
            put("portrait", "outfit", f"{o}_{build}", outfit.draw_outfit, o, build, random.Random(len(o) * 7 + len(build)))
    for shape in face.FACES:
        put("portrait", "head", shape, face.draw_head, shape)
        for kind in face.FACIAL_HAIR:
            put("portrait", "facial_hair", f"{kind}_{shape}", face.draw_facial_hair, kind, shape, random.Random(len(kind) + len(shape)))
    for age in face.AGES:
        put("portrait", "age", age, face.draw_age, age)
    for kind in face.NOSES:
        put("portrait", "nose", kind, face.draw_nose, kind)
    for expr in face.EXPRESSIONS:
        put("portrait", "mouth", expr, face.draw_mouth, expr)
        put("portrait", "brows", f"{expr}_thin", face.draw_brows, expr, False)
        put("portrait", "brows", f"{expr}_heavy", face.draw_brows, expr, True)
        for gaze in face.GAZES:
            put("portrait", "eyes", f"{expr}_{gaze}", face.draw_eyes, expr, gaze)
    for kind in face.SCARS:
        put("portrait", "scar", kind, face.draw_scar, kind)
    for kind in face.TATTOOS:
        put("portrait", "tattoo", kind, face.draw_tattoo, kind)
    for kind in face.MAKEUP:
        put("portrait", "makeup", kind, face.draw_makeup, kind)
    for kind in face.PIERCINGS:
        put("portrait", "piercing", kind, face.draw_piercing, kind)
    for kind in gear.CYBER:
        put("portrait", "cyber_low" if kind in gear.CYBER_LOW else "cyber", kind, gear.draw_cyber, kind, random.Random(len(kind)))
    for style in hair.HAIR:
        put("portrait", "hair", style, hair.draw_hair, style, random.Random(len(style) * 13))
        if style in ("long", "tied", "locs", "braids"):
            put("portrait", "hair_back", style, hair.draw_hair_back, style, random.Random(len(style)))
    for kind in gear.ACCESSORIES:
        put("portrait", "accessory", kind, gear.draw_accessory, kind, random.Random(len(kind) * 3))
    # --- body ---
    for build in body.BUILDS:
        for posture in body.POSTURES:
            key = f"{build}_{posture}"
            put("body", "body", key, body.draw_body_base, build, posture)
            for o in body.OUTFITS:
                put("body", "outfit", f"{o}_{key}", body.draw_body_outfit, o, build, posture, random.Random(len(o) + len(key)))
            for kind in body.BODY_CYBER:
                put("body", "cyber", f"{kind}_{key}", body.draw_body_cyber, kind, build, posture)
            for style in body.BODY_HAIR:
                put("body", "hair", f"{style}_{key}", body.draw_body_hair, style, build, posture, random.Random(len(style)))
            for kind in body.BODY_ACC:
                put("body", "acc", f"{kind}_{key}", body.draw_body_acc, kind, build, posture)
    return parts


def generate():
    parts = build_parts()
    os.makedirs(OUT_DIR, exist_ok=True)
    pc, bc = face.portrait(), body.body_canvas()
    k = UPSCALE
    manifest = {"version": 4, "sizes": {"portrait": [pc.w * k, pc.h * k], "body": [bc.w * k, bc.h * k]},
                "layer_order": {"portrait": PORTRAIT_ORDER, "body": BODY_ORDER},
                "eyes": {"y": face.HEY * k + k // 2, "x": [x * k + k // 2 for x in face.HEX]}, "atlases": {}, "parts": {}}
    total = 0
    for view, slots in parts.items():
        manifest["parts"][view] = {}
        for slot, items in slots.items():
            boxes = []
            for pid, part in items.items():
                ys, xs = np.nonzero(part.codes)
                if len(xs):
                    bb = (int(xs.min()), int(ys.min()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1))
                    boxes.append((pid, part, bb))
            # Shelf pack, max width 2048.
            x = y = row_h = 0
            placed = {}
            width = 2048
            for pid, cv, (bx, by, bw, bh) in sorted(boxes, key=lambda t: -t[2][3]):
                if x + bw > width:
                    x, y, row_h = 0, y + row_h + 1, 0
                placed[pid] = (x, y, bw, bh, bx, by)
                x += bw + 1
                row_h = max(row_h, bh)
            height = max(1, y + row_h)
            buf = np.zeros((height, width, 4), dtype=np.uint8)
            for pid, part, (bx, by, bw, bh) in boxes:
                ax, ay = placed[pid][0], placed[pid][1]
                c = part.codes[by:by + bh, bx:bx + bw].astype(np.int32)
                on = c > 0
                v = c - 1
                tile = buf[ay:ay + bh, ax:ax + bw]
                tile[..., 0] = np.where(on, (v // 8) * 16, tile[..., 0])
                tile[..., 1] = np.where(on, (v % 8) * 32, tile[..., 1])
                tile[..., 3] = np.where(on, 255, tile[..., 3])
            atlas = Image.fromarray(buf, "RGBA")
            name = f"{view}_{slot}.png"
            atlas.save(os.path.join(OUT_DIR, name), optimize=True)
            manifest["atlases"][f"{view}/{slot}"] = "res://assets/sprites/characters_hd/" + name
            manifest["parts"][view][slot] = {pid: list(v) for pid, v in placed.items()}
            total += len(placed)
    path = os.path.join(ROOT, "data", "character_parts.json")
    with open(path, "w") as fh:
        json.dump(manifest, fh, separators=(",", ":"))
        fh.write("\n")
    print("character parts HD:", total, "in", len(manifest["atlases"]), "atlases")
    return parts
