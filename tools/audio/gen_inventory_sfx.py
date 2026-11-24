"""Build Fallout Forecast's homemade weapons, item actions and supply cues.

Run from the repository root with Python and NumPy. Pass --pickup-only to
regenerate just the pickup cue.
"""
import argparse

import numpy as np

from gen_gun_sfx import (
    env_ad, env_ahr, fft_bp, granular_scatter, master_cue, modal_bank,
    street_slapback, sweep_exp, sweep_power, swept_bp_noise,
)
from gen_juice_sfx import SR, env, finish, lowpass, t_axis, write


def sweep(frequency):
    return np.sin(2 * np.pi * np.cumsum(frequency) / SR)


def noise(t, rng, low, high, decay, at=0.0, attack=0.001):
    return fft_bp(rng.standard_normal(t.size), low, high, order=2) * env_ad(t, attack, decay, at)


def gun_nail_driver():
    """Pneumatic striker, air puff, then the magazine's return tick."""
    t = t_axis(0.104)
    rng = np.random.default_rng(671)
    striker = modal_bank(t, [(780, 0.52, 0.015), (2160, 0.38, 0.011), (5100, 0.16, 0.006)])
    exhaust = noise(t, rng, 950, 5200, 0.011, 0.003) * 0.8
    bounce = modal_bank(t, [(1350, 0.23, 0.007), (4900, 0.17, 0.004)], start=0.024)
    return master_cue(striker + exhaust + bounce, level_db=-20.0, fade_out=0.014)


def gun_hunting_rifle():
    """A dry, bright initial snap with one clear distant return."""
    t = t_axis(0.73)
    rng = np.random.default_rng(672)
    crack = noise(t, rng, 2700, 12500, 0.006, attack=0.0003) * 1.6
    muzzle = noise(t, rng, 280, 2650, 0.053, 0.002) * 1.3
    muzzle += sweep_exp(t, 145, 50, 0.02) * env_ad(t, 0.001, 0.081) * 1.05
    chamber = modal_bank(t, [(520, 0.31, 0.039), (1370, 0.22, 0.031)], start=0.009)
    tail = street_slapback(crack + muzzle + chamber, [(0.167, 0.34, 1800), (0.41, 0.19, 860)],
                           tail_decay=0.19, tail_gain=0.13, rng=rng)
    return master_cue(tail, level_db=-17.1)


def gun_pressure_washer():
    """Pump chatter under a narrow jet that spreads into spray."""
    t = t_axis(0.16)
    rng = np.random.default_rng(673)
    pump = sweep_exp(t, 142, 250, 0.022) + 0.27 * sweep_exp(t, 294, 484, 0.022)
    pump *= env_ad(t, 0.007, 0.038) * 0.54
    spray = swept_bp_noise(t, rng, 1250 + 3700 * np.exp(-t / 0.063), q=1.1)
    spray *= env_ahr(t, 0.009, 0.03, 0.02) * (0.76 + 0.24 * np.cos(2 * np.pi * 49 * t))
    droplets = granular_scatter(t, rng, 13, 0.014, 0.094, 3700, 9400, 0.0025, gain=0.27)
    return master_cue(pump + spray + droplets, level_db=-20.2, fade_out=0.018)


def gun_rock_salt():
    """A blunt report followed by grains rattling against sheet metal."""
    t = t_axis(0.37)
    rng = np.random.default_rng(674)
    pop = noise(t, rng, 210, 3500, 0.026) * 1.4
    pop += sweep_exp(t, 134, 63, 0.02) * env_ad(t, 0.001, 0.049)
    grains = granular_scatter(t, rng, 34, 0.015, 0.15, 2700, 8600, 0.004, gain=0.67, ring_prob=0.25)
    tin = modal_bank(t, [(634, 0.20, 0.048), (1330, 0.16, 0.024)], start=0.041)
    return master_cue(pop + grains + tin, level_db=-17.2)


