#!/usr/bin/env python3
"""
Rauta's sounds, made from scratch.

One family, in one key (D major pentatonic), from three instruments modelled
here rather than sampled:

- a warm wooden bar (a marimba-ish mallet on rosewood: partials at 1, 3.9, 9.2),
- a soft glass bowl (partials at 1, 2.76, 5.4, 8.9, long and shimmering),
- a thumb-piano tine (a kalimba: a bright attack that settles into a pure note),

plus RAUTA's own voice: short formant chirps, so the character has a sound of
its own. A touch of tape saturation and a small synthetic room glue them
together. Nothing here is a stock beep or a plain sine chime.

Deterministic: fixed seeds, so running it again changes nothing in git.

    python3 scripts/sounds/generate.py            # writes ios/Rauta/Rauta/Resources/Sounds/*.caf
    python3 scripts/sounds/generate.py --preview  # also writes a preview reel .m4a

Needs numpy and scipy; converts with macOS `afconvert`.
"""

import argparse
import os
import subprocess
import tempfile
import wave

import numpy as np
from scipy.signal import lfilter

SR = 44_100
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "ios", "Rauta", "Rauta", "Resources", "Sounds")

# D major pentatonic, by name.
NOTE = {
    "D3": 146.83, "F#3": 185.00, "A3": 220.00,
    "D4": 293.66, "E4": 329.63, "F#4": 369.99, "A4": 440.00, "B4": 493.88,
    "D5": 587.33, "E5": 659.26, "F#5": 739.99, "A5": 880.00, "B5": 987.77,
    "D6": 1174.66, "E6": 1318.51, "F#6": 1479.98, "A6": 1760.00,
}

RNG = np.random.default_rng(20260928)


def silence(seconds):
    return np.zeros(int(SR * seconds))


def t_axis(seconds):
    return np.arange(int(SR * seconds)) / SR


def envelope(t, attack, decay):
    """A soft attack into an exponential decay."""
    a = np.clip(t / max(attack, 1e-4), 0, 1)
    a = np.sin(a * np.pi / 2) ** 2
    return a * np.exp(-t / decay)


def modal(freq, seconds, partials, attack=0.002, detune=0.0015, bright=1.0):
    """A struck body: a sum of decaying partials, each a hair out of tune so
    the note has life in it."""
    t = t_axis(seconds)
    out = np.zeros_like(t)
    for ratio, amp, decay in partials:
        f = freq * ratio * (1 + RNG.uniform(-detune, detune))
        if f > SR / 2.2:
            continue
        phase = RNG.uniform(0, 2 * np.pi)
        out += amp * (bright if ratio > 1 else 1) * np.sin(2 * np.pi * f * t + phase) * envelope(t, attack, decay)
    return out


def lowpass(x, cutoff):
    """One-pole lowpass: soft and cheap, enough to round off a noise."""
    alpha = np.exp(-2 * np.pi * cutoff / SR)
    return lfilter([1 - alpha], [1, -alpha], x)


def mallet_noise(seconds=0.012, cutoff=3500, amp=0.25):
    """The felt of the mallet: a tiny filtered puff at the strike."""
    n = RNG.standard_normal(int(SR * seconds))
    n = lowpass(n, cutoff)
    n *= np.hanning(len(n) * 2)[len(n):]
    return amp * n / (np.max(np.abs(n)) + 1e-9)


def wood(note, seconds=0.45, bright=1.0):
    f = NOTE[note] if isinstance(note, str) else note
    body = modal(f, seconds, [(1, 1.0, 0.16), (3.9, 0.32, 0.045), (9.2, 0.1, 0.015)], attack=0.0015, bright=bright)
    body[: int(SR * 0.012)] += mallet_noise()
    return body


def glass(note, seconds=1.6, bright=1.0):
    f = NOTE[note] if isinstance(note, str) else note
    return modal(
        f, seconds,
        [(1, 1.0, 0.9), (2.76, 0.42, 0.45), (5.4, 0.18, 0.22), (8.9, 0.07, 0.12)],
        attack=0.004, detune=0.0025, bright=bright,
    )


def tine(note, seconds=0.9):
    f = NOTE[note] if isinstance(note, str) else note
    body = modal(f, seconds, [(1, 1.0, 0.42), (5.93, 0.2, 0.05), (13.7, 0.06, 0.018)], attack=0.001)
    body[: int(SR * 0.006)] += mallet_noise(0.006, 6000, 0.18)
    return body


def thump(seconds=0.35, start=110, end=52, amp=0.8):
    """A soft low body under a moment that matters: a falling sine, like a
    felt beater on a drum."""
    t = t_axis(seconds)
    f = end + (start - end) * np.exp(-t / 0.05)
    phase = 2 * np.pi * np.cumsum(f) / SR
    return amp * np.sin(phase) * envelope(t, 0.003, 0.09)


