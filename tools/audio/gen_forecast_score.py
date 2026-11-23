"""Render the four-stem adaptive Fallout Forecast score (Python + NumPy).

Running this script rewrites ONLY assets/audio/music/forecast_{theme,pulse,
storm,boss}.wav. Sound effects in assets/audio/sfx/ (thunder included) are
tuned separately and are never touched unless you pass --effects, which
re-renders airdrop_land.wav only.

All four stems are 32 beats of A minor at 128 BPM (exactly 330750 frames,
15 s, mono 16-bit 22050 Hz) and are phase-locked: game/sound.gd plays them
together and only rides their gains. Every note, echo and reverb tail is
written circularly (indices wrap modulo the loop length) and whole-loop
oscillators are tuned to whole cycles, so the loop seam has no click.

  theme  Calm / title: dark detuned pads, sub heartbeat, sparse echoing arp.
  pulse  Fight groove: four-on-the-floor kick, overdriven 16th octave bass
         with sidechain pump, tight hats and a rim on 2 and 4.
  storm  Firefight adrenaline: gated slam snare, open hats + 16th rolls,
         crashes, metal clangs, distorted 16th lead arp, minor-2nd/tritone
         stabs and filtered risers into each phrase.
  boss   Peak crisis: galloping saw power chords, 16th double kick, tom
         fills, a screaming octave lead and a tritone alarm.
"""
from pathlib import Path
import sys
import wave

import numpy as np


RATE = 22050
BPM = 128
BEATS = 32
BEAT = RATE * 60 / BPM
FRAMES = round(BEAT * BEATS)
SEC_BEAT = 60 / BPM
ROOT = Path(__file__).resolve().parents[2] / "assets" / "audio"
RNG = np.random.default_rng(1987)
FREQS = np.fft.rfftfreq(FRAMES, 1 / RATE)

# Am - F - Dm - E, two bars (8 beats) each.
CHORDS = [[57, 60, 64], [53, 57, 60], [50, 53, 57], [52, 56, 59]]
BASS = [33, 29, 38, 28]
STEM_RMS_DB = {"theme": -18.5, "pulse": -15.0, "storm": -14.5, "boss": -14.0}
# RMS (dBFS) each stem is pushed to before tanh saturation: hotter = more grit
# and less crest factor. The theme stays clean; combat stems get squashed.
STEM_DRIVE_DB = {"theme": -15.0, "pulse": -10.0, "storm": -9.0, "boss": -8.5}
# Top-end roll-off (Hz) so 22 kHz noise/hats stay crisp instead of fizzy.
STEM_TOP = {"theme": 7000.0, "pulse": 9000.0, "storm": 8000.0, "boss": 8000.0}
# In-game peak mix (see Sound._process): theme, pulse, storm, boss gains.
PEAK_MIX = (0.34, 0.95, 1.0, 0.95)
PEAK_MIX_CEILING_DB = -1.0


# --- utilities --------------------------------------------------------------

def write(directory, name, samples):
    with wave.open(str(ROOT / directory / (name + ".wav")), "wb") as file:
        file.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        file.writeframes(np.round(np.clip(samples, -1, 1) * 32767).astype("<i2").tobytes())


def hz(note):
    return 440.0 * 2 ** ((np.asarray(note, dtype=float) - 69) / 12)


def put(track, beat, values):
    start = round(beat * BEAT)
    indices = (start + np.arange(len(values))) % FRAMES
    np.add.at(track, indices, values)


def seconds(beats):
    return beats * SEC_BEAT


def circ_filter(x, low=None, high=None, order=2):
    """Zero-phase circular low/high-pass (wraps around the loop seamlessly)."""
    spec = np.fft.rfft(x)
    gain = np.ones_like(FREQS)
    if low:
        gain /= np.sqrt(1 + (FREQS / low) ** (2 * order))
    if high:
        gain /= np.sqrt(1 + (high / np.maximum(FREQS, 1e-3)) ** (2 * order))
    return np.fft.irfft(spec * gain, FRAMES)


