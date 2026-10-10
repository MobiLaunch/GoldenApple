#!/usr/bin/env python3
"""CitronOS's own sounds, synthesized (no samples, nothing borrowed): the
alert sounds to choose from in Settings › Sound and the chime when power is
connected. Writes apps/lib/assets/sounds/*.wav (the shell reaches them through ui/) (48 kHz, 16-bit mono).

    python3 design/sounds.py

Each is a few sine partials (a struck glass or bell has inharmonic ones)
with a fast attack and an exponential ring-out, then faded at the end so
it never clicks."""
from __future__ import annotations

import math
from pathlib import Path
import struct
import wave

RATE = 48000
OUT = Path(__file__).resolve().parents[1] / "apps/lib/assets/sounds"


def tone(partials, length, attack=0.004, at=0.0):
    """partials: (frequency Hz, amplitude, decay seconds); `at` delays it."""
    n = int(RATE * (length + at))
    out = [0.0] * n
    start = int(RATE * at)
    for i in range(start, n):
        t = (i - start) / RATE
        env = min(1.0, t / attack)
        s = 0.0
        for f, a, d in partials:
            s += a * math.exp(-t / d) * math.sin(2 * math.pi * f * t)
        out[i] = env * s
    return out


def mix(*parts):
    n = max(len(p) for p in parts)
    return [sum(p[i] for p in parts if i < len(p)) for i in range(n)]


def write(name, samples, peak=0.55):
    top = max(abs(s) for s in samples) or 1.0
    fade = int(RATE * 0.02)
    data = bytearray()
    for i, s in enumerate(samples):
        g = min(1.0, (len(samples) - i) / fade)
        data += struct.pack("<h", int(max(-1.0, min(1.0, s / top * peak * g)) * 32767))
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(data))


def glass(f):
    # A struck glass: the fundamental and the slightly sharp upper modes.
    return [(f, 1.0, 0.32), (f * 2.76, 0.32, 0.12), (f * 5.40, 0.10, 0.05)]


SOUNDS = {
    # The default: two glassy notes a fourth apart, close together.
    "Crystal": lambda: mix(tone(glass(1318.5), 0.55), tone(glass(1760.0), 0.6, at=0.085)),
    "Ping": lambda: tone([(1567.98, 1.0, 0.45), (3135.96, 0.18, 0.12)], 0.9),
    "Pebble": lambda: tone([(880.0, 1.0, 0.07), (1760.0, 0.25, 0.03), (2640.0, 0.1, 0.02)], 0.25),
    "Bubble": lambda: mix(tone([(698.46, 1.0, 0.08)], 0.2), tone([(1046.5, 0.9, 0.09)], 0.25, at=0.06)),
    "Breeze": lambda: mix(tone([(523.25, 0.7, 0.5), (1046.5, 0.25, 0.3)], 1.0, attack=0.06),
                          tone([(783.99, 0.6, 0.5)], 0.9, attack=0.06, at=0.12)),
    "Chord": lambda: mix(*(tone(glass(f), 0.9, at=k * 0.03) for k, f in enumerate((1046.5, 1318.5, 1567.98)))),
    # Power connected: a soft rising pair, low and short.
    "Charging": lambda: mix(tone([(659.25, 1.0, 0.18), (1318.5, 0.2, 0.08)], 0.35),
                            tone([(987.77, 1.0, 0.22), (1975.5, 0.2, 0.09)], 0.45, at=0.09)),
}

if __name__ == "__main__":
    for name, make in SOUNDS.items():
        write(name, make(), peak=0.42 if name == "Charging" else 0.55)
    print("sounds:", ", ".join(SOUNDS))
