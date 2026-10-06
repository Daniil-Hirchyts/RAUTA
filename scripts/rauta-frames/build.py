#!/usr/bin/env python3
"""
RAUTA's frames, for the places its Rive rig cannot run.

RiveRuntime has no watchOS build, and WidgetKit cannot draw its Metal view, so
the watch and the Lock Screen play frames of the real rig instead, rendered
here from ios/Rauta/Media/rauta.riv by the local `rive-mcp` renderer:

- the watch gets one sprite sheet per mood loop
  (ios/Rauta/RautaWatch/RautaFrames/rauta-<loop>.png and .json), played by
  `RautaSprite`;
- the Live Activity gets timer fonts (ios/Rauta/RautaWidgets/RautaFonts/):
  for each loop, 2F fonts whose digits are frames as colour `sbix` bitmaps,
  plus one mask font. `RautaTimerSprite` stacks `Text(date, style: .timer)`
  views in those fonts, each revealed for 1/F of a second in turn, which plays
  the loop at F frames a second with no updates from the app.

    python3 scripts/rauta-frames/build.py            # everything
    python3 scripts/rauta-frames/build.py --fonts 4  # Lock Screen fonts at 4 fps

Deterministic: running it again over the same rig writes the same files.
Needs Pillow and fontTools, and `rive-mcp` on the PATH.

How the Lock Screen loop works, for layer k of L = 2F:
  - its frame timer counts from epoch + k/F; its font draws frame 2F*j + k on
    the even digit 2j and nothing on odd digits, so it shows only in even
    seconds of its own count;
  - its mask timer counts from epoch + (k+1)/F + 1 in the mask font, a solid
    square on even digits — shown in the other half of each two seconds;
  - the two overlap for exactly [k/F, (k+1)/F) of every two seconds, so one
    layer at a time is visible, and five passes of the ten-second digit make a
    ten-second loop of 10F frames.
"""

import argparse
import io
import json
import os
import plistlib
import subprocess
import sys
import tempfile

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import newTable
from fontTools.ttLib.tables.sbixGlyph import Glyph as SbixGlyph
from fontTools.ttLib.tables.sbixStrike import Strike
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RIG = os.path.join(ROOT, "ios", "Rauta", "Media", "rauta.riv")
WATCH_DIR = os.path.join(ROOT, "ios", "Rauta", "RautaWatch", "RautaFrames")
FONT_DIR = os.path.join(ROOT, "ios", "Rauta", "RautaWidgets", "RautaFonts")
FONT_SWIFT = os.path.join(ROOT, "ios", "Rauta", "RautaWidgets", "RautaSpriteFonts.swift")
WIDGET_PLIST = os.path.join(ROOT, "ios", "Rauta", "Config", "RautaWidgets-Info.plist")

ARTBOARD = "KettlebellBot"
RIG_FPS = 60

# The rig's mood loops the two places use, by what they are for. Lengths are
# the loops' own, in the rig's frames.
LOOPS = {
    # name: (rig animation, loop length in rig frames)
    "calm": ("mood_00_calm", 312),
    "focused": ("mood_07_focused", 144),
    "happy": ("mood_09_happy", 120),
    "proud": ("mood_10_proud", 180),
    "determined": ("mood_16_determined", 210),
    "recovering": ("mood_18_recovering", 300),
}

# The watch: every loop it plays, at its own length. Waiting calm, bracing
# for a set, breathing through a rest, glad of a set logged, proud at the end.
WATCH_LOOPS = ["calm", "determined", "recovering", "happy", "proud"]
WATCH_FPS = 15
WATCH_PIXELS = 132

# The Lock Screen: ten seconds of each loop, as many of its cycles as fit. One
# loop per phase of the workout: warming up, a set, a rest, paused, done.
LOCK_LOOPS = ["focused", "determined", "recovering", "calm", "proud"]
LOCK_SECONDS = 10
# The card draws RAUTA 72 points across: three pixels a point.
LOCK_PIXELS = 216
UNITS_PER_EM = 1000
DIGITS = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]


