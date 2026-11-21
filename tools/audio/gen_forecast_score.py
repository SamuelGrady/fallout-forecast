"""Render the original Fallout Forecast score and weather cues (Python + NumPy)."""
from pathlib import Path
import wave

import numpy as np


RATE = 22050
BEAT = RATE * 60 / 108
FRAMES = round(BEAT * 32)
ROOT = Path(__file__).resolve().parents[2] / "assets" / "audio"
RNG = np.random.default_rng(1987)


def write(directory, name, samples):
    with wave.open(str(ROOT / directory / (name + ".wav")), "wb") as file:
        file.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        file.writeframes((np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes())


def put(track, beat, values):
    start = round(beat * BEAT)
    indices = (start + np.arange(len(values))) % FRAMES
    np.add.at(track, indices, values)


def tone(note, length, voice):
    t = np.arange(round(length * RATE)) / RATE
    hz = 440 * 2 ** ((note - 69) / 12)
    p = 2 * np.pi * hz * t
    if voice == "pad":
        wavelet = np.sin(p) + 0.38 * np.sin(p * 1.006) + 0.22 * np.sin(2 * p)
        return wavelet * np.minimum(t / 0.55, 1) * np.minimum((length - t) / 0.65, 1)
    if voice == "bass":
        wavelet = np.sin(p) + 0.42 * np.sin(2 * p) + 0.21 * np.sin(3 * p)
    elif voice == "brass":
        wavelet = np.sin(p) + 0.50 * np.sin(2 * p) + 0.34 * np.sin(3 * p) + 0.22 * np.sin(5 * p)
    else:
        wavelet = np.sin(p + 0.8 * np.exp(-t * 7) * np.sin(2 * p))
    return wavelet * np.minimum(t / 0.009, 1) * np.exp(-t * 3.7) * np.minimum((length - t) / 0.045, 1)


def drum(kind):
    t = np.arange(round(0.29 * RATE)) / RATE
    noise = RNG.standard_normal(len(t))
    if kind == "kick":
        phase = 2 * np.pi * (46 * t + 3 * (1 - np.exp(-t * 34)))
        return (np.sin(phase) + 0.17 * noise * np.exp(-t * 170)) * np.exp(-t * 17)
    if kind == "snare":
        return (0.55 * noise + 0.42 * np.sin(2 * np.pi * 166 * t) * np.exp(-t * 34)) * np.exp(-t * 27)
    return np.append(0, np.diff(noise)) * np.exp(-t * 58) * 0.4


def render_score():
    theme, pulse, storm, boss = (np.zeros(FRAMES) for _ in range(4))
    progression = [([45, 52, 55, 60], 33), ([41, 48, 52, 57], 29),
                   ([48, 55, 59, 64], 36), ([43, 50, 53, 59], 31)]
    motifs = [[69, 72, 76, 74, 71], [69, 65, 72, 74, 72],
              [67, 71, 76, 79, 76], [74, 71, 69, 67, 64]]
    for section, (chord, root) in enumerate(progression):
        at = section * 8
        for note in chord:
            put(theme, at, 0.078 * tone(note, 8 * BEAT / RATE + 0.7, "pad"))
        for step, note in zip([0, 1.5, 3, 5, 6.5], motifs[section]):
            line = tone(note, 0.86, "lead")
            put(theme, at + step, 0.24 * line)
            put(theme, at + step + 0.75, 0.07 * line)
        for step in range(16):
            if step % 4 != 3:
                put(pulse, at + step * 0.5, 0.22 * tone(root + (12 if step % 8 == 6 else 0), 0.32, "bass"))
            put(storm, at + step * 0.5, 0.074 * tone(chord[(step + 1) % 4] + 24, 0.21, "lead"))
            put(storm, at + step * 0.5, 0.055 * drum("hat"))
        for step in [0, 2.5, 4, 6, 7.5]:
            put(pulse, at + step, 0.34 * drum("kick"))
        for step in [1, 3, 5, 7]:
            put(storm, at + step, 0.24 * drum("snare"))
        for step, interval in [(0, 0), (1.5, 7), (3, 12), (4, 0), (6, 3), (7, 7)]:
            put(boss, at + step, 0.27 * tone(root + 24 + interval, 0.46, "brass"))
        for step in [1, 3, 5, 7]:
            put(boss, at + step, 0.29 * drum("kick"))
    for name, track in zip(("theme", "pulse", "storm", "boss"), (theme, pulse, storm, boss)):
        write("music", "forecast_" + name, track)


def render_effects():
    def smooth(noise, width):
        return np.convolve(noise, np.ones(width) / width, "same")

    t = np.arange(RATE * 4) / RATE
    raw = RNG.standard_normal(len(t))
    mid = smooth(raw, 5) - smooth(raw, 40)
    roll = smooth(raw, 42) * (1.1 + 0.45 * np.sin(2 * np.pi * 2.1 * t))
    thunder = mid * (0.90 * np.exp(-t * 16) + 0.34 * np.exp(-t * 1.4))
    thunder += 2.1 * roll * (1 - np.exp(-t * 16)) * np.exp(-t * 1.1)
    thunder *= np.minimum(1, 700 * t) * np.minimum(1, 3 * (4.0 - t))
    write("sfx", "thunder_web", 0.89 * thunder / np.max(np.abs(thunder)))
    t = np.arange(round(RATE * 0.43)) / RATE
    rattle = RNG.standard_normal(len(t)) * np.exp(-t * 13)
    impact = np.sin(2 * np.pi * (48 * t + 1.8 * (1 - np.exp(-t * 45)))) * np.exp(-t * 12)
    write("sfx", "airdrop_land", (0.72 * impact + 0.22 * rattle) * np.minimum(1, 450 * t))


if __name__ == "__main__":
    render_score()
    render_effects()
