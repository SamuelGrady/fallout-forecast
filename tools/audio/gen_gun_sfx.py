"""Synthesize Fallout Forecast's core and cursed firearm reports.

Gunpowder reports combine a fast crack, muzzle-blast body, mechanical detail
and outdoor reflections. Cursed variants add coin, compressor and tape-deck
textures. Fixed seeds produce reproducible 44.1 kHz mono 16-bit WAVs.

Run from the repository root: python tools/audio/gen_gun_sfx.py
Requires NumPy.
"""
import argparse
import os
import wave

import numpy as np

SR = 44100
OUT = os.path.join("assets", "audio", "sfx")


# ---------------------------------------------------------------------------
# Legacy helpers preserved verbatim for gen_storm_sfx.py and unchanged cues
# (hit_flesh, shotgun_pump, rifle_reload).
# ---------------------------------------------------------------------------

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


# ---------------------------------------------------------------------------
# Shared synthesis and mastering for weapon and item cues
# ---------------------------------------------------------------------------

def _rfft_padded(x):
    n = x.size
    nfft = 1 << int(np.ceil(np.log2(max(n * 2, 1024))))
    return np.fft.rfft(x, nfft), np.fft.rfftfreq(nfft, 1.0 / SR), n, nfft


def fft_lp(x, cutoff, order=3):
    spec, freqs, n, nfft = _rfft_padded(x)
    ratio = freqs / max(float(cutoff), 1.0)
    resp = 1.0 / np.sqrt(1.0 + np.power(ratio, 2 * order))
    return np.fft.irfft(spec * resp, nfft)[:n]


def fft_hp(x, cutoff, order=3):
    spec, freqs, n, nfft = _rfft_padded(x)
    ratio = max(float(cutoff), 1.0) / np.maximum(freqs, 1e-6)
    resp = 1.0 / np.sqrt(1.0 + np.power(ratio, 2 * order))
    resp[0] = 0.0
    return np.fft.irfft(spec * resp, nfft)[:n]


def fft_bp(x, low, high, order=3):
    spec, freqs, n, nfft = _rfft_padded(x)
    r_lo = max(float(low), 1.0) / np.maximum(freqs, 1e-6)
    r_hi = freqs / max(float(high), 1.0)
    resp = (1.0 / np.sqrt(1.0 + np.power(r_lo, 2 * order))) * (1.0 / np.sqrt(1.0 + np.power(r_hi, 2 * order)))
    resp[0] = 0.0
    return np.fft.irfft(spec * resp, nfft)[:n]


def fft_peak(x, center, q, gain_db):
    """Parametric bell EQ (positive gain_db boosts, negative cuts)."""
    spec, freqs, n, nfft = _rfft_padded(x)
    g = 10.0 ** (gain_db / 20.0)
    bw = max(float(center) / max(float(q), 0.2), 10.0)
    bell = np.exp(-0.5 * ((freqs - center) / (bw * 0.6)) ** 2)
    resp = 1.0 + (g - 1.0) * bell
    return np.fft.irfft(spec * resp, nfft)[:n]


def env_ad(t, attack, decay, start=0.0):
    dt = t - start
    a = np.clip(dt / max(attack, 1.0 / SR), 0.0, 1.0)
    d = np.exp(-np.maximum(dt, 0.0) / max(decay, 1e-4))
    out = a * d
    out[dt < 0.0] = 0.0
    return out


def env_ahr(t, attack, hold, release, start=0.0):
    dt = t - start
    out = np.zeros_like(t)
    mask = dt >= 0.0
    dtm = dt[mask]
    atk = np.clip(dtm / max(attack, 1.0 / SR), 0.0, 1.0)
    rel = np.exp(-np.maximum(dtm - attack - hold, 0.0) / max(release, 1e-4))
    out[mask] = atk * rel
    return out


def sweep_exp(t, f0, f1, glide, start=0.0, phase0=0.0):
    dt = np.maximum(t - start, 0.0)
    freq = f1 + (f0 - f1) * np.exp(-dt / max(glide, 1e-4))
    freq = np.where(t >= start, freq, 0.0)
    phase = phase0 + 2.0 * np.pi * np.cumsum(freq) / SR
    out = np.sin(phase)
    out[t < start] = 0.0
    return out


def sweep_power(t, f0, f1, duration, start=0.0, power=1.0, phase0=0.0):
    dt = np.clip((t - start) / max(duration, 1e-4), 0.0, 1.0)
    freq = f0 + (f1 - f0) * (dt ** power)
    freq = np.where(t >= start, freq, 0.0)
    phase = phase0 + 2.0 * np.pi * np.cumsum(freq) / SR
    out = np.sin(phase)
    out[t < start] = 0.0
    return out