def gun_battery_zapper():
    """Stuttering arcs over the short growl of a loaded inverter."""
    t = t_axis(0.28)
    rng = np.random.default_rng(675)
    inverter = sweep_exp(t, 660, 390, 0.068)
    inverter = np.tanh(inverter * 2.8) * env_ad(t, 0.003, 0.069) * 0.48
    arc = np.zeros_like(t)
    for at, gain in [(0.0, 1.0), (0.027, 0.86), (0.067, 0.75), (0.125, 0.47)]:
        arc += gain * noise(t, rng, 1050, 8850, 0.012, at, attack=0.0004)
        arc += gain * 0.27 * sweep_exp(t, 2450, 783, 0.012, at) * env_ad(t, 0.0008, 0.020, at)
    return master_cue(arc + inverter, level_db=-18.8)


def gun_flare_launcher():
    """Snap of a disposable tube and the climbing whistle of its flare."""
    t = t_axis(0.49)
    rng = np.random.default_rng(676)
    tube = modal_bank(t, [(385, 0.52, 0.035), (1060, 0.27, 0.018), (2400, 0.13, 0.010)])
    pop = noise(t, rng, 650, 6600, 0.023) * 1.4
    flare = sweep_power(t, 550, 1850, 0.16, 0.025, power=0.74)
    flare += 0.31 * sweep_power(t, 1110, 3660, 0.16, 0.025, power=0.74)
    flare *= env_ahr(t, 0.025, 0.06, 0.071, 0.025) * 0.72
    exhaust = noise(t, rng, 1550, 8700, 0.095, 0.029, attack=0.016) * 0.67
    return master_cue(tube + pop + flare + exhaust, level_db=-17.6)


def gun_harpoon():
    """Spring release with the whir and uneven ratchet of the paying-out cable."""
    t = t_axis(0.39)
    rng = np.random.default_rng(677)
    release = modal_bank(t, [(308, 0.7, 0.059), (980, 0.28, 0.028), (2480, 0.37, 0.016)],
                         bend_ratio=-0.11)
    cable = swept_bp_noise(t, rng, 760 + 1900 * np.exp(-t / 0.11), q=2.7)
    cable *= env_ahr(t, 0.012, 0.042, 0.087, 0.013) * 1.08
    for at, gain in [(0.036, 0.7), (0.057, 0.53), (0.087, 0.42), (0.132, 0.31), (0.19, 0.20)]:
        cable += gain * modal_bank(t, [(1685, 0.46, 0.008), (3530, 0.34, 0.006)], start=at)
    return master_cue(release + cable, level_db=-18.4)


def gun_leaf_blower():
    """A low spinning impeller under a broad gust."""
    t = t_axis(0.246)
    rng = np.random.default_rng(678)
    rotor = 190 + 122 * np.sin(np.pi * np.minimum(t / 0.25, 1.0)) + 9 * np.sin(2 * np.pi * 43 * t)
    phase = 2 * np.pi * np.cumsum(rotor) / SR
    fan = np.sin(phase) + 0.5 * np.sin(2 * phase) + 0.22 * np.sin(3 * phase)
    fan *= env_ahr(t, 0.015, 0.075, 0.034) * 0.63
    gust = noise(t, rng, 175, 1900, 0.074, attack=0.018) * (0.8 + 0.2 * np.sin(phase))
    return master_cue(fan + gust, level_db=-18.3, fade_out=0.026)


def gun_disruptor():
    """An abrupt capacitor discharge, then a broken radio sweep."""
    t = t_axis(0.48)
    rng = np.random.default_rng(679)
    discharge = sweep_exp(t, 510, 104, 0.043) * env_ad(t, 0.002, 0.093) * 0.85
    discharge += noise(t, rng, 510, 5400, 0.027) * 0.96
    carrier = sweep_power(t, 2590, 423, 0.225, 0.022, power=0.5)
    modulator = sweep_exp(t, 46, 23, 0.14, 0.022)
    sweep_out = np.tanh(carrier * 2.3) * (0.3 + 0.7 * modulator ** 2)
    sweep_out += noise(t, rng, 1180, 2800, 0.105, 0.031) * 0.48
    sweep_out *= env_ahr(t, 0.013, 0.10, 0.06, 0.016)
    return master_cue(discharge + sweep_out * 0.76, level_db=-15.9)