def resonator(x, freq, q):
    """A two-pole band-pass: the vocal tract of RAUTA's chirp."""
    w = 2 * np.pi * freq / SR
    r = np.exp(-w / (2 * q))
    a1, a2 = -2 * r * np.cos(w), r * r
    return lfilter([1 - r], [1, a1, a2], x)


def chirp(start, end, seconds=0.14, vowel=(650, 1250), amp=1.0):
    """RAUTA's voice: a small buzzy glide through two formants, like a
    creature saying "brrp?"."""
    t = t_axis(seconds)
    shape = t / seconds
    f0 = start * (end / start) ** (shape ** 0.8)
    phase = np.cumsum(f0) / SR
    saw = 2 * (phase - np.floor(phase + 0.5))
    wobble = 1 + 0.12 * np.sin(2 * np.pi * 28 * t)
    voiced = saw * wobble
    formed = resonator(voiced, vowel[0], 6) + 0.7 * resonator(voiced, vowel[1], 9)
    env = envelope(t, 0.012, seconds * 0.45) * np.clip((seconds - t) / 0.02, 0, 1)
    out = formed * env
    return amp * out / (np.max(np.abs(out)) + 1e-9)


def breath(seconds=0.4, start=2200, end=500, amp=0.5):
    """An exhale: air through a closing band, falling."""
    n = RNG.standard_normal(int(SR * seconds))
    t = t_axis(seconds)
    out = np.zeros_like(n)
    # A few steps of a sweeping band, blended, is enough for air.
    steps = 6
    for k in range(steps):
        f = start * (end / start) ** (k / (steps - 1))
        seg = resonator(n, f, 2.2)
        weight = np.exp(-((t / seconds - k / (steps - 1)) ** 2) / 0.03)
        out += seg * weight
    env = np.sin(np.clip(t / seconds, 0, 1) * np.pi) ** 1.5
    out *= env
    return amp * out / (np.max(np.abs(out)) + 1e-9)


def place(layers, seconds):
    """Mixes (offset seconds, signal, gain) layers into one track."""
    out = silence(seconds)
    for offset, sig, gain in layers:
        i = int(SR * offset)
        n = min(len(sig), len(out) - i)
        if n > 0:
            out[i:i + n] += gain * sig[:n]
    return out


