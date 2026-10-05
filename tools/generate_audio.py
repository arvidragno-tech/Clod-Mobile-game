#!/usr/bin/env python3
"""Synthesises the game's soundscape: SFX (16-bit mono WAV), seamless ambience
layers and three music loops (OGG Vorbis via ffmpeg). Standard library only,
plus the ffmpeg binary for OGG encoding (falls back to WAV if missing).

Everything is deterministic (seeded), so re-running reproduces the same files.
Run:  python3 tools/generate_audio.py [sfx|ambience|music ...]
"""
from __future__ import annotations

import math
import os
import random
import shutil
import struct
import subprocess
import sys
import wave

RATE = 22050          # SFX
MUSIC_RATE = 32000    # ambience + music
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "audio")
TAU = 2 * math.pi


# --- primitives -------------------------------------------------------------

def env(i: int, n: int, attack: float = 0.01, release: float = 0.6) -> float:
    t = i / n
    if t < attack:
        return t / attack
    return max(0.0, 1.0 - (t - attack) / (1.0 - attack)) ** (1.0 / max(release, 0.01))


def square(phase: float) -> float:
    return 1.0 if (phase % 1.0) < 0.5 else -1.0


def sine(phase: float) -> float:
    return math.sin(phase * TAU)


def saw(phase: float) -> float:
    return 2.0 * (phase % 1.0) - 1.0


def tri(phase: float) -> float:
    p = phase % 1.0
    return 4.0 * p - 1.0 if p < 0.5 else 3.0 - 4.0 * p


def tone(freq_from, freq_to, dur, wave_fn=square, vol=0.4, release=0.5, rate=RATE, attack=0.01):
    n = int(rate * dur)
    out, phase = [], 0.0
    for i in range(n):
        f = freq_from + (freq_to - freq_from) * (i / n)
        phase += f / rate
        out.append(wave_fn(phase) * vol * env(i, n, attack=attack, release=release))
    return out


def noise(dur, vol=0.3, lowpass=0.3, seed=1, rate=RATE, shaped=True):
    rng = random.Random(seed)
    n = int(rate * dur)
    out, prev = [], 0.0
    for i in range(n):
        prev += (rng.uniform(-1, 1) - prev) * lowpass
        out.append(prev * vol * (env(i, n) if shaped else 1.0))
    return out


def concat(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def mixdown(*parts):
    n = max(len(p) for p in parts)
    return [sum(p[i] for p in parts if i < len(p)) for i in range(n)]


def silence(dur, rate=RATE):
    return [0.0] * int(rate * dur)


def gain(samples, g):
    return [s * g for s in samples]


def normalize(samples, peak=0.9):
    m = max(1e-6, max(abs(s) for s in samples))
    return [s * peak / m for s in samples]


def write_wav(path, samples, rate):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32000)) for s in samples))


def write(rel, samples, rate=RATE):
    path = os.path.join(ROOT, rel)
    write_wav(path, samples, rate)
    print("wrote", rel)


def write_ogg(rel, samples, rate=MUSIC_RATE, quality=3):
    """Encodes a loop as OGG Vorbis (small, streamable). Falls back to WAV."""
    path = os.path.join(ROOT, rel)
    tmp = path + ".tmp.wav"
    write_wav(tmp, samples, rate)
    if shutil.which("ffmpeg"):
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(quality), path], check=True)
        os.remove(tmp)
        print("wrote", rel)
    else:
        os.replace(tmp, path[:-4] + ".wav")
        print("wrote", rel[:-4] + ".wav (no ffmpeg)")


class OnePole:
    """Simple one-pole low-pass filter (coefficient 0..1)."""

    def __init__(self, k):
        self.k = k
        self.y = 0.0

    def __call__(self, x):
        self.y += (x - self.y) * self.k
        return self.y


def seamless(buf, fade_sec, rate):
    """Crossfades the tail into the head so the buffer loops without a click."""
    fade = int(rate * fade_sec)
    n = len(buf)
    for i in range(fade):
        a = i / fade
        buf[i] = buf[i] * a + buf[n - fade + i] * (1 - a)
    return buf[: n - fade]


