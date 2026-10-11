"""Generates the procedural spell sound effects used by Elemental Duel.

Run: python tools/gen_sfx.py   (writes assets/audio/spells/*.wav)
All output is original, synthesized audio (no third-party samples).
"""
import math
import random
import struct
import wave
from pathlib import Path

RATE = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "spells"
random.seed(7)


def write(name, samples):
    OUT.mkdir(parents=True, exist_ok=True)
    peak = max(1e-6, max(abs(s) for s in samples))
    scale = 0.9 / peak
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * scale)) * 32767)) for s in samples))


def env(t, dur, attack=0.01, release=None):
    release = dur * 0.6 if release is None else release
    if t < attack:
        return t / attack
    if t > dur - release:
        return max(0.0, (dur - t) / release)
    return 1.0


class LowPass:
    def __init__(self):
        self.y = 0.0

    def __call__(self, x, a):
        self.y += a * (x - self.y)
        return self.y


def noise_sweep(dur, a0, a1, amp_fn=None):
    lp = LowPass()
    lp2 = LowPass()
    n = int(dur * RATE)
    out = []
    for i in range(n):
        t = i / RATE
        k = t / dur
        a = a0 + (a1 - a0) * k
        s = lp2(lp(random.uniform(-1, 1), a), a)
        out.append(s * (amp_fn(t) if amp_fn else env(t, dur)))
    return out


def tone(dur, f0, f1, wave_fn=math.sin, vib=0.0, amp_fn=None):
    n = int(dur * RATE)
    out = []
    ph = 0.0
    for i in range(n):
        t = i / RATE
        f = f0 * (f1 / f0) ** (t / dur)
        f *= 1 + vib * math.sin(t * 40)
        ph += 2 * math.pi * f / RATE
        out.append(wave_fn(ph) * (amp_fn(t) if amp_fn else env(t, dur)))
    return out


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] if i < len(t) else 0 for t in tracks) for i in range(n)]


def gain(track, g):
    return [s * g for s in track]


def square(ph):
    return 1.0 if math.sin(ph) > 0 else -1.0


def saw(ph):
    return ((ph / math.pi) % 2) - 1


# Fire cast: roaring whoosh
write("fire_cast", mix(noise_sweep(0.5, 0.05, 0.25), gain(tone(0.5, 120, 70, saw), 0.25)))
# Explosion: low boom with crackle
boom = noise_sweep(1.1, 0.12, 0.01, lambda t: math.exp(-t * 4.5))
crack = [random.uniform(-1, 1) * math.exp(-t / RATE * 12) * 0.4 for t in range(int(0.4 * RATE))]
write("explosion", mix(boom, gain(tone(0.8, 90, 35, amp_fn=lambda t: math.exp(-t * 5)), 0.8), crack))
# Water: bubbly splash
water = noise_sweep(0.45, 0.4, 0.08)
bub = []
for b in range(6):
    start = int(random.uniform(0, 0.25) * RATE)
    f = random.uniform(500, 1100)
    seg = tone(0.08, f, f * 1.8, amp_fn=lambda t: math.exp(-t * 40))
    bub.append([0] * start + seg)
write("water_cast", mix(gain(water, 0.8), *[gain(b, 0.35) for b in bub]))
write("splash", mix(noise_sweep(0.6, 0.5, 0.05, lambda t: math.exp(-t * 6)), *[gain(b, 0.3) for b in bub]))
# Wind: airy sweep up then down
write("wind_cast", noise_sweep(0.8, 0.02, 0.35, lambda t: math.sin(math.pi * t / 0.8) ** 2))
# Earth: rumble + crunch
rumble = gain(tone(0.9, 60, 40, saw, amp_fn=lambda t: env(t, 0.9, 0.05)), 0.6)
grit = noise_sweep(0.9, 0.06, 0.03, lambda t: env(t, 0.9, 0.05) * (0.6 + 0.4 * math.sin(t * 60)))
write("earth_cast", mix(rumble, grit))
# Lightning: zap + thunder crack
zap = tone(0.35, 2400, 300, square, vib=0.3, amp_fn=lambda t: math.exp(-t * 8))
thunder = noise_sweep(1.2, 0.5, 0.01, lambda t: math.exp(-t * 3))
write("thunder", mix(gain(zap, 0.35), thunder))
write("zap", mix(gain(zap, 0.6), noise_sweep(0.3, 0.6, 0.2, lambda t: math.exp(-t * 14))))
# Warning hum for incoming strikes
write("charge", tone(0.6, 200, 900, saw, amp_fn=lambda t: env(t, 0.6, 0.3, 0.1) * 0.6))
# Teleport: sci-fi sweep
write("teleport", mix(tone(0.45, 300, 1800, amp_fn=lambda t: env(t, 0.45, 0.02, 0.3)),
                      gain(tone(0.45, 450, 2700, amp_fn=lambda t: env(t, 0.45, 0.02, 0.3)), 0.5),
                      gain(noise_sweep(0.45, 0.3, 0.6), 0.3)))
# Shield / buff chime
write("buff", mix(*[gain([0] * int(i * 0.07 * RATE) + tone(0.6, f, f, amp_fn=lambda t: math.exp(-t * 5)), 0.5)
                    for i, f in enumerate([523, 659, 784, 1046])]))
# Element select blips (one per element)
for name, f in [("fire", 440), ("water", 523), ("earth", 349), ("wind", 659), ("lightning", 784)]:
    write(f"elem_{name}", mix(tone(0.12, f, f * 1.05, amp_fn=lambda t: math.exp(-t * 25)),
                              gain(tone(0.12, f * 2, f * 2, amp_fn=lambda t: math.exp(-t * 30)), 0.3)))
# Fizzle (not enough mana / cooldown)
write("fizzle", gain(tone(0.25, 220, 110, square, amp_fn=lambda t: math.exp(-t * 10)), 0.5))
# Hurt grunt-ish thud
write("hurt", mix(tone(0.25, 160, 80, amp_fn=lambda t: math.exp(-t * 14)),
                  noise_sweep(0.2, 0.2, 0.05, lambda t: math.exp(-t * 20))))
# Round fanfare / defeat
fan = []
for i, f in enumerate([392, 523, 659, 784]):
    fan.append([0] * int(i * 0.12 * RATE) + tone(0.5 if i < 3 else 0.9, f, f, saw, amp_fn=lambda t: math.exp(-t * 3)))
write("victory", mix(*fan))
lose = []
for i, f in enumerate([392, 349, 311, 262]):
    lose.append([0] * int(i * 0.18 * RATE) + tone(0.5 if i < 3 else 1.0, f, f, saw, amp_fn=lambda t: math.exp(-t * 3)))
write("defeat", mix(*lose))
write("countdown", tone(0.15, 880, 880, amp_fn=lambda t: math.exp(-t * 18)))
write("fight", mix(tone(0.5, 660, 990, saw, amp_fn=lambda t: math.exp(-t * 4)), gain(noise_sweep(0.5, 0.3, 0.05), 0.5)))
print("wrote", len(list(OUT.glob("*.wav"))), "files to", OUT)
