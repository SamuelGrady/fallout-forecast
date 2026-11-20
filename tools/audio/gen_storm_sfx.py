"""Render Fallout Forecast's original storm and hazard cues to 16-bit WAV.

Run from the repository root with NumPy installed:
    python tools/audio/gen_storm_sfx.py
"""

import numpy as np

from gen_gun_sfx import bandpass, delay, env, finish, sweep, t_axis, write


def downpour():
    rng = np.random.default_rng(501)
    t = t_axis(0.74)
    noise = rng.standard_normal(t.size)
    tom = sweep(t, 186, 57, 0.042) * env(t, 0.15)
    shell = 0.29 * sweep(t, 335, 157, 0.035) * env(t, 0.085)
    snare = bandpass(noise, 720, 5800) * (0.59 * env(t, 0.045) + 0.39 * env(t, 0.007))
    dry = tom + shell + snare
    # Dense early reflections feed a plate-like wash. The wet signal holds
    # its level, then closes in 24 ms like a noise gate on the reverb return.
    wet = np.zeros_like(dry)
    for at in np.linspace(0.027, 0.52, 38) + rng.uniform(-0.006, 0.006, 38):
        wet += delay(dry, at, rng.uniform(-0.16, 0.18), 3700)
    plate = bandpass(rng.standard_normal(t.size), 270, 3400)
    wet += plate * 0.19 * np.clip((t - 0.022) / 0.065, 0, 1)
    gate = np.clip((0.41 - t) / 0.024, 0, 1)
    return finish(dry + 1.4 * wet * gate, drive=1.15)


def wind_loop():
    rng = np.random.default_rng(502)
    t = t_axis(6.0)
    noise = rng.standard_normal(t.size)
    # Filter two copies and retain the second so the filter has a matching
    # history on either side of the seam. The gust envelopes repeat too.
    doubled = np.tile(noise, 2)
    low = bandpass(doubled, 65, 300)[t.size:]
    high = bandpass(doubled, 320, 1400)[t.size:]
    gust = 0.54 + 0.23 * np.sin(2 * np.pi * t / 3.0) + 0.12 * np.cos(2 * np.pi * t / 2.0)
    wind = (low + 0.27 * high) * gust
    return wind * (0.74 / np.max(np.abs(wind)))


def bulletin(notes, seed, length=0.65):
    rng = np.random.default_rng(seed)
    t = t_axis(length)
    audio = np.zeros_like(t)
    for i, frequency in enumerate(notes):
        at = 0.012 + i * 0.112
        age = np.maximum(0, t - at)
        phase = 2 * np.pi * frequency * age + 0.19 * np.sin(2 * np.pi * 6 * age)
        carrier = np.sin(phase) + 0.32 * np.sin(2 * phase) + 0.1 * np.sin(3 * phase)
        audio += carrier * np.minimum(1, age / 0.009) * env(t, 0.12, at)
    speaker = bandpass(audio + 0.045 * rng.standard_normal(t.size) * env(t, 0.14), 230, 3700)
    return finish(speaker, drive=0.9, fade=0.10)


def warning(seed, start, end, rasp_hz, length, pulse):
    rng = np.random.default_rng(seed)
    t = t_axis(length)
    bend = sweep(t, start, end, length / 3)
    throat = np.tanh(2.0 * bend)
    noise = bandpass(rng.standard_normal(t.size), rasp_hz / 3, rasp_hz)
    breath = np.sin(2 * np.pi * pulse * t + 3 * t * t) * 0.24 + 0.76
    shape = np.sin(np.pi * np.clip(t / (length * 0.92), 0, 1)) ** 0.75
    return finish((0.38 * throat + noise) * breath * shape, drive=1.5)


def skid():
    rng = np.random.default_rng(506)
    t = t_axis(0.44)
    noise = rng.standard_normal(t.size)
    scrape = bandpass(noise, 610, 4100) * env(t, 0.075) * 0.55
    body = sweep(t, 132, 48, 0.026) * env(t, 0.065) * 0.64
    splash = bandpass(noise, 440, 2100) * env(t, 0.076, 0.042)
    return finish(scrape + body + splash, drive=1.3)


def mechanism(seed, length, deploy):
    rng = np.random.default_rng(seed)
    t = t_axis(length)
    noise = rng.standard_normal(t.size)
    snap = bandpass(noise, 1300, 5700) * env(t, 0.012)
    air = bandpass(noise, 450, 2500) * (env(t, 0.27) - env(t, 0.036)) * 1.25
    lift = sweep(t, 100, 440, 0.10) if deploy else sweep(t, 380, 84, 0.10)
    hum = (lift + 0.37 * lift**3) * (env(t, 0.24) - env(t, 0.028))
    return finish(snap + air + hum * 0.79, drive=1.1)


def decon():
    rng = np.random.default_rng(509)
    t = t_axis(1.35)
    noise = rng.standard_normal(t.size)
    valve = bandpass(noise, 1100, 5100) * env(t, 0.016)
    pump = sweep(t, 165, 76, 0.067) * env(t, 0.14) * 0.71
    spray = bandpass(noise, 630, 4900) * (env(t, 0.43, 0.033) - env(t, 0.13, 0.033))
    drips = bandpass(noise, 520, 1500) * (env(t, 0.05, 0.58) + env(t, 0.035, 0.76)) * 0.23
    return finish(valve + pump + spray + drips, drive=1.4, fade=0.12)


if __name__ == "__main__":
    write("downpour", downpour())
    write("storm_wind", wind_loop())
    write("storm_countdown", bulletin([392], 510, 0.34))
    write("storm_arrival", bulletin([277, 233, 185], 511))
    write("storm_clear", bulletin([262, 330, 392, 523], 512))
    write("drip_windup", warning(503, 81, 103, 1700, 0.43, 19))
    write("gutter_windup", warning(504, 124, 355, 4500, 0.64, 28))
    write("mister_windup", warning(505, 46, 75, 1040, 0.44, 11))
    write("gutter_skid", skid())
    write("dome_deploy", mechanism(507, 0.92, True))
    write("dome_collapse", mechanism(508, 0.55, False))
    write("decon_spray", decon())
