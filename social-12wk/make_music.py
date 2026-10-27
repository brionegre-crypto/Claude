"""Original background music for the Reels, synthesized from scratch (no samples,
no third-party audio), so there is no copyright claim or muting risk.

Writes music/<name>.wav, 40-second stereo loops at 44.1 kHz.
Usage: python3.13 make_music.py      (needs numpy)
"""
import os, wave
import numpy as np

SR = 44100
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'music')
rng = np.random.default_rng(7)

def hz(note):
    names = {'C': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3, 'E': 4, 'F': 5, 'F#': 6, 'Gb': 6,
             'G': 7, 'G#': 8, 'Ab': 8, 'A': 9, 'A#': 10, 'Bb': 10, 'B': 11}
    n, o = note[:-1], int(note[-1])
    return 440.0 * 2 ** ((names[n] + 12 * (o + 1) - 69) / 12)

def lp_fast(x, cutoff):
    """Cheap low-pass using FFT masking (fine for offline music beds)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1 / np.sqrt(1 + (f / cutoff) ** 4)
    return np.fft.irfft(X, len(x))

def hp_fast(x, cutoff):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1 / np.sqrt(1 + (cutoff / np.maximum(f, 1)) ** 4)
    return np.fft.irfft(X, len(x))

def env(n, a, d, s, r, total):
    """ADSR envelope of length total samples (a, d, r in seconds)."""
    A, D, R = int(a * SR), int(d * SR), int(r * SR)
    e = np.full(total, s, dtype=float)
    e[:A] = np.linspace(0, 1, A, endpoint=False) if A else e[:A]
    e[A:A + D] = np.linspace(1, s, D, endpoint=False)[: max(0, min(D, total - A))]
    if R and total > R:
        e[-R:] *= np.linspace(1, 0, R)
    return e

def pad_voice(freq, n, detune=0.004, bright=0.35):
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k, dt in enumerate((-detune, 0, detune)):
        f = freq * (1 + dt)
        ph = 2 * np.pi * f * t + rng.uniform(0, 2 * np.pi)
        # soft saw: a few harmonics with 1/k^1.5 falloff
        for h in range(1, 7):
            out += np.sin(h * ph) / h ** (1.5 + (1 - bright))
    return out / 6

def pluck(freq, n, decay=1.6):
    t = np.arange(n) / SR
    x = (np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(4 * np.pi * freq * t) + 0.12 * np.sin(6 * np.pi * freq * t))
    return x * np.exp(-t * decay) * np.minimum(1, t * 200)

def kick(n):
    t = np.arange(n) / SR
    f = 45 + 75 * np.exp(-t * 30)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t * 7) * 0.9

def snare(n):
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    body = np.sin(2 * np.pi * 185 * t) * np.exp(-t * 25)
    return (lp_fast(hp_fast(noise, 1500), 4500) * np.exp(-t * 22) * 0.22 + body * 0.35)

def hat(n):
    t = np.arange(n) / SR
    return lp_fast(hp_fast(rng.standard_normal(n), 7000), 11000) * np.exp(-t * 70) * 0.10

def add(buf, x, at):
    i = int(at * SR)
    if i >= len(buf): return
    j = min(len(buf), i + len(x))
    buf[i:j] += x[: j - i]

def track(name, bpm, chords, arp=True, drums='full', bright=0.35, swing=0.0, length=40):
    beat = 60 / bpm
    bar = 4 * beat
    n = int(length * SR)
    L = np.zeros(n); R = np.zeros(n)
    drums_bus = np.zeros(n); bass = np.zeros(n); keys = np.zeros(n)
    t0 = 0.0; ci = 0
    while t0 < length:
        root, notes = chords[ci % len(chords)]
        dur = 2 * bar
        m = int(dur * SR) + int(0.8 * SR)
        e = env(m, 0.35, 0.6, 0.75, 0.9, m)
        for k, nt in enumerate(notes):
            v = pad_voice(hz(nt), m, bright=bright) * e * 0.18
            pan = (k / max(1, len(notes) - 1)) - 0.5
            add(L, v * (0.6 - 0.35 * pan), t0); add(R, v * (0.6 + 0.35 * pan), t0)
        # sub bass on the root, re-struck each bar
        for b in range(2):
            bn = int(bar * SR)
            tb = np.arange(bn) / SR
            add(bass, np.sin(2 * np.pi * hz(root) * tb) * np.exp(-tb * 0.9) * np.minimum(1, tb * 80) * 0.32, t0 + b * bar)
        if arp:
            seq = notes + notes[-2:0:-1]
            step = beat / 2
            for s in range(int(dur / step)):
                nt = seq[s % len(seq)]
                f = hz(nt) * 2
                st = t0 + s * step + (swing * step if s % 2 else 0)
                add(keys, pluck(f, int(0.9 * SR)) * (0.10 if s % 4 else 0.13), st)
        t0 += dur; ci += 1
    # drums
    nbeats = int(length / beat)
    for b in range(nbeats):
        tb = b * beat
        if drums in ('full', 'light'):
            if b % 4 in (0, 2) or (drums == 'full' and b % 8 == 7):
                add(drums_bus, kick(int(0.5 * SR)), tb if b % 8 != 7 else tb + beat / 2)
            if b % 4 in (1, 3):
                add(drums_bus, snare(int(0.35 * SR)) * (1.0 if drums == 'full' else 0.6), tb)
            for h in range(2):
                add(drums_bus, hat(int(0.12 * SR)) * (0.8 if h == 0 else 0.5), tb + h * beat / 2 + (swing * beat / 2 if h else 0))
        elif drums == 'sparse':
            if b % 4 == 0: add(drums_bus, kick(int(0.5 * SR)) * 0.8, tb)
            if b % 8 == 4: add(drums_bus, snare(int(0.35 * SR)) * 0.5, tb)
            add(drums_bus, hat(int(0.12 * SR)) * 0.4, tb + beat / 2)
    keys = lp_fast(keys, 5000)
    L = lp_fast(L, 3200 + 3000 * bright); R = lp_fast(R, 3200 + 3000 * bright)
    # gentle vinyl texture for warmth
    crackle = hp_fast(rng.standard_normal(n), 3000) * 0.004 * (rng.random(n) > 0.9993) * 25
    mixL = L + bass + drums_bus * 0.9 + keys * 0.9 + crackle
    mixR = R + bass + drums_bus * 0.9 + keys * 1.0 + crackle
    st = np.stack([mixL, mixR], 1)
    st = np.tanh(st * 1.2) / np.tanh(1.2)                 # soft clip
    rms = np.sqrt(np.mean(st ** 2))
    st *= (10 ** (-17 / 20)) / max(rms, 1e-9)            # ~ -17 dBFS RMS
    st = np.clip(st, -0.98, 0.98)
    fade = int(0.4 * SR)
    st[:fade] *= np.linspace(0, 1, fade)[:, None]
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + '.wav'), 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((st * 32767).astype('<i2').tobytes())
    print('wrote', name)

if __name__ == '__main__':
    # Be The Man: steady, minor, grounded
    track('btm-steady', 84, [('A1', ['A3', 'C4', 'E4', 'G4']), ('F1', ['F3', 'A3', 'C4', 'E4']),
                             ('C2', ['G3', 'C4', 'E4', 'B4']), ('G1', ['G3', 'B3', 'D4', 'F4'])], swing=0.12)
    track('btm-resolve', 78, [('D2', ['D3', 'F3', 'A3', 'C4']), ('Bb1', ['Bb2', 'D3', 'F3', 'A3']),
                              ('F1', ['F3', 'A3', 'C4', 'E4']), ('C2', ['G3', 'C4', 'E4', 'Bb3'])], drums='sparse', bright=0.2)
    # Couples: warm, major, soulful
    track('cpl-home', 80, [('C2', ['E3', 'G3', 'B3', 'D4']), ('A1', ['E3', 'G3', 'C4', 'E4']),
                           ('F1', ['A3', 'C4', 'E4', 'G4']), ('G1', ['B3', 'D4', 'F4', 'A4'])], drums='light', bright=0.45, swing=0.15)
    # Lift: hopeful, for calls to action
    track('lift', 92, [('G1', ['G3', 'B3', 'D4', 'F#4']), ('D2', ['F#3', 'A3', 'D4', 'E4']),
                       ('E2', ['E3', 'G3', 'B3', 'D4']), ('C2', ['E3', 'G3', 'C4', 'D4'])], bright=0.5, swing=0.08)
