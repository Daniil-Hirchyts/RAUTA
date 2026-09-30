#!/usr/bin/env python3
"""
Candidate sound packs for Rauta: the same fifteen moments played in nine
different styles, so a set can be chosen by ear before any of it goes into
the app.

    python3 scripts/sounds/packs.py

writes, under build/sounds/ (ignored by git):

    <pack>/<sound>.wav        every sound on its own, 44.1 kHz mono
    audition/packs/<pack>.wav one file per pack, the sounds end to end
    audition/index.html       the listening test (scripts/sounds/audition.html
                              with the manifest filled in)

Needs numpy and scipy. Deterministic: every noise source is seeded by the
sound it belongs to.
"""

import json
import os
import wave
import zlib

import numpy as np
from scipy.signal import bilinear, butter, fftconvolve, lfilter, sosfilt

SR = 44_100
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(ROOT, "build", "sounds")
TAU = 2 * np.pi

# id, name, when it is heard, group, level against the loudest moments (dB)
EVENTS = [
    ("tick-3", "Three", "3 seconds left on a countdown", "Countdown and rest", -3),
    ("tick-2", "Two", "2 seconds left", "Countdown and rest", -3),
    ("tick-1", "One", "1 second left", "Countdown and rest", -3),
    ("rest-over", "Rest over", "Rest hits zero: back to the bar", "Countdown and rest", 0),
    ("warmup-over", "Warm-up over", "Warm-up hits zero: first exercise", "Countdown and rest", 0),
    ("rest-start", "Rest starts", "A rest begins without a set being logged", "Countdown and rest", -6),
    ("set-logged", "Set logged", "You log a set", "Workout", -3),
    ("exercise-done", "Exercise done", "You tick an exercise off", "Workout", -2),
    ("workout-start", "Workout starts", "The start countdown ends", "Workout", -1),
    ("workout-finish", "Workout finished", "You finish the workout", "Workout", 0),
    ("menu-open", "RAUTA's menu", "You tap RAUTA", "Interface", -10),
    ("plan-built", "Plan built", "RAUTA finishes building a week", "Interface", -4),
    ("favorite-on", "Favourite", "You like an exercise", "Interface", -8),
    ("favorite-off", "Unfavourite", "You unlike an exercise", "Interface", -10),
    ("warning", "Warning", "Something was refused", "Interface", -6),
]

SMALL = {"tick-3", "tick-2", "tick-1", "menu-open", "favorite-on", "favorite-off", "warning"}

RNG = np.random.default_rng(0)


# ------------------------------------------------------------------ basics

def hz(note):
    """A frequency from a note name ("A4", "C#5", "Bb3") or a number."""
    if isinstance(note, (int, float)):
        return float(note)
    steps = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    pitch, i = steps[note[0]], 1
    if note[i] == "#":
        pitch, i = pitch + 1, i + 1
    elif note[i] == "b":
        pitch, i = pitch - 1, i + 1
    midi = 12 * (int(note[i:]) + 1) + pitch
    return 440.0 * 2 ** ((midi - 69) / 12)


def tt(seconds):
    return np.arange(int(SR * seconds)) / SR


def env(t, attack, decay):
    """A raised-cosine attack into an exponential decay."""
    rise = 0.5 * (1 - np.cos(np.pi * np.clip(t / attack, 0, 1)))
    return rise * np.exp(-t / decay)


def swell(t, attack, hold, release):
    """A slow rise, a hold, then an exponential fall: a pad's shape."""
    rise = 0.5 * (1 - np.cos(np.pi * np.clip(t / attack, 0, 1)))
    fall = np.exp(-np.clip(t - attack - hold, 0, None) / release)
    return rise * fall


def mix(layers):
    """Sums (offset seconds, signal, gain) layers."""
    n = max(int(round(o * SR)) + len(s) for o, s, _ in layers)
    out = np.zeros(n)
    for o, s, g in layers:
        i = int(round(o * SR))
        out[i:i + len(s)] += g * s
    return out


def seq(inst, notes, **common):
    """Plays (time, note or chord, gain, overrides) on one instrument."""
    layers = []
    for item in notes:
        at, what = item[0], item[1]
        gain = item[2] if len(item) > 2 else 1.0
        extra = item[3] if len(item) > 3 else {}
        for note in what if isinstance(what, (list, tuple)) else [what]:
            layers.append((at, inst(note, **{**common, **extra}), gain))
    return mix(layers)


def lp(x, cutoff, order=2):
    return sosfilt(butter(order, cutoff, "low", fs=SR, output="sos"), x)


def hp(x, cutoff, order=2):
    return sosfilt(butter(order, cutoff, "high", fs=SR, output="sos"), x)


def bp(x, low, high, order=2):
    return sosfilt(butter(order, [low, high], "band", fs=SR, output="sos"), x)


def reson(x, freq, q):
    """A two-pole resonator."""
    w = TAU * freq / SR
    r = np.exp(-w / (2 * q))
    return lfilter([1 - r], [1, -2 * r * np.cos(w), r * r], x)


def noise(n):
    return RNG.standard_normal(n)


def unit(x):
    return x / (np.max(np.abs(x)) + 1e-12)


def glide(f0, f1, n, time):
    """A pitch that leaves f0 and settles on f1."""
    t = np.arange(n) / SR
    return f1 + (f0 - f1) * np.exp(-t / time)


def room(x, rt=0.45, wet=0.12, bright=5000):
    """A room: decaying, darkened noise as the impulse. Dense, so it never
    rings like a spring."""
    n = int(SR * rt * 1.1)
    t = np.arange(n) / SR
    ir = np.random.default_rng(11).standard_normal(n) * np.exp(-6.91 * t / rt)
    ir = hp(lp(ir, bright), 250)
    ramp = int(0.004 * SR)
    ir[:ramp] *= np.linspace(0, 1, ramp)
    ir /= np.sqrt(np.sum(ir ** 2))
    pre = int(0.012 * SR)
    tail = fftconvolve(x, ir)
    out = np.zeros(len(x) + n + pre)
    out[:len(x)] += x
    out[pre:pre + len(tail)] += wet * tail
    return out


