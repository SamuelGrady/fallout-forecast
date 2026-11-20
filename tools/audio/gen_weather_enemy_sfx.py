"""Generate weather infected telegraphs and the incoming group sting.

Run from the repository root with Python and numpy.
"""
import numpy as np

from gen_juice_sfx import SR, env, finish, lowpass, t_axis, write


def sweep(frequency):
    return np.sin(2 * np.pi * np.cumsum(frequency) / SR)


def pulse(t, frequency, start, decay):
    return np.sin(2 * np.pi * frequency * (t - start)) * env(t, decay, start)


def main():
    rng = np.random.default_rng(1987)

    t = t_axis(.32)
    x = sum(pulse(t, f, i * .065, .033) for i, f in enumerate((1250, 1990, 2880)))
    write("sleet_leap", finish(x + rng.normal(0, .24, t.size) * env(t, .12)))

    t = t_axis(.92)
    rumble = lowpass(rng.standard_normal(t.size), 470)
    x = (rumble + .43 * sweep(64 + 48 * t)) * (t / .92) ** .7
    x += sum(pulse(t, 280 + 20 * i, i * .19, .031) for i in range(4)) * .42
    write("hailstone_charge", finish(x))
    t = t_axis(.49)
    x = lowpass(rng.standard_normal(t.size), 975) * env(t, .10)
    x += .55 * sweep(48 + 46 * np.exp(-t * 31)) * env(t, .12)
    write("hailstone_crash", finish(x))

    t = t_axis(.43)
    x = sum(.45 * pulse(t, 270 - i * 37, i * .068, .06) for i in range(4))
    write("undertow_lurk", finish(x))
    t = t_axis(.61)
    water = lowpass(rng.standard_normal(t.size), 1900)
    x = .40 * sweep(132 + 1030 * t ** 2) * np.sin(np.pi * t / .61)
    x += water * (.36 * env(t, .061) + .83 * env(t, .072, .33))
    write("undertow_emerge", finish(x))

    for name, seconds, low, high in (
        ("static_shock", .57, 440, 1800),
        ("static_power", .54, 225, 960),
        ("static_blink", .21, 1300, 300),
    ):
        t = t_axis(seconds)
        buzz = np.sign(sweep(low + (high - low) * t / seconds))
        crackle = rng.standard_normal(t.size)
        gate = .14 + .86 * (np.sin(2 * np.pi * (21 * t + 18 * t ** 2)) > .42)
        x = (.48 * buzz + .23 * crackle) * gate * np.minimum(t * 35, 1)
        write(name, finish(x))

    t = t_axis(.68)
    bubbles = sum(pulse(t, f, i * .102, .08) for i, f in enumerate((150, 220, 165, 300, 116)))
    x = .56 * bubbles + .77 * lowpass(rng.standard_normal(t.size), 670) * (t / .68) ** .6
    write("smog_spit", finish(x))
    t = t_axis(.55)
    noise = rng.standard_normal(t.size)
    x = (lowpass(noise, 2900) - .7 * lowpass(noise, 420)) * env(t, .09)
    x += .42 * sweep(82 + 270 * np.exp(-t * 21)) * env(t, .095)
    write("smog_splash", finish(x))

    t = t_axis(1.72)
    rate = np.cumsum(3 + 11 * (t / 1.72) ** 2) / SR
    ticks = (.5 + .5 * np.cos(2 * np.pi * rate)) ** 8
    x = (.41 * sweep(53 + 35 * t) + .33 * sweep(320 + 555 * t)) * (.26 + .74 * ticks)
    x += .32 * lowpass(rng.standard_normal(t.size), 1300) * ticks
    write("thunderhead_fuse", finish(x * np.minimum(1.0, t * 8)))

    t = t_axis(.47)
    x = sum(pulse(t, f, i * .08, .09) for i, f in enumerate((620, 435, 620)))
    x += .22 * lowpass(rng.standard_normal(t.size), 1240) * env(t, .16)
    write("incoming_group", finish(x))


if __name__ == "__main__":
    main()