def reverb(x, decay, mix, tone=3500.0, seed=0):
    """Circular convolution reverb with a decaying noise impulse."""
    rng = np.random.default_rng(seed)
    n = round(decay * RATE)
    t = np.arange(n) / RATE
    impulse = rng.standard_normal(n) * np.exp(-t * 6.9 / decay) * np.minimum(t / 0.012, 1)
    kernel = np.zeros(FRAMES)
    kernel[:n] = impulse / np.sqrt(np.sum(impulse ** 2))
    kernel = circ_filter(kernel, low=tone)
    wet = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(kernel), FRAMES)
    return x + mix * wet


def echo(x, beats, feedback, taps, tone=2500.0):
    """Circular feedback echo: tap i is delayed i * beats and darkened i times."""
    out = x.copy()
    tap = x
    for i in range(1, taps + 1):
        tap = circ_filter(tap, low=tone) * feedback
        out += np.roll(tap, round(beats * BEAT * i))
    return out


def envelope(n, attack=0.005, release=0.03, decay=None, sustain=1.0):
    t = np.arange(n) / RATE
    env = np.minimum(t / max(attack, 1e-4), 1)
    if decay:
        env *= sustain + (1 - sustain) * np.exp(-t / decay)
    env *= np.clip((n / RATE - t) / max(release, 1e-4), 0, 1)
    return env


def synth(freq, n, shape="saw", cutoff=4000.0, res=0.0, seamless=False, phase0=0.0):
    """Additive band-limited oscillator with a per-sample harmonic low-pass.

    freq and cutoff may be scalars or length-n arrays (filter sweeps, glides).
    seamless=True nudges the pitch by a few millihertz so the oscillator runs
    whole cycles over the buffer (for oscillators spanning the whole loop).
    """
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,)).copy()
    fc = np.broadcast_to(np.asarray(cutoff, dtype=float), (n,))
    phase = 2 * np.pi * (np.cumsum(f) - f) / RATE
    if seamless:
        cycles = (phase[-1] + 2 * np.pi * f[-1] / RATE) / (2 * np.pi)
        phase -= 2 * np.pi * (cycles - round(cycles)) * np.arange(n) / n
    phase += phase0
    top = min(RATE * 0.47, float(fc.max()) * 6)
    harmonics = max(1, int(top / max(float(f.min()), 20.0)))
    out = np.zeros(n)
    for k in range(1, harmonics + 1):
        if shape == "square" and k % 2 == 0:
            continue
        if shape == "sine" and k > 1:
            break
        amp = 1.0 / k
        partial = k * f
        weight = amp / np.sqrt(1 + (partial / fc) ** 4)
        if res:
            weight *= 1 + res * np.exp(-((partial - fc) / (0.22 * fc)) ** 2)
        weight *= np.clip((RATE * 0.47 - partial) / 600, 0, 1)
        if not np.any(weight > 1e-4):
            continue
        out += weight * np.sin(k * phase)
    return out


def noise(n, rng=RNG):
    return rng.standard_normal(n)


def highpass_noise(n, passes=2, rng=RNG):
    x = noise(n + passes, rng)
    for _ in range(passes):
        x = np.diff(x)
    return x[:n] / (2 ** passes / 2)


def svf_lowpass(x, cutoff, q=0.35):
    """Time-varying Chamberlin state-variable low-pass (short buffers only)."""
    low = band = 0.0
    out = np.empty(len(x))
    coeff = 2 * np.sin(np.pi * np.clip(cutoff, 20, 4200) / RATE)
    for i, sample in enumerate(x):
        f = coeff[i]
        low += f * band
        high = sample - low - q * band
        band += f * high
        out[i] = low
    return out


def sat(x, drive):
    return np.tanh(drive * x) / np.tanh(drive)


# --- drums ------------------------------------------------------------------

def kick(length=0.36, tight=False):
    n = round(length * RATE)
    t = np.arange(n) / RATE
    f = 46 + 120 * np.exp(-t * 30) + 420 * np.exp(-t * 190)
    body = np.sin(2 * np.pi * np.cumsum(f) / RATE)
    body *= np.exp(-t * (16 if tight else 8.5))
    click = highpass_noise(n, 1) * np.exp(-t * 320)
    hit = sat(body + 0.35 * click, 2.4)
    return hit * envelope(n, 0.0005, 0.02)