# ------------------------------------------------------------------ mastering

def _a_weighting():
    f1, f2, f3, f4 = 20.598997, 107.65265, 737.86223, 12194.217
    num = [(TAU * f4) ** 2 * 10 ** (1.9997 / 20), 0, 0, 0, 0]
    den = np.polymul([1, 2 * TAU * f4, (TAU * f4) ** 2], [1, 2 * TAU * f1, (TAU * f1) ** 2])
    den = np.polymul(np.polymul(den, [1, TAU * f3]), [1, TAU * f2])
    return bilinear(num, den, SR)


A_B, A_A = _a_weighting()


def loudness(x):
    """How loud the loudest tenth of a second is, as the ear weighs it (dB)."""
    w = lfilter(A_B, A_A, np.concatenate([x, np.zeros(int(0.1 * SR))]))
    n = int(0.1 * SR)
    power = np.cumsum(np.concatenate([[0.0], w ** 2]))
    windows = (power[n:] - power[:-n]) / n
    return 10 * np.log10(np.max(windows) + 1e-12)


def master(x, level):
    """Trims the tail, rounds the ends and sets the loudness."""
    x = hp(x - np.mean(x), 70)
    peak = np.max(np.abs(x))
    audible = np.nonzero(np.abs(x) > peak * 10 ** (-44 / 20))[0]
    x = x[: min(len(x), audible[-1] + int(0.08 * SR))]
    fade_in, fade_out = int(0.0005 * SR), min(len(x), int(0.1 * SR))
    x[:fade_in] *= np.linspace(0, 1, fade_in)
    x[-fade_out:] *= 0.5 * (1 + np.cos(np.linspace(0, np.pi, fade_out)))
    x = x * 10 ** ((-14.0 + level - loudness(x)) / 20)
    ceiling = 10 ** (-1.0 / 20)
    peak = np.max(np.abs(x))
    if peak > ceiling:
        x *= ceiling / peak
    return np.concatenate([x, np.zeros(int(0.005 * SR))])


# ------------------------------------------------------------------ 1. Pure
# Soft sine tones with a trace of harmonics. Nothing but the note.

def pure(note, decay=0.14, attack=0.005):
    f = hz(note)
    t = tt(attack + 7 * decay)
    ph = TAU * f * t
    x = np.sin(ph) + 0.10 * np.sin(2 * ph) * np.exp(-t / (decay * 0.5)) + 0.03 * np.sin(3 * ph) * np.exp(-t / (decay * 0.3))
    return x * env(t, attack, decay)


def bloop(f0, f1, decay=0.04, time=0.02, attack=0.004):
    """A sine that slides into its note: a small soft pop."""
    n = int(SR * (attack + 7 * decay))
    ph = TAU * np.cumsum(glide(f0, f1, n, time)) / SR
    return (np.sin(ph) + 0.08 * np.sin(2 * ph)) * env(np.arange(n) / SR, attack, decay)


PURE = {
    "tick-3": lambda: pure("A5", 0.05),
    "tick-2": lambda: pure("A5", 0.05),
    "tick-1": lambda: pure("A5", 0.05),
    "rest-over": lambda: seq(pure, [(0, "A5", 0.9, {"decay": 0.12}), (0.13, "E6", 1, {"decay": 0.3})]),
    "warmup-over": lambda: seq(pure, [(0, "A5", 0.8, {"decay": 0.1}), (0.11, "C#6", 0.85, {"decay": 0.1}), (0.22, "E6", 1, {"decay": 0.32})]),
    "rest-start": lambda: seq(pure, [(0, "E6", 0.8, {"decay": 0.1}), (0.14, "A5", 1, {"decay": 0.24})]),
    "set-logged": lambda: bloop(760, 1175, 0.06, 0.018),
    "exercise-done": lambda: seq(pure, [(0, "E5", 0.8, {"decay": 0.1}), (0.09, "A5", 0.9, {"decay": 0.1}), (0.18, "C#6", 1, {"decay": 0.3})]),
    "workout-start": lambda: seq(pure, [(0, ["A4", "E5"], 0.6, {"decay": 0.16}), (0.18, "A5", 1, {"decay": 0.36})]),
    "workout-finish": lambda: seq(pure, [
        (0, "A4", 0.7, {"decay": 0.12}), (0.11, "C#5", 0.75, {"decay": 0.12}), (0.22, "E5", 0.8, {"decay": 0.12}),
        (0.33, "A5", 0.9, {"decay": 0.16}),
        (0.52, ["A5", "C#6", "E6"], 0.5, {"decay": 0.55, "attack": 0.012}),
    ]),
    "menu-open": lambda: bloop(600, 900, 0.03, 0.015),
    "plan-built": lambda: seq(pure, [(0, "E5", 0.8, {"decay": 0.09}), (0.08, "A5", 0.85, {"decay": 0.09}), (0.16, "B5", 0.9, {"decay": 0.09}), (0.27, "E6", 1, {"decay": 0.34})]),
    "favorite-on": lambda: seq(pure, [(0, "E6", 0.8, {"decay": 0.04}), (0.07, "A6", 1, {"decay": 0.1})]),
    "favorite-off": lambda: bloop(900, 587, 0.05, 0.03),
    "warning": lambda: mix([(0, bloop(466, 440, 0.06, 0.03), 1), (0.14, bloop(466, 415, 0.08, 0.03), 1)]),
}


# ------------------------------------------------------------------ 2. Marimba
# A rosewood bar under a soft mallet: the second partial two octaves up, as a
# tuned marimba has it, so every note is in tune with itself.