def gun_frag_throw():
    """Pin ring and delayed lever snap underneath the hand toss."""
    t = t_axis(0.26)
    rng = np.random.default_rng(681)
    pin = modal_bank(t, [(1890, 0.37, 0.028), (4130, 0.35, 0.020)])
    lever = modal_bank(t, [(1120, 0.56, 0.020), (2780, 0.45, 0.012)], start=0.062)
    lever += noise(t, rng, 2600, 10500, 0.006, 0.062) * 0.62
    motion = noise(t, rng, 240, 2400, 0.048, attack=0.027) * 0.55
    return master_cue(pin + lever + motion, level_db=-17.2)


def gun_frag_blast():
    """A low pressure burst, fragments and a wet concrete return."""
    t = t_axis(0.91)
    rng = np.random.default_rng(682)
    blast = noise(t, rng, 150, 5300, 0.084) * 1.5
    blast += sweep_exp(t, 107, 38, 0.054) * env_ad(t, 0.003, 0.143) * 1.75
    blast += noise(t, rng, 1900, 10800, 0.013, attack=0.0004) * 0.82
    shards = granular_scatter(t, rng, 41, 0.014, 0.42, 2800, 9000, 0.006, gain=0.64, ring_prob=0.35)
    echo = street_slapback(blast + shards, [(0.116, 0.34, 1550), (0.296, 0.22, 690)],
                           tail_decay=0.22, tail_gain=0.18, rng=rng)
    return master_cue(echo, level_db=-11.9)


def gun_dome_throw():
    """A hollow polymer capsule twists open and chirps as it leaves the hand."""
    t = t_axis(0.31)
    rng = np.random.default_rng(683)
    case = modal_bank(t, [(282, 0.37, 0.028), (695, 0.53, 0.034), (1670, 0.20, 0.018)])
    case += noise(t, rng, 820, 4650, 0.018) * 0.73
    chirp = sweep_power(t, 430, 820, 0.068, 0.043)
    chirp += 0.38 * sweep_power(t, 655, 1230, 0.068, 0.043)
    chirp *= env_ad(t, 0.011, 0.085, 0.043) * 0.65
    return master_cue(case + chirp, level_db=-17.7)


def gun_dome_expand():
    """An expanding glassy field settles into a low harmonic lock."""
    t = t_axis(0.83)
    rng = np.random.default_rng(684)
    rise = np.zeros_like(t)
    for low, high, gain in [(118, 238, 0.73), (175, 356, 0.44), (353, 713, 0.25)]:
        rise += sweep_power(t, low, high, 0.21) * gain
    rise *= env_ahr(t, 0.041, 0.16, 0.102)
    field = noise(t, rng, 450, 5400, 0.132, attack=0.028) * 0.8
    lock = modal_bank(t, [(240, 0.53, 0.136), (720, 0.28, 0.112), (1196, 0.18, 0.082)],
                      start=0.22, attack=0.012)
    return master_cue(rise + field + lock, level_db=-12.9)


def gun_umbrella():
    """Loose ribs knock against the shaft as it is tossed."""
    t = t_axis(0.26)
    rng = np.random.default_rng(685)
    shaft = modal_bank(t, [(588, 0.62, 0.044), (1605, 0.27, 0.034), (2950, 0.12, 0.014)])
    for at, gain in [(0.019, 0.42), (0.046, 0.29), (0.084, 0.18)]:
        shaft += gain * noise(t, rng, 1150, 4700, 0.013, at)
    cloth = noise(t, rng, 250, 2400, 0.047, 0.021, attack=0.020) * 0.74
    return master_cue(shaft + cloth, level_db=-18.0)


