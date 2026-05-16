#!/usr/bin/env python3
"""
Select the sharpest, temporally-spread frames from a directory of JPEGs.
Called by splat.sh between frame extraction and COLMAP.

Usage:
    python select_frames.py <input_dir> <output_dir> [--target N] [--blur-pct N]
"""
import argparse
import shutil
import sys
from pathlib import Path

import numpy as np


def load_gray(path):
    try:
        from PIL import Image
        return np.array(Image.open(path).convert("L"), dtype=np.float32)
    except ImportError:
        pass
    try:
        import cv2
        img = cv2.imread(str(path), cv2.IMREAD_GRAYSCALE)
        if img is None:
            raise RuntimeError(f"cv2 could not read {path}")
        return img.astype(np.float32)
    except ImportError:
        pass
    print(
        "ERROR: Pillow or OpenCV is required.\n"
        "Fix: mamba install -n tools -c conda-forge pillow",
        file=sys.stderr,
    )
    sys.exit(1)


def sharpness(gray):
    """Variance of the discrete Laplacian — higher means sharper."""
    lap = (
        gray[:-2, 1:-1] + gray[2:, 1:-1]
        + gray[1:-1, :-2] + gray[1:-1, 2:]
        - 4 * gray[1:-1, 1:-1]
    )
    return float(lap.var())


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("input_dir",  help="directory of frame_*.jpg files")
    ap.add_argument("output_dir", help="destination for selected frames")
    ap.add_argument("--target",   type=int, default=150,
                    help="number of frames to keep (default: 150)")
    ap.add_argument("--blur-pct", type=int, default=20,
                    help="drop the blurriest bottom N%% of frames (default: 20)")
    args = ap.parse_args()

    frames = sorted(Path(args.input_dir).glob("frame_*.jpg"))
    total = len(frames)
    if total == 0:
        print(f"ERROR: no frame_*.jpg found in {args.input_dir}", file=sys.stderr)
        sys.exit(1)

    print(f"[select] Scoring {total} frames for sharpness...", flush=True)
    scores = []
    for i, f in enumerate(frames):
        if i > 0 and i % 50 == 0:
            print(f"[select]   {i}/{total} scored", flush=True)
        scores.append((f, sharpness(load_gray(f))))
    print(f"[select]   {total}/{total} scored", flush=True)

    # Drop the blurriest frames below the Nth percentile
    threshold = float(np.percentile([s for _, s in scores], args.blur_pct))
    sharp = [(f, s) for f, s in scores if s >= threshold]
    dropped = total - len(sharp)

    # Pick temporally-spread subset up to --target
    if len(sharp) <= args.target:
        selected = [f for f, _ in sharp]
    else:
        step = len(sharp) / args.target
        selected = [sharp[int(i * step)][0] for i in range(args.target)]

    # Write selected frames to output dir (clear old contents first)
    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("*.jpg"):
        old.unlink()
    for f in selected:
        shutil.copy(f, out / f.name)

    print(
        f"[select] {total} extracted"
        f"  →  {dropped} blurry dropped (bottom {args.blur_pct}%)"
        f"  →  {len(selected)} frames selected for COLMAP",
        flush=True,
    )


if __name__ == "__main__":
    main()