def marimba(note, mute=1.0, hard=0.5):
    f = hz(note)
    d = 0.30 * (440 / f) ** 0.55 * mute
    t = tt(0.002 + 7 * d)
    x = np.sin(TAU * f * t) * np.exp(-t / d)
    if 4 * f < 15000:
        x += 0.5 * hard * np.sin(TAU * 4 * f * t) * np.exp(-t / (d * 0.2))
    if 10 * f < 15000:
        x += 0.18 * hard * np.sin(TAU * 10 * f * t) * np.exp(-t / (d * 0.05))
    x *= np.clip(t / 0.0015, 0, 1)
    thock = lp(noise(len(t)), min(2600, 3 * f)) * np.exp(-t / 0.005)
    return x + 0.35 * hard * unit(thock)


MARIMBA = {
    "tick-3": lambda: marimba("G4", 0.5),
    "tick-2": lambda: marimba("B4", 0.5),
    "tick-1": lambda: marimba("D5", 0.5),
    "rest-over": lambda: seq(marimba, [(0, "G5", 0.9), (0.07, "B5", 0.9), (0.14, "D6", 1)]),
    "warmup-over": lambda: seq(marimba, [(0, "G4", 0.8), (0.075, "D5", 0.8), (0.15, "G5", 0.85), (0.225, "B5", 0.9), (0.3, "D6", 1)]),
    "rest-start": lambda: seq(marimba, [(0, "E5", 0.8), (0.11, "D5", 0.8), (0.22, "B4", 0.9)], hard=0.3),
    "set-logged": lambda: seq(marimba, [(0, "D5", 0.85), (0.075, "G5", 1)]),
    "exercise-done": lambda: seq(marimba, [(0, "G5", 0.8), (0.075, "A5", 0.85), (0.15, "B5", 0.9), (0.225, "D6", 1)]),
    "workout-start": lambda: seq(marimba, [(0, "G4", 0.9), (0.1, "D5", 0.9), (0.2, ["G5", "B5"], 0.8, {"hard": 0.7})]),
    "workout-finish": lambda: seq(marimba, [
        (0, "D5", 0.8), (0.11, "G5", 0.85), (0.22, "B5", 0.9), (0.36, "D6", 1),
        (0.62, ["G5", "D6"], 0.6), (0.69, ["G5", "D6"], 0.65), (0.76, ["G5", "D6"], 0.7), (0.83, ["G5", "D6"], 0.75),
        (0.92, ["G5", "B5", "G6"], 0.7, {"hard": 0.7}),
    ]),
    "menu-open": lambda: marimba("B5", 0.5, 0.25),
    "plan-built": lambda: seq(marimba, [(0, "D5", 0.75), (0.06, "E5", 0.8), (0.12, "G5", 0.85), (0.18, "A5", 0.9), (0.24, "B5", 0.95), (0.33, "D6", 1)]),
    "favorite-on": lambda: seq(marimba, [(0, "B5", 0.8, {"mute": 0.5}), (0.07, "D6", 1)], hard=0.35),
    "favorite-off": lambda: marimba("D5", 0.4, 0.2),
    "warning": lambda: seq(marimba, [(0, "D4", 1), (0.13, "D4", 1)], mute=0.22, hard=0.9),
}


# ------------------------------------------------------------------ 3. Harp
# A plucked nylon string. What a string model gives: every harmonic of the
# pluck, the high ones dying first.

def pluck(note, mute=1.0, bright=1.0, pos=0.21):
    f = hz(note)
    d1 = 0.6 * (330 / f) ** 0.5 * mute
    t = tt(min(0.003 + 6.5 * d1, 3.2))
    x = np.zeros(len(t))
    for h in range(1, int(14000 / f) + 1):
        amp = np.sin(np.pi * h * pos) / h
        if abs(amp) < 1e-3:
            continue
        stiff = np.sqrt(1 + 0.00012 * h * h)
        x += amp * np.sin(TAU * f * h * stiff * t) * np.exp(-t * (1 + 0.055 * h * h / bright) / d1)
    return x * np.clip(t / 0.0012, 0, 1)


HARP = {
    "tick-3": lambda: pluck("D5", 0.3, 0.7),
    "tick-2": lambda: pluck("D5", 0.3, 0.7),
    "tick-1": lambda: pluck("D5", 0.3, 0.7),
    "rest-over": lambda: seq(pluck, [(0, "D5", 0.8), (0.03, "F#5", 0.8), (0.06, "A5", 0.85), (0.09, "D6", 1)]),
    "warmup-over": lambda: seq(pluck, [(0, "A4", 0.8), (0.035, "D5", 0.8), (0.07, "F#5", 0.8), (0.105, "A5", 0.85), (0.3, "D6", 1)]),
    "rest-start": lambda: seq(pluck, [(0, "A5", 0.8), (0.16, "D5", 1)], bright=0.6),
    "set-logged": lambda: seq(pluck, [(0, "A5", 0.85, {"mute": 0.6}), (0.08, "D6", 1, {"mute": 0.7})]),
    "exercise-done": lambda: seq(pluck, [(0, "F#5", 0.8), (0.09, "A5", 0.9), (0.18, "D6", 1)], mute=0.8),
    "workout-start": lambda: seq(pluck, [(0, "D4", 0.9), (0.03, "A4", 0.9), (0.06, "D5", 0.9), (0.2, "A5", 1)]),
    "workout-finish": lambda: seq(pluck, [
        (0, "D5", 0.7), (0.055, "E5", 0.72), (0.11, "F#5", 0.75), (0.165, "A5", 0.8), (0.22, "B5", 0.85), (0.275, "D6", 0.9),
        (0.5, "D5", 0.8), (0.53, "A5", 0.8), (0.56, "D6", 0.85), (0.59, "F#6", 0.9),
    ]),
    "menu-open": lambda: pluck("A5", 0.35, 0.4),
    "plan-built": lambda: seq(pluck, [(0, "D5", 0.75), (0.06, "F#5", 0.8), (0.12, "A5", 0.85), (0.18, "B5", 0.9), (0.3, "E6", 1)]),
    "favorite-on": lambda: seq(pluck, [(0, "F#5", 0.8), (0.07, "A5", 1)], mute=0.5),
    "favorite-off": lambda: pluck("D5", 0.18, 0.4),
    "warning": lambda: seq(pluck, [(0, "D4", 1), (0.13, "D4", 1)], mute=0.12, bright=0.5),
}