class Rive:
    """A minimal MCP client for the `rive-mcp` renderer, over stdio."""

    def __init__(self):
        self.process = subprocess.Popen(
            ["rive-mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True,
        )
        self.next_id = 0
        self.request("initialize", {
            "protocolVersion": "2024-11-05",
            "capabilities": {},
            "clientInfo": {"name": "rauta-frames", "version": "1"},
        })
        self.send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})

    def send(self, message):
        self.process.stdin.write(json.dumps(message) + "\n")
        self.process.stdin.flush()

    def request(self, method, params):
        self.next_id += 1
        self.send({"jsonrpc": "2.0", "id": self.next_id, "method": method, "params": params})
        while True:
            line = self.process.stdout.readline()
            if not line:
                raise RuntimeError("rive-mcp closed the connection")
            message = json.loads(line)
            if message.get("id") != self.next_id:
                continue
            if "error" in message:
                raise RuntimeError(message["error"])
            return message["result"]

    def sprites(self, animation, count, seconds, pixels, out):
        result = self.request("tools/call", {"name": "riv_render_sprites", "arguments": {
            "path": RIG, "artboard": ARTBOARD, "animation": animation,
            "count": count, "duration": seconds, "width": pixels, "height": pixels, "out": out,
        }})
        if result.get("isError"):
            raise RuntimeError(f"rendering {animation} failed: {result}")
        with open(os.path.splitext(out)[0] + ".json") as handle:
            return json.load(handle)

    def close(self):
        self.process.terminate()
        self.process.wait(timeout=10)


def frames_of(sheet_path, meta):
    """The cells of a sprite sheet, in order."""
    sheet = Image.open(sheet_path).convert("RGBA")
    width, height = meta["cellW"], meta["cellH"]
    return [
        sheet.crop((column * width, row * height, (column + 1) * width, (row + 1) * height))
        for index in range(meta["count"])
        for row, column in [divmod(index, meta["cols"])]
    ]


# MARK: Watch

def build_watch(rive, scratch):
    os.makedirs(WATCH_DIR, exist_ok=True)
    for stale in os.listdir(WATCH_DIR):
        os.remove(os.path.join(WATCH_DIR, stale))
    for loop in WATCH_LOOPS:
        animation, length = LOOPS[loop]
        seconds = length / RIG_FPS
        count = round(seconds * WATCH_FPS)
        out = os.path.join(WATCH_DIR, f"rauta-{loop}.png")
        meta = rive.sprites(animation, count, seconds, WATCH_PIXELS, out)
        compact = png(Image.open(out).convert("RGBA"))
        with open(out, "wb") as handle:
            handle.write(compact)
        meta["fps"] = count / seconds
        with open(os.path.splitext(out)[0] + ".json", "w") as handle:
            json.dump(meta, handle, indent=2, sort_keys=True)
            handle.write("\n")
        print(f"watch  {loop:8s} {count} frames, {seconds:.1f} s")


# MARK: Lock Screen

def png(image):
    """A frame as a palette PNG: RAUTA is charcoal and off-white, so 256
    colours hold it all, at about a fifth of the size."""
    data = io.BytesIO()
    image.quantize(colors=256, method=Image.Quantize.FASTOCTREE).save(data, format="PNG", optimize=True)
    return data.getvalue()


def base_font(name, glyph_order):
    builder = FontBuilder(UNITS_PER_EM, isTTF=True)
    builder.setupGlyphOrder(glyph_order)
    cmap = {0x20: "space", 0x3A: "colon"}
    cmap.update({0x30 + digit: DIGITS[digit] for digit in range(10)})
    builder.setupCharacterMap(cmap)
    builder.setupNameTable({"familyName": name, "styleName": "Regular", "psName": name})
    return builder


def finish(builder, glyphs, metrics):
    builder.setupGlyf(glyphs)
    builder.setupHorizontalMetrics(metrics)
    # One em tall, sitting on the baseline, so a line of these is exactly one
    # glyph high.
    builder.setupHorizontalHeader(ascent=UNITS_PER_EM, descent=0)
    builder.setupOS2(
        sTypoAscender=UNITS_PER_EM, sTypoDescender=0, sTypoLineGap=0,
        usWinAscent=UNITS_PER_EM, usWinDescent=0, fsType=0,
    )
    builder.setupPost()
    builder.setupMaxp()


def empty_glyph():
    return TTGlyphPen(None).glyph()


def frame_font(name, frames, pixels):
    """Digits as colour bitmaps: frame `frames[d]` on digit d, none where
    `frames[d]` is None. The colon and space take no room, so the last digit
    of a growing timer always sits in the same place."""
    order = [".notdef", "space", "colon"] + DIGITS
    builder = base_font(name, order)
    finish(builder, {glyph: empty_glyph() for glyph in order}, advances(order))

    strike = Strike(ppem=pixels, resolution=72)
    for digit, frame in zip(DIGITS, frames):
        if frame is None:
            continue
        strike.glyphs[digit] = SbixGlyph(
            glyphName=digit, graphicType="png ", imageData=png(frame), originOffsetX=0, originOffsetY=0,
        )
    sbix = newTable("sbix")
    sbix.version = 1
    sbix.flags = 1
    sbix.strikes = {pixels: strike}
    builder.font["sbix"] = sbix
    return builder.font