def snare(length=0.34, gated=True, bright=1.0):
    n = round(length * RATE)
    t = np.arange(n) / RATE
    hp = highpass_noise(n, 1)
    body = 0.9 * np.sin(2 * np.pi * (182 * t + 9 * (1 - np.exp(-t * 40)))) * np.exp(-t * 28)
    body += 0.45 * np.sin(2 * np.pi * 331 * t) * np.exp(-t * 42)
    crack = bright * hp * np.exp(-t * 24)
    tail = 0.6 * hp * np.exp(-t * 7)
    if gated:
        tail *= np.clip((0.25 - t) / 0.025, 0, 1)
    return sat(body + 0.95 * crack + tail, 2.0) * envelope(n, 0.0005, 0.02)


def rim(length=0.12):
    n = round(length * RATE)
    t = np.arange(n) / RATE
    tone_ = np.sin(2 * np.pi * 820 * t) + 0.6 * np.sin(2 * np.pi * 1690 * t)
    return (0.6 * tone_ * np.exp(-t * 60) + 0.6 * highpass_noise(n) * np.exp(-t * 90))


def clap(length=0.28):
    n = round(length * RATE)
    t = np.arange(n) / RATE
    burst = np.zeros(n)
    for offset in (0.0, 0.009, 0.019, 0.028):
        burst += np.exp(-np.maximum(t - offset, 0) * 140) * (t >= offset)
    burst += 0.5 * np.exp(-np.maximum(t - 0.028, 0) * 18) * (t >= 0.028)
    return highpass_noise(n, 1) * burst


METAL = np.array([205.3, 304.4, 369.6, 522.7, 540.0, 800.0]) * 2.6


def hat(length=0.05, open_=False):
    n = round(length * RATE)
    t = np.arange(n) / RATE
    metal = sum(np.sign(np.sin(2 * np.pi * f * t + i)) for i, f in enumerate(METAL)) / 6
    metal = np.append(0, np.diff(metal))
    x = 0.75 * highpass_noise(n) + 0.55 * metal
    decay = 9 if open_ else 70
    return x * np.exp(-t * decay) * envelope(n, 0.0003, 0.01 if not open_ else 0.04)


def crash(length=2.0):
    n = round(length * RATE)
    t = np.arange(n) / RATE
    metal = sum(np.sign(np.sin(2 * np.pi * f * 1.37 * t + i)) for i, f in enumerate(METAL)) / 6
    metal = np.append(0, np.diff(metal))
    x = highpass_noise(n, 1) * (0.8 * np.exp(-t * 2.3) + 0.6 * np.exp(-t * 14)) + 0.4 * metal * np.exp(-t * 3)
    return x * envelope(n, 0.001, 0.3)


def clang(base=310.0, length=0.45):
    """Industrial FM metal hit."""
    n = round(length * RATE)
    t = np.arange(n) / RATE
    index = 7 * np.exp(-t * 12)
    x = np.sin(2 * np.pi * base * t + index * np.sin(2 * np.pi * base * 1.414 * t))
    x += 0.6 * np.sin(2 * np.pi * base * 2.76 * t + 0.6 * index * np.sin(2 * np.pi * base * 3.11 * t))
    x = x * np.exp(-t * 8) + 0.5 * highpass_noise(n) * np.exp(-t * 40)
    return sat(x, 1.8) * envelope(n, 0.0005, 0.05)


def tom(base, length=0.32):
    n = round(length * RATE)
    t = np.arange(n) / RATE
    f = base * (1 + 0.55 * np.exp(-t * 22))
    x = np.sin(2 * np.pi * np.cumsum(f) / RATE) * np.exp(-t * 9)
    x += 0.25 * highpass_noise(n, 1) * np.exp(-t * 80)
    return sat(x, 2.0) * envelope(n, 0.0005, 0.03)