# ------------------------------------------------------------------ 4. Keys
# An electric piano, the FM way: a warm body that barks less as it rings, and
# a small bell on the attack.

def keys(note, vel=0.7, long=1.0):
    f = hz(note)
    d = 0.6 * (440 / f) ** 0.4 * long
    t = tt(0.004 + 6.5 * d)
    out = np.zeros(len(t))
    for cents in (-2.0, 2.0):
        fd = f * 2 ** (cents / 1200)
        body = np.sin(TAU * fd * t + (0.25 + 1.3 * vel * np.exp(-t / 0.22)) * np.sin(TAU * fd * t))
        # The bell sits near 6 kHz whatever the note, not up where only dogs hear it.
        ratio = int(np.clip(round(6000 / fd), 3, 14))
        tine = np.sin(TAU * fd * t + 0.7 * vel * np.exp(-t / 0.05) * np.sin(TAU * ratio * fd * t))
        out += 0.75 * body + 0.3 * tine * np.exp(-t / 0.3)
    return out * env(t, 0.003, d) / 2


KEYS = {
    "tick-3": lambda: keys("G5", 0.5, 0.18),
    "tick-2": lambda: keys("G5", 0.5, 0.18),
    "tick-1": lambda: keys("G5", 0.5, 0.18),
    "rest-over": lambda: seq(keys, [(0, "C5", 0.6), (0.04, "E5", 0.6), (0.08, "G5", 0.65), (0.2, "B5", 1)], long=0.8),
    "warmup-over": lambda: seq(keys, [(0, "F4", 0.6), (0.09, "A4", 0.6), (0.18, "C5", 0.65), (0.27, "E5", 0.7), (0.42, "G5", 1)], long=0.8),
    "rest-start": lambda: seq(keys, [(0, "E5", 0.8), (0.16, ["A4", "C5"], 0.7)], vel=0.4, long=0.6),
    "set-logged": lambda: seq(keys, [(0, "G5", 0.8), (0.07, "C6", 1)], long=0.4),
    "exercise-done": lambda: seq(keys, [(0, "E5", 0.7), (0.08, "G5", 0.75), (0.16, "C6", 0.85), (0.3, "D6", 1)], long=0.7),
    "workout-start": lambda: seq(keys, [(0, ["C4", "G4", "C5", "E5"], 0.55, {"vel": 0.95}), (0.2, "G5", 1)], long=0.8),
    "workout-finish": lambda: seq(keys, [
        (0, ["F4", "A4", "C5", "E5"], 0.5, {"long": 0.5}),
        (0.28, ["G4", "B4", "D5"], 0.55, {"long": 0.5}),
        (0.56, ["C5", "E5", "G5"], 0.6, {"vel": 0.9}), (0.62, "D6", 0.8),
    ]),
    "menu-open": lambda: keys("E6", 0.3, 0.15),
    "plan-built": lambda: seq(keys, [(0, "A4", 0.6), (0.07, "C5", 0.65), (0.14, "E5", 0.7), (0.21, "G5", 0.75), (0.32, "B5", 1)], long=0.7),
    "favorite-on": lambda: seq(keys, [(0, "G5", 0.8), (0.07, "C6", 1)], vel=0.4, long=0.25),
    "favorite-off": lambda: keys("E5", 0.3, 0.2),
    "warning": lambda: seq(keys, [(0, ["A4", "Eb5"], 0.7), (0.15, ["A4", "Eb5"], 0.7)], vel=0.9, long=0.12),
}


# ------------------------------------------------------------------ 5. Air
# Slow, breathy pads. Nothing strikes; everything swells and lets go.

def air(note, attack=0.05, hold=0.0, release=0.3, breath=0.15):
    f = hz(note)
    t = tt(attack + hold + 6 * release)
    x = np.zeros(len(t))
    for cents in (-6.0, 0.0, 6.0):
        x += np.sin(TAU * f * 2 ** (cents / 1200) * t + RNG.uniform(0, TAU)) / 3
    x += 0.18 * np.sin(TAU * 2 * f * t + RNG.uniform(0, TAU)) + 0.05 * np.sin(TAU * 3 * f * t + RNG.uniform(0, TAU))
    breathy = unit(lp(reson(noise(len(t)), min(2 * f, 4000), 6), 5000))
    return (x + breath * breathy) * swell(t, attack, hold, release)


def wind(seconds, start, end, q=2.5):
    """Air through a band that moves: a breath in, or out."""
    n = int(SR * seconds)
    t = np.arange(n) / SR
    source = noise(n)
    out = np.zeros(n)
    steps = 7
    for k in range(steps):
        f = start * (end / start) ** (k / (steps - 1))
        out += reson(source, f, q) * np.exp(-((t / seconds - k / (steps - 1)) ** 2) / 0.025)
    return unit(lp(out, 6000) * np.sin(np.pi * np.clip(t / seconds, 0, 1)) ** 1.5)


