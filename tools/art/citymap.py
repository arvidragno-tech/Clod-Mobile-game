"""City map of Caldera (320x180 art px, 3x on screen): a flooded volcanic
caldera, the ring wall, the canal, and seven districts drawn as dense
blocks of rooftops in each district's own palette (data/districts.json).
Dark, low-saturation, with only a few lit windows - a fixer's map, not a
tourist poster."""
from __future__ import annotations

import json
import math
import os
import random

from . import palette as pal
from .lib import Canvas, bayer

MW, MH = 320, 180
WATER = pal.ramp("16202a", 0.04)
ROCK = pal.ramp("2a2622", 0.05)


def _c(ramp, i):
    c = ramp[max(0, min(7, int(i)))]
    return (c[0], c[1], c[2], 255)


def generate():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "districts.json")
    districts = json.load(open(root))["districts"]
    rng = random.Random(7)
    cv = Canvas(MW, MH, fill=_c(WATER, 1))
    cx, cy = MW * 0.5, MH * 0.52
    # Water with dithered swell
    for y in range(MH):
        for x in range(MW):
            v = 1.4 + 0.6 * math.sin(x * 0.11 + y * 0.07) + (0.5 if bayer(x, y) < 0.2 else 0)
            cv.shade_px(x, y, WATER, v)
    # Caldera ring wall (rock) with the land inside it
    for y in range(MH):
        for x in range(MW):
            d = math.hypot((x - cx) / (MW * 0.47), (y - cy) / (MH * 0.47))
            if 0.93 < d < 1.08:
                cv.shade_px(x, y, ROCK, 2.4 + (1.08 - d) * 10 * 0.3 + rng.random() * 0.4)
            elif d <= 0.93 and d > 0.88:
                cv.shade_px(x, y, ROCK, 1.6)
    # Land: everything inside the ring, split into districts (nearest
    # district centre), ground first, then building footprints on top.
    centres = [(d["map"][0] * MW, d["map"][1] * MH) for d in districts]
    ramps = [[pal.ramp(h, 0.05) for h in d["palette"]] for d in districts]
    owner = [[-1] * MW for _ in range(MH)]
    for y in range(MH):
        for x in range(MW):
            d = math.hypot((x - cx) / (MW * 0.47), (y - cy) / (MH * 0.47))
            if d > 0.87 + 0.02 * math.sin(x * 0.3 + y * 0.2):
                continue
            best, bi = 1e9, 0
            for i, (qx, qy) in enumerate(centres):
                dd = (x - qx) ** 2 + ((y - qy) * 1.5) ** 2
                if dd < best:
                    best, bi = dd, i
            # The drowned edge by the restricted zone is under water.
            if districts[bi]["id"] == "restricted" and (x + y * 0.6) > 300 and bayer(x, y) < 0.55:
                continue
            owner[y][x] = bi
            cv.set(x, y, _c(ROCK, 1))
    # Roads along district borders.
    for y in range(1, MH - 1):
        for x in range(1, MW - 1):
            o = owner[y][x]
            if o >= 0 and (owner[y][x + 1] not in (o, -1) or owner[y + 1][x] not in (o, -1)):
                cv.set(x, y, _c(ROCK, 3))
    # Building footprints: shaded rectangles, roof highlight, cast shadow.
    for _ in range(2600):
        x, y = rng.randrange(MW), rng.randrange(MH)
        o = owner[y][x]
        if o < 0:
            continue
        did = districts[o]["id"]
        big = did in ("corporate", "restricted", "industrial")
        w = rng.randrange(3, 10 if big else 7)
        h = rng.randrange(2, 6 if big else 4)
        if any(owner[min(MH - 1, y + j)][min(MW - 1, x + i)] != o for i in (0, w) for j in (0, h)):
            continue
        ramp = ramps[o][rng.randrange(len(ramps[o]))]
        base = rng.uniform(1.6, 2.8)
        for j in range(h):
            for i in range(w):
                v = base + (1.2 if j == 0 else 0) - (0.8 if i == w - 1 else 0)
                cv.shade_px(x + i, y + j, ramp, v)
        for i in range(1, w + 1):  # shadow
            if owner[min(MH - 1, y + h)][min(MW - 1, x + i)] == o:
                cv.set(x + i, y + h, _c(ROCK, 0))
        if rng.random() < 0.35:  # a lit window
            warm = did in ("undercity", "industrial", "oldcity", "market", "entertainment")
            cv.set(x + rng.randrange(w), y + rng.randrange(1, max(2, h)), (190, 140, 84, 255) if warm else (140, 172, 196, 255))
    # The canal through the market to the drowned district
    pts = [(40, 150), (100, 128), (166, 112), (220, 96), (276, 60)]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        steps = int(max(abs(x1 - x0), abs(y1 - y0)))
        for k in range(steps):
            x = x0 + (x1 - x0) * k / steps
            y = y0 + (y1 - y0) * k / steps
            for w in range(-1, 2):
                cv.set(int(x), int(y) + w, _c(WATER, 2 + (1 if bayer(int(x), int(y)) < 0.3 else 0)))
    # Grid of the old roads (faint)
    for x in range(0, MW, 40):
        for y in range(MH):
            if cv.px[y][x] and bayer(x, y) < 0.25:
                c = cv.px[y][x]
                cv.px[y][x] = (min(255, c[0] + 8), min(255, c[1] + 8), min(255, c[2] + 8), 255)
    cv.save("ui/city_map.png")
    print("city map")
