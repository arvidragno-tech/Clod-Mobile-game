#!/usr/bin/env python3
"""Synthesises tiny placeholder sound effects (16-bit mono WAV, 22.05 kHz).

These exist so every AudioManager hook is audible during prototyping.
Replace any file with final audio using the same name.
Run:  python3 tools/generate_placeholder_audio.py   (standard library only)
"""
from __future__ import annotations

import math
import os
import random
import struct
import wave

RATE = 22050
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")


def env(i: int, n: int, attack: float = 0.01, release: float = 0.6) -> float:
    t = i / n
    if t < attack:
        return t / attack
    return max(0.0, 1.0 - (t - attack) / (1.0 - attack)) ** (1.0 / max(release, 0.01))


def square(phase: float) -> float:
    return 1.0 if (phase % 1.0) < 0.5 else -1.0


def tone(freq_from: float, freq_to: float, dur: float, wave_fn=square, vol: float = 0.4, release: float = 0.5) -> list[float]:
    n = int(RATE * dur)
    out, phase = [], 0.0
    for i in range(n):
        f = freq_from + (freq_to - freq_from) * (i / n)
        phase += f / RATE
        out.append(wave_fn(phase) * vol * env(i, n, release=release))
    return out


def noise(dur: float, vol: float = 0.3, lowpass: float = 0.3, seed: int = 1) -> list[float]:
    rng = random.Random(seed)
    n = int(RATE * dur)
    out, prev = [], 0.0
    for i in range(n):
        prev += (rng.uniform(-1, 1) - prev) * lowpass
        out.append(prev * vol * env(i, n))
    return out


def sine(phase: float) -> float:
    return math.sin(phase * 2 * math.pi)


def concat(*parts: list[float]) -> list[float]:
    out: list[float] = []
    for p in parts:
        out.extend(p)
    return out


def mixdown(*parts: list[float]) -> list[float]:
    n = max(len(p) for p in parts)
    return [sum(p[i] for p in parts if i < len(p)) for i in range(n)]


def silence(dur: float) -> list[float]:
    return [0.0] * int(RATE * dur)


def write(rel: str, samples: list[float]) -> None:
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32000)) for s in samples))
    print("wrote", os.path.relpath(path, os.path.join(ROOT, "..")))


def ambient_hum(dur: float = 4.0) -> list[float]:
    """Seamless loop: 50 Hz mains hum + soft filtered noise (drip-free)."""
    rng = random.Random(9)
    n = int(RATE * dur)
    out, prev = [], 0.0
    for i in range(n):
        t = i / RATE
        hum = 0.10 * math.sin(2 * math.pi * 50 * t) + 0.04 * math.sin(2 * math.pi * 100 * t)
        prev += (rng.uniform(-1, 1) - prev) * 0.02
        out.append(hum + prev * 0.25)
    # Crossfade the tail into the head for a click-free loop.
    fade = int(RATE * 0.2)
    for i in range(fade):
        a = i / fade
        out[i] = out[i] * a + out[n - fade + i] * (1 - a)
    return out[: n - fade]


def main() -> None:
    write("sfx/click.wav", tone(1400, 1100, 0.035, vol=0.25))
    write("sfx/tool_select.wav", concat(tone(700, 700, 0.03, vol=0.2), tone(1050, 1050, 0.04, vol=0.2)))
    write("sfx/cut.wav", noise(0.12, vol=0.35, lowpass=0.6, seed=2))
    write("sfx/burn.wav", mixdown(noise(0.18, vol=0.3, lowpass=0.8, seed=3), tone(180, 120, 0.18, vol=0.08)))
    write("sfx/clamp.wav", concat(tone(300, 200, 0.03, vol=0.35), tone(900, 900, 0.02, vol=0.2)))
    write("sfx/zap.wav", mixdown(tone(1800, 400, 0.12, vol=0.25), noise(0.1, vol=0.2, lowpass=0.9, seed=4)))
    write("sfx/stitch.wav", concat(tone(1200, 1200, 0.02, vol=0.25), silence(0.02), tone(800, 800, 0.03, vol=0.2)))
    write("sfx/implant_install.wav", concat(tone(160, 90, 0.08, vol=0.45), tone(880, 880, 0.06, vol=0.2), tone(1320, 1320, 0.12, sine, vol=0.25)))
    write("sfx/stage_complete.wav", concat(tone(660, 660, 0.06, vol=0.2), tone(990, 990, 0.1, vol=0.2)))
    write("sfx/mistake.wav", tone(160, 110, 0.18, vol=0.35, release=0.8))
    write("sfx/warning.wav", concat(tone(880, 880, 0.09, vol=0.25), silence(0.04), tone(660, 660, 0.09, vol=0.25)))
    write("sfx/surgery_success.wav", concat(*[tone(f, f, 0.09, vol=0.22) for f in (523, 659, 784)], tone(1046, 1046, 0.3, sine, vol=0.3)))
    write("sfx/surgery_failure.wav", concat(*[tone(f, f * 0.97, 0.16, vol=0.25) for f in (392, 311, 233)], tone(155, 120, 0.4, vol=0.3)))
    write("sfx/customer_arrival.wav", concat(tone(220, 220, 0.12, vol=0.25), silence(0.05), tone(220, 220, 0.12, vol=0.25)))
    write("sfx/cash.wav", concat(tone(1568, 1568, 0.05, vol=0.2), tone(2093, 2093, 0.12, sine, vol=0.25)))
    write("sfx/level_up.wav", concat(*[tone(f, f, 0.07, vol=0.2) for f in (440, 554, 659, 880)], tone(1108, 1108, 0.25, sine, vol=0.25)))
    write("ambient/clinic_hum.wav", ambient_hum())


if __name__ == "__main__":
    main()
