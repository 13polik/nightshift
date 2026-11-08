"""NIGHT SHIFT original sound library (offline synthesis, NumPy only).

Renders every audio cue the game uses to assets/audio/<category>/<cue>.wav at 44.1 kHz.
All sounds are synthesised here (modal synthesis, filtered noise, FM, FFT convolution
reverb), so the library is original project work - see assets/ASSET_MANIFEST.md.

    python tools/audio/gen_audio.py [--only cue,cue]

Variants: cues with several takes are written as <cue>_1.wav ... and the game picks one
at random (footsteps, clanks, clicks) to avoid machine-gun repetition.
"""
import argparse
import os
import wave

import numpy as np

SR = 44100
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "audio")
rng_global = np.random.default_rng(7)


# ------------------------------------------------------------------ DSP helpers
def t_axis(sec):
    return np.arange(int(sec * SR)) / SR


def noise(sec, seed=0, color="white"):
    r = np.random.default_rng(seed)
    x = r.standard_normal(int(sec * SR))
    if color == "white":
        return x / 3
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X = np.fft.rfft(x)
    f[0] = 1
    if color == "pink":
        X /= np.sqrt(f)
    elif color == "brown":
        X /= f
    y = np.fft.irfft(X, len(x))
    return y / (np.max(np.abs(y)) + 1e-9) * 0.5