def mask_font(name):
    """A solid square on even digits, nothing on odd ones."""
    order = [".notdef", "space", "colon"] + DIGITS
    builder = base_font(name, order)
    glyphs = {glyph: empty_glyph() for glyph in order}
    for digit in range(0, 10, 2):
        pen = TTGlyphPen(None)
        pen.moveTo((0, 0))
        pen.lineTo((0, UNITS_PER_EM))
        pen.lineTo((UNITS_PER_EM, UNITS_PER_EM))
        pen.lineTo((UNITS_PER_EM, 0))
        pen.closePath()
        glyphs[DIGITS[digit]] = pen.glyph()
    finish(builder, glyphs, advances(order))
    return builder.font


def advances(order):
    """Digits one em wide; the colon and space none."""
    metrics = {glyph: (0, 0) for glyph in order}
    metrics.update({digit: (UNITS_PER_EM, 0) for digit in DIGITS})
    metrics[".notdef"] = (UNITS_PER_EM, 0)
    return metrics


def build_lock_screen(rive, scratch, fps):
    os.makedirs(FONT_DIR, exist_ok=True)
    for stale in os.listdir(FONT_DIR):
        if stale.endswith(".ttf"):
            os.remove(os.path.join(FONT_DIR, stale))
    layers = 2 * fps
    total = LOCK_SECONDS * fps
    names = ["RautaMask"]
    mask_font("RautaMask").save(os.path.join(FONT_DIR, "RautaMask.ttf"))
    for loop in LOCK_LOOPS:
        animation, length = LOOPS[loop]
        cycle = length / RIG_FPS
        # As many of the loop's own cycles as fit ten seconds, played to fill
        # them exactly, so the ten-second seam is the loop's own seam.
        cycles = max(1, round(LOCK_SECONDS / cycle))
        out = os.path.join(scratch, f"lock-{loop}.png")
        meta = rive.sprites(animation, total, cycles * cycle, LOCK_PIXELS, out)
        frames = frames_of(out, meta)
        family = "Rauta" + loop.capitalize()
        for layer in range(layers):
            digits = [frames[2 * fps * (digit // 2) + layer] if digit % 2 == 0 else None for digit in range(10)]
            name = f"{family}{layer}"
            frame_font(name, digits, LOCK_PIXELS).save(os.path.join(FONT_DIR, name + ".ttf"))
            names.append(name)
        print(f"lock   {loop:8s} {total} frames in {layers} fonts, {cycles} cycles of {cycle:.2f} s")
    write_font_list(names, fps, layers)
    return names


def write_font_list(names, fps, layers):
    """Registers the fonts with the widget extension and tells its code how
    they were cut."""
    with open(WIDGET_PLIST, "rb") as handle:
        info = plistlib.load(handle)
    info["UIAppFonts"] = [name + ".ttf" for name in names]
    with open(WIDGET_PLIST, "wb") as handle:
        plistlib.dump(info, handle, sort_keys=True)
    loops = ", ".join(f'"{loop}"' for loop in LOCK_LOOPS)
    with open(FONT_SWIFT, "w") as handle:
        handle.write(f"""// Generated by scripts/rauta-frames/build.py. Do not edit; run it again.

/// How RAUTA's Lock Screen frames were cut into fonts: see
/// `scripts/rauta-frames/build.py` for the timing.
nonisolated enum RautaSpriteFonts {{
    /// Frames a second.
    static let framesPerSecond = {fps}
    /// Fonts per loop: two seconds of frames.
    static let layers = {layers}
    static let mask = "RautaMask"
    /// Each loop's fonts are "Rauta<Loop><layer>".
    static let loops: [String] = [{loops}]
}}
""")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    parser.add_argument("--fonts", type=int, default=8, help="Lock Screen frames a second (default 8)")
    parser.add_argument("--only", choices=["watch", "lock"], help="build one of the two")
    args = parser.parse_args()
    rive = Rive()
    try:
        with tempfile.TemporaryDirectory() as scratch:
            if args.only in (None, "watch"):
                build_watch(rive, scratch)
            if args.only in (None, "lock"):
                names = build_lock_screen(rive, scratch, args.fonts)
                print(f"lock   {len(names)} fonts registered in Config/RautaWidgets-Info.plist")
    finally:
        rive.close()


if __name__ == "__main__":
    sys.exit(main())