def circular_delay(buf, delay_sec, feedback, mix, rate, lowpass=0.35):
    """Feedback delay that wraps around the loop, so echoes stay seamless."""
    n = len(buf)
    d = int(delay_sec * rate)
    out = list(buf)
    lp = OnePole(lowpass)
    tap = [0.0] * n
    for _ in range(2):  # two passes let the wrapped tail settle
        for i in range(n):
            j = (i - d) % n
            tap[i] = lp(out[j] * feedback + buf[j])
    return [buf[i] + tap[i] * mix for i in range(n)]


# --- SFX --------------------------------------------------------------------

def make_sfx():
    write("sfx/click.wav", tone(1400, 1100, 0.035, vol=0.22))
    write("sfx/tool_select.wav", concat(tone(700, 700, 0.03, vol=0.2), tone(1050, 1050, 0.04, vol=0.2)))
    write("sfx/cut.wav", noise(0.12, vol=0.35, lowpass=0.6, seed=2))
    write("sfx/burn.wav", mixdown(noise(0.18, vol=0.3, lowpass=0.8, seed=3), tone(180, 120, 0.18, vol=0.08)))
    write("sfx/clamp.wav", concat(tone(300, 200, 0.03, vol=0.35), tone(900, 900, 0.02, vol=0.2)))
    write("sfx/zap.wav", mixdown(tone(1800, 400, 0.12, vol=0.25), noise(0.1, vol=0.2, lowpass=0.9, seed=4)))
    write("sfx/stitch.wav", concat(tone(1200, 1200, 0.02, vol=0.25), silence(0.02), tone(800, 800, 0.03, vol=0.2)))
    write("sfx/implant_install.wav", concat(tone(160, 90, 0.08, vol=0.45), tone(880, 880, 0.06, vol=0.2), tone(1320, 1320, 0.12, sine, vol=0.25)))
    write("sfx/stage_complete.wav", concat(tone(660, 660, 0.06, sine, vol=0.25), tone(990, 990, 0.1, sine, vol=0.25)))
    write("sfx/mistake.wav", mixdown(tone(160, 110, 0.18, vol=0.3, release=0.8), noise(0.08, vol=0.15, lowpass=0.5, seed=12)))
    write("sfx/warning.wav", concat(tone(880, 880, 0.09, vol=0.22), silence(0.04), tone(660, 660, 0.09, vol=0.22)))
    write("sfx/surgery_success.wav", concat(*[tone(f, f, 0.09, sine, vol=0.25) for f in (523, 659, 784)], tone(1046, 1046, 0.35, sine, vol=0.3)))
    write("sfx/surgery_failure.wav", concat(*[tone(f, f * 0.97, 0.16, vol=0.22) for f in (392, 311, 233)], tone(155, 120, 0.4, vol=0.28)))
    write("sfx/customer_arrival.wav", concat(tone(220, 220, 0.12, sine, vol=0.3), silence(0.05), tone(330, 330, 0.16, sine, vol=0.25)))
    write("sfx/cash.wav", concat(tone(1568, 1568, 0.05, vol=0.18), tone(2093, 2093, 0.14, sine, vol=0.25)))
    write("sfx/level_up.wav", concat(*[tone(f, f, 0.07, vol=0.18) for f in (440, 554, 659, 880)], tone(1108, 1108, 0.3, sine, vol=0.25)))
    write("sfx/drill.wav", mixdown(concat(*[tone(240, 210, 0.025, vol=0.22) for _ in range(8)]), noise(0.2, vol=0.18, lowpass=0.5, seed=7)))
    write("sfx/glitch.wav", concat(tone(90, 60, 0.05, vol=0.3), noise(0.04, vol=0.25, lowpass=0.95, seed=8), tone(2400, 1800, 0.04, vol=0.15), noise(0.06, vol=0.2, lowpass=0.7, seed=9)))
    write("sfx/event.wav", concat(tone(392, 392, 0.08, sine, vol=0.25), tone(587, 587, 0.08, sine, vol=0.25), tone(523, 523, 0.18, sine, vol=0.22)))
    # Step 3 additions.
    write("sfx/monitor_beep.wav", tone(1000, 1000, 0.07, sine, vol=0.22, release=0.3))
    write("sfx/servo.wav", mixdown(tone(180, 420, 0.22, saw, vol=0.08, release=0.9), tone(360, 840, 0.22, tri, vol=0.06, release=0.9), noise(0.22, vol=0.05, lowpass=0.4, seed=21)))
    write("sfx/cyber_activate.wav", concat(tone(300, 1200, 0.12, tri, vol=0.2), mixdown(tone(1600, 1600, 0.25, sine, vol=0.15, release=0.4), tone(2400, 2400, 0.25, sine, vol=0.08, release=0.3))))
    write("sfx/critical.wav", mixdown(tone(980, 980, 1.1, sine, vol=0.22, release=0.95, attack=0.002), tone(70, 40, 0.6, sine, vol=0.5, release=0.6), noise(0.4, vol=0.2, lowpass=0.2, seed=31)))
    write("sfx/confirm.wav", concat(tone(880, 880, 0.04, sine, vol=0.22), tone(1320, 1320, 0.07, sine, vol=0.22)))
    write("sfx/back.wav", tone(900, 600, 0.05, sine, vol=0.2))
    write("sfx/denied.wav", concat(tone(140, 140, 0.08, square, vol=0.16), silence(0.03), tone(140, 120, 0.12, square, vol=0.16)))
    write("sfx/unlock.wav", concat(*[tone(f, f, 0.06, tri, vol=0.22) for f in (523, 784, 1046)], tone(1568, 1568, 0.3, sine, vol=0.22)))
    write("sfx/purchase.wav", concat(tone(600, 600, 0.03, square, vol=0.12), tone(1568, 1568, 0.05, sine, vol=0.2), tone(2093, 2093, 0.16, sine, vol=0.22)))
    write("sfx/heartbeat.wav", concat(tone(60, 45, 0.09, sine, vol=0.6, release=0.5), silence(0.08), tone(55, 40, 0.11, sine, vol=0.45, release=0.5)))
    write("sfx/spark.wav", concat(noise(0.03, vol=0.35, lowpass=0.95, seed=41), noise(0.05, vol=0.2, lowpass=0.9, seed=42)))
    write("sfx/hover.wav", tone(2600, 2400, 0.018, sine, vol=0.08, release=0.3))  # PC hover tick
    write("sfx/tutorial.wav", concat(tone(1046, 1046, 0.05, sine, vol=0.18), tone(1568, 1568, 0.09, sine, vol=0.18)))
    # Dialogue voice blip (pitched per character at runtime) and comms chime.
    write("sfx/voice.wav", mixdown(tone(210, 190, 0.045, square, vol=0.12, release=0.6), noise(0.03, vol=0.04, lowpass=0.3, seed=71)))
    write("sfx/comms.wav", concat(tone(1320, 1320, 0.03, sine, vol=0.15), silence(0.03), tone(990, 990, 0.03, sine, vol=0.12), silence(0.05), tone(1320, 1320, 0.06, sine, vol=0.15)))
    # One-shot ambient details (scheduled randomly by AudioManager).
    write("ambient/oneshots/drip.wav", concat(tone(1800, 900, 0.03, sine, vol=0.25, release=0.3), silence(0.15), tone(1500, 1000, 0.02, sine, vol=0.08)))
    write("ambient/oneshots/siren.wav", siren())
    write("ambient/oneshots/train.wav", train())
    write("ambient/oneshots/servo_far.wav", gain(mixdown(tone(200, 380, 0.5, saw, vol=0.06, release=0.9), noise(0.5, vol=0.04, lowpass=0.3, seed=51)), 0.8))
    write("ambient/oneshots/beep_far.wav", concat(tone(1200, 1200, 0.05, sine, vol=0.08), silence(0.12), tone(1200, 1200, 0.05, sine, vol=0.08)))


