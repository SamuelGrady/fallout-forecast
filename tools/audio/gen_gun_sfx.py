"""Synthesize the gun sounds (gunpowder reports, impacts, mechanics).

Each report is layered the way a real shot is heard: a sharp supersonic
crack, the muzzle-blast body, a low chest thump, a short mechanical click,
and an outdoor tail with slapback echoes off buildings. Soft saturation glues
the layers. Output: 44.1 kHz mono 16-bit WAVs in assets/audio/sfx/.

Run from the repository root:  python tools/audio/gen_gun_sfx.py
Only needs numpy. Seeds are fixed, so the output is reproducible.
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


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bandpass(x, low, high):
    return lowpass(highpass(x, low), high)


def env(t, decay, start=0.0):
    e = np.exp(-np.maximum(t - start, 0.0) / decay)
    e[t < start] = 0.0
    return e


def sweep(t, f0, f1, glide):
    """Sine whose pitch falls from f0 to f1 over `glide` seconds."""
    freq = f1 + (f0 - f1) * np.exp(-t / glide)
    return np.sin(2.0 * np.pi * np.cumsum(freq) / SR)


def delay(x, seconds, gain, cutoff):
    n = int(SR * seconds)
    out = np.zeros_like(x)
    out[n:] = lowpass(x[:-n], cutoff) * gain
    return out


def finish(x, drive=2.2, fade=0.05):
    x = np.tanh(x * drive)
    n = int(SR * fade)
    x[-n:] *= np.linspace(1.0, 0.0, n)
    return x / np.max(np.abs(x)) * 0.89  # about -1 dBFS


def report(seed, length, crack_decay, crack_hp, body_decay, body_lp, thump, tail_decay, tail_lp, echoes, mech_at=None, crack_gain=1.0, body_gain=0.9, thump_gain=0.9, tail_gain=0.18):
    rng = np.random.default_rng(seed)
    t = t_axis(length)
    noise = rng.standard_normal(t.size)
    crack = highpass(noise, crack_hp) * env(t, crack_decay) * crack_gain
    body = lowpass(noise, body_lp) * env(t, body_decay) * body_gain
    f0, f1, glide, thump_decay = thump
    low = sweep(t, f0, f1, glide) * env(t, thump_decay) * thump_gain
    tail = lowpass(rng.standard_normal(t.size), tail_lp) * env(t, tail_decay, 0.006) * tail_gain
    x = crack + body + low + tail
    if mech_at is not None:
        click = bandpass(rng.standard_normal(t.size), 2500, 6500) * env(t, 0.0012, mech_at) * 0.35
        ring = (np.sin(2 * np.pi * 2900 * t) + 0.6 * np.sin(2 * np.pi * 4400 * t)) * env(t, 0.012, mech_at) * 0.06
        x += click + ring
    dry = x.copy()
    for at, gain, cutoff in echoes:
        x += delay(dry, at, gain, cutoff)
    return finish(x)


def impact(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(0.22)
    noise = rng.standard_normal(t.size)
    thud = lowpass(noise, 700) * env(t, 0.03) * 1.2
    body = sweep(t, 190, 80, 0.03) * env(t, 0.045) * 0.8
    squelch = bandpass(noise, 900, 2400) * env(t, 0.018, 0.004) * 0.45
    tick = highpass(noise, 4000) * env(t, 0.0015) * 0.3
    return finish(thud + body + squelch + tick, drive=1.8, fade=0.03)


def clack(t, rng, at, pitch=1.0, gain=1.0):
    click = bandpass(rng.standard_normal(t.size), 1800 * pitch, 5200 * pitch) * env(t, 0.004, at)
    ring = (np.sin(2 * np.pi * 2300 * pitch * t) + 0.7 * np.sin(2 * np.pi * 3700 * pitch * t)) * env(t, 0.02, at) * 0.18
    knock = sweep(np.maximum(t - at, 0), 420 * pitch, 160 * pitch, 0.01) * env(t, 0.015, at) * 0.4
    return (click + ring + knock) * gain


def pump(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(0.42)
    slide = bandpass(rng.standard_normal(t.size), 600, 2600) * (env(t, 0.06, 0.02) - env(t, 0.006, 0.02)) * 0.12
    x = clack(t, rng, 0.0, 0.9, 1.0) + slide + clack(t, rng, 0.17, 1.05, 1.15)
    return finish(x, drive=1.6, fade=0.04)


def mag_swap(seed):
    rng = np.random.default_rng(seed)
    t = t_axis(0.95)
    x = clack(t, rng, 0.0, 0.8, 0.7)  # mag out
    x += clack(t, rng, 0.42, 0.9, 1.0)  # mag seated
    x += clack(t, rng, 0.72, 1.15, 0.9) + clack(t, rng, 0.8, 1.25, 1.1)  # bolt back, forward
    return finish(x, drive=1.6, fade=0.05)


def write(name, x):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    pcm = (np.clip(x, -1.0, 1.0) * 32767).astype("<i2")
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    print("wrote", path, f"{x.size / SR:.2f}s")


if __name__ == "__main__":
    street = [(0.13, 0.28, 1600), (0.29, 0.13, 1000)]
    write("gun_rifle", report(11, 0.85, 0.0025, 2200, 0.035, 2600, (150, 55, 0.02, 0.05), 0.24, 800, street, mech_at=0.016))
    write("gun_shotgun", report(23, 1.35, 0.004, 1600, 0.07, 1800, (115, 38, 0.035, 0.12), 0.45, 600,
                                [(0.16, 0.32, 1200), (0.34, 0.16, 800)], crack_gain=1.1, body_gain=1.1, thump_gain=1.25, tail_gain=0.24))
    write("gun_revolver", report(37, 1.1, 0.003, 2000, 0.05, 2200, (125, 45, 0.03, 0.08), 0.38, 700,
                                 [(0.15, 0.3, 1300), (0.31, 0.14, 900)], thump_gain=1.05, tail_gain=0.2))
    rng = np.random.default_rng(41)
    t = t_axis(1.0)
    pop = report(41, 1.0, 0.002, 2500, 0.03, 1500, (95, 50, 0.02, 0.06), 0.3, 500, street, crack_gain=0.6, thump_gain=1.1)
    hiss = bandpass(rng.standard_normal(t.size), 2500, 8000) * env(t, 0.45, 0.02) * 0.22
    write("gun_flare", finish(pop + hiss, drive=1.4))
    write("hit_flesh", impact(53))
    write("shotgun_pump", pump(61))
    write("rifle_reload", mag_swap(71))
