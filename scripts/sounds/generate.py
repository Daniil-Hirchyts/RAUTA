#!/usr/bin/env python3
"""
Rauta's sounds, as the app ships them.

They were picked by ear from the candidates in packs.py: Pure, soft sine
tones, for the cues and the taps, and Marimba where something is completed.
What the app makes on the spot (RAUTA's voice, a thought, a card arriving)
is Pure again, made by `SoundSynth` in the app.

    python3 scripts/sounds/generate.py

writes ios/Rauta/Rauta/Resources/Sounds/rauta-<name>.caf. Deterministic, so
running it again changes nothing in git. Needs numpy and scipy; converts with
macOS `afconvert`.
"""

import os
import subprocess
import tempfile

from packs import EVENTS, PACKS, ROOT, SR, render, write_wav

OUT = os.path.join(ROOT, "ios", "Rauta", "Rauta", "Resources", "Sounds")

# Every sound is Pure unless it is named here.
MARIMBA = {"exercise-done", "workout-finish", "plan-built"}


def main():
    packs = {pack[0]: pack for pack in PACKS}
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        for event in EVENTS:
            name = event[0]
            pack = packs["marimba" if name in MARIMBA else "pure"]
            signal = render(pack, event)
            wav = os.path.join(tmp, name + ".wav")
            write_wav(wav, signal)
            caf = os.path.join(OUT, f"rauta-{name}.caf")
            subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16@44100", "-c", "1", wav, caf], check=True)
            print(f"rauta-{name:16s} {pack[1]:8s} {len(signal) / SR:5.2f}s")


if __name__ == "__main__":
    main()
