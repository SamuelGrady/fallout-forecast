"""Synthesize the VCR sounds for the title screen.

- vcr_insert: the cassette shoved into the slot: plastic scrape, then the
  loading carriage grabbing it with a heavy clunk.
- vcr_whirr: the drum spinning up and the tape threading (motor whine that
  rises, gear chatter, a soft latch at the end).
- vcr_ff: a short fast-forward squeal for menu transitions.
- vcr_eject: motor run, then the cassette popping back out.

Output: 44.1 kHz mono 16-bit WAVs in assets/audio/sfx/.
Run from the repository root:  python tools/audio/gen_vcr_sfx.py
Only needs numpy. Seeds are fixed, so the output is reproducible.
"""
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join("assets", "audio", "sfx")
rng = np.random.default_rng(1987)


def t_axis(seconds):
    return np.arange(int(SR * seconds)) / SR


def lowpass(x, cutoff):
    # One-pole low-pass, vectorised enough for short clips.
    a = np.exp(-2.0 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc = (1.0 - a) * v + a * acc
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def env(t, decay, start=0.0):
    e = np.exp(-np.maximum(t - start, 0.0) / decay)
    e[t < start] = 0.0
    return e


def tone(freq):
    """Sine with a per-sample frequency array."""
    return np.sin(2.0 * np.pi * np.cumsum(freq) / SR)


def clunk(t, start, weight=1.0):
    """A plastic-and-metal latch: click transient, body knock, low thud."""
    noise = rng.standard_normal(t.size)
    click = highpass(noise, 2500.0) * env(t, 0.004, start) * 0.9
    knock = np.sin(2.0 * np.pi * 310.0 * (t - start)) * env(t, 0.03, start) * 0.6
    thud = np.sin(2.0 * np.pi * 70.0 * (t - start)) * env(t, 0.09, start) * weight
    rattle = lowpass(noise, 1800.0) * env(t, 0.05, start + 0.012) * 0.35
    return click + knock + thud + rattle


def motor(t, f0, f1, rise):
    """Small DC motor: a whine with harmonics and a little speed flutter."""
    freq = f1 + (f0 - f1) * np.exp(-t / rise)
    freq = freq * (1.0 + 0.01 * np.sin(2.0 * np.pi * 7.0 * t))
    s = tone(freq) * 0.5 + tone(freq * 2.0) * 0.25 + tone(freq * 3.01) * 0.12
    return s


def finish(x, peak=0.85):
    x = np.tanh(x * 1.4)
    fade = int(SR * 0.01)
    x[-fade:] *= np.linspace(1.0, 0.0, fade)
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def write(name, x):
    os.makedirs(OUT, exist_ok=True)
    data = (np.clip(x, -1.0, 1.0) * 32767.0).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print("wrote", name, f"{x.size / SR:.2f}s")


def insert():
    t = t_axis(0.55)
    noise = rng.standard_normal(t.size)
    # Scrape of the shell on the flap for the first 0.12 s.
    scrape = lowpass(highpass(noise, 900.0), 4000.0) * np.clip(t / 0.02, 0, 1) * env(t, 0.06) * 0.3
    x = scrape + clunk(t, 0.11, 1.2) + clunk(t, 0.19, 0.5) * 0.5
    return finish(x)


def whirr():
    t = t_axis(1.25)
    m = motor(t, 60.0, 190.0, 0.35) * np.clip(t / 0.08, 0, 1) * np.clip((1.2 - t) / 0.25, 0, 1) * 0.35
    # Gear chatter: little ticks that speed up with the motor.
    ticks = np.zeros_like(t)
    noise = rng.standard_normal(t.size)
    pos = 0.05
    while pos < 1.05:
        ticks += highpass(noise, 3000.0) * env(t, 0.003, pos) * 0.25
        pos += 0.09 * np.exp(-pos * 1.3) + 0.03
    hiss = lowpass(highpass(noise, 1500.0), 6000.0) * 0.04 * np.clip(t / 0.3, 0, 1)
    x = m + ticks + hiss + clunk(t, 1.08, 0.4) * 0.45
    return finish(x, 0.7)


def ff():
    t = t_axis(0.32)
    freq = 900.0 + 1400.0 * (t / t[-1])
    squeal = tone(freq) * 0.25 + tone(freq * 1.5) * 0.1
    noise = rng.standard_normal(t.size)
    hiss = highpass(noise, 2000.0) * 0.18
    shape = np.clip(t / 0.03, 0, 1) * np.clip((t[-1] - t) / 0.08, 0, 1)
    x = (squeal + hiss + motor(t, 220.0, 260.0, 0.1) * 0.2) * shape
    return finish(x, 0.6)


def eject():
    t = t_axis(0.9)
    m = motor(t, 200.0, 120.0, 0.3) * np.clip(t / 0.05, 0, 1) * np.clip((0.55 - t) / 0.1, 0, 1) * 0.35
    noise = rng.standard_normal(t.size)
    pop = lowpass(noise, 2500.0) * env(t, 0.05, 0.56) * 0.5
    x = m + clunk(t, 0.02, 0.4) * 0.5 + clunk(t, 0.55, 1.0) + pop
    return finish(x)


if __name__ == "__main__":
    write("vcr_insert", insert())
    write("vcr_whirr", whirr())
    write("vcr_ff", ff())
    write("vcr_eject", eject())