def riser(beats):
    n = round(seconds(beats) * RATE)
    t = np.arange(n) / n
    cutoff = 250 * (4000 / 250) ** (t ** 1.6)
    swept = svf_lowpass(noise(n), cutoff, q=0.18)
    swell = t ** 2.2
    pitch = synth(hz(57) * 2 ** (t * 2), n, "saw", cutoff=cutoff)
    return (0.9 * swept + 0.35 * pitch) * swell * envelope(n, 0.01, 0.01)


# --- instruments ------------------------------------------------------------

def pad(note, length):
    n = round(length * RATE)
    t = np.arange(n) / RATE
    cutoff = 700 + 500 * np.sin(2 * np.pi * t / length * 1.0 - np.pi / 2) ** 2
    voices = sum(synth(hz(note + cents / 100), n, "saw", cutoff, 0.6, phase0=RNG.uniform(0, 6.28))
                 for cents in (-11, 0, 9))
    voices += 0.6 * synth(hz(note - 12), n, "sine")
    return voices * envelope(n, 0.9, 1.1)


def pluck(note, length=0.32, bright=2600.0):
    n = round(length * RATE)
    t = np.arange(n) / RATE
    cutoff = 350 + bright * np.exp(-t * 14)
    x = synth(hz(note), n, "square", cutoff, 1.2) + 0.5 * synth(hz(note + 12.07), n, "saw", cutoff)
    return x * envelope(n, 0.002, 0.06, decay=0.16, sustain=0.0)


def bell(note, length=3.0):
    n = round(length * RATE)
    t = np.arange(n) / RATE
    f = hz(note)
    x = np.sin(2 * np.pi * f * t + 2.2 * np.exp(-t * 3) * np.sin(2 * np.pi * f * 3.5 * t))
    return x * np.exp(-t * 1.6) * envelope(n, 0.003, 0.4)


def bass_note(note, length, velocity=1.0):
    n = round(length * RATE)
    t = np.arange(n) / RATE
    cutoff = 320 + 2300 * velocity * np.exp(-t * 26)
    x = synth(hz(note), n, "saw", cutoff, 1.6) + 0.55 * synth(hz(note - 12), n, "square", 600)
    return sat(x * envelope(n, 0.002, 0.018), 2.6)


def brass(notes, length, cutoff=2600.0, drive=3.0):
    n = round(length * RATE)
    t = np.arange(n) / RATE
    fc = cutoff * (0.45 + 0.55 * np.exp(-t * 7))
    x = sum(synth(hz(note + cents / 100), n, "saw", fc, 0.9, phase0=RNG.uniform(0, 6.28))
            for note in notes for cents in (-8, 7))
    return sat(x / len(notes) * envelope(n, 0.004, 0.03), drive)


def stab(notes, length=0.2):
    n = round(length * RATE)
    t = np.arange(n) / RATE
    fc = 900 + 3000 * np.exp(-t * 18)
    x = sum(synth(hz(note), n, "saw", fc, 1.8) for note in notes)
    return sat(x * envelope(n, 0.002, 0.05), 3.4)


def lead_line(notes, cutoff=3800.0, vib_depth=0.28, octave_mix=0.5, drive=3.0):
    """Whole-loop monophonic lead with portamento and delayed vibrato.

    notes: list of (beat, length_beats, midi); wraps circularly.
    """
    pitch = np.zeros(FRAMES)
    gate = np.zeros(FRAMES)
    onset = np.full(FRAMES, 10.0)
    for beat, length, note in notes:
        n = round(length * BEAT)
        idx = (round(beat * BEAT) + np.arange(n)) % FRAMES
        pitch[idx] = note
        t = np.arange(n) / RATE
        gate[idx] = envelope(n, 0.008, 0.035)
        onset[idx] = t
    # Rests hold the previous pitch (gate is closed, so it is silent).
    for i in np.where(gate == 0)[0]:
        pitch[i] = pitch[i - 1]
    if pitch[0] == 0:
        pitch[pitch == 0] = notes[-1][2]
    # Circular portamento: smooth the pitch curve with a short exp kernel.
    k = np.zeros(FRAMES)
    kt = np.arange(round(0.05 * RATE)) / RATE
    k[:len(kt)] = np.exp(-kt / 0.014)
    k /= k.sum()
    glided = np.fft.irfft(np.fft.rfft(pitch) * np.fft.rfft(k), FRAMES)
    vibrato = vib_depth * np.clip((onset - 0.18) / 0.25, 0, 1) * np.sin(2 * np.pi * 5.6 * np.arange(FRAMES) / RATE)
    freq = hz(glided + vibrato)
    x = synth(freq, FRAMES, "saw", cutoff, 0.8, seamless=True)
    x += octave_mix * synth(freq * 2, FRAMES, "saw", cutoff * 1.2, 0.5, seamless=True)
    return sat(x * gate, drive)