def siren():
    n = int(RATE * 3.0)
    out, ph = [], 0.0
    lp = OnePole(0.15)
    for i in range(n):
        t = i / RATE
        f = 600 + 250 * math.sin(TAU * 0.7 * t)
        ph += f / RATE
        a = math.sin(math.pi * i / n) ** 2 * 0.12
        out.append(lp(tri(ph)) * a)
    return out


def train():
    rng = random.Random(61)
    n = int(RATE * 4.0)
    out, lp, prev = [], OnePole(0.03), 0.0
    for i in range(n):
        t = i / RATE
        clack = 0.6 if (t * 3.1) % 1.0 < 0.03 else 0.0
        prev = lp(rng.uniform(-1, 1) + clack)
        a = math.sin(math.pi * i / n) ** 1.5
        out.append(prev * 0.9 * a)
    return normalize(out, 0.35)


# --- Ambience layers (seamless loops) ---------------------------------------

def layer_hum(dur=8.0):
    rng = random.Random(9)
    n = int(MUSIC_RATE * (dur + 0.5))
    lp = OnePole(0.004)
    out = []
    for i in range(n):
        t = i / MUSIC_RATE
        hum = 0.10 * math.sin(TAU * 50 * t) + 0.05 * math.sin(TAU * 100 * t) + 0.02 * math.sin(TAU * 150 * t)
        out.append(hum * (0.85 + 0.15 * math.sin(TAU * 0.25 * t)) + lp(rng.uniform(-1, 1)) * 0.5)
    return seamless(out, 0.5, MUSIC_RATE)