AIR = {
    "tick-3": lambda: air("B4", 0.012, 0, 0.07, 0.12),
    "tick-2": lambda: air("B4", 0.012, 0, 0.07, 0.12),
    "tick-1": lambda: air("B4", 0.012, 0, 0.07, 0.12),
    "rest-over": lambda: mix([(0, seq(air, [(0, ["E5", "G#5", "B5"], 0.5)], attack=0.07, hold=0.12, release=0.22), 1), (0.16, air("E6", 0.06, 0.05, 0.3), 0.55)]),
    "warmup-over": lambda: mix([(0, seq(air, [(0, ["A4", "C#5", "E5"], 0.5)], attack=0.12, hold=0.12, release=0.12), 1), (0.34, seq(air, [(0, ["B4", "E5", "G#5", "B5"], 0.45)], attack=0.1, hold=0.15, release=0.3), 1)]),
    "rest-start": lambda: mix([(0, wind(0.5, 2600, 600), 0.22), (0.04, seq(air, [(0, ["B4", "E5"], 0.5)], attack=0.08, hold=0.0, release=0.2, breath=0.1), 1)]),
    "set-logged": lambda: seq(air, [(0, "B5", 0.8), (0.09, "E6", 1)], attack=0.015, release=0.09, breath=0.12),
    "exercise-done": lambda: seq(air, [(0, "E5", 0.7), (0.1, "B5", 0.8), (0.2, "G#5", 0.9, {"release": 0.26})], attack=0.03, release=0.14),
    "workout-start": lambda: mix([(0, wind(0.55, 500, 3200), 0.2), (0.0, seq(air, [(0, ["E4", "B4", "E5"], 0.5)], attack=0.45, hold=0.1, release=0.2), 1), (0.45, air("B5", 0.05, 0.05, 0.28), 0.5)]),
    "workout-finish": lambda: seq(air, [
        (0, ["E4", "B4"], 0.5, {"attack": 0.18}), (0.14, "E5", 0.45, {"attack": 0.2}), (0.28, "G#5", 0.42, {"attack": 0.22}),
        (0.42, "B5", 0.4, {"attack": 0.25}), (0.62, "F#6", 0.28, {"attack": 0.3}),
    ], hold=0.35, release=0.4),
    "menu-open": lambda: mix([(0, wind(0.09, 900, 2600, 3), 0.35), (0.02, air("G#5", 0.015, 0, 0.06, 0.1), 1)]),
    "plan-built": lambda: seq(air, [(0, "B4", 0.7), (0.12, "E5", 0.75), (0.24, "F#5", 0.8), (0.36, "B5", 0.9, {"release": 0.3})], attack=0.05, release=0.18),
    "favorite-on": lambda: seq(air, [(0, "B5", 0.8), (0.08, "E6", 1)], attack=0.012, release=0.07, breath=0.1),
    "favorite-off": lambda: seq(air, [(0, "E6", 0.9), (0.08, "B5", 0.8)], attack=0.012, release=0.05, breath=0.1),
    "warning": lambda: seq(air, [(0, ["F#4", "C5"], 0.6), (0.16, ["F#4", "C5"], 0.6)], attack=0.012, release=0.05, breath=0.05),
}


# ------------------------------------------------------------------ 6. Analog
# Two detuned saws through a resonant filter that snaps shut: a synth pluck.

def saws(f, fc, q=2.0, detune=7.0):
    """Two saws, f and the filter's cutoff both moving (Hz per sample)."""
    out = np.zeros(len(f))
    top = int(15000 / (np.max(f) * 1.006))
    for cents in (-detune, detune):
        fd = f * 2 ** (cents / 1200)
        ph = TAU * np.cumsum(fd) / SR
        for h in range(1, top + 1):
            r = h * fd / fc
            out += np.sin(h * ph) / (h * np.sqrt((1 - r * r) ** 2 + (r / q) ** 2))
    return out / 2


def synth(note, decay=0.2, lo=450, hi=4200, snap=0.06, q=2.0, attack=0.003):
    t = tt(attack + 6 * decay)
    fc = lo + (hi - lo) * np.exp(-t / snap)
    return saws(np.full(len(t), hz(note)), fc, q) * env(t, attack, decay)


def riser(start, end, seconds, lo=400, hi=5000):
    n = int(SR * seconds)
    t = np.arange(n) / SR
    f = hz(start) * (hz(end) / hz(start)) ** (t / seconds)
    fc = lo * (hi / lo) ** (t / seconds)
    shape = (t / seconds) ** 1.5 * np.clip((seconds - t) / 0.02, 0, 1)
    return saws(f, fc, 2.5) * shape


def zap(f0, f1, decay=0.05, time=0.025, lo=700, hi=5000):
    n = int(SR * (0.003 + 6 * decay))
    t = np.arange(n) / SR
    fc = lo + (hi - lo) * np.exp(-t / 0.03)
    return saws(glide(f0, f1, n, time), fc, 3.0) * env(t, 0.003, decay)


ANALOG = {
    "tick-3": lambda: synth("A4", 0.06, 500, 3000, 0.03),
    "tick-2": lambda: synth("A4", 0.06, 500, 3000, 0.03),
    "tick-1": lambda: synth("A4", 0.06, 500, 3800, 0.03),
    "rest-over": lambda: seq(synth, [(0, "A4", 0.8), (0.07, "C5", 0.8), (0.14, "E5", 0.85), (0.21, "A5", 1, {"decay": 0.3, "snap": 0.12})], decay=0.1),
    "warmup-over": lambda: seq(synth, [(0, "A3", 0.8), (0.07, "E4", 0.8), (0.14, "A4", 0.8), (0.21, "C5", 0.85), (0.28, "E5", 0.9), (0.35, "A5", 1, {"decay": 0.3, "snap": 0.12})], decay=0.1),
    "rest-start": lambda: synth("E4", 0.3, 300, 3200, 0.16, 2.8),
    "set-logged": lambda: seq(synth, [(0, "A4", 0.85), (0.07, "E5", 1)], decay=0.09, q=2.8),
    "exercise-done": lambda: seq(synth, [(0, "C5", 0.8), (0.08, "E5", 0.85), (0.16, "G5", 1, {"decay": 0.26, "snap": 0.1})], decay=0.1),
    "workout-start": lambda: mix([(0, riser("A3", "A4", 0.38), 0.5), (0.38, seq(synth, [(0, ["A4", "E5", "A5"], 0.5)], decay=0.3, hi=6000, snap=0.14), 1)]),
    "workout-finish": lambda: seq(synth, [
        (0, "A4", 0.7), (0.08, "C5", 0.7), (0.16, "E5", 0.75), (0.24, "G5", 0.8),
        (0.36, ["A4", "C5", "E5", "G5"], 0.4, {"decay": 0.16, "snap": 0.08}),
        (0.64, ["C5", "E5", "G5", "C6"], 0.45, {"decay": 0.5, "hi": 6000, "snap": 0.25}),
    ], decay=0.09),
    "menu-open": lambda: zap(330, 660, 0.035),
    "plan-built": lambda: seq(synth, [(0, "A4", 0.7), (0.065, "C5", 0.75), (0.13, "D5", 0.8), (0.195, "E5", 0.85), (0.26, "G5", 0.9), (0.325, "A5", 1, {"decay": 0.26, "snap": 0.12})], decay=0.07),
    "favorite-on": lambda: seq(synth, [(0, "E5", 0.8), (0.065, "A5", 1)], decay=0.06, q=3.0),
    "favorite-off": lambda: zap(880, 440, 0.04, 0.03, 500, 2500),
    "warning": lambda: seq(synth, [(0, "A3", 1), (0.14, "A3", 1)], decay=0.06, lo=1800, hi=2600, q=1.2),
}