def gun_umbrella_open():
    """Ribs spring outward and the canopy pulls taut."""
    t = t_axis(0.38)
    rng = np.random.default_rng(686)
    ribs = granular_scatter(t, rng, 16, 0.006, 0.08, 700, 4300, 0.006, gain=0.67, ring_prob=0.3)
    canopy = noise(t, rng, 160, 3600, 0.057, 0.045, attack=0.018) * 1.05
    lock = modal_bank(t, [(251, 0.73, 0.056), (744, 0.32, 0.021), (2440, 0.2, 0.016)], start=0.086)
    return master_cue(ribs + canopy + lock, level_db=-13.2)


def gun_bleach_bomb():
    """Liquid sloshes twice against the bottle as it is thrown."""
    t = t_axis(0.28)
    rng = np.random.default_rng(687)
    bottle = noise(t, rng, 440, 3450, 0.031, attack=0.005) * 0.68
    for at, pitch in [(0.009, 580), (0.077, 406)]:
        bottle += noise(t, rng, 170, 1720, 0.033, at, attack=0.011)
        bottle += sweep_exp(t, pitch, pitch * 0.55, 0.015, at) * env_ad(t, 0.004, 0.039, at) * 0.53
    return master_cue(bottle, level_db=-17.6)


def gun_bleach_burst():
    """Thin glass fractures into a wet splash and short fizz."""
    t = t_axis(0.61)
    rng = np.random.default_rng(688)
    glass = granular_scatter(t, rng, 36, 0.003, 0.14, 2000, 10400, 0.005, gain=0.71, ring_prob=0.55)
    splash = noise(t, rng, 200, 5300, 0.086, attack=0.005) * 1.12
    fizz = noise(t, rng, 1800, 9000, 0.118, 0.07, attack=0.034)
    fizz *= 0.74 + 0.26 * np.sin(2 * np.pi * 31 * t + 1.2 * np.sin(2 * np.pi * 9 * t))
    return master_cue(glass + splash + fizz * 0.75, level_db=-13.6)


def gun_bait_radio():
    """A battery case clacks and a thumb switch spits static."""
    t = t_axis(0.29)
    rng = np.random.default_rng(689)
    case = modal_bank(t, [(419, 0.57, 0.041), (1110, 0.3, 0.021), (2350, 0.16, 0.013)])
    click = noise(t, rng, 2700, 6800, 0.005, 0.048) * 0.69
    static = noise(t, rng, 720, 3400, 0.061, 0.055, attack=0.004)
    static *= 0.7 + 0.3 * np.sin(2 * np.pi * 54 * t)
    return master_cue(case + click + static, level_db=-17.4)


def gun_bait_activate():
    """The dropped radio catches its channel as the lure tune starts."""
    t = t_axis(0.31)
    rng = np.random.default_rng(690)
    clunk = modal_bank(t, [(294, 0.55, 0.034), (710, 0.32, 0.020), (1692, 0.24, 0.013)])
    signal = noise(t, rng, 820, 4570, 0.041, attack=0.003) * 0.8
    squelch = sweep_power(t, 2040, 710, 0.076, 0.037) * env_ad(t, 0.004, 0.041, 0.037) * 0.44
    return master_cue(clunk + signal + squelch, level_db=-15.0)


def gun_sandbag():
    """A padded impact with smaller landings as the load settles."""
    t = t_axis(0.36)
    rng = np.random.default_rng(691)
    drop = np.zeros_like(t)
    for at, gain in [(0.0, 1.0), (0.054, 0.46), (0.122, 0.21)]:
        mass = sweep_exp(t, 142, 61, 0.029, at) * env_ad(t, 0.004, 0.058, at)
        cloth = noise(t, rng, 140, 1740, 0.042, at, attack=0.005) * 1.4
        drop += gain * (mass + cloth)
    sand = granular_scatter(t, rng, 37, 0.018, 0.22, 540, 3900, 0.007, gain=0.35)
    return master_cue(drop + sand, level_db=-17.0)