def layer_vent(dur=10.0):
    rng = random.Random(10)
    n = int(MUSIC_RATE * (dur + 0.8))
    lp1, lp2 = OnePole(0.05), OnePole(0.02)
    out = []
    for i in range(n):
        t = i / MUSIC_RATE
        swell = 0.75 + 0.25 * math.sin(TAU * 0.1 * t) + 0.08 * math.sin(TAU * 1.3 * t)
        out.append((lp1(rng.uniform(-1, 1)) * 0.8 + lp2(rng.uniform(-1, 1)) * 1.2) * swell)
    return normalize(seamless(out, 0.8, MUSIC_RATE), 0.35)


def layer_crt(dur=6.0):
    rng = random.Random(11)
    n = int(MUSIC_RATE * (dur + 0.3))
    out = []
    for i in range(n):
        t = i / MUSIC_RATE
        buzz = 0.03 * saw(60 * t) + 0.02 * math.sin(TAU * 120 * t)
        crackle = rng.uniform(-1, 1) * 0.25 if rng.random() < 0.0015 else 0.0
        out.append(buzz + crackle)
    return seamless(out, 0.3, MUSIC_RATE)


def layer_city(dur=12.0):
    """Distant city through concrete: low rumble, rain hiss, far traffic swells."""
    rng = random.Random(12)
    n = int(MUSIC_RATE * (dur + 1.0))
    rumble, hiss_hp, hiss_lp = OnePole(0.004), OnePole(0.6), OnePole(0.9)
    out = []
    for i in range(n):
        t = i / MUSIC_RATE
        r = rumble(rng.uniform(-1, 1)) * 6.0
        w = rng.uniform(-1, 1)
        rain = (hiss_lp(w) - hiss_hp(w)) * 0.12
        swell = 0.6 + 0.4 * math.sin(TAU * t / 6.0) ** 2
        out.append(r * swell + rain)
    return normalize(seamless(out, 1.0, MUSIC_RATE), 0.4)


def layer_pump(dur=12.0):
    """Pump station through the wall: slow heavy thumps, pipe groan, metal ticks."""
    rng = random.Random(13)
    rate = MUSIC_RATE
    n = int(rate * (dur + 0.6))
    out = [0.0] * n
    lp = OnePole(0.01)
    for i in range(n):
        out[i] = lp(rng.uniform(-1, 1)) * 0.6
    period = 1.6
    t = 0.2
    while t < dur:
        start = int(t * rate)
        for i in range(int(0.35 * rate)):
            if start + i < n:
                f = 48 - 18 * i / (0.35 * rate)
                out[start + i] += math.sin(TAU * f * i / rate) * 0.55 * math.exp(-i / (0.09 * rate))
        t += period
    for _ in range(int(dur * 0.8)):
        start = rng.randrange(n - int(0.05 * rate))
        f = rng.choice([1900, 2600, 3300])
        for i in range(int(0.04 * rate)):
            out[start + i] += math.sin(TAU * f * i / rate) * 0.05 * math.exp(-i / (0.006 * rate))
    groan_ph = 0.0
    for i in range(n):
        tt = i / rate
        f = 70 + 12 * math.sin(TAU * tt / 7.0)
        groan_ph += f / rate
        out[i] += saw(groan_ph) * 0.03 * (0.5 + 0.5 * math.sin(TAU * tt / 5.0)) ** 4
    return normalize(seamless(out, 0.6, rate), 0.4)