# ------------------------------------------------------------------ 7. Chip
# A games console: a pulse wave and a triangle, in steps of a sixtieth of a
# second.

def pulse(f, duty=0.5, top=8000):
    ph = TAU * np.cumsum(f) / SR
    out = np.zeros(len(f))
    for h in range(1, int(top / np.max(f)) + 1):
        amp = 2 / (h * np.pi) * np.sin(np.pi * h * duty)
        if abs(amp) > 1e-4:
            out += amp * np.cos(h * ph)
    return out


def triangle(f, top=8000):
    ph = TAU * np.cumsum(f) / SR
    out = np.zeros(len(f))
    for k, h in enumerate(range(1, int(top / np.max(f)) + 1, 2)):
        out += 8 / np.pi ** 2 * (-1) ** k / (h * h) * np.sin(h * ph)
    return out


def chip(note, frames, duty=0.5, fade=None, to=None, vib=0.0, tri=False):
    """One note, `frames` sixtieths long. `fade` steps the volume down to
    nothing over that many frames, as the old sound chips did."""
    n = int(frames * SR / 60)
    t = np.arange(n) / SR
    f = np.full(n, hz(note))
    if to is not None:
        f = hz(note) * (hz(to) / hz(note)) ** (t / t[-1])
    if vib:
        f = f * (1 + vib * np.sin(TAU * 11 * t))
    x = triangle(f) if tri else pulse(f, duty)
    gate = np.clip(t / 0.0015, 0, 1) * np.clip((t[-1] - t) / 0.0015, 0, 1)
    if fade:
        gate *= np.clip(1 - np.floor(t * 60) / fade, 0, 1)
    return x * gate


def line(notes, **common):
    """Notes one after another: (note or None for a rest, frames, overrides)."""
    layers, at = [], 0.0
    for item in notes:
        note, frames = item[0], item[1]
        extra = item[2] if len(item) > 2 else {}
        if note is not None:
            layers.append((at, chip(note, frames, **{**common, **extra}), 1.0))
        at += frames / 60
    return mix(layers)


CHIP = {
    "tick-3": lambda: chip("A5", 4),
    "tick-2": lambda: chip("A5", 4),
    "tick-1": lambda: chip("A5", 4),
    "rest-over": lambda: line([("A5", 3), ("C#6", 3), ("E6", 3), ("A6", 18, {"fade": 18})]),
    "warmup-over": lambda: line([("E5", 3), ("A5", 3), ("E5", 3), ("A5", 3), ("C#6", 3), ("E6", 20, {"fade": 20, "vib": 0.006})]),
    "rest-start": lambda: line([("E6", 4, {"duty": 0.25}), ("C#6", 4, {"duty": 0.25}), ("A5", 10, {"duty": 0.25, "fade": 10})]),
    "set-logged": lambda: line([("G5", 3), ("D6", 14, {"fade": 14})]),
    "exercise-done": lambda: line([("A5", 3), ("B5", 3), ("C#6", 3), ("E6", 3), ("A6", 16, {"fade": 16})]),
    "workout-start": lambda: mix([(0, chip("A3", 16, 0.25, to="A5"), 0.8), (16 / 60, line([("A5", 4), ("E6", 20, {"fade": 20, "vib": 0.006})]), 1)]),
    "workout-finish": lambda: mix([
        (0, line([("E5", 4), ("A5", 4), ("C#6", 4), ("E6", 4), ("D6", 9), ("C#6", 4), ("E6", 5), ("A6", 34, {"fade": 34, "vib": 0.006})]), 1),
        (0, line([("A3", 16, {"tri": True}), ("D4", 9, {"tri": True}), ("E4", 9, {"tri": True}), ("A4", 30, {"tri": True, "fade": 30})]), 0.9),
    ]),
    "menu-open": lambda: line([("A5", 2), ("E6", 3)], duty=0.25),
    "plan-built": lambda: line([("A5", 3), ("C#6", 3), ("E6", 3), ("A6", 3), ("E6", 3), ("A6", 14, {"fade": 14})]),
    "favorite-on": lambda: line([("E6", 3), ("A6", 8, {"fade": 8})]),
    "favorite-off": lambda: line([("A5", 3), ("E5", 6, {"fade": 6})]),
    "warning": lambda: line([("A3", 6), (None, 2), ("G#3", 9)], duty=0.25),
}


# ------------------------------------------------------------------ 8. Dot
# A stopwatch's beeper: hard little bips in patterns, like dots and dashes.

LOW, MID, HIGH = 1568.0, 2093.0, 2637.0   # G6, C7, E7


def bip(f, seconds):
    n = int(SR * (seconds + 0.03))
    t = np.arange(n) / SR
    x = np.sin(TAU * f * t) + 0.12 * np.sin(TAU * 3 * f * t)
    shape = np.clip(t / 0.0012, 0, 1) * np.where(t < seconds, 1.0, np.exp(-(t - seconds) / 0.004))
    return x * shape


def bips(pattern):
    """(time, pitch, length) bips."""
    return mix([(at, bip(f, length), 1.0) for at, f, length in pattern])