def modal_bank(t, modes, start=0.0, attack=0.0005, bend_ratio=0.0, bend_time=0.012):
    """Sum of damped physical resonator modes: (freq, amp, decay) tuples."""
    dt = t - start
    active = dt >= 0.0
    if not np.any(active):
        return np.zeros_like(t)
    out = np.zeros_like(t)
    dtm = dt[active]
    atk = np.clip(dtm / max(attack, 1.0 / SR), 0.0, 1.0)
    for freq, amp, decay in modes:
        if bend_ratio != 0.0:
            f_inst = freq * (1.0 + bend_ratio * np.exp(-dtm / max(bend_time, 1e-4)))
            ph = 2.0 * np.pi * np.cumsum(f_inst) / SR
        else:
            ph = 2.0 * np.pi * freq * dtm
        out[active] += amp * np.sin(ph) * np.exp(-dtm / max(decay, 1e-4)) * atk
    return out


def swept_bp_noise(t, rng, f_curve, q=2.2, n_bands=10):
    """Time-varying resonant bandpass noise following frequency array `f_curve`."""
    raw = rng.standard_normal(t.size)
    f_min = max(float(np.min(f_curve)) * 0.75, 60.0)
    f_max = min(float(np.max(f_curve)) * 1.25, SR * 0.45)
    centers = np.geomspace(f_min, max(f_max, f_min * 1.2), n_bands)
    log_c = np.log(centers)
    log_f = np.log(np.clip(f_curve, f_min, f_max))
    step = (log_c[-1] - log_c[0]) / max(n_bands - 1, 1)
    out = np.zeros_like(t)
    for c, lc in zip(centers, log_c):
        bw = c / max(q, 0.5)
        band = fft_bp(raw, max(c - bw * 0.55, 35.0), min(c + bw * 0.55, SR * 0.46), order=2)
        w = np.exp(-0.5 * ((log_f - lc) / max(step * 0.85, 0.08)) ** 2)
        out += band * w
    return out


def granular_scatter(t, rng, count, start, span, f_lo, f_hi, grain_decay, gain=1.0,
                     density_power=1.4, ring_prob=0.0):
    """Scatter `count` crisp physical micro-grains across [start, start + span]."""
    out = np.zeros_like(t)
    raw = rng.standard_normal(t.size)
    filtered = fft_bp(raw, f_lo, f_hi, order=2)
    offsets = start + span * (rng.random(count) ** density_power)
    amps = rng.uniform(0.35, 1.0, count) * gain
    decays = grain_decay * rng.uniform(0.55, 1.65, count)
    win_len = min(int(SR * grain_decay * 6.5) + 32, t.size)
    lt = np.arange(win_len) / SR
    for off, amp, dec in zip(offsets, amps, decays):
        i0 = int(off * SR)
        if i0 >= t.size:
            continue
        i1 = min(i0 + win_len, t.size)
        n = i1 - i0
        e = np.exp(-lt[:n] / dec) * np.minimum(lt[:n] / 0.0004, 1.0)
        chunk = filtered[i0:i1] * e * amp
        if ring_prob > 0.0 and rng.random() < ring_prob:
            rf = rng.uniform(f_lo * 1.1, min(f_hi * 0.9, 9500.0))
            chunk = chunk + 0.35 * amp * np.sin(2.0 * np.pi * rf * lt[:n]) * np.exp(-lt[:n] / (dec * 1.8))
        out[i0:i1] += chunk
    return out


def street_slapback(x, taps, tail_decay=0.0, tail_lp=950.0, tail_gain=0.0, rng=None):
    """Multi-tap outdoor concrete street reflections + optional diffuse canyon tail."""
    out = x.copy()
    n = x.size
    for at, gain, cutoff in taps:
        d = int(SR * at)
        if 0 < d < n:
            delayed = fft_lp(x[:n - d], cutoff, order=2) * gain
            out[d:] += delayed
    if tail_gain > 0.0 and tail_decay > 0.0:
        r = rng if rng is not None else np.random.default_rng(777)
        ir_len = min(int(SR * min(tail_decay * 4.5, 1.1)), n)
        it = np.arange(ir_len) / SR
        ir = r.standard_normal(ir_len) * np.exp(-it / tail_decay)
        ir *= np.minimum(it / 0.018, 1.0)  # pre-delay bloom
        ir = fft_lp(ir, tail_lp, order=2)
        ir /= max(np.sqrt(np.sum(ir ** 2)), 1e-6)
        nfft = 1 << int(np.ceil(np.log2(n + ir_len)))
        wet = np.fft.irfft(np.fft.rfft(x, nfft) * np.fft.rfft(ir, nfft), nfft)[:n]
        out += wet * tail_gain
    return out