# --- stems ------------------------------------------------------------------

def render_theme():
    track = np.zeros(FRAMES)
    pads = np.zeros(FRAMES)
    arps = np.zeros(FRAMES)
    motifs = [[69, 72, 76, 77, 76, 72, 71, 69],
              [69, 72, 77, 76, 72, 69, 68, 69],
              [65, 69, 74, 72, 69, 65, 64, 65],
              [68, 71, 76, 77, 76, 71, 68, 64]]
    steps = [0, 3, 6, 10, 12, 19, 22, 28]
    for section, (chord, root) in enumerate(zip(CHORDS, BASS)):
        at = section * 8
        for note in chord + [chord[0] + 12]:
            put(pads, at, 0.22 * pad(note, seconds(8) + 1.0))
        put(pads, at, 0.35 * bell(chord[2] + 24, 3.5))
        for step, note in zip(steps, motifs[section]):
            put(arps, at + step / 4, 0.42 * pluck(note))
        # Brooding sub heartbeat: lub-dub on every beat, root two octaves down.
        for beat in range(8):
            for offset, gain in ((0, 0.55), (0.25, 0.3)):
                n = round(0.22 * RATE)
                t = np.arange(n) / RATE
                thump = np.sin(2 * np.pi * hz(root + 12) * t) * np.exp(-t * 14) * envelope(n, 0.004, 0.02)
                put(track, at + beat + offset, gain * (1.0 if beat % 2 == 0 else 0.65) * thump)
    drone = 0.16 * synth(hz(33), FRAMES, "saw", 180, 0.5, seamless=True)
    track += drone
    pads = reverb(pads, 2.6, 0.55, 3000, seed=1)
    arps = reverb(echo(arps, 0.75, 0.42, 4, 2200), 1.8, 0.4, 3500, seed=2)
    return circ_filter(track + pads + arps, high=32)