DOT = {
    "tick-3": lambda: bip(MID, 0.055),
    "tick-2": lambda: bip(MID, 0.055),
    "tick-1": lambda: bip(MID, 0.055),
    "rest-over": lambda: bips([(0, HIGH, 0.06), (0.11, HIGH, 0.06), (0.34, HIGH, 0.06), (0.45, HIGH, 0.06)]),
    "warmup-over": lambda: bips([(0, MID, 0.05), (0.1, MID, 0.05), (0.2, MID, 0.05), (0.3, HIGH, 0.3)]),
    "rest-start": lambda: bips([(0, MID, 0.045), (0.08, LOW, 0.1)]),
    "set-logged": lambda: bips([(0, LOW, 0.04), (0.06, MID, 0.07)]),
    "exercise-done": lambda: bips([(0, LOW, 0.045), (0.065, MID, 0.045), (0.13, HIGH, 0.09)]),
    "workout-start": lambda: bips([(0, LOW, 0.05), (0.09, LOW, 0.05), (0.18, MID, 0.05), (0.27, HIGH, 0.26)]),
    "workout-finish": lambda: bips([
        (0, LOW, 0.05), (0.09, LOW, 0.05), (0.18, LOW, 0.05), (0.27, MID, 0.16),
        (0.54, MID, 0.05), (0.63, MID, 0.05), (0.72, HIGH, 0.4),
    ]),
    "menu-open": lambda: bip(MID, 0.016),
    "plan-built": lambda: bips([(i * 0.045, (LOW, MID, HIGH, MID)[i % 4], 0.025) for i in range(8)] + [(0.4, HIGH, 0.16)]),
    "favorite-on": lambda: bips([(0, MID, 0.025), (0.05, HIGH, 0.04)]),
    "favorite-off": lambda: bip(LOW, 0.03),
    "warning": lambda: bips([(0, 784.0, 0.11), (0.17, 784.0, 0.11)]),
}


# ------------------------------------------------------------------ 9. Drum
# A drum machine: no notes, only hits.

def clave():
    t = tt(0.12)
    return np.sin(TAU * 2450 * t) * env(t, 0.0004, 0.016)


def block(f=900):
    t = tt(0.2)
    return (np.sin(TAU * f * t) + 0.35 * np.sin(TAU * f * 2.71 * t) * np.exp(-t / 0.008)) * env(t, 0.0005, 0.028)


def rim():
    t = tt(0.1)
    tone = (np.sin(TAU * 1720 * t) + 0.6 * np.sin(TAU * 480 * t)) * env(t, 0.0003, 0.009)
    return tone + 0.5 * unit(hp(noise(len(t)), 3000)) * np.exp(-t / 0.003)


def tom(f=220, decay=0.14):
    t = tt(0.004 + 6 * decay)
    ph = TAU * np.cumsum(f * (1 + 0.55 * np.exp(-t / 0.035))) / SR
    body = (np.sin(ph) + 0.25 * np.sin(2 * ph) * np.exp(-t / (decay * 0.3))) * env(t, 0.001, decay)
    return body + 0.2 * unit(lp(noise(len(t)), 4000)) * np.exp(-t / 0.004)


def kick():
    t = tt(0.6)
    ph = TAU * np.cumsum(62 + 170 * np.exp(-t / 0.035)) / SR
    return np.sin(ph) * env(t, 0.001, 0.11) + 0.35 * unit(lp(noise(len(t)), 5000)) * np.exp(-t / 0.003)


def snare(decay=0.1):
    t = tt(0.004 + 6 * decay)
    drop = 1 + 0.4 * np.exp(-t / 0.02)
    tone = (np.sin(TAU * np.cumsum(190 * drop) / SR) + 0.6 * np.sin(TAU * np.cumsum(335 * drop) / SR)) * env(t, 0.0007, 0.06)
    wires = unit(bp(noise(len(t)), 1500, 9000)) * env(t, 0.0007, decay)
    return 0.7 * tone + wires


def clap(decay=0.09):
    t = tt(0.03 + 6 * decay)
    shape = sum(np.where(t >= d, np.exp(-(t - d) / 0.005), 0.0) for d in (0.0, 0.011, 0.022))
    shape = shape * (t < 0.03) + np.where(t >= 0.03, np.exp(-(t - 0.03) / decay), 0.0)
    return unit(bp(noise(len(t)), 800, 2600)) * shape


def hat(decay=0.025, tone=7000):
    t = tt(0.002 + 6 * decay)
    return unit(hp(noise(len(t)), tone, 4)) * env(t, 0.0005, decay)


def cowbell():
    t = tt(0.9)
    x = pulse(np.full(len(t), 540.0), top=6000) + pulse(np.full(len(t), 800.0), top=6000)
    shape = np.clip(t / 0.0008, 0, 1) * (0.7 * np.exp(-t / 0.012) + 0.3 * np.exp(-t / 0.12))
    return bp(x, 600, 3000) * shape


def shaker():
    t = tt(0.2)
    return unit(hp(noise(len(t)), 4500, 3)) * env(t, 0.012, 0.03)


def kit(hits):
    return mix([(at, make(), gain) for at, make, gain in hits])