def master_cue(x, level_db=-15.0, peak_db=-2.5, drive=1.25, fade_in=0.0005, fade_out=0.035):
    """Level-match the loudest 50 ms while reserving headroom for stacked fire."""
    x = fft_hp(x, 35, order=2)
    window = int(SR * 0.05)
    energy = np.cumsum(np.r_[0.0, x * x])
    rms = np.sqrt(np.max(energy[window:] - energy[:-window]) / window)
    target = 10.0 ** (level_db / 20.0)
    ceiling = 10.0 ** (peak_db / 20.0)
    # Soft knee and tape-head rolloff before the final peak check.
    y = ceiling * np.tanh(x * target * drive / max(rms * ceiling, 1e-9))
    y = fft_lp(y, 13000, order=2)
    y *= min(1.0, ceiling / max(np.max(np.abs(y)), 1e-9))
    n_in = int(SR * fade_in)
    n_out = int(SR * fade_out)
    y[:n_in] *= np.linspace(0.0, 1.0, n_in)
    y[-n_out:] *= 0.5 + 0.5 * np.cos(np.linspace(0.0, np.pi, n_out))
    return y


# ---------------------------------------------------------------------------
# Core and cursed firearms, plus flare ignition
# ---------------------------------------------------------------------------

def gun_revolver():
    """Service Revolver (.38/.357 snub): crisp bark, iron cylinder snap, tight street slapback."""
    rng = np.random.default_rng(1037)
    t = t_axis(0.62)
    n = rng.standard_normal(t.size)

    # Hammer drop & primer snap at t=0
    primer = fft_bp(n, 2800, 8200, order=2) * env_ad(t, 0.0003, 0.0032) * 1.25
    frame = modal_bank(t, [(1920, 0.24, 0.011), (3480, 0.16, 0.008), (5200, 0.09, 0.006)], start=0.0)

    # Authoritative snub-nose bark (forward mid-high crack + tight powder body)
    crack = fft_bp(rng.standard_normal(t.size), 1500, 8800, order=2) * env_ad(t, 0.0005, 0.011, 0.001) * 1.45
    body = fft_bp(rng.standard_normal(t.size), 220, 2500, order=2) * env_ad(t, 0.0012, 0.048, 0.0015) * 1.25
    chest = sweep_exp(t, 168, 50, 0.026, 0.001) * env_ad(t, 0.001, 0.068, 0.001) * 1.35

    # Crisp steel cylinder stop/index snap just after ignition
    cyl = modal_bank(t, [(3350, 0.14, 0.009), (5850, 0.08, 0.006)], start=0.024)
    cyl += fft_bp(rng.standard_normal(t.size), 3200, 7500) * env_ad(t, 0.0003, 0.0022, 0.024) * 0.28

    dry = primer + frame + crack + body + chest + cyl
    dry = fft_peak(dry, 1350, 1.4, 3.0)
    wet = street_slapback(
        dry,
        taps=[(0.092, 0.36, 1750), (0.205, 0.20, 1150), (0.355, 0.11, 760)],
        tail_decay=0.18,
        tail_lp=920,
        tail_gain=0.22,
        rng=rng,
    )
    return master_cue(wet, level_db=-14.6, drive=1.3, fade_in=0.0003, fade_out=0.06)