def band(x, lo=20.0, hi=20000.0, soft=1.4):
    """Spectral band-pass with smooth (log-domain) edges."""
    n = len(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    f[0] = 1e-3
    g = np.ones_like(f)
    if lo > 20:
        g *= 1 / (1 + (lo / f) ** (2 * soft))
    if hi < 20000:
        g *= 1 / (1 + (f / hi) ** (2 * soft))
    return np.fft.irfft(np.fft.rfft(x) * g, n)


def peak(x, freqs, q=8.0, gains=None):
    """Resonant peaks (formants / body resonances) applied spectrally."""
    n = len(x)
    f = np.fft.rfftfreq(n, 1 / SR)
    g = np.zeros_like(f)
    for i, fc in enumerate(freqs):
        bw = fc / q
        g += (gains[i] if gains else 1.0) * np.exp(-0.5 * ((f - fc) / bw) ** 2)
    return np.fft.irfft(np.fft.rfft(x) * (0.15 + g), n)


def env_ad(sec, attack, decay_tau, sustain_end=None):
    t = t_axis(sec)
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    d = np.exp(-np.maximum(t - attack, 0) / decay_tau)
    e = a * d
    if sustain_end:
        e *= np.clip((sec - t) / sustain_end, 0, 1)
    return e


def fade(x, fin=0.01, fout=0.05):
    n = len(x)
    i = int(fin * SR)
    o = int(fout * SR)
    if i:
        x[:i] *= np.linspace(0, 1, i)
    if o:
        x[-o:] *= np.linspace(1, 0, o)
    return x


def modal(sec, freqs, decays, amps, seed=0, strike=0.004):
    """Inharmonic modal synthesis - metal, glass, chitin."""
    t = t_axis(sec)
    y = np.zeros_like(t)
    r = np.random.default_rng(seed)
    for f, d, a in zip(freqs, decays, amps):
        y += a * np.sin(2 * np.pi * f * t + r.random() * 6.28) * np.exp(-t / d)
    exc = noise(sec, seed + 1) * np.exp(-t / strike)
    return y + exc * 0.6


def fm(sec, carrier, mod_ratio, index, env=None):
    t = t_axis(sec)
    c = carrier if np.ndim(carrier) else np.full_like(t, carrier)
    phase_c = 2 * np.pi * np.cumsum(c) / SR
    phase_m = 2 * np.pi * np.cumsum(c * mod_ratio) / SR
    idx = index if np.ndim(index) else np.full_like(t, index)
    y = np.sin(phase_c + idx * np.sin(phase_m))
    return y * (env if env is not None else 1)


def saw(freq_arr):
    ph = np.cumsum(freq_arr) / SR
    return 2 * (ph % 1.0) - 1


def reverb(x, decay=1.2, wet=0.3, pre=0.012, tone=4500, seed=99):
    ir_len = int(decay * 3 * SR)
    t = np.arange(ir_len) / SR
    ir = np.random.default_rng(seed).standard_normal(ir_len) * np.exp(-t * 6.9 / (decay * 2))
    ir = band(ir, 120, tone)
    ir[: int(pre * SR)] = 0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    n = len(x) + ir_len
    y = np.fft.irfft(np.fft.rfft(x, n) * np.fft.rfft(ir, n), n)
    out = np.zeros(n)
    out[: len(x)] += x * (1 - wet)
    out += y * wet
    return out


def loopify(x, xfade=0.4):
    """Seamless loop: crossfade the tail into the head."""
    n = int(xfade * SR)
    if n * 2 >= len(x):
        return x
    head = x[:n].copy()
    tail = x[-n:].copy()
    k = np.linspace(0, 1, n)
    out = x[:-n].copy()
    out[:n] = head * k + tail * (1 - k)
    return out


def norm(x, peak_db=-1.0):
    p = np.max(np.abs(x)) + 1e-9
    return x / p * (10 ** (peak_db / 20))


def soft_clip(x, drive=2.0):
    return np.tanh(x * drive) / np.tanh(drive)


def write(cat, name, x, stereo=None, peak_db=-1.0):
    d = os.path.join(OUT, cat)
    os.makedirs(d, exist_ok=True)
    if stereo is not None:
        left, right = norm(x, peak_db), norm(stereo, peak_db)
        data = np.stack([left, right], -1)
        ch = 2
    else:
        data = norm(x, peak_db)[:, None]
        ch = 1
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(os.path.join(d, f"{name}.wav"), "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# ------------------------------------------------------------------ ambience (loops)
def amb_vent():
    x = band(noise(12, 1, "pink"), 90, 2400) + band(noise(12, 3, "brown"), 30, 300) * 0.8
    t = t_axis(12)
    x *= 0.8 + 0.2 * np.sin(2 * np.pi * t / 6) * np.sin(2 * np.pi * t / 4)
    rattle = band(noise(12, 4), 900, 3500) * (np.sin(2 * np.pi * 7.3 * t) > 0.92) * 0.25
    write("ambience", "amb_vent", loopify(x + rattle, 1.0))


def amb_hum():
    t = t_axis(8)
    flutter = 1 + 0.002 * np.sin(2 * np.pi * 0.25 * t)
    x = sum(a * np.sin(2 * np.pi * 50 * k * flutter * t) for k, a in ((1, 1.0), (2, 0.5), (3, 0.35), (4, 0.12), (6, 0.08)))
    x += band(noise(8, 5), 2000, 7000) * 0.05 * (1 + np.sin(2 * np.pi * 100 * t))
    write("ambience", "amb_hum", loopify(x, 0.5))


def amb_drone():
    t = t_axis(16)
    chans = []
    for seed, det in ((11, 0.0), (12, 0.6)):
        y = np.zeros_like(t)
        for f, a in ((41.2, 1.0), (61.7, 0.6), (82.4, 0.45), (123.5, 0.25), (87.3 + det, 0.3)):
            lfo = 1 + 0.003 * np.sin(2 * np.pi * (0.05 + seed * 0.003) * t + seed)
            y += a * saw(np.full_like(t, f) * lfo)
        y = band(y, 30, 600)
        y += band(noise(16, seed, "brown"), 20, 200) * 0.6
        y *= 0.75 + 0.25 * np.sin(2 * np.pi * t / 16 + seed)
        chans.append(loopify(reverb(y, 3.0, 0.4, seed=seed)[: len(t)], 2.0))
    write("ambience", "amb_drone", chans[0], chans[1], -3)


def amb_distant():
    for v in range(1, 4):
        sec = 4.0
        x = modal(sec, [55 * v * 0.9, 133, 211 + v * 17, 347, 589], [1.2, 0.9, 0.6, 0.4, 0.25], [1, 0.7, 0.5, 0.35, 0.2], seed=v, strike=0.02)
        x = band(x, 40, 1800)
        x = reverb(x, 3.5, 0.75, 0.05, 2000, seed=v)
        write("ambience", f"amb_distant_{v}", fade(x[: int(5.5 * SR)], 0.002, 1.0))


def amb_creak():
    for v in range(1, 3):
        sec = 2.4
        t = t_axis(sec)
        f = 90 + 40 * np.sin(2 * np.pi * (0.7 + v * 0.2) * t) + 25 * np.random.default_rng(v).standard_normal(len(t)).cumsum() / 400
        stick = (np.sin(2 * np.pi * np.cumsum(f * 0.25) / SR) > 0.6).astype(float)
        x = saw(f) * (0.5 + stick) * env_ad(sec, 0.3, 1.5, 0.5)
        x = peak(x, [400, 1100, 2400], 5)
        write("ambience", f"amb_creak_{v}", reverb(x, 1.6, 0.4)[: int(3.2 * SR)])


def amb_drip():
    for v in range(1, 4):
        sec = 0.8
        t = t_axis(sec)
        f0 = 900 + v * 260
        x = np.sin(2 * np.pi * np.cumsum(f0 * (1 + 1.2 * np.exp(-t * 40))) / SR) * np.exp(-t * 18)
        write("ambience", f"amb_drip_{v}", reverb(x, 1.8, 0.5)[: int(2.0 * SR)])


# ------------------------------------------------------------------ music layers (stereo loops)
def music_tension():
    sec = 16.0
    t = t_axis(sec)
    chans = []
    for c in range(2):
        y = np.zeros_like(t)
        for i, f in enumerate((220.0, 233.08, 329.6, 311.1)):
            det = 1 + 0.003 * np.sin(2 * np.pi * (0.11 + i * 0.03 + c * 0.02) * t)
            y += saw(np.full_like(t, f) * det) * (0.5 + 0.5 * np.sin(2 * np.pi * t / (8 + i * 2) + i + c))
        y = band(y, 150, 1800)
        y += band(noise(sec, 20 + c), 3000, 9000) * 0.03 * (np.sin(2 * np.pi * 6 * t) > 0)
        chans.append(loopify(reverb(y, 4.0, 0.55, seed=30 + c)[: len(t)], 2.0))
    write("music", "music_tension", chans[0], chans[1], -4)


def music_pulse():
    sec = 4.0  # 60 bpm double beat
    t = t_axis(sec)
    y = np.zeros_like(t)
    for beat in np.arange(0, sec, 1.0):
        for off, amp in ((0.0, 1.0), (0.27, 0.6)):
            tt = t - beat - off
            m = tt >= 0
            y[m] += amp * np.sin(2 * np.pi * (48 + 30 * np.exp(-tt[m] * 30)) * tt[m]) * np.exp(-tt[m] * 9)
    y = band(y, 25, 400)
    write("music", "music_pulse", loopify(reverb(y, 1.5, 0.25)[: len(t)], 0.05), None, -2)


def music_chase():
    sec = 4.0  # 120 bpm, 2 bars
    t = t_axis(sec)
    chans = []
    for c in range(2):
        y = np.zeros_like(t)
        for k, beat in enumerate(np.arange(0, sec, 0.25)):
            tt = t - beat
            m = tt >= 0
            if k % 4 == 0 or k % 8 == 6:
                y[m] += np.sin(2 * np.pi * (50 + 90 * np.exp(-tt[m] * 35)) * tt[m]) * np.exp(-tt[m] * 7) * 1.2
            if k % 2 == 1:
                y[m] += band(noise(sec, k + c), 2000, 9000)[m] * np.exp(-tt[m] * 40) * 0.25
        ost = saw(np.where((t * 4).astype(int) % 8 < 6, 110.0, 116.5)) * 0.25
        ost = band(ost, 80, 1200) * (0.6 + 0.4 * ((t * 8) % 1 < 0.6))
        y += ost
        chans.append(loopify(soft_clip(reverb(y, 1.2, 0.25, seed=40 + c)[: len(t)], 1.6), 0.02))
    write("music", "music_chase", chans[0], chans[1], -2)


# ------------------------------------------------------------------ player / foley
def footsteps():
    for v in range(1, 5):
        sec = 0.35
        t = t_axis(sec)
        heel = band(noise(sec, 50 + v), 120, 2500) * np.exp(-t / 0.018)
        scuff = band(noise(sec, 60 + v), 800, 6000) * np.exp(-np.maximum(t - 0.04, 0) / 0.03) * (t > 0.04) * 0.4
        thump = np.sin(2 * np.pi * (85 + v * 6) * t) * np.exp(-t / 0.04) * 0.8
        gear = modal(sec, [1800 + v * 90, 2700, 3900], [0.05, 0.04, 0.03], [0.15, 0.1, 0.08], seed=v) * 0.3
        write("foley", f"step_player_{v}", reverb(heel + scuff + thump + gear, 0.5, 0.18)[: int(0.6 * SR)])


def foley():
    t = t_axis(0.5)
    write("foley", "player_hurt", reverb(band(noise(0.5, 70), 200, 3000) * np.exp(-t / 0.06) + np.sin(2 * np.pi * 140 * t) * np.exp(-t / 0.08), 0.6, 0.2))
    s = 0.9
    tt = t_axis(s)
    write("foley", "heal", reverb(band(noise(s, 71), 2000, 8000) * env_ad(s, 0.05, 0.3) * 0.4 + np.sin(2 * np.pi * np.cumsum(400 + 400 * tt / s) / SR) * env_ad(s, 0.05, 0.4) * 0.3, 0.8, 0.3))
    write("foley", "pickup", reverb(modal(0.5, [1320, 1980, 2640], [0.15, 0.1, 0.08], [0.6, 0.3, 0.2], seed=72) + band(noise(0.5, 73), 1000, 5000) * np.exp(-t_axis(0.5) / 0.03) * 0.5, 0.5, 0.2))
    write("foley", "flashlight", band(noise(0.06, 74), 1500, 9000) * np.exp(-t_axis(0.06) / 0.005) + modal(0.06, [3200, 5100], [0.01, 0.008], [0.4, 0.2], seed=75))
    s = 1.4
    tt = t_axis(s)
    write("foley", "downed", reverb(band(noise(s, 76, "pink"), 100, 1500) * env_ad(s, 0.02, 0.4) + np.sin(2 * np.pi * np.cumsum(180 - 120 * tt / s) / SR) * env_ad(s, 0.05, 0.6) * 0.5, 1.4, 0.35))
    s = 1.2
    tt = t_axis(s)
    rum = np.zeros_like(tt)
    for k in range(6):
        tk = tt - k * 0.16 - 0.02 * k
        m = tk >= 0
        rum[m] += band(noise(s, 80 + k), 300, 4000)[m] * np.exp(-tk[m] / 0.05) * (0.6 + 0.4 * (k % 2))
    write("foley", "search", reverb(rum + modal(s, [900, 1500], [0.05, 0.04], [0.2, 0.1], seed=81) * 0.3, 0.7, 0.2))
    s = 0.9
    tt = t_axis(s)
    zap = band(noise(s, 82), 1500, 12000) * (np.sin(2 * np.pi * 60 * tt) > 0.2) * np.exp(-tt / 0.35)
    write("foley", "stun", reverb(soft_clip(zap + fm(s, 2400, 1.41, 6, np.exp(-tt / 0.3)) * 0.3, 3), 0.8, 0.25))


# ------------------------------------------------------------------ doors / machines
def doors():
    for name, rev in (("door_open", False), ("door_close", True)):
        s = 1.1
        tt = t_axis(s)
        prog = tt / s if not rev else 1 - tt / s
        servo = np.sin(2 * np.pi * np.cumsum(220 + 160 * prog) / SR) * 0.25 + saw(440 + 320 * prog) * 0.06
        rumble = band(noise(s, 90 if rev else 91, "brown"), 40, 400) * 0.8
        x = (servo + rumble) * env_ad(s, 0.08, 10, 0.2)
        clunk_t = tt - 0.95
        m = clunk_t >= 0
        x[m] += modal(s, [95, 210, 480, 1150], [0.25, 0.15, 0.08, 0.05], [1, 0.6, 0.3, 0.2], seed=92)[: m.sum()] * 1.2
        write("doors", name, reverb(x, 1.0, 0.3)[: int(2.0 * SR)])
    s = 0.4
    write("doors", "door_locked", reverb(soft_clip(saw(np.full(int(s * SR), 140.0)) * env_ad(s, 0.005, 0.2) * 0.6 + modal(s, [600, 1300], [0.05, 0.03], [0.3, 0.2], seed=93), 2), 0.5, 0.2))
    for v in range(1, 3):
        s = 1.2
        x = modal(s, [70 + v * 9, 160, 310 + v * 20, 720, 1500], [0.6, 0.4, 0.3, 0.2, 0.1], [1, 0.8, 0.6, 0.4, 0.2], seed=94 + v, strike=0.03)
        x = soft_clip(x * 1.5, 2) + band(noise(s, 96 + v), 200, 3000) * np.exp(-t_axis(s) / 0.06) * 0.7
        write("doors", f"door_bash_{v}", reverb(x, 1.8, 0.35))


def machines():
    s = 6.0
    tt = t_axis(s)
    fire = 28.0
    eng = sum(a * np.sin(2 * np.pi * fire * k * tt) for k, a in ((1, 1.0), (2, 0.6), (3, 0.4), (5, 0.2), (8, 0.1)))
    eng *= 1 + 0.35 * (np.sin(2 * np.pi * fire / 2 * tt) > 0.3)
    eng += band(noise(s, 100, "brown"), 30, 500) * 0.8 + band(noise(s, 101), 1500, 6000) * 0.08
    write("machines", "generator_loop", loopify(soft_clip(eng * 0.6, 1.5), 0.5))
    s = 3.0
    tt = t_axis(s)
    sweep = 30 + 230 * (tt / s) ** 1.5
    pu = saw(sweep) * 0.3 + np.sin(2 * np.pi * np.cumsum(sweep * 2) / SR) * 0.3 + band(noise(s, 102), 1000, 6000) * 0.1 * tt / s
    write("machines", "power_up", reverb(pu * env_ad(s, 0.2, 10, 0.6), 2.0, 0.35))
    sweep = 230 * (1 - tt / s) ** 1.2 + 25
    pd = saw(sweep) * 0.3 + np.sin(2 * np.pi * np.cumsum(sweep * 2) / SR) * 0.3
    pd[: int(0.08 * SR)] += band(noise(0.08, 103), 400, 6000) * 2
    write("machines", "power_down", reverb(pd * env_ad(s, 0.005, 10, 1.0), 2.5, 0.4))
    s = 2.0
    tt = t_axis(s)
    write("machines", "elevator", loopify(band(noise(s, 104, "brown"), 40, 300) + np.sin(2 * np.pi * 70 * tt) * 0.3 + saw(np.full_like(tt, 140.0)) * 0.04, 0.3))
    s = 2.0
    tt = t_axis(s)
    alarm = np.where((tt % 1.0) < 0.5, 1.0, 0.0)
    f = np.where(alarm > 0, 660.0, 495.0)
    x = saw(f) * 0.5 + np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.5
    x = peak(x, [700, 1400, 2800], 4)
    write("machines", "alarm", loopify(reverb(soft_clip(x, 1.5), 1.6, 0.35)[: len(tt)], 0.02))
    s = 3.0
    tt = t_axis(s)
    horn = sum(saw(np.full_like(tt, 110.0 * k * (1 + 0.004 * k))) / k for k in range(1, 5))
    write("machines", "evac_horn", reverb(band(horn, 80, 2500) * env_ad(s, 0.25, 10, 0.8), 3.0, 0.5))
    s = 1.0
    tt = t_axis(s)
    beeps = np.zeros_like(tt)
    r = np.random.default_rng(105)
    for k in range(9):
        st = r.uniform(0, 0.9)
        m = (tt >= st) & (tt < st + 0.05)
        beeps[m] += np.sin(2 * np.pi * r.uniform(1400, 2600) * tt[m]) * 0.3
    write("machines", "interact_loop", loopify(beeps + band(noise(s, 106), 200, 3000) * 0.05 + np.sin(2 * np.pi * 120 * tt) * 0.04, 0.05))


# ------------------------------------------------------------------ THE HUNTER
def hunter():
    # breathing loop: wet rasp through formants, slow and heavy
    s = 4.0
    tt = t_axis(s)
    cyc = 0.5 - 0.5 * np.cos(2 * np.pi * tt / 2.0)
    rasp = band(noise(s, 200, "pink"), 150, 4000) * cyc ** 2
    rasp = peak(rasp, [420, 980, 2300], 4, [1.0, 0.8, 0.4])
    gurgle = np.sin(2 * np.pi * 34 * tt) * (np.sin(2 * np.pi * 9 * tt) > 0.6) * cyc * 0.25
    write("hunter", "hunter_breath", loopify(rasp + gurgle, 0.2))
    # chitin clicks (several takes)
    for v in range(1, 5):
        s = 1.0
        tt = t_axis(s)
        x = np.zeros_like(tt)
        r = np.random.default_rng(210 + v)
        pos = 0.02
        for k in range(r.integers(3, 7)):
            seg = modal(0.12, [r.uniform(1500, 2600), r.uniform(3200, 4800), r.uniform(6000, 8000)], [0.02, 0.012, 0.008], [1, 0.6, 0.3], seed=k + v * 10, strike=0.002)
            a = int(pos * SR)
            x[a:a + len(seg)] += seg[: max(0, min(len(seg), len(x) - a))]
            pos += r.uniform(0.05, 0.16)
        write("hunter", f"hunter_click_{v}", reverb(x, 0.9, 0.3))
    # growl: sub-harmonic, rough, formant-shaped
    for v in range(1, 3):
        s = 2.4
        tt = t_axis(s)
        f0 = 62 + v * 6 + 8 * np.sin(2 * np.pi * 0.6 * tt)
        src = saw(f0) * (0.6 + 0.4 * np.sin(2 * np.pi * 23 * tt)) + band(noise(s, 220 + v), 60, 1200) * 0.6
        x = peak(src, [300, 750, 1600], 5, [1, 0.7, 0.3])
        x = soft_clip(x * env_ad(s, 0.25, 10, 0.7), 2.5)
        write("hunter", f"hunter_growl_{v}", reverb(x, 1.6, 0.3))
    # screech: layered FM shriek + torn noise, falling formants
    s = 1.8
    tt = t_axis(s)
    car = 760 + 420 * np.sin(2 * np.pi * 2.2 * tt) * np.exp(-tt) + 120 * np.random.default_rng(230).standard_normal(len(tt)).cumsum() / 900
    shriek = fm(s, car, 1.48, 5 + 3 * np.sin(2 * np.pi * 7 * tt))
    tear = band(noise(s, 231), 1800, 9000) * (0.5 + 0.5 * np.sin(2 * np.pi * 31 * tt))
    low = saw(55 + 20 * tt) * 0.4
    x = (shriek * 0.6 + tear * 0.5 + low) * env_ad(s, 0.03, 10, 0.6)
    x = peak(x, [900, 2100, 3700], 3, [1, 0.8, 0.5])
    write("hunter", "hunter_screech", reverb(soft_clip(x, 2.2), 2.2, 0.35))
    # attack: whoosh + flesh/metal impact
    s = 0.8
    tt = t_axis(s)
    whoosh = band(noise(s, 240), 400, 4000) * np.exp(-((tt - 0.12) / 0.06) ** 2)
    hit = modal(s, [120, 340, 910], [0.15, 0.08, 0.05], [1, 0.6, 0.3], seed=241, strike=0.02) * (tt > 0.18)
    write("hunter", "hunter_attack", reverb(soft_clip(whoosh + hit * 1.3, 2), 0.9, 0.25))
    # heavy digitigrade steps
    for v in range(1, 5):
        s = 0.6
        tt = t_axis(s)
        thud = np.sin(2 * np.pi * (48 + v * 4) * tt) * np.exp(-tt / 0.09)
        claw = modal(s, [2100 + v * 150, 3400, 5200], [0.03, 0.02, 0.015], [0.5, 0.3, 0.2], seed=250 + v) * (tt > 0.02)
        grit = band(noise(s, 260 + v), 200, 2500) * np.exp(-tt / 0.04) * 0.5
        write("hunter", f"step_hunter_{v}", reverb(thud + claw * 0.6 + grit, 0.9, 0.25))
    # presence rumble loop (felt more than heard when it is near)
    s = 6.0
    tt = t_axis(s)
    write("hunter", "hunter_presence", loopify(band(noise(s, 270, "brown"), 25, 120) * (0.7 + 0.3 * np.sin(2 * np.pi * 0.33 * tt)) + np.sin(2 * np.pi * 31 * tt) * 0.25, 0.5))
    # heartbeat for the player when it is close
    s = 1.0
    tt = t_axis(s)
    hb = np.zeros_like(tt)
    for off, a in ((0.0, 1.0), (0.28, 0.7)):
        m = tt >= off
        hb[m] += a * np.sin(2 * np.pi * (42 + 25 * np.exp(-(tt[m] - off) * 30)) * (tt[m] - off)) * np.exp(-(tt[m] - off) * 14)
    write("hunter", "heartbeat", loopify(band(hb, 25, 300), 0.02))


# ------------------------------------------------------------------ UI
def ui():
    def tone(fs, s, decay):
        tt = t_axis(s)
        y = np.zeros_like(tt)
        seg = len(tt) // len(fs)
        for i, f in enumerate(fs):
            m = slice(i * seg, (i + 1) * seg if i < len(fs) - 1 else len(tt))
            y[m] = np.sin(2 * np.pi * f * tt[m]) + 0.3 * np.sin(4 * np.pi * f * tt[m])
        return fade(y * np.exp(-tt / decay), 0.002, 0.03)

    write("ui", "ui_click", band(noise(0.04, 300), 1500, 8000) * np.exp(-t_axis(0.04) / 0.006) + tone([1800], 0.04, 0.01) * 0.3)
    write("ui", "ui_confirm", reverb(tone([880, 1320], 0.24, 0.12), 0.5, 0.2))
    write("ui", "ui_back", reverb(tone([900, 600], 0.22, 0.1), 0.5, 0.2))
    write("ui", "ui_error", reverb(soft_clip(saw(np.full(int(0.3 * SR), 180.0)) * env_ad(0.3, 0.005, 0.12), 2) * 0.5, 0.4, 0.15))
    write("ui", "interact_done", reverb(tone([523, 784, 1046], 0.45, 0.25), 0.8, 0.25))
    s = 2.2
    tt = t_axis(s)
    chord = sum(np.sin(2 * np.pi * f * tt) * np.exp(-tt / 0.9) for f in (392, 493.9, 587.3, 784))
    write("ui", "objective", reverb(fade(chord * 0.25, 0.02, 0.3), 2.0, 0.4))
    write("ui", "ping", reverb(tone([1500, 1900], 0.3, 0.15), 1.0, 0.35))


SETS = {"ambience": [amb_vent, amb_hum, amb_drone, amb_distant, amb_creak, amb_drip],
        "music": [music_tension, music_pulse, music_chase], "foley": [footsteps, foley],
        "doors": [doors], "machines": [machines], "hunter": [hunter], "ui": [ui]}

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    only = [s for s in a.only.split(",") if s]
    for cat, fns in SETS.items():
        if only and cat not in only:
            continue
        for fn in fns:
            fn()
            print("rendered", fn.__name__)
