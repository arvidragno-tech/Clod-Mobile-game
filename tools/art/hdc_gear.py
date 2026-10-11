"""HD portrait cyberware and accessories."""
from __future__ import annotations

import random

from .hdc_core import (S, SK, HR, CA, CB, MT, GL, FX, CC, LT, GR, BL, F_OUT, F_EYEW, F_HI, F_INK, F_LENS,
                       HDCanvas, grid, P, HL, VL, LN, H, plate, screw, stitch_h)
from .hdc_face import CX, HCX, HEX, HEY, EYE_X, EYE_Y, PH, head_mask

HPH = int(round(PH * S))

CYBER = ["optic", "twin_optics", "visor", "jaw_plate", "face_half", "temple_ports", "neck_ports", "skull_plate",
         "cheek_leds", "skin_seam", "mouth_grille", "ear_module", "forehead_chip", "shoulder_chrome",
         "spine_cables", "organic_growth", "serial_marks", "patched_implant"]
CYBER_LOW = {"temple_ports", "skull_plate", "cheek_leds", "skin_seam", "forehead_chip", "serial_marks",
             "organic_growth", "patched_implant", "neck_ports", "jaw_plate", "face_half", "mouth_grille"}


def _lens(c, X, Y, r, glow_shade=5):
    """A round optic at HD centre (X, Y), radius r HD px: housing ring lit
    top-left, black bezel, glowing glass with a hot core and a glint."""
    for dy in range(-r - 2, r + 3):
        for dx in range(-r - 2, r + 3):
            d = (dx * dx + dy * dy) ** 0.5
            if d <= r + 1.6:
                P(c, X + dx, Y + dy, MT, 6 if (dx < 0 and dy < 0) else (2 if dx > 0 else 3))
            if d <= r + 0.4:
                P(c, X + dx, Y + dy, FX, F_OUT)
            if d <= r - 0.6:
                P(c, X + dx, Y + dy, GL, glow_shade - (d > r - 1.8) - (d > r - 1.0))
    P(c, X, Y, GL, 7)
    P(c, X + 1, Y, GL, 6)
    P(c, X - 1, Y - 1 - (r > 3), FX, F_HI)
    # Concentric aperture ring.
    if r >= 4:
        for dx in (-2, 2):
            P(c, X + dx, Y, GL, glow_shade - 2)
        for dy in (-2, 2):
            P(c, X, Y + dy, GL, glow_shade - 2)