def gun_shotgun():
    """Pump Shotgun (12-gauge): thunderous chest punch, wide scatter blast, canyon echo."""
    rng = np.random.default_rng(1023)
    t = t_axis(0.92)
    n = rng.standard_normal(t.size)

    # Heavy receiver slam + blistering high-SPL muzzle crack
    breech = modal_bank(t, [(290, 0.32, 0.024), (1180, 0.18, 0.015), (2420, 0.12, 0.010)], start=0.0)
    crack = fft_bp(n, 1600, 9800, order=2) * env_ad(t, 0.0004, 0.015, 0.001) * 1.45

    # Massive 12-gauge chest punch + sub-bass weight
    punch = sweep_exp(t, 128, 34, 0.042, 0.001) * env_ad(t, 0.001, 0.145, 0.001) * 1.75
    sub = sweep_exp(t, 72, 27, 0.055, 0.002) * env_ad(t, 0.002, 0.175, 0.002) * 1.15

    # Wide fiery scatter blast + buckshot wad burst
    roar = fft_bp(rng.standard_normal(t.size), 140, 4600, order=2) * env_ad(t, 0.002, 0.088, 0.0015) * 1.55
    wad = granular_scatter(t, rng, 18, 0.004, 0.045, 1800, 7200, 0.0045, gain=0.45)

    dry = breech + crack + punch + sub + roar + wad
    dry = fft_peak(dry, 95, 1.1, 3.5)
    wet = street_slapback(
        dry,
        taps=[(0.115, 0.38, 1450), (0.235, 0.25, 1020), (0.40, 0.15, 720), (0.61, 0.09, 520)],
        tail_decay=0.32,
        tail_lp=780,
        tail_gain=0.34,
        rng=rng,
    )
    return master_cue(wet, level_db=-12.8, drive=1.28, fade_in=0.0003, fade_out=0.08)


def gun_rifle():
    """Spray Rifle (5.56 carbine): snappy crack, crisp bolt-carrier clack, clean rapid auto."""
    rng = np.random.default_rng(1011)
    t = t_axis(0.31)
    n = rng.standard_normal(t.size)

    # Razor supersonic whip-crack
    crack = fft_bp(n, 2300, 10800, order=2) * env_ad(t, 0.0003, 0.006, 0.0) * 1.55
    # Focused carbine bark & snappy punch
    body = fft_bp(rng.standard_normal(t.size), 320, 3100, order=2) * env_ad(t, 0.0008, 0.032, 0.0008) * 1.25
    thump = sweep_exp(t, 182, 60, 0.019, 0.0005) * env_ad(t, 0.0008, 0.044, 0.0005) * 1.20

    # Iconic bolt-carrier steel cycle clack during full-auto fire
    bolt = modal_bank(t, [(2580, 0.26, 0.014), (4120, 0.20, 0.011), (6050, 0.11, 0.007)], start=0.017)
    bolt += fft_bp(rng.standard_normal(t.size), 2800, 7400) * env_ad(t, 0.0003, 0.0025, 0.017) * 0.45

    dry = crack + body + thump + bolt
    dry = fft_peak(dry, 2200, 1.5, 2.5)
    wet = street_slapback(
        dry,
        taps=[(0.078, 0.30, 1850), (0.175, 0.14, 1100)],
        tail_decay=0.11,
        tail_lp=950,
        tail_gain=0.16,
        rng=rng,
    )
    return master_cue(wet, level_db=-15.1, drive=1.3, fade_in=0.0002, fade_out=0.045)


def gun_lucky_penny_revolver():
    """Cursed Lucky Penny Revolver: crisp revolver crack + unmistakable ringing copper coin-spin ping."""
    rng = np.random.default_rng(1091)
    t = t_axis(0.96)
    n = rng.standard_normal(t.size)

    # Leaner, sharper brass-frame revolver bark (distinct from Service Revolver)
    crack = fft_bp(n, 1800, 9500, order=2) * env_ad(t, 0.0003, 0.0085, 0.0) * 1.35
    body = fft_bp(rng.standard_normal(t.size), 280, 2700, order=2) * env_ad(t, 0.001, 0.036, 0.001) * 1.05
    thump = sweep_exp(t, 192, 58, 0.022, 0.0008) * env_ad(t, 0.0008, 0.052, 0.0008) * 1.15
    gun = street_slapback(
        crack + body + thump,
        taps=[(0.088, 0.26, 1650), (0.19, 0.12, 1000)],
        tail_decay=0.14,
        tail_lp=900,
        tail_gain=0.14,
        rng=rng,
    )

    # Brass-on-steel coin flick impact at 14 ms
    flick = fft_bp(rng.standard_normal(t.size), 3800, 10500) * env_ad(t, 0.0003, 0.003, 0.014) * 0.55

    # Coin resonances with amplitude modulation from its spin
    # Inharmonic modes give the jingle a metallic ring.
    base_f = 4120.0
    spin_wobble = 0.72 + 0.28 * np.sin(2.0 * np.pi * 13.5 * np.maximum(t - 0.014, 0.0) + 0.4)
    coin = modal_bank(
        t,
        [
            (base_f, 0.44, 0.36),
            (base_f * 1.505, 0.30, 0.27),
            (base_f * 2.02, 0.18, 0.19),
            (base_f * 2.61, 0.09, 0.12),
            (2760.0, 0.14, 0.15),  # warm copper body harmonic
        ],
        start=0.015,
        attack=0.0006,
        bend_ratio=0.012,
        bend_time=0.010,
    ) * spin_wobble

    # Second faint ricochet shimmer as the lucky coin flips
    coin2 = modal_bank(
        t,
        [(base_f * 1.03, 0.14, 0.22), (base_f * 1.54, 0.09, 0.15)],
        start=0.125,
        attack=0.001,
    ) * (0.75 + 0.25 * np.sin(2.0 * np.pi * 17.0 * t))

    sig = gun * 0.92 + flick + (coin + coin2) * 1.15
    return master_cue(sig, level_db=-14.0, fade_in=0.0003, fade_out=0.07)


