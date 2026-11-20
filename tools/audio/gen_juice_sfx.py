"""Synthesize the "juice" cues: shell casings, kill confirms, heartbeat,
splashes, suit-breach beep, surface footsteps.

Run from the repo root:  python tools/audio/gen_juice_sfx.py   (numpy only)
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join("assets", "audio", "sfx")


def t_axis(seconds):
    return np.arange(int(SR * seconds)) / SR


def lowpass(x, cutoff):
    a = np.exp(-2.0 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1.0 - a) * v + a * acc
        y[i] = acc
    return y


def env(t, decay, start=0.0):
    e = np.exp(-np.maximum(t - start, 0.0) / decay)
    e[t < start] = 0.0
    return e


def finish(x, peak=0.85, fade=0.02):
    n = int(SR * fade)
    if n and x.size > n:
        x[-n:] *= np.linspace(1.0, 0.0, n)
    m = np.max(np.abs(x))
    return x / m * peak if m > 0 else x


def write(name, x):
    os.makedirs(OUT, exist_ok=True)
    pcm = (np.clip(x, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("wrote", name, f"{x.size / SR:.2f}s")


def casing(seed):
    """Brass shell hitting asphalt: two or three bright pings, decaying."""
    rng = np.random.default_rng(seed)
    t = t_axis(0.45)
    x = np.zeros_like(t)
    at = 0.0
    for bounce in range(3):
        f = rng.uniform(3800, 5200)
        amp = 0.9 * (0.45 ** bounce)
        x += (np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 1.51 * t)) * env(t, 0.03, at) * amp
        x += rng.standard_normal(t.size) * env(t, 0.002, at) * amp * 0.4
        at += rng.uniform(0.07, 0.12) * (0.7 ** bounce)
    return finish(x, 0.7)


def kill_confirm():
    t = t_axis(0.22)
    f = 1400 - 600 * np.minimum(t / 0.12, 1.0)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(t, 0.06)
    x += np.sin(2 * np.pi * 2800 * t) * env(t, 0.015) * 0.4
    return finish(x, 0.7)


def multikill():
    t = t_axis(0.5)
    x = np.zeros_like(t)
    for i, f in enumerate([880, 1175, 1568]):
        x += np.sin(2 * np.pi * f * t) * env(t, 0.12, i * 0.07) * 0.6
    return finish(x, 0.75)


def heartbeat():
    """One lub-dub, about 0.85 s, made to loop."""
    t = t_axis(0.85)
    x = np.zeros_like(t)
    for at, amp in [(0.0, 1.0), (0.22, 0.75)]:
        f = 60 - 25 * np.minimum(np.maximum(t - at, 0) / 0.08, 1)
        x += np.sin(2 * np.pi * np.cumsum(f) / SR) * env(t, 0.06, at) * amp
    return finish(lowpass(x, 300), 0.9, 0.0)


def splash(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(0.35)
    noise = rng.standard_normal(t.size)
    x = lowpass(noise, 2400) * env(t, 0.06) - lowpass(noise, 300) * env(t, 0.06)
    x += np.sin(2 * np.pi * np.cumsum(500 + 900 * np.exp(-t * 30)) / SR) * env(t, 0.04, 0.01) * 0.25
    return finish(x, 0.6)


def suit_beep():
    t = t_axis(0.16)
    x = np.sign(np.sin(2 * np.pi * 1250 * t)) * 0.35 * env(t, 0.08)
    return finish(lowpass(x, 5000), 0.55)


def step(seed, cutoff, decay, body):
    rng = np.random.default_rng(seed)
    t = t_axis(0.2)
    noise = rng.standard_normal(t.size)
    x = lowpass(noise, cutoff) * env(t, decay)
    x += np.sin(2 * np.pi * body * t) * env(t, 0.03) * 0.5
    return finish(x, 0.5)


if __name__ == "__main__":
    for i in range(3):
        write(f"casing_{i}", casing(100 + i))
    write("kill_confirm", kill_confirm())
    write("multikill", multikill())
    write("heartbeat", heartbeat())
    for i in range(2):
        write(f"splash_{i}", splash(200 + i))
    write("suit_beep", suit_beep())
    for i in range(2):
        write(f"step_grass_{i}", step(300 + i, 1800, 0.05, 90))
        write(f"step_wood_{i}", step(400 + i, 900, 0.025, 160))
