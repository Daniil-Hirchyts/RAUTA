#!/usr/bin/env python3
"""Upscale the per-exercise animation GIFs with a real (learned) super-resolution
model instead of naive interpolation.

Every frame of every source GIF is upscaled with OpenCV's dnn_superres module
using the ESPCN x2 model (Apache-2.0, see scripts/models/ESPCN_x2.pb and
THIRD_PARTY_NOTICES.md), then the frames are re-quantized to a shared palette
and re-encoded as a new animated GIF with the original per-frame durations and
loop count preserved.

Usage:
    python scripts/upscale_exercise_gifs.py SOURCE_DIR OUTPUT_DIR \
        [--model scripts/models/ESPCN_x2.pb] [--scale 2]

SOURCE_DIR/OUTPUT_DIR may be the same directory; files are processed into a
temporary path and only replace the original on success.

Requires: opencv-contrib-python-headless, numpy, Pillow (see
scripts/requirements-upscale.txt).
"""

import argparse
import sys
import tempfile
from pathlib import Path

import cv2
import numpy as np
from cv2 import dnn_superres
from PIL import Image, ImageSequence


def upscale_gif(path: Path, out_path: Path, sr: "dnn_superres.DnnSuperResImpl") -> None:
    im = Image.open(path)
    loop = im.info.get("loop", 0)

    frames = []
    durations = []
    for frame in ImageSequence.Iterator(im):
        durations.append(frame.info.get("duration", 100))
        rgb = np.array(frame.convert("RGB"))
        bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
        upscaled_bgr = sr.upsample(bgr)
        upscaled_rgb = cv2.cvtColor(upscaled_bgr, cv2.COLOR_BGR2RGB)
        frames.append(Image.fromarray(upscaled_rgb))

    # Quantize every frame against a single shared palette (built from the
    # first frame) so playback doesn't flicker/shift color between frames.
    # 64 colors is visually indistinguishable from 256 for this source
    # material (mostly grayscale gradients + a limited red highlight range)
    # and meaningfully smaller once GIF-compressed.
    palette_source = frames[0].quantize(colors=64, method=Image.MEDIANCUT)
    quantized = [frame.quantize(palette=palette_source) for frame in frames]

    with tempfile.NamedTemporaryFile(
        suffix=".gif", dir=out_path.parent, delete=False
    ) as tmp:
        tmp_path = Path(tmp.name)

    quantized[0].save(
        tmp_path,
        save_all=True,
        append_images=quantized[1:],
        duration=durations,
        loop=loop,
        disposal=2,
        optimize=True,
    )
    tmp_path.replace(out_path)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument(
        "--model",
        type=Path,
        default=Path("scripts/models/ESPCN_x2.pb"),
        help="Path to the dnn_superres model file (default: ESPCN x2).",
    )
    parser.add_argument(
        "--model-name",
        default="espcn",
        help="Model name for dnn_superres.setModel (default: espcn).",
    )
    parser.add_argument(
        "--scale", type=int, default=2, help="Upscale factor (default: 2)."
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=None,
        help="Only process the first N files (for testing).",
    )
    args = parser.parse_args()

    sr = dnn_superres.DnnSuperResImpl_create()
    sr.readModel(str(args.model))
    sr.setModel(args.model_name, args.scale)

    args.output_dir.mkdir(parents=True, exist_ok=True)
    sources = sorted(args.source_dir.glob("*.gif"))
    if args.limit:
        sources = sources[: args.limit]

    total = len(sources)
    for index, source in enumerate(sources, start=1):
        out_path = args.output_dir / source.name
        upscale_gif(source, out_path, sr)
        if index % 50 == 0 or index == total:
            print(f"{index}/{total} upscaled", file=sys.stderr)

    print(f"Done. Upscaled {total} GIFs into {args.output_dir}")


if __name__ == "__main__":
    main()