DRUM = {
    "tick-3": clave,
    "tick-2": clave,
    "tick-1": clave,
    "rest-over": lambda: kit([(0, lambda: tom(300, 0.1), 0.8), (0.12, lambda: tom(300, 0.1), 0.85), (0.24, snare, 0.8), (0.24, lambda: hat(0.2, 6000), 0.35)]),
    "warmup-over": lambda: kit([(0, hat, 0.5), (0.1, hat, 0.55), (0.2, hat, 0.6), (0.3, hat, 0.7), (0.4, lambda: tom(200, 0.14), 0.9), (0.55, clap, 0.8)]),
    "rest-start": lambda: kit([(0, shaker, 0.8), (0.12, lambda: hat(0.14, 5500), 0.5)]),
    "set-logged": lambda: kit([(0, rim, 0.8), (0.085, lambda: block(1100), 0.9)]),
    "exercise-done": lambda: kit([(0, lambda: snare(0.05), 0.5), (0.07, lambda: snare(0.05), 0.65), (0.14, lambda: snare(0.05), 0.8), (0.23, clap, 0.9)]),
    "workout-start": lambda: kit([(0, lambda: tom(170, 0.12), 0.85), (0.11, lambda: tom(220, 0.12), 0.85), (0.22, lambda: tom(300, 0.12), 0.9), (0.34, snare, 0.8), (0.34, kick, 0.8), (0.34, lambda: hat(0.3, 5500), 0.3)]),
    "workout-finish": lambda: kit([
        (0, lambda: snare(0.05), 0.45), (0.075, lambda: snare(0.05), 0.55), (0.15, lambda: snare(0.05), 0.65), (0.225, lambda: snare(0.05), 0.75),
        (0.3, lambda: tom(300, 0.11), 0.85), (0.4, lambda: tom(220, 0.12), 0.85), (0.5, lambda: tom(170, 0.13), 0.9),
        (0.64, kick, 0.9), (0.64, clap, 0.6), (0.64, lambda: hat(0.55, 4500), 0.4),
    ]),
    "menu-open": lambda: hat(0.012, 6500),
    "plan-built": lambda: kit([(0, shaker, 0.6), (0.1, shaker, 0.6), (0.2, rim, 0.8), (0.3, rim, 0.8), (0.4, cowbell, 0.8)]),
    "favorite-on": lambda: kit([(0, lambda: clap(0.035), 0.9)]),
    "favorite-off": lambda: tom(150, 0.05),
    "warning": lambda: kit([(0, lambda: tom(120, 0.07), 1), (0.15, lambda: tom(110, 0.09), 1)]),
}


# ------------------------------------------------------------------ the packs

# id, name, what it is in a line, (reverb time, reverb amount, brightness), sounds
PACKS = [
    ("pure", "Pure", "Soft sine tones. Nothing but the note.", (0.35, 0.07, 6000), PURE),
    ("marimba", "Marimba", "A warm wooden bar under a soft mallet.", (0.4, 0.1, 5000), MARIMBA),
    ("harp", "Harp", "A plucked nylon string, strummed for the big moments.", (0.6, 0.14, 5000), HARP),
    ("keys", "Keys", "A mellow electric piano with jazzier chords.", (0.5, 0.12, 4500), KEYS),
    ("air", "Air", "Breathy pads that swell and let go. Nothing strikes.", (1.3, 0.3, 4500), AIR),
    ("analog", "Analog", "A synthesizer pluck: saws through a snapping filter.", (0.35, 0.08, 5500), ANALOG),
    ("chip", "Chip", "An old games console: pulse waves in quick steps.", (0.2, 0.03, 6000), CHIP),
    ("dot", "Dot", "A stopwatch beeper, in dots and dashes.", (0.2, 0.03, 6000), DOT),
    ("drum", "Drum", "A drum machine. No notes, only hits.", (0.3, 0.07, 7000), DRUM),
]


def render(pack, event):
    global RNG
    pack_id, _, _, (rt, wet, bright), sounds = pack
    event_id, _, _, _, level = event
    RNG = np.random.default_rng(zlib.crc32(f"{pack_id}/{event_id}".encode()))
    if event_id in SMALL:
        # A tick a second apart, or a tap: a long tail would only smear it.
        rt, wet = min(rt, 0.3), wet * 0.6
    return master(room(sounds[event_id](), rt, wet, bright), level)


def write_wav(path, x):
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def outline(x, columns=28, rows=5):
    """The sound's shape as dot heights, for the page to draw."""
    edges = np.linspace(0, len(x), columns + 1).astype(int)
    peaks = np.array([np.max(np.abs(x[a:b])) if b > a else 0.0 for a, b in zip(edges[:-1], edges[1:])])
    db = 20 * np.log10(peaks / (np.max(peaks) + 1e-12) + 1e-6)
    return [int(v) for v in np.clip(np.ceil((db + 40) / 40 * rows), 0, rows)]


def main():
    page = os.path.join(OUT, "audition")
    os.makedirs(os.path.join(page, "packs"), exist_ok=True)
    manifest = {
        "events": [{"id": e[0], "name": e[1], "when": e[2], "group": e[3]} for e in EVENTS],
        "packs": [],
    }
    gap = np.zeros(int(0.08 * SR))
    for pack in PACKS:
        pack_id, name, blurb, _, _ = pack
        os.makedirs(os.path.join(OUT, pack_id), exist_ok=True)
        strip, clips, at = [], {}, 0
        for event in EVENTS:
            x = render(pack, event)
            write_wav(os.path.join(OUT, pack_id, event[0] + ".wav"), x)
            clips[event[0]] = {"at": round(at / SR, 5), "len": round(len(x) / SR, 5), "shape": outline(x)}
            strip += [x, gap]
            at += len(x) + len(gap)
            print(f"{pack_id:8s} {event[0]:15s} {len(x) / SR:5.2f}s  peak {20 * np.log10(np.max(np.abs(x))):6.1f} dB  loud {loudness(x):6.1f} dB")
        write_wav(os.path.join(page, "packs", pack_id + ".wav"), np.concatenate(strip))
        manifest["packs"].append({"id": pack_id, "name": name, "blurb": blurb, "clips": clips})

    with open(os.path.join(OUT, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=1)
    template = os.path.join(HERE, "audition.html")
    if os.path.exists(template):
        with open(template) as f:
            html = f.read()
        html = html.replace("/*MANIFEST*/null", json.dumps(manifest, separators=(",", ":")))
        # index.html is the page's content alone, as it is published; local.html
        # is the same inside a document, for `python3 -m http.server`.
        with open(os.path.join(page, "index.html"), "w") as f:
            f.write(html)
        with open(os.path.join(page, "local.html"), "w") as f:
            f.write('<!doctype html><html><head><meta charset="utf-8">'
                    '<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">'
                    "<style>body{margin:0}[hidden]{display:none!important}</style></head><body>"
                    + html + "</body></html>")
        print("page:", os.path.join(page, "index.html"))


if __name__ == "__main__":
    main()