def make_ambience():
    write_ogg("ambient/pump.ogg", layer_pump())
    write_ogg("ambient/hum.ogg", layer_hum())
    write_ogg("ambient/vent.ogg", layer_vent())
    write_ogg("ambient/crt.ogg", layer_crt())
    write_ogg("ambient/city.ogg", layer_city())


# --- Music ------------------------------------------------------------------

def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def render_music(bpm, bars, chords, arp, bass_pattern, pulse=False, detune=0.0, seed=1, pad_vol=0.18, arp_vol=0.09):
    """Renders a loop: warm pad chords, sub bass, sparse plucked arpeggio,
    optional heartbeat pulse; circular delay keeps it seamless."""
    rate = MUSIC_RATE
    beat = 60.0 / bpm
    bar_len = beat * 4
    n = int(rate * bar_len * bars)
    buf = [0.0] * n
    rng = random.Random(seed)
    # Pads: detuned saws through a slow low-pass, one chord per bar.
    for b in range(bars):
        chord = chords[b % len(chords)]
        start = int(b * bar_len * rate)
        length = int(bar_len * rate)
        for note in chord:
            for dt in (-0.12 - detune, 0.12 + detune):
                f = midi(note) * 2 ** (dt / 12)
                lp = OnePole(0.06)
                ph = rng.random()
                for i in range(length + int(0.4 * rate)):
                    k = (start + i) % n
                    x = i / length
                    a = min(1.0, x * 6) * (1.0 if x < 1.0 else max(0.0, 1.0 - (x - 1.0) * 2.5))
                    ph += f / rate
                    buf[k] += lp(saw(ph)) * pad_vol * a / len(chord)
    # Sub bass.
    for b in range(bars):
        root = chords[b % len(chords)][0] - 12
        for step, on in enumerate(bass_pattern):
            if not on:
                continue
            start = int((b * bar_len + step * beat / 2) * rate)
            length = int(beat / 2 * rate * 0.9)
            ph = 0.0
            for i in range(length):
                ph += midi(root) / rate
                buf[(start + i) % n] += math.sin(ph * TAU) * 0.22 * env(i, length, attack=0.02, release=0.7)
    # Plucked arpeggio (16ths, sparse).
    for b in range(bars):
        chord = chords[b % len(chords)]
        for step in range(16):
            if arp[step % len(arp)] == 0 or rng.random() < 0.15:
                continue
            note = chord[(arp[step % len(arp)] - 1) % len(chord)] + 12
            start = int((b * bar_len + step * beat / 4) * rate)
            length = int(0.35 * rate)
            ph, lp = 0.0, OnePole(0.25)
            for i in range(length):
                ph += midi(note) / rate
                buf[(start + i) % n] += lp(square(ph)) * arp_vol * math.exp(-i / (0.08 * rate))
    # Heartbeat pulse for tension.
    if pulse:
        for bt in range(bars * 4):
            for off, amp in ((0.0, 0.5), (0.18, 0.35)):
                start = int((bt * beat + off) * rate)
                length = int(0.12 * rate)
                for i in range(length):
                    f = 55 - 20 * i / length
                    buf[(start + i) % n] += math.sin(TAU * f * i / rate) * amp * 0.5 * math.exp(-i / (0.04 * rate))
    buf = circular_delay(buf, beat * 0.75, 0.35, 0.35, rate)
    return normalize(buf, 0.85)


