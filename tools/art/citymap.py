"""City map of Caldera, laid out on a 320x180 grid (the units the map view,
location pins and taps use) and painted at K=3 pixels per unit (960x540,
one texel per screen pixel at the 3x map scale): a flooded volcanic
caldera, the ring wall, the canal, and seven districts drawn as dense
blocks of rooftops in each district's own palette (data/districts.json).
Rooftops carry fine detail the old grid could not hold: lit parapets, AC
units, water tanks, skylights, single lit windows. Dark, low-saturation -
a fixer's map, not a tourist poster."""
from __future__ import annotations

import json
import math
import os
import random

import numpy as np
from PIL import Image

from . import palette as pal
from .lib import SPRITES

MW, MH = 320, 180
K = 3
WATER = pal.ramp("16202a", 0.04)
ROCK = pal.ramp("2a2622", 0.05)
BAYER = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]], dtype=np.float32) / 16.0


def _shade(ramp, v):
    """Continuous shade value -> ramp colour (rounded)."""
    return ramp[max(0, min(7, int(round(v))))]


def generate():
    root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "data", "districts.json")
    districts = json.load(open(root))["districts"]
    rng = random.Random(7)
    W, H = MW * K, MH * K
    img = np.zeros((H, W, 3), dtype=np.uint8)
    YY, XX = np.mgrid[0:H, 0:W]
    x = (XX + 0.5) / K - 0.5  # design coordinates of each pixel centre
    y = (YY + 0.5) / K - 0.5
    bay = np.tile(BAYER, (H // 4 + 1, W // 4 + 1))[:H, :W]
    cx, cy = MW * 0.5, MH * 0.52
    wat = np.array(WATER, dtype=np.uint8)
    rock = np.array(ROCK, dtype=np.uint8)

    # Water with a fine dithered swell and caustic glints.
    v = 1.4 + 0.6 * np.sin(x * 0.11 + y * 0.07) + 0.35 * np.sin(x * 0.53 - y * 0.41) * (bay < 0.5)
    v = v + (bay < 0.12) * 0.6
    img[:] = wat[np.clip(np.round(v), 0, 7).astype(int)]
    # Caldera ring wall: rock with strata and a lit inner lip.
    d = np.hypot((x - cx) / (MW * 0.47), (y - cy) / (MH * 0.47))
    ring = (d > 0.93) & (d < 1.08)
    rng_np = np.random.default_rng(7)
    rv = (2.4 + (1.08 - d) * 3 + np.sin(np.arctan2(y - cy, x - cx) * 60) * 0.35 + (bay - 0.5) * 0.8
          + rng_np.normal(0, 0.45, d.shape))
    img[ring] = rock[np.clip(np.round(rv[ring]), 0, 7).astype(int)]
    lip = (d <= 0.93) & (d > 0.88)
    img[lip] = rock[2]
    img[(d > 0.925) & (d <= 0.935)] = rock[4]
    img[(d > 1.075) & (d <= 1.085)] = rock[0]

    # Land: inside the ring, split into districts (nearest district centre).
    centres = [(dd["map"][0] * MW, dd["map"][1] * MH) for dd in districts]
    ramps = [[pal.ramp(h, 0.05) for h in dd["palette"]] for dd in districts]
    land = d <= 0.87 + 0.02 * np.sin(x * 0.3 + y * 0.2)
    dist = np.stack([(x - qx) ** 2 + ((y - qy) * 1.5) ** 2 for qx, qy in centres])
    owner = np.argmin(dist, axis=0)
    for i, dd in enumerate(districts):
        if dd["id"] == "restricted":  # its drowned edge is under water
            sunk = (owner == i) & ((x + y * 0.6) > 300) & (bay < 0.55)
            land &= ~sunk
    owner = np.where(land, owner, -1)
    img[land] = rock[1]
    # Street grain: a faint per-district ground texture.
    grain = land & (bay < 0.08)
    img[grain] = rock[2]
    # Roads along district borders: a lit two-pixel avenue with lane dots.
    border = np.zeros_like(land)
    border[:, :-K] |= (owner[:, :-K] != owner[:, K:]) & (owner[:, :-K] >= 0) & (owner[:, K:] >= 0)
    border[:-K, :] |= (owner[:-K, :] != owner[K:, :]) & (owner[:-K, :] >= 0) & (owner[K:, :] >= 0)
    img[border] = rock[3]
    img[border & ((XX + YY) % 6 == 0)] = rock[5]

    def owner_at(px, py):
        X, Y = int(px * K), int(py * K)
        if 0 <= X < W and 0 <= Y < H:
            return owner[Y, X]
        return -1

    warm_ids = ("undercity", "industrial", "oldcity", "market", "entertainment")
    # Building footprints: shaded roofs with a lit parapet, a cast shadow,
    # rooftop kit and lit windows, at the fine grid.
    for _ in range(6000):
        bx, by = rng.uniform(0, MW), rng.uniform(0, MH)
        o = owner_at(bx, by)
        if o < 0:
            continue
        did = districts[o]["id"]
        big = did in ("corporate", "restricted", "industrial")
        w = rng.randrange(2 * K, (10 if big else 6) * K) / K
        h = rng.randrange(2 * K, (6 if big else 4) * K) / K
        if any(owner_at(bx + i, by + j) != o for i in (0, w) for j in (0, h + 1)):
            continue
        ramp = ramps[o][rng.randrange(len(ramps[o]))]
        X0, Y0 = int(bx * K), int(by * K)
        X1, Y1 = int((bx + w) * K), int((by + h) * K)
        base = rng.uniform(1.6, 2.8)
        # Shadow (one design px down-right).
        sh = owner[Y1:Y1 + K, X0 + K:X1 + K] == o
        img[Y1:Y1 + K, X0 + K:X1 + K][sh] = rock[0]
        sh = owner[Y0 + K:Y1 + K, X1:X1 + K] == o
        img[Y0 + K:Y1 + K, X1:X1 + K][sh] = rock[0]
        # Roof, parapet light on top/left, dark lip on bottom/right.
        img[Y0:Y1, X0:X1] = _shade(ramp, base)
        img[Y0:Y0 + 1, X0:X1] = _shade(ramp, base + 2)
        img[Y0:Y1, X0:X0 + 1] = _shade(ramp, base + 1)
        img[Y1 - 1:Y1, X0:X1] = _shade(ramp, base - 1.2)
        img[Y0:Y1, X1 - 1:X1] = _shade(ramp, base - 1)
        # Roof seams on large blocks.
        if X1 - X0 > 12 and rng.random() < 0.5:
            sx = X0 + (X1 - X0) // 2
            img[Y0 + 1:Y1 - 1, sx] = _shade(ramp, base - 0.8)
        # Rooftop kit: AC boxes, a water tank, a skylight.
        for _k in range(rng.randrange(0, 3)):
            if X1 - X0 < 6 or Y1 - Y0 < 5:
                break
            ax = rng.randrange(X0 + 1, X1 - 3)
            ay = rng.randrange(Y0 + 1, Y1 - 3)
            kind = rng.random()
            if kind < 0.5:
                img[ay:ay + 2, ax:ax + 3] = _shade(ramp, base + 1.5)
                img[ay + 2, ax:ax + 3] = rock[0]
            elif kind < 0.75:
                img[ay:ay + 3, ax:ax + 3] = _shade(ROCK, 3)
                img[ay, ax + 1] = rock[5]
                img[ay + 1, ax:ax + 3] = rock[4]
            else:
                img[ay:ay + 2, ax:ax + 2] = (60, 78, 92)
                img[ay, ax] = (110, 134, 150)
        # Lit windows: single fine pixels, sometimes a row.
        if rng.random() < 0.45:
            warm = did in warm_ids
            col = (190, 140, 84) if warm else (140, 172, 196)
            n = rng.choice((1, 1, 2, 3))
            wx = rng.randrange(X0 + 1, max(X0 + 2, X1 - n))
            wy = rng.randrange(Y0 + 1, max(Y0 + 2, Y1 - 1))
            img[wy, wx:wx + n] = col
        if did in ("corporate", "entertainment") and rng.random() < 0.08:
            # Aviation light / sign glow on a tower.
            img[Y0 + 1, X0 + 1] = (200, 60, 70) if did == "corporate" else (200, 70, 160)

    # The canal through the market to the drowned district: water with
    # embankment walls and a centre ripple.
    pts = [(40, 150), (100, 128), (166, 112), (220, 96), (276, 60)]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        steps = int(max(abs(x1 - x0), abs(y1 - y0)) * K)
        for k in range(steps):
            px = (x0 + (x1 - x0) * k / steps) * K
            py = (y0 + (y1 - y0) * k / steps) * K
            X = int(px)
            for wv in range(-5, 6):
                Y = int(py) + wv
                if 0 <= X < W and 0 <= Y < H:
                    if abs(wv) == 5:
                        img[Y, X] = rock[4] if wv < 0 else rock[0]
                    else:
                        img[Y, X] = wat[2 + (1 if bay[Y, X] < 0.25 else 0) + (1 if wv == 0 and k % 7 < 3 else 0)]
    # Grid of the old roads (faint).
    for gx in range(0, MW, 40):
        col = img[:, gx * K]
        m = (bay[:, gx * K] < 0.25) & land[:, gx * K]
        img[m, gx * K] = np.minimum(255, col[m].astype(int) + 8).astype(np.uint8)

    path = os.path.join(SPRITES, "ui/city_map.png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(img, "RGB").save(path, optimize=True)
    print("city map (960x540)")
