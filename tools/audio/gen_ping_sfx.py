"""Render the original Fallout Forecast radio pings as mono WAVs."""

from array import array
from math import exp, sin, tau
from pathlib import Path
from random import Random
from sys import byteorder
import wave


SAMPLE_RATE = 22050
OUT_DIR = Path(__file__).resolve().parents[2] / "assets" / "audio" / "sfx"
# Each note specifies its start, length, and start/end frequencies.
CUES = {
    "go": [(0.00, 0.08, 470, 540), (0.085, 0.14, 705, 765)],
    "enemy": [(0.00, 0.095, 770, 540), (0.10, 0.10, 540, 375)],
    "item": [(0.00, 0.055, 580, 580), (0.062, 0.14, 880, 820)],
    "shelter": [(0.00, 0.09, 740, 680), (0.09, 0.17, 510, 500)],
    "danger": [(0.00, 0.11, 410, 550), (0.12, 0.17, 580, 360)],
    "revive": [(0.00, 0.09, 620, 635), (0.105, 0.09, 620, 635),
               (0.21, 0.19, 810, 690)],
}


def render(notes):
    samples = [0.0] * round((notes[-1][0] + notes[-1][1] + 0.07) * SAMPLE_RATE)
    noise = Random(7819)
    for start, length, low, high in notes:
        offset = round(start * SAMPLE_RATE)
        count = round(length * SAMPLE_RATE)
        phase = 0.0
        for i in range(count):
            t = i / SAMPLE_RATE
            phase += tau * (low + (high - low) * t / length) / SAMPLE_RATE
            envelope = min(t / 0.004, (length - t) / 0.03, 1.0)
            tone = sin(phase) + 0.20 * sin(phase * 2.0) + 0.10 * sin(phase * 3.0)
            click = 0.26 * exp(-t / 0.015) * noise.uniform(-1.0, 1.0)
            voice = 0.43 * envelope * (tone + click)
            samples[offset + i] += voice
            samples[offset + i + round(0.048 * SAMPLE_RATE)] += voice * 0.20
    pcm = array("h", (round(32767 * max(-1.0, min(1.0, value))) for value in samples))
    if byteorder != "little":
        pcm.byteswap()
    return pcm.tobytes()


def main():
    for cue, notes in CUES.items():
        with wave.open(str(OUT_DIR / f"ping_{cue}.wav"), "wb") as stream:
            stream.setparams((1, 2, SAMPLE_RATE, 0, "NONE", "not compressed"))
            stream.writeframes(render(notes))


if __name__ == "__main__":
    main()