def render_pulse():
    drums = np.zeros(FRAMES)
    bass = np.zeros(FRAMES)
    k = kick()
    for beat in range(BEATS):
        put(drums, beat, 0.95 * k)
    for bar in range(BEATS // 4):
        if bar % 2 == 1:
            put(drums, bar * 4 + 3.75, 0.6 * kick(tight=True))
    pattern = [0, 0, 12, 0]
    velocity = [1.0, 0.65, 0.95, 0.7]
    for section, root in enumerate(BASS):
        for step in range(32):
            beat = section * 8 + step / 4
            interval = pattern[step % 4]
            if section == 3 and step >= 28:
                interval = [12, 13, 15, 16][step - 28]  # chromatic climb back to A
            put(bass, beat, 0.5 * velocity[step % 4] * bass_note(root + interval, seconds(0.23), velocity[step % 4]))
    # Sidechain pump: the bass ducks under every kick, then swells back.
    since = (np.arange(FRAMES) % BEAT) / RATE
    bass *= 1 - 0.62 * np.exp(-since * 11)
    for step in range(BEATS * 4):
        accent = [0.45, 0.3, 1.0, 0.35][step % 4]
        put(drums, step / 4, 0.32 * accent * hat())
    for beat in range(1, BEATS, 2):
        put(drums, beat, 0.38 * rim())
        put(drums, beat, 0.22 * clap())
    return circ_filter(drums + bass, high=30)


def render_storm():
    drums = np.zeros(FRAMES)
    synths = np.zeros(FRAMES)
    big = snare()
    for beat in range(1, BEATS, 2):
        put(drums, beat, 0.9 * big)
    for section in range(4):
        at = section * 8
        for offset, gain in ((7.5, 0.35), (7.75, 0.5)):
            put(drums, at + offset, gain * snare(0.2, gated=False))
        # Syncopated industrial metal.
        put(drums, at + 2.75, 0.5 * clang(310))
        put(drums, at + 6.5, 0.45 * clang(415))
    # Snare roll into the loop seam: 16ths then 32nds, crescendo.
    roll = [30 + i / 4 for i in range(4)] + [31 + i / 8 for i in range(8)]
    for i, beat in enumerate(roll):
        put(drums, beat, (0.25 + 0.035 * i) * snare(0.13, gated=False))
    for beat in range(BEATS):
        put(drums, beat + 0.5, 0.42 * hat(0.28, open_=True))
        put(drums, beat + 0.25, 0.22 * hat())
        put(drums, beat + 0.75, 0.26 * hat())
    for at in (0, 16):
        put(drums, at, 0.75 * crash())
    for at in (8, 24):
        put(drums, at, 0.4 * crash(1.2))
    # Distorted 16th arp riff with a minor-9th bite.
    shapes = [[0, 1, 2, 3, 2, 1, 2, 3, 4, 3, 2, 1, 2, 3, 5, 3],
              [0, 2, 1, 3, 2, 4, 3, 5, 3, 2, 1, 2, 0, 1, 2, 3]]
    arp = np.zeros(FRAMES)
    for section, chord in enumerate(CHORDS):
        tones = [chord[0] + 12, chord[1] + 12, chord[2] + 12, chord[0] + 24, chord[1] + 24, chord[0] + 25]
        for step in range(32):
            note = tones[shapes[step // 16][step % 16]]
            n = round(seconds(0.24) * RATE)
            t = np.arange(n) / RATE
            fc = 1100 + 3200 * np.exp(-t * 20)
            x = synth(hz(note), n, "saw", fc, 1.5) * envelope(n, 0.002, 0.02)
            put(arp, section * 8 + step / 4, 0.3 * x)
        root = chord[0]
        # Minor-2nd / tritone tension stabs at the end of each phrase.
        put(synths, section * 8 + 6.5, 0.35 * stab([root, root + 1, root + 6]))
        put(synths, section * 8 + 7.0, 0.35 * stab([root + 1, root + 7, root + 12]))
        put(synths, section * 8 + 3.5, 0.25 * stab([root, root + 6], 0.14))
    arp = sat(arp, 2.6)
    for at in (12, 28):
        put(synths, at, 0.5 * riser(4))
    synths += 0.55 * echo(arp, 0.75, 0.28, 2, 2600)
    drums = reverb(drums, 0.9, 0.22, 4500, seed=3)
    synths = reverb(synths, 1.4, 0.3, 3500, seed=4)
    return circ_filter(drums + synths, high=60)


def render_boss():
    drums = np.zeros(FRAMES)
    chords = np.zeros(FRAMES)
    dk = kick(0.16, tight=True)
    for step in range(BEATS * 4):
        if step % 32 >= 28:
            continue  # tom fill takes the last beat of every section
        put(drums, step / 4, (0.75 if step % 2 == 0 else 0.5) * dk)
    for section in range(4):
        at = section * 8
        for i, base in enumerate((230, 185, 145, 108)):
            put(drums, at + 7 + i / 4, (0.6 + 0.08 * i) * tom(base))
    gallop = [(0, 0.45), (0.75, 0.2), (1.0, 0.2), (1.5, 0.45), (2.25, 0.2), (2.5, 0.2), (3.0, 0.4), (3.5, 0.4)]
    for section, root in enumerate(BASS):
        power = [root + 12, root + 19, root + 24]
        for bar in range(2):
            for offset, length in gallop:
                if section == 3 and bar == 1 and offset >= 3.0:
                    continue  # leave the tom fill room
                put(chords, section * 8 + bar * 4 + offset, 0.42 * brass(power, seconds(length) + 0.03))
    melody = [
        (0, 2, 88), (2, 1, 86), (3, 1, 84), (4, 3, 81), (7, 1, 80),
        (8, 2, 84), (10, 1, 86), (11, 1, 84), (12, 3, 89), (15, 1, 88),
        (16, 2, 86), (18, 1, 84), (19, 1, 81), (20, 2, 86), (22, 1, 89), (23, 1, 88),
        (24, 2, 83), (26, 1, 84), (27, 1, 86), (28, 2, 88), (30, 1, 89), (31, 0.85, 92),
    ]
    lead = 0.26 * lead_line(melody)
    # Tritone alarm: E5 / A#5 alternating each beat, thin square, seamless.
    alarm_pitch = np.where((np.arange(FRAMES) // BEAT) % 2 == 0, 76.0, 82.0)
    k = np.zeros(FRAMES)
    k[:round(0.03 * RATE)] = 1
    alarm_pitch = np.fft.irfft(np.fft.rfft(alarm_pitch) * np.fft.rfft(k / k.sum()), FRAMES)
    alarm = synth(hz(alarm_pitch), FRAMES, "square", 2200, 0.6, seamless=True)
    alarm *= 0.65 + 0.35 * np.cos(2 * np.pi * (np.arange(FRAMES) % BEAT) / BEAT)
    chords = reverb(chords, 1.1, 0.25, 3200, seed=5)
    lead = reverb(echo(lead, 0.5, 0.25, 2, 3000), 1.6, 0.35, 4000, seed=6)
    return circ_filter(drums + chords + lead + 0.07 * alarm, high=35)


# --- master -----------------------------------------------------------------

def rms(x):
    return np.sqrt(np.mean(x ** 2))


def master(name, track):
    track = circ_filter(track, low=STEM_TOP[name], order=1)
    track = np.tanh(track * 10 ** (STEM_DRIVE_DB[name] / 20) / rms(track))
    return track * 10 ** (STEM_RMS_DB[name] / 20) / rms(track)


def render_score():
    stems = {"theme": render_theme(), "pulse": render_pulse(), "storm": render_storm(), "boss": render_boss()}
    stems = {name: master(name, track) for name, track in stems.items()}
    # Keep the hottest in-game mix (boss fight) below the ceiling, since the
    # Web build has no master limiter. Only the combat stems are scaled, so
    # Calm and the title keep their level.
    mix = sum(gain * stems[name] for gain, name in zip(PEAK_MIX, stems))
    theme_part = PEAK_MIX[0] * stems["theme"]
    ceiling = 10 ** (PEAK_MIX_CEILING_DB / 20)
    scale = 1.0
    while np.max(np.abs(theme_part + scale * (mix - theme_part))) > ceiling:
        scale *= 0.99
    for name, track in stems.items():
        if name != "theme":
            track = track * scale
        peak = np.max(np.abs(track))
        if peak > 0.97:
            track *= 0.97 / peak
        write("music", "forecast_" + name, track)
        print(f"forecast_{name}: {FRAMES} frames, {FRAMES / RATE:.3f} s, "
              f"peak {20 * np.log10(np.max(np.abs(track))):.2f} dBFS, rms {20 * np.log10(rms(track)):.2f} dBFS")
    print(f"combat stems scaled {20 * np.log10(scale):.2f} dB for the {PEAK_MIX_CEILING_DB} dBFS peak-mix ceiling")


def render_effects():
    """Opt-in (--effects): re-render airdrop_land.wav. Thunder is not made here."""
    rng = np.random.default_rng(1988)
    t = np.arange(round(RATE * 0.43)) / RATE
    rattle = rng.standard_normal(len(t)) * np.exp(-t * 13)
    impact = np.sin(2 * np.pi * (48 * t + 1.8 * (1 - np.exp(-t * 45)))) * np.exp(-t * 12)
    write("sfx", "airdrop_land", (0.72 * impact + 0.22 * rattle) * np.minimum(1, 450 * t))


if __name__ == "__main__":
    render_score()
    if "--effects" in sys.argv[1:]:
        render_effects()