def gun_leaky_nailgun():
    """Cursed Leaky Nailgun: heavier unstable metallic slam + wet hissing acid/air leak + erratic rattle."""
    rng = np.random.default_rng(1093)
    t = t_axis(0.46)
    n = rng.standard_normal(t.size)

    # Heavy over-pressurized unstable striker slam (meaner & lower than standard nail_driver)
    punch = sweep_exp(t, 168, 54, 0.022, 0.0) * env_ad(t, 0.0006, 0.044, 0.0) * 1.35
    anvil = modal_bank(
        t,
        [(455, 0.42, 0.042), (1085, 0.32, 0.032), (2230, 0.24, 0.022), (3880, 0.16, 0.014)],
        start=0.002,
        bend_ratio=-0.045,
        bend_time=0.018,
    )
    snap = fft_bp(n, 1400, 7600, order=2) * env_ad(t, 0.0004, 0.014, 0.001) * 1.15

    # Sinister wet hissing acid/air leak (modulated pressurized hiss + corrosive bubbling gurgle)
    leak_mod = 0.55 + 0.45 * np.sin(2.0 * np.pi * 27.0 * t + 1.4 * np.sin(2.0 * np.pi * 7.5 * t))
    acid_hiss = fft_bp(rng.standard_normal(t.size), 2100, 10200, order=2) * env_ahr(t, 0.006, 0.08, 0.16, 0.005)
    acid_hiss *= (0.65 + 0.50 * leak_mod) * 0.95
    # Wet sputtering acid droplets / bubbling chirps
    bubbles = np.zeros_like(t)
    for b_at in [0.028, 0.062, 0.105, 0.155, 0.215, 0.278]:
        f_b = rng.uniform(750, 1450)
        bubbles += sweep_power(t, f_b, f_b * 1.9, 0.018, b_at, power=1.2) * env_ad(t, 0.0015, 0.012, b_at) * 0.26

    # Erratic cursed internal nail-strip rattle
    rattle = np.zeros_like(t)
    for r_at, r_gain in [(0.048, 0.36), (0.092, 0.26), (0.148, 0.20), (0.195, 0.15)]:
        rattle += modal_bank(
            t,
            [(1840 * rng.uniform(0.92, 1.12), r_gain, 0.014),
             (3420 * rng.uniform(0.92, 1.12), r_gain * 0.65, 0.010)],
            start=r_at,
        )
        rattle += fft_bp(rng.standard_normal(t.size), 2400, 6800) * env_ad(t, 0.0004, 0.003, r_at) * r_gain * 0.6

    sig = punch + anvil + snap + acid_hiss + bubbles + rattle
    sig = street_slapback(sig, taps=[(0.082, 0.18, 1500)], rng=rng)
    return master_cue(sig, level_db=-15.2, fade_in=0.0003, fade_out=0.04)