def gun_lightning_rod():
    """A hammered stake rings like a fork over a short induction hum."""
    t = t_axis(0.39)
    rng = np.random.default_rng(692)
    strike = modal_bank(t, [(257, 0.55, 0.035), (1063, 0.61, 0.120), (2964, 0.27, 0.053)])
    strike += noise(t, rng, 370, 7180, 0.015) * 1.26
    hum = sweep_power(t, 106, 218, 0.21, 0.041) + 0.37 * sweep_power(t, 212, 436, 0.21, 0.041)
    hum *= env_ahr(t, 0.015, 0.038, 0.09, 0.041) * 0.33
    return master_cue(strike + hum, level_db=-17.7)


def gun_med_tin():
    """Tin lid pops, then two tablets rattle inside."""
    t = t_axis(0.33)
    rng = np.random.default_rng(693)
    lid = modal_bank(t, [(723, 0.58, 0.039), (1720, 0.49, 0.032), (3515, 0.20, 0.017)], bend_ratio=0.10)
    lid += noise(t, rng, 1700, 8200, 0.011) * 0.74
    for at, gain in [(0.047, 0.72), (0.081, 0.56), (0.134, 0.42), (0.156, 0.29)]:
        lid += modal_bank(t, [(2210, gain * 0.37, 0.013), (4960, gain * 0.28, 0.008)], start=at)
        lid += gain * 0.38 * noise(t, rng, 3000, 8600, 0.007, at)
    return master_cue(lid, level_db=-17.5)


def gun_suit_patch():
    """A backing strip peels away, then the rubber patch seats."""
    t = t_axis(0.42)
    rng = np.random.default_rng(694)
    peel = swept_bp_noise(t, rng, 1360 + 3250 * np.exp(-t / 0.076), q=1.6)
    peel *= env_ahr(t, 0.009, 0.096, 0.046) * (0.77 + 0.23 * np.sin(2 * np.pi * (26 * t + 79 * t ** 2)))
    rip = granular_scatter(t, rng, 23, 0.005, 0.16, 2350, 8420, 0.006, gain=0.52)
    press = sweep_exp(t, 230, 88, 0.023, 0.176) * env_ad(t, 0.008, 0.054, 0.176) * 0.54
    press += noise(t, rng, 250, 2530, 0.058, 0.176, attack=0.011) * 0.8
    return master_cue(peel + rip + press, level_db=-17.7)


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
    cues = (
        gun_nail_driver, gun_hunting_rifle, gun_pressure_washer, gun_rock_salt, gun_battery_zapper,
        gun_flare_launcher, gun_harpoon, gun_leaf_blower, gun_disruptor, gun_frag_throw, gun_frag_blast,
        gun_dome_throw, gun_dome_expand, gun_umbrella, gun_umbrella_open, gun_bleach_bomb,
        gun_bleach_burst, gun_bait_radio, gun_bait_activate, gun_sandbag,
        gun_lightning_rod, gun_med_tin, gun_suit_patch,
    )
    for synth in cues:
        write(synth.__name__, synth())
    write("gun_field_deploy", chirps([390, 540, 780], 0.44, 0.065))
    write("gun_supply_drop", chirps([330, 392, 523, 784], 0.8, 0.115))
    write("gun_bait_loop", chirps([262, 330, 392, 330, 294, 349, 440, 349], 1.8, 0.195))
    t = t_axis(0.88)
    signal = sweep(135 + 580 * t**1.5) * np.sin(np.pi * t / 0.9)
    signal *= 0.65 + 0.35 * np.sin(2 * np.pi * t * 31)
    write("gun_disruptor_charge", finish(signal, 0.63))


if __name__ == "__main__":
    main()