def draw_cyber(c: HDCanvas, kind: str, rng):
    ex0, ex1 = HEX
    if kind == "optic":
        _lens(c, ex1, HEY, 5)
        for k in range(5):  # socket plate screws
            P(c, ex1 + 7, HEY - 4 + k * 2, MT, 6 - (k % 2) * 3)
        HL(c, ex1 - 6, ex1 + 6, HEY - 7, MT, 3)
        HL(c, ex1 - 5, ex1 + 5, HEY - 8, MT, 5)
        LN(c, ex1 + 6, HEY + 6, ex1 + 9, HEY + 10, MT, 2)  # seam to the cheek
    elif kind == "twin_optics":
        for ex in HEX:
            _lens(c, ex, HEY, 3, 4)
        HL(c, ex0 + 5, ex1 - 5, HEY - 1, MT, 4)  # bridge
        HL(c, ex0 + 5, ex1 - 5, HEY, MT, 2)
    elif kind == "visor":
        for X, Y, x, y in grid(CX - 19, EYE_Y - 3, CX + 20, EYE_Y + 3):
            c.shade_px(X, Y, MT, 4.4 - (x - CX) / 12 - (y > EYE_Y + 1) * 1.5)
        HL(c, H(CX - 16), H(CX + 16), HEY, GL, 5)
        HL(c, H(CX - 16), H(CX + 16), HEY + 1, GL, 3)
        HL(c, H(CX - 12), H(CX + 8), HEY - 1, GL, 3)
        for k in range(4):  # scanline segments
            HL(c, H(CX - 14) + k * 10, H(CX - 14) + k * 10 + 5, HEY, GL, 6)
        P(c, H(CX - 10), HEY, GL, 7)
        HL(c, H(CX - 19), H(CX + 19), H(EYE_Y - 3), MT, 6)
    elif kind == "jaw_plate":
        for X, Y, x, y in grid(CX + 3, 54, CX + 17, 67):
            if x < CX + 17 - max(0, y - 60):
                c.shade_px(X, Y, MT, 3.6 - (x - CX) / 9 - (y - 54) / 14)
        HL(c, H(CX + 3), H(CX + 15), H(54), MT, 6)
        for k in range(3):
            P(c, H(CX + 6 + k * 4), H(60), FX, F_OUT)
            P(c, H(CX + 6 + k * 4), H(59), MT, 6)
            P(c, H(CX + 6 + k * 4) + 1, H(60), FX, F_OUT)
        LN(c, H(CX + 4), H(63), H(CX + 13), H(63), MT, 1)
    elif kind == "face_half":
        mask = head_mask("oval")
        for (X, Y) in mask:
            if X >= HCX + 2 and H(30) <= Y <= H(64):
                c.shade_px(X, Y, MT, 4.0 - (X - HCX) / 13.5)
        for Y in range(H(30), H(65), 6):  # panel seams
            HL(c, HCX + 2, H(CX + 14), Y, MT, 2)
            HL(c, HCX + 2, H(CX + 14), Y + 1, MT, 5)
        VL(c, HCX + 2, H(30), H(64), MT, 6)
        VL(c, HCX + 3, H(30), H(64), MT, 1)
        _lens(c, ex1, HEY, 5)
        for k in range(6):
            P(c, H(CX + 3) + k * 3, H(58), GL, 3 + (k % 2))
        screw(c, H(CX + 12), H(33))
        screw(c, H(CX + 12), H(61))
    elif kind == "temple_ports":
        for side in (-1, 1):
            x = CX + 0.5 + side * 14
            for k in range(3):
                plate(c, x - 1.5, 33 + k * 4, x + 0.5, 35 + k * 4, MT)
                P(c, H(x), H(34 + k * 4), FX, F_OUT)
                P(c, H(x) + 1, H(34 + k * 4), GL, 4 if k == 0 else 2)
    elif kind == "neck_ports":
        for k in range(3):
            y = 68 + k * 4
            plate(c, CX + 3, y, CX + 6, y + 2, MT)
            HL(c, H(CX + 4), H(CX + 5) + 1, H(y + 1), FX, F_OUT)
        P(c, H(CX + 5), H(69), GL, 5)
        P(c, H(CX + 5) + 1, H(69), GL, 3)
    elif kind == "skull_plate":
        for X, Y, x, y in grid(CX - 15, 16, CX + 2, 31):
            if ((x - CX + 6) / 10) ** 2 + ((y - 24) / 8) ** 2 <= 1:
                c.shade_px(X, Y, MT, 5.0 - (y - 16) / 6 - (x > CX - 6))
        for k in range(8):  # stitched edge: screws round the rim
            P(c, H(CX - 14) + k * 3, H(30) - (k % 2), MT, 1)
            P(c, H(CX - 13) + k * 3, H(30) - (k % 2), MT, 6)
        LN(c, H(CX - 12), H(20), H(CX - 2), H(26), MT, 2)  # a weld seam
    elif kind == "cheek_leds":
        for side in (-1, 1):
            for k in range(5):
                X, Y = HCX + side * (15 + k), H(48) + k
                P(c, X, Y, GL, 4 if k % 2 == 0 else 2)
                P(c, X, Y + 1, SK, 2)
    elif kind == "skin_seam":
        for k in range(24):
            P(c, H(CX - 14) + k, H(62) + (k > 12) + (k > 19), SK, 3)
        VL(c, H(CX + 8), H(66), H(76), SK, 3)
        P(c, H(CX + 8) + 1, H(70), GL, 2)
    elif kind == "mouth_grille":
        for Y in range(H(57), H(63)):
            HL(c, H(CX - 6), H(CX + 6), Y, MT, 5 - (Y - H(57)) // 3)
        for X in range(H(CX - 5), H(CX + 6), 3):
            VL(c, X, H(58), H(61), FX, F_OUT)
        HL(c, H(CX - 6), H(CX + 6), H(57), MT, 6)
        P(c, H(CX - 7), H(60), GL, 4)
    elif kind == "ear_module":
        plate(c, CX + 17, 38, CX + 21, 49, MT, screws=True)
        VL(c, H(CX + 20), H(26), H(38), MT, 5)   # antenna
        VL(c, H(CX + 20) + 1, H(26), H(38), MT, 2)
        P(c, H(CX + 20), H(25), GL, 7)
        P(c, H(CX + 20), H(25) - 1, GL, 4)
        P(c, H(CX + 19), H(44), GL, 3)
    elif kind == "forehead_chip":
        plate(c, CX - 3, 25, CX + 3, 29, MT, lo=2, hi=5)
        HL(c, H(CX - 2), H(CX + 2) + 1, H(27), GL, 4)
        for k in range(3):
            P(c, H(CX - 2) + k * 3, H(27) + 1, GL, 2)
        for side in (-1, 1):  # traces under the skin
            HL(c, H(CX + side * 4), H(CX + side * 7), H(27), SK, 3)
            P(c, H(CX + side * 7), H(27) - 1, SK, 3)
    elif kind == "shoulder_chrome":
        for X, Y, x, y in grid(CX - 38, 82, CX - 20, PH):
            if ((x - CX + 28) / 12) ** 2 + ((y - 96) / 16) ** 2 <= 1:
                c.shade_px(X, Y, MT, 5.4 - (x - CX + 38) / 10 - (y - 82) / 22)
        for Y in range(H(86), HPH, 7):  # segment plates
            HL(c, H(CX - 36), H(CX - 22), Y, MT, 1)
            HL(c, H(CX - 36), H(CX - 22), Y + 1, MT, 6)
        P(c, H(CX - 27), H(92), GL, 5)
        P(c, H(CX - 27) + 1, H(92), GL, 3)
    elif kind == "spine_cables":
        for side in (-1, 1):
            for k in range(33):
                X = HCX + side * (13 + k)
                Y = H(72) + int(k * 0.55) + (k % 6 == 0)
                P(c, X, Y, MT, 5 if side < 0 else 3)
                P(c, X, Y + 1, MT, 2)
                P(c, X, Y + 2, FX, F_OUT)
        P(c, HCX + 13, H(72), GL, 5)
    elif kind == "organic_growth":
        rngx = random.Random(11)
        pts = [(H(CX + 6), H(76))]
        for k in range(38):
            X, Y = pts[-1]
            pts.append((X + rngx.choice((1, 1, 0)), Y - rngx.choice((1, 1, 0, 2)) if k < 27 else Y + 1))
        for (X, Y) in pts:
            P(c, X, Y, BL, 3)
            P(c, X + 1, Y, GL, 2)
            P(c, X - 1, Y, BL, 2)
        for k in range(9):
            X, Y = pts[rngx.randint(0, len(pts) - 1)]
            P(c, X - 1, Y, GL, 5)
        for X, Y, x, y in grid(CX + 3, 70, CX + 10, 78):
            if rngx.random() < 0.35:
                P(c, X, Y, BL, 2)
    elif kind == "serial_marks":
        for k in range(11):
            VL(c, H(CX - 15) + k * 2, H(70), H(70) + 1 + (k % 2), FX, F_INK)
        HL(c, H(CX - 16), H(CX - 3), H(72) + 1, FX, F_INK)
    elif kind == "patched_implant":
        plate(c, CX - 15, 48, CX - 8, 55, MT, lo=1.6, hi=4.4)
        for k in range(9):  # tape + crude stitches
            P(c, H(CX - 16) + k * 2, H(47), CB, 5)
            P(c, H(CX - 16) + k * 2, H(47) + 1, CB, 4)
            P(c, H(CX - 16) + k * 2, H(56), FX, F_OUT)
            P(c, H(CX - 16) + k * 2, H(56) + 1, FX, F_OUT)
        P(c, H(CX - 12), H(51), GL, 4)
        P(c, H(CX - 11), H(52), BL, 2)


ACCESSORIES = ["shades", "goggles", "glasses", "headset", "surgical_mask", "beanie", "cap", "hood", "helmet",
               "bandana", "scarf", "cigarette", "earpiece", "chain", "dog_tags", "choker", "headlamp",
               "respirator", "monocle"]


def draw_accessory(c: HDCanvas, kind: str, rng):
    ex0, ex1 = HEX
    if kind == "shades":
        for ex in HEX:
            for Y in range(HEY - 4, HEY + 4):
                for X in range(ex - 6, ex + 7):
                    corner = (abs(X - ex) == 6) and (Y in (HEY - 4, HEY + 3))
                    if not corner:
                        P(c, X, Y, CC, 1 if Y > HEY else 0)
            LN(c, ex - 4, HEY - 3, ex - 1, HEY - 3, FX, F_LENS)  # reflections
            P(c, ex - 5, HEY - 2, FX, F_LENS)
            P(c, ex + 3, HEY + 1, CC, 3)
        HL(c, ex0 + 7, ex1 - 7, HEY - 3, MT, 4)
        HL(c, H(CX - 22), ex0 - 7, HEY - 3, MT, 3)
        HL(c, ex1 + 7, H(CX + 22), HEY - 3, MT, 2)
    elif kind == "goggles":
        HL(c, H(CX - 22), H(CX + 22), H(31), LT, 2)
        HL(c, H(CX - 22), H(CX + 22), H(31) + 1, LT, 3)
        HL(c, H(CX - 22), H(CX + 22), H(32) + 1, LT, 1)
        for ex in (H(CX - 8), H(CX + 9)):
            _lens(c, ex, H(30), 5, 2)
    elif kind == "glasses":
        for ex in HEX:
            for X in range(ex - 6, ex + 7):
                P(c, X, HEY - 4, MT, 4)
                P(c, X, HEY + 4, MT, 2)
            VL(c, ex - 6, HEY - 4, HEY + 4, MT, 4)
            VL(c, ex + 6, HEY - 4, HEY + 4, MT, 2)
            LN(c, ex - 4, HEY - 2, ex - 2, HEY - 3, FX, F_LENS)
        HL(c, ex0 + 7, ex1 - 7, HEY - 3, MT, 4)
    elif kind == "headset":
        for X in range(H(CX - 20), H(CX + 21)):
            dx = (X - HCX) / H(20)
            Y = int(H(18) + dx * dx * H(18))
            P(c, X, Y, CC, 3)
            P(c, X, Y + 1, CC, 1)
        plate(c, CX - 22, 38, CX - 17, 48, CC, lo=1, hi=4, screws=True)
        for k in range(15):  # boom mic
            P(c, H(CX - 18) + k, H(52) + k // 2, CC, 2)
            P(c, H(CX - 18) + k, H(52) + k // 2 + 1, CC, 1)
        P(c, H(CX - 8), H(57), GL, 5)
        P(c, H(CX - 8) + 1, H(57), GL, 3)
    elif kind == "surgical_mask":
        for X, Y, x, y in grid(CX - 15, 50, CX + 16, 66):
            if abs(x - CX) <= 15 - max(0, y - 60):
                c.shade_px(X, Y, CB, 5.4 - (x - CX) / 10 - (y - 50) / 14)
        for k in range(3):  # pleats
            HL(c, H(CX - 12), H(CX + 12), H(54 + k * 3), CB, 3)
            HL(c, H(CX - 12), H(CX + 12), H(54 + k * 3) + 1, CB, 6)
        for side in (-1, 1):
            HL(c, H(CX + side * 15), H(CX + side * 19), H(48), CB, 4)
        HL(c, H(CX - 4), H(CX + 4), H(50), MT, 5)  # nose wire
        from .hdc_outfit import _stains
        _stains(c, rng, [(BL, 3), (GR, 4)], 2, (CX - 10, 56, CX + 10, 63))
    elif kind == "beanie":
        for X, Y, x, y in grid(CX - 20, 10, CX + 21, 30):
            if ((x - CX) / 20.5) ** 2 + ((y - 30) / 19) ** 2 <= 1:
                knit = (X % 4 == 0)
                c.shade_px(X, Y, CC, 4.6 - (x - CX) / 9 - (y - 10) / 14 - knit * 0.8)
        for X, Y, x, y in grid(CX - 20, 26, CX + 21, 31):  # ribbed cuff
            P(c, X, Y, CC, (3 - (y >= 30)) + (X % 3 == 0) - (X > HCX))
    elif kind == "cap":
        for X, Y, x, y in grid(CX - 19, 12, CX + 20, 28):
            if ((x - CX) / 19.5) ** 2 + ((y - 28) / 15) ** 2 <= 1:
                c.shade_px(X, Y, CC, 4.4 - (x - CX) / 10)
        VL(c, HCX, H(13), H(27), CC, 2)  # panel seam
        P(c, HCX, H(13) - 1, CC, 5)       # button
        for X in range(H(CX - 20), H(CX + 12)):  # brim
            P(c, X, H(28), CC, 3)
            P(c, X, H(28) + 1, CC, 2)
            P(c, X, H(29) + 1, CC, 1)
    elif kind == "hood":
        for X, Y, x, y in grid(CX - 30, 6, CX + 31, 92):
            outer = ((x - CX) / 27) ** 2 + ((y - 40) / 34) ** 2 <= 1
            inner = ((x - CX) / 19.5) ** 2 + ((y - 42) / 27) ** 2 <= 1
            if outer and not inner:
                c.shade_px(X, Y, CC, 3.8 - (x - CX) / 9 - (y > 60) * 0.8)
        for X in range(H(CX - 19), H(CX + 20)):  # inner shadow on the forehead
            dx = (X - HCX) / H(20)
            P(c, X, int(H(16) + dx * dx * H(10)), CC, 1)
            P(c, X, int(H(16) + dx * dx * H(10)) + 1, CC, 0)
        stitch_h(c, H(CX - 18), H(CX - 4), H(8), CC, 4)
    elif kind == "helmet":
        for X, Y, x, y in grid(CX - 21, 10, CX + 22, 36):
            if ((x - CX) / 21.5) ** 2 + ((y - 34) / 24) ** 2 <= 1:
                c.shade_px(X, Y, CA, 4.8 - (x - CX) / 10 - (y - 10) / 16)
        HL(c, H(CX - 21), H(CX + 21), H(34), MT, 5)
        HL(c, H(CX - 21), H(CX + 21), H(34) + 1, MT, 2)
        plate(c, CX - 16, 22, CX + 16, 28, MT, lo=2, hi=5)  # raised visor
        HL(c, H(CX - 14), H(CX + 14), H(25), GL, 2)
        HL(c, H(CX - 10), H(CX + 2), H(25), GL, 4)
        for side in (-1, 1):
            plate(c, CX + side * 20 - 2, 34, CX + side * 20 + 2, 50, CA, screws=True)
    elif kind == "bandana":
        for X, Y, x, y in grid(CX - 18, 53, CX + 19, 72):
            if abs(x - CX) <= 18 - max(0, y - 64) * 2:
                c.shade_px(X, Y, CC, 4.2 - (x - CX) / 10 - (y > 64))
        for k in range(8):  # paisley-ish print
            P(c, H(CX - 10) + k * 4, H(60) + (k % 2) * 2, CC, 1)
            P(c, H(CX - 10) + k * 4 + 1, H(60) + (k % 2) * 2, CC, 6)
        for k in range(6):  # folds
            P(c, HCX - 6 + k * 2, H(66) + k // 2, CC, 1)
    elif kind == "scarf":
        for X, Y, x, y in grid(CX - 16, 66, CX + 17, 86):
            if abs(x - CX) <= 16 - max(0, y - 80):
                c.shade_px(X, Y, CC, 4.0 - (x - CX) / 10 + ((X + Y) % 5 == 0) * 0.8)
        for k in range(4):
            LN(c, H(CX - 14) + k * 8, H(68), H(CX - 10) + k * 8, H(84), CC, 2)
    elif kind == "cigarette":
        for k in range(12):
            P(c, H(CX + 5) + k, H(60) + k // 6, CB, 6)
            P(c, H(CX + 5) + k, H(60) + k // 6 + 1, CB, 4)
        HL(c, H(CX + 5), H(CX + 7), H(60), CC, 4)  # filter
        P(c, H(CX + 13), H(62), GL, 7)
        P(c, H(CX + 14), H(62), GL, 5)
        P(c, H(CX + 13), H(62) + 1, GL, 4)
        for k in range(9):  # smoke wisp
            P(c, H(CX + 15) + (k % 3 == 1) - (k % 3 == 2), H(60) - k * 2, FX, F_EYEW)
    elif kind == "earpiece":
        plate(c, CX - 20, 43, CX - 17, 47, MT)
        P(c, H(CX - 18), H(45), GL, 6)
        for k in range(12):
            P(c, H(CX - 19), H(48) + k, CC, 1)
    elif kind == "chain":
        for k in range(39):
            X = H(CX - 13) + k
            Y = H(82) + int(abs(k - 19) * -0.27 + 9)
            P(c, X, Y, MT, 6 if k % 3 == 0 else (4 if k % 3 == 1 else 2))
    elif kind == "dog_tags":
        for k in range(15):
            P(c, H(CX - 5) + k, H(80) + abs(k - 7) // 2, MT, 5 if k % 2 else 3)
        plate(c, CX - 1, 85, CX + 3, 90, MT)
        HL(c, H(CX) + 1, H(CX + 2), H(87), MT, 2)
        HL(c, H(CX) + 1, H(CX + 2) - 1, H(88) + 1, MT, 2)
    elif kind == "choker":
        HL(c, H(CX - 8), H(CX + 8), H(72), LT, 3)
        HL(c, H(CX - 8), H(CX + 8), H(72) + 1, LT, 2)
        HL(c, H(CX - 8), H(CX + 8), H(73) + 1, LT, 1)
        for k in range(-6, 7, 3):
            P(c, HCX + k, H(72) + 1, MT, 6)
        P(c, HCX, H(74), MT, 6)
        P(c, HCX, H(74) + 1, MT, 4)
    elif kind == "headlamp":
        HL(c, H(CX - 19), H(CX + 19), H(27), LT, 2)
        HL(c, H(CX - 19), H(CX + 19), H(27) + 1, LT, 1)
        plate(c, CX - 4, 22, CX + 4, 28, MT, screws=True)
        for dx in range(-1, 2):
            for dy in range(-1, 2):
                P(c, HCX + dx, H(25) + dy, GL, 7 - abs(dx) - abs(dy))
    elif kind == "respirator":
        for X, Y, x, y in grid(CX - 11, 52, CX + 12, 68):
            if abs(x - CX) <= 11 - max(0, y - 63):
                c.shade_px(X, Y, CB, 3.6 - (x - CX) / 8)
        for side in (-1, 1):
            c.lsphere(CX + 0.5 + side * 10, 62, 4, 4.5, MT, lo=1.2, hi=5.0)
            for k in range(-2, 3):  # filter slots
                HL(c, H(CX + 0.5 + side * 10) - 2, H(CX + 0.5 + side * 10) + 2, H(62) + k * 2, FX, F_OUT)
        for side in (-1, 1):
            HL(c, H(CX + side * 12), H(CX + side * 20), H(50), LT, 1)
            HL(c, H(CX + side * 12), H(CX + side * 20), H(50) + 1, LT, 2)
    elif kind == "monocle":
        _lens(c, HEX[0], HEY, 5, 3)
        for k in range(15):
            P(c, HEX[0] - 5 - k // 3, HEY + 6 + k, MT, 4 if k % 2 else 6)
