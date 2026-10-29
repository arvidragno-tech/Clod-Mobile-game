"""Character art, HD: 144x168 portraits and 60x120 in-room bodies.

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

from PIL import Image

from .lib import ROOT
from .hdc_core import bbox, ink_outline
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


def build_parts():
    parts = {"portrait": {}, "body": {}}

    def put(view, slot, pid, fn, *args):
        cv = face.portrait() if view == "portrait" else body.body_canvas()
        fn(cv, *args)
        if slot in OUTLINED.get(view, ()) and pid not in FLAT_PARTS:
            ink_outline(cv)
        parts[view].setdefault(slot, {})[pid] = cv

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
    manifest = {"version": 3, "sizes": {"portrait": [pc.w, pc.h], "body": [bc.w, bc.h]},
                "layer_order": {"portrait": PORTRAIT_ORDER, "body": BODY_ORDER},
                "eyes": {"y": face.HEY, "x": list(face.HEX)}, "atlases": {}, "parts": {}}
    total = 0
    for view, slots in parts.items():
        manifest["parts"][view] = {}
        for slot, items in slots.items():
            boxes = []
            for pid, cv in items.items():
                bb = bbox(cv)
                if bb:
                    boxes.append((pid, cv, bb))
            # Shelf pack, max width 1024.
            x = y = row_h = 0
            placed = {}
            width = 1024
            for pid, cv, (bx, by, bw, bh) in sorted(boxes, key=lambda t: -t[2][3]):
                if x + bw > width:
                    x, y, row_h = 0, y + row_h + 1, 0
                placed[pid] = (x, y, bw, bh, bx, by)
                x += bw + 1
                row_h = max(row_h, bh)
            height = max(1, y + row_h)
            atlas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
            px = atlas.load()
            for pid, cv, (bx, by, bw, bh) in boxes:
                ax, ay = placed[pid][0], placed[pid][1]
                for yy in range(bh):
                    row = cv.px[by + yy]
                    for xx in range(bw):
                        c = row[bx + xx]
                        if c is not None:
                            px[ax + xx, ay + yy] = (c[0] * 16, c[1] * 32, 0, 255)
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
