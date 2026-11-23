"""Build Fallout Forecast's original surplus weapons and supply cues.

Run from the repository root with Python and NumPy. Pass --pickup-only to
regenerate just the pickup cue.
"""
import argparse

import numpy as np

from gen_juice_sfx import SR, env, finish, lowpass, t_axis, write


def sweep(frequency):
    return np.sin(2 * np.pi * np.cumsum(frequency) / SR)


def effect(seed, duration, fundamental, decay, noise_cutoff, motor=0.0):
    t = t_axis(duration)
    rng = np.random.default_rng(seed)
    raw = rng.standard_normal(t.size)
    noise = lowpass(raw, noise_cutoff) - 0.65 * lowpass(raw, noise_cutoff / 5)
    tone = sweep(fundamental * (0.58 + 0.42 * np.exp(-t * 18)))
    signal = (tone * 0.46 + noise * 0.68) * env(t, decay)
    signal += rng.standard_normal(t.size) * env(t, 0.002) * 0.14
    if motor:
        motor_tone = sweep(motor * (1.0 + 0.20 * np.sin(2 * np.pi * 18 * t)))
        signal += (motor_tone + 0.4 * np.sign(motor_tone)) * env(t, decay * 1.6) * 0.22
    return finish(signal, 0.74)


def chirps(notes, duration, separation):
    t = t_axis(duration)
    signal = np.zeros(t.size)
    for index, note in enumerate(notes):
        start = index * separation
        tone = np.sin(2 * np.pi * note * (t - start))
        signal += (tone + 0.29 * np.sign(tone)) * env(t, 0.09, start)
    return finish(lowpass(signal, 4500), 0.59)


def pickup():
    """A padded gear latch closing, with a soft wooden body and a short snap."""
    t = t_axis(0.128)
    raw = np.random.default_rng(4817).standard_normal(t.size)
    click = lowpass(raw, 4400) - lowpass(raw, 1050)
    signal = 0.42 * click * env(t, 0.0031)
    signal += 0.12 * click * env(t, 0.0026, 0.015)
    signal += 0.61 * np.sin(2 * np.pi * 184 * t) * env(t, 0.035)
    signal += 0.18 * np.sin(2 * np.pi * 368 * t) * env(t, 0.016)
    for note, start, gain in [(520, 0.007, 0.11), (680, 0.024, 0.065)]:
        signal += gain * np.sin(2 * np.pi * note * (t - start)) * env(t, 0.022, start)
    signal *= np.minimum(t / 0.0007, 1.0)
    return finish(signal, 0.76, fade=0.018)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pickup-only", action="store_true", help="write only pickup.wav")
    args = parser.parse_args()
    write("pickup", pickup())
    if args.pickup_only:
        return
    cues = {
        "nail_driver": (0.095, 380, 0.028, 3600, 170),
        "hunting_rifle": (0.42, 124, 0.087, 5100, 0),
        "pressure_washer": (0.15, 200, 0.095, 2600, 86),
        "rock_salt": (0.36, 91, 0.085, 2350, 0),
        "battery_zapper": (0.29, 730, 0.057, 5500, 126),
        "flare_launcher": (0.59, 210, 0.119, 3000, 510),
        "harpoon": (0.49, 314, 0.088, 3200, 152),
        "leaf_blower": (0.24, 143, 0.133, 940, 268),
        "disruptor": (0.45, 484, 0.115, 3950, 71),
        "sandbag": (0.28, 88, 0.078, 460, 0),
        "umbrella": (0.27, 465, 0.049, 2340, 0),
        "lightning_rod": (0.34, 962, 0.045, 5500, 62),
        "bleach_bomb": (0.24, 350, 0.069, 4900, 102),
        "med_tin": (0.33, 1330, 0.045, 3700, 0),
        "suit_patch": (0.38, 728, 0.07, 2350, 510),
        "bait_radio": (0.31, 318, 0.055, 3700, 123),
    }
    for index, (name, settings) in enumerate(cues.items()):
        write("gun_" + name, effect(670 + index, *settings))
    write("gun_field_deploy", chirps([390, 540, 780], 0.44, 0.065))
    write("gun_supply_drop", chirps([330, 392, 523, 784], 0.8, 0.115))
    write("gun_bait_loop", chirps([262, 330, 392, 330, 294, 349, 440, 349], 1.8, 0.195))
    t = t_axis(0.88)
    signal = sweep(135 + 580 * t**1.5) * np.sin(np.pi * t / 0.9)
    signal *= 0.65 + 0.35 * np.sin(2 * np.pi * t * 31)
    write("gun_disruptor_charge", finish(signal, 0.63))


if __name__ == "__main__":
    main()