def render_industrial(bpm, bars, roots, seed=1, clank=None, kick=None, drone_vol=0.22, bell=None):
    """Dark, minimal industrial loop: a low two-oscillator drone that shifts
    root every two bars, sparse metal clanks (noise through a ringing comb),
    a muffled kick like a press in another room and a distant detuned bell."""
    rate = MUSIC_RATE
    beat = 60.0 / bpm
    bar_len = beat * 4
    n = int(rate * bar_len * bars)
    buf = [0.0] * n
    rng = random.Random(seed)
    clank = clank or [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0]
    kick = kick or [1, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0]
    # Drone
    ph1 = ph2 = 0.0
    lp = OnePole(0.02)
    for i in range(n):
        t = i / rate
        root = roots[int(t / (bar_len * 2)) % len(roots)]
        f = midi(root - 24)
        ph1 += f / rate
        ph2 += f * 1.005 / rate
        swell = 0.7 + 0.3 * math.sin(TAU * t / (bar_len * 2))
        buf[i] += lp(saw(ph1) + saw(ph2) * 0.8) * drone_vol * swell
    # Kick / press
    for b in range(bars):
        for step, on in enumerate(kick):
            if not on:
                continue
            start = int((b * bar_len + step * beat / 4) * rate)
            for i in range(int(0.3 * rate)):
                f = 60 - 30 * i / (0.3 * rate)
                buf[(start + i) % n] += math.sin(TAU * f * i / rate) * 0.45 * math.exp(-i / (0.07 * rate))
    # Metal clanks: noise burst into a short comb delay (rings like a pipe).
    for b in range(bars):
        for step, on in enumerate(clank):
            if not on or rng.random() < 0.25:
                continue
            start = int((b * bar_len + step * beat / 4) * rate)
            length = int(0.4 * rate)
            delay = int(rate / rng.choice([620, 840, 1130]))
            burst = [rng.uniform(-1, 1) * math.exp(-i / (0.004 * rate)) for i in range(length)]
            for i in range(delay, length):
                burst[i] += burst[i - delay] * 0.92
            amp = rng.uniform(0.05, 0.1)
            for i in range(length):
                buf[(start + i) % n] += burst[i] * amp * math.exp(-i / (0.15 * rate))
    # Distant bell on bar starts.
    for b in range(0, bars, 2):
        note = (bell or roots)[(b // 2) % len(bell or roots)] + 12
        start = int(b * bar_len * rate)
        for i in range(int(2.5 * rate)):
            t = i / rate
            v = math.sin(TAU * midi(note) * t) + 0.5 * math.sin(TAU * midi(note) * 2.76 * t)
            buf[(start + i) % n] += v * 0.035 * math.exp(-t / 0.9)
    buf = circular_delay(buf, beat * 1.5, 0.45, 0.4, rate, lowpass=0.2)
    return normalize(buf, 0.8)


def make_music():
    # Clinic: dark minimal industrial (A / F / D / E roots).
    write_ogg("music/clinic.ogg", render_industrial(66, 8, [57, 53, 50, 52], seed=3))
    # Surgery: tense pulse (Dm - Bb - Gm - A).
    write_ogg("music/surgery.ogg", render_music(96, 8, [[50, 53, 57], [46, 50, 53], [43, 46, 50], [45, 49, 52]],
                                                [1, 0, 2, 0, 3, 0, 2, 0, 1, 0, 2, 0, 3, 0, 2, 3], [1, 0, 1, 0, 1, 0, 1, 0], pulse=True, seed=5, pad_vol=0.14, arp_vol=0.07))
    # Black market: industrial, heavier press, tritone roots.
    write_ogg("music/market.ogg", render_industrial(80, 8, [48, 54, 48, 44], seed=7,
                                                    clank=[1, 0, 0, 1, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0],
                                                    kick=[1, 0, 0, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0]))
    # Conversations: almost nothing - a drone and a bell.
    write_ogg("music/dialogue.ogg", render_industrial(56, 8, [45, 41, 43, 40], seed=11, clank=[0] * 16,
                                                      kick=[0] * 16, drone_vol=0.16))


def main(groups):
    if "sfx" in groups:
        make_sfx()
    if "ambience" in groups:
        make_ambience()
    if "music" in groups:
        make_music()


if __name__ == "__main__":
    main(sys.argv[1:] or ["sfx", "ambience", "music"])