def room(x, seconds=0.45, mix=0.13):
    """A small warm room: decaying, darkened noise as the impulse."""
    n = int(SR * seconds)
    ir = RNG.standard_normal(n) * np.exp(-np.arange(n) / (SR * seconds / 5))
    ir = lowpass(ir, 4200)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    wet = np.convolve(x, ir)[: len(x) + n // 2]
    dry = np.concatenate([x, np.zeros(len(wet) - len(x))])
    return (1 - mix) * dry + mix * wet * 3


def finish(x, peak_db=-3.0, drive=1.25):
    """Tape-ish saturation, a gentle fade out, and a set peak."""
    x = np.tanh(drive * x / (np.max(np.abs(x)) + 1e-9)) / np.tanh(drive)
    fade = min(len(x), int(SR * 0.03))
    x[-fade:] *= np.linspace(1, 0, fade)
    return x * (10 ** (peak_db / 20))


# ---------------------------------------------------------------- the set

def s_tick(note):
    return finish(room(wood(note, 0.16, bright=1.3), 0.25, 0.08), -5)


def s_go():
    layers = [
        (0.00, thump(0.4, 120, 55), 0.55),
        (0.00, glass("D5", 1.3), 0.55),
        (0.025, glass("F#5", 1.2), 0.42),
        (0.05, glass("A5", 1.1), 0.36),
        (0.00, tine("D6", 0.6), 0.3),
    ]
    return finish(room(place(layers, 1.35)), -2.5)


def s_rest_over():
    layers = [
        (0.00, tine("A5", 0.5), 0.7),
        (0.11, glass("D6", 1.2), 0.6),
        (0.11, thump(0.3, 100, 58, 0.5), 0.5),
    ]
    return finish(room(place(layers, 1.35)), -2.5)


def s_warmup_over():
    layers = [
        (0.00, tine("D5", 0.6), 0.6),
        (0.09, tine("F#5", 0.6), 0.6),
        (0.18, tine("A5", 0.7), 0.62),
        (0.27, glass("D6", 1.4), 0.5),
        (0.27, thump(0.35, 110, 55, 0.6), 0.45),
    ]
    return finish(room(place(layers, 1.75)), -2.5)


def s_rest_start():
    layers = [
        (0.00, breath(0.42, 2400, 520, 0.9), 0.35),
        (0.05, wood("A4", 0.5, 0.8), 0.45),
        (0.05, wood("D4", 0.5, 0.8), 0.25),
    ]
    return finish(room(place(layers, 0.6)), -9)


def s_set_logged():
    layers = [
        (0.00, wood("A4", 0.45), 0.8),
        (0.075, wood("D5", 0.55), 0.85),
    ]
    return finish(room(place(layers, 0.68)), -5)


def s_exercise_done():
    layers = [
        (0.00, tine("D5", 0.6), 0.6),
        (0.085, tine("F#5", 0.6), 0.6),
        (0.17, tine("A5", 0.9), 0.7),
        (0.17, glass("A5", 1.0, 0.8), 0.25),
    ]
    return finish(room(place(layers, 1.2)), -4)


def s_workout_start():
    t = t_axis(0.5)
    swell = glass("D4", 0.5) * np.clip(t / 0.45, 0, 1) ** 2
    layers = [
        (0.00, swell, 0.6),
        (0.00, breath(0.5, 500, 1800, 0.8), 0.18),
        (0.44, tine("D5", 0.8), 0.7),
        (0.44, glass("A5", 1.0), 0.35),
        (0.44, thump(0.35, 110, 55, 0.6), 0.5),
    ]
    return finish(room(place(layers, 1.5)), -3)


def s_workout_finish():
    # RAUTA's motif: up to the fifth, the third, then home an octave up.
    layers = [
        (0.00, tine("D5", 0.7), 0.6),
        (0.13, tine("A5", 0.7), 0.6),
        (0.26, tine("F#5", 0.7), 0.6),
        (0.40, tine("D6", 1.2), 0.7),
        (0.40, glass("D5", 1.8), 0.4),
        (0.40, glass("A5", 1.6), 0.25),
        (0.40, thump(0.4, 110, 50, 0.7), 0.55),
        (0.62, chirp(520, 880, 0.13, (700, 1400)), 0.18),
    ]
    return finish(room(place(layers, 2.3), 0.6, 0.16), -2)


def s_menu_open():
    layers = [
        (0.00, chirp(430, 760, 0.12, (620, 1250)), 0.7),
        (0.06, glass("E6", 0.35, 0.6), 0.12),
    ]
    return finish(room(place(layers, 0.42), 0.3, 0.1), -10)


def s_plan_built():
    layers = [
        (0.00, chirp(500, 900, 0.12, (700, 1350)), 0.35),
        (0.10, tine("A5", 0.6), 0.55),
        (0.20, tine("D6", 0.9), 0.6),
        (0.20, glass("D6", 1.3, 0.8), 0.3),
    ]
    return finish(room(place(layers, 1.5)), -5)


def plop(start, end, seconds=0.09):
    t = t_axis(seconds)
    f = end + (start - end) * np.exp(-t / 0.018)
    phase = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(phase) * envelope(t, 0.002, 0.03)


def s_favorite_on():
    layers = [
        (0.00, plop(420, 900), 0.8),
        (0.04, glass("E6", 0.6, 0.8), 0.28),
    ]
    return finish(room(place(layers, 0.65), 0.3, 0.1), -9)


def s_favorite_off():
    layers = [(0.00, plop(760, 330, 0.1), 0.8)]
    return finish(room(place(layers, 0.25), 0.25, 0.06), -12)


def s_warning():
    layers = [
        (0.00, wood("F#3", 0.3, 0.6), 0.8),
        (0.12, wood("D3", 0.35, 0.6), 0.8),
    ]
    return finish(room(place(layers, 0.55), 0.3, 0.08), -8)


SOUNDS = {
    "rauta-tick-3": lambda: s_tick("A5"),
    "rauta-tick-2": lambda: s_tick("B5"),
    "rauta-tick-1": lambda: s_tick("D6"),
    "rauta-go": s_go,
    "rauta-rest-over": s_rest_over,
    "rauta-warmup-over": s_warmup_over,
    "rauta-rest-start": s_rest_start,
    "rauta-set-logged": s_set_logged,
    "rauta-exercise-done": s_exercise_done,
    "rauta-workout-start": s_workout_start,
    "rauta-workout-finish": s_workout_finish,
    "rauta-menu-open": s_menu_open,
    "rauta-plan-built": s_plan_built,
    "rauta-favorite-on": s_favorite_on,
    "rauta-favorite-off": s_favorite_off,
    "rauta-warning": s_warning,
}


def write_wav(path, x):
    pcm = np.clip(x, -1, 1)
    pcm = (pcm * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", help="also write a preview reel to this .m4a path")
    args = parser.parse_args()

    os.makedirs(OUT, exist_ok=True)
    reel = []
    with tempfile.TemporaryDirectory() as tmp:
        for name, make in SOUNDS.items():
            signal = make()
            wav = os.path.join(tmp, name + ".wav")
            write_wav(wav, signal)
            caf = os.path.join(OUT, name + ".caf")
            subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16@44100", "-c", "1", wav, caf], check=True)
            reel += [signal, silence(0.7)]
            print(f"{name:24s} {len(signal) / SR:5.2f}s")
        if args.preview:
            wav = os.path.join(tmp, "reel.wav")
            write_wav(wav, np.concatenate(reel))
            subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "192000", wav, args.preview], check=True)
            print("preview:", args.preview)


if __name__ == "__main__":
    main()