def gun_boombox_launcher():
    """Cursed Boombox Launcher: 80s gated-reverb bass kick + tape-deck thoomp + distorted synth chord."""
    rng = np.random.default_rng(1097)
    t = t_axis(0.85)
    n = rng.standard_normal(t.size)

    # Cassette-deck transport clunk at t=0
    deck = modal_bank(t, [(360, 0.28, 0.018), (1540, 0.20, 0.011), (3100, 0.12, 0.008)], start=0.0)

    # Gated drum-machine kick and low speaker port resonance
    kick = sweep_exp(t, 162, 41, 0.036, 0.002) * env_ad(t, 0.001, 0.165, 0.002) * 1.85
    port = sweep_exp(t, 98, 64, 0.06, 0.004) * env_ad(t, 0.003, 0.14, 0.004) * 0.95
    # Gated room burst
    gate_env = env_ahr(t, 0.006, 0.21, 0.022, 0.004)
    gated_rev = fft_bp(n, 320, 5600, order=2) * gate_env * 0.92

    # Detuned synth chord slides down as the rocket departs.
    wow = 1.0 + 0.008 * np.sin(2.0 * np.pi * 6.5 * t)
    doppler = 1.0 - 0.16 * np.clip((t - 0.08) / 0.42, 0.0, 1.0)
    chord = np.zeros_like(t)
    for f_note, amp in [(146.83, 0.36), (220.0, 0.30), (293.66, 0.32), (349.23, 0.24), (440.0, 0.16)]:
        for det in (-0.006, 0.006):
            ph = 2.0 * np.pi * np.cumsum(f_note * (1.0 + det) * wow * doppler) / SR
            # Saw-brass harmonic stack
            voice = np.sin(ph) + 0.50 * np.sin(2 * ph) + 0.32 * np.sin(3 * ph) + 0.20 * np.sin(4 * ph)
            chord += voice * amp * 0.5
    chord = np.tanh(chord * 1.9) * env_ahr(t, 0.012, 0.16, 0.20, 0.014)
    chord = fft_bp(chord, 220, 4800, order=2) * 0.85  # boombox speaker EQ

    # Cassette rocket propellant whoosh flying away
    f_whoosh = 1900.0 * np.exp(-np.maximum(t - 0.04, 0.0) / 0.38) + 280.0
    rocket = swept_bp_noise(t, rng, f_whoosh, q=1.5) * env_ahr(t, 0.025, 0.18, 0.30, 0.03) * 0.85

    sig = deck + kick + port + gated_rev + chord + rocket
    sig = fft_peak(sig, 85, 1.2, 3.0)
    sig = street_slapback(sig, taps=[(0.135, 0.26, 1300), (0.28, 0.13, 850)], rng=rng)
    return master_cue(sig, level_db=-12.9, fade_in=0.0004, fade_out=0.075)


def gun_flare():
    """Road Flare ground deploy: asphalt clatter + roaring magnesium pyrotechnic ignition and hiss."""
    rng = np.random.default_rng(1041)
    t = t_axis(0.92)

    # Flare tube hitting wet pavement
    clatter = modal_bank(t, [(420, 0.34, 0.024), (1180, 0.24, 0.016), (2650, 0.14, 0.010)], start=0.0)
    clatter += modal_bank(t, [(460, 0.18, 0.016), (1320, 0.12, 0.012)], start=0.068)
    clatter += fft_bp(rng.standard_normal(t.size), 900, 4200) * env_ad(t, 0.001, 0.014, 0.0) * 0.45

    # Ignition pop + fiery whoosh bloom
    ign = sweep_exp(t, 155, 58, 0.032, 0.025) * env_ad(t, 0.004, 0.085, 0.025) * 0.85
    bloom_f = 650.0 + 1850.0 * np.exp(-np.maximum(t - 0.03, 0.0) / 0.28)
    whoosh = swept_bp_noise(t, rng, bloom_f, q=1.4) * env_ahr(t, 0.022, 0.16, 0.38, 0.025) * 0.95

    # Roaring white-hot magnesium hiss + lively flame flicker + ember crackles
    flicker = 0.65 + 0.35 * np.sin(2.0 * np.pi * 23.0 * t + 2.2 * np.sin(2.0 * np.pi * 6.3 * t))
    hiss = fft_bp(rng.standard_normal(t.size), 1700, 10800, order=2) * env_ahr(t, 0.03, 0.32, 0.32, 0.03)
    hiss *= (0.72 + 0.40 * flicker) * 1.15
    sparks = granular_scatter(t, rng, 46, 0.04, 0.78, 3200, 10500, 0.0038, gain=0.58, density_power=1.0)

    sig = clatter + ign + whoosh + hiss + sparks
    return master_cue(sig, level_db=-15.2, fade_in=0.0005, fade_out=0.085)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--signatures-only", action="store_true", help="skip shared impacts and reloads")
    args = parser.parse_args()
    for synth in (gun_revolver, gun_shotgun, gun_rifle, gun_lucky_penny_revolver,
                  gun_leaky_nailgun, gun_boombox_launcher, gun_flare):
        write(synth.__name__, synth())
    if not args.signatures_only:
        write("hit_flesh", impact(53))
        write("shotgun_pump", pump(61))
        write("rifle_reload", mag_swap(71))


if __name__ == "__main__":
    main()
