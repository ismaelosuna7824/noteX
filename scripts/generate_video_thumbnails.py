#!/usr/bin/env python3
"""
generate_video_thumbnails.py
----------------------------
Extracts a thumbnail frame from every .mp4 in assets/images/ and saves it
as a JPEG in assets/thumbnails/.

Strategy:
  1. ffmpeg extracts the raw frame (no scale filter — avoids yuvj420p issues
     on some ffmpeg builds).
  2. Pillow resizes + center-crops to THUMB_WIDTH × THUMB_HEIGHT.

Requirements:
  - ffmpeg on PATH:
      Windows: winget install ffmpeg   OR   choco install ffmpeg
      macOS:   brew install ffmpeg
      Linux:   sudo apt install ffmpeg
  - Pillow:
      pip install Pillow

Usage (run from project root):
  python3 scripts/generate_video_thumbnails.py

Pass --force to regenerate thumbnails that already exist.
"""

import re
import subprocess
import sys
from pathlib import Path

# Force UTF-8 output so filenames with CJK/special chars print correctly on Windows
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

try:
    from PIL import Image
except ImportError:
    print("ERROR: Pillow not installed.  Run:  pip install Pillow")
    sys.exit(1)

# ── Config ────────────────────────────────────────────────────────────────────
VIDEOS_DIR   = Path("assets/images")
THUMBS_DIR   = Path("assets/thumbnails")
THUMB_WIDTH  = 320
THUMB_HEIGHT = 180
JPEG_QUALITY = 85          # Pillow JPEG quality (1-95)
SEEK_SECONDS = 2           # grab frame at this timestamp
# ─────────────────────────────────────────────────────────────────────────────


def safe_stem(filename: str) -> str:
    """Convert a filename to a safe ASCII slug for Flutter asset keys."""
    stem = Path(filename).stem
    slug = re.sub(r"[^a-zA-Z0-9]+", "_", stem)
    slug = slug.strip("_")
    # Fallback for names that become empty after stripping (e.g. CJK filenames)
    return slug or f"video_{abs(hash(filename)) % 100000}"


def thumb_filename(video_filename: str) -> str:
    return safe_stem(video_filename) + "_thumb.jpg"


def check_ffmpeg() -> bool:
    try:
        subprocess.run(["ffmpeg", "-version"], capture_output=True, check=True)
        return True
    except (FileNotFoundError, subprocess.CalledProcessError):
        return False


def extract_frame(video_path: Path, out_path: Path, seek: float) -> bool:
    """
    Extract a single raw frame using ffmpeg with NO scale filter.
    Avoids yuvj420p conversion errors on some ffmpeg/Windows builds.
    Returns True on success.
    """
    cmd = [
        "ffmpeg", "-y",
        "-ss", str(seek),
        "-i", str(video_path),
        "-frames:v", "1",
        "-update", "1",   # required by newer ffmpeg for single-image output
        "-q:v", "2",
        str(out_path),
    ]
    result = subprocess.run(cmd, capture_output=True)
    return result.returncode == 0 and out_path.exists() and out_path.stat().st_size > 0


def resize_with_pillow(src: Path, dst: Path) -> bool:
    """Resize + letterbox to THUMB_WIDTH × THUMB_HEIGHT using Pillow."""
    try:
        with Image.open(src) as img:
            img = img.convert("RGB")
            img.thumbnail((THUMB_WIDTH, THUMB_HEIGHT), Image.LANCZOS)
            canvas = Image.new("RGB", (THUMB_WIDTH, THUMB_HEIGHT), (0, 0, 0))
            offset = (
                (THUMB_WIDTH  - img.width)  // 2,
                (THUMB_HEIGHT - img.height) // 2,
            )
            canvas.paste(img, offset)
            canvas.save(dst, "JPEG", quality=JPEG_QUALITY, optimize=True)
        return True
    except Exception as exc:
        print(f"\n    Pillow error: {exc}")
        return False


def extract_thumb(video_path: Path, thumb_path: Path) -> bool:
    """Full pipeline: ffmpeg raw frame → Pillow resize → final JPEG."""
    tmp = thumb_path.with_suffix(".tmp.jpg")

    # Try at SEEK_SECONDS, fall back to frame 0 for short videos
    for seek in (SEEK_SECONDS, 0):
        if extract_frame(video_path, tmp, seek):
            break
    else:
        return False

    success = resize_with_pillow(tmp, thumb_path)
    if tmp.exists():
        tmp.unlink()
    return success


def main():
    force = "--force" in sys.argv

    if not check_ffmpeg():
        print("ERROR: ffmpeg not found. Install it and make sure it's on PATH.")
        print("  Windows: winget install ffmpeg")
        print("  macOS:   brew install ffmpeg")
        print("  Linux:   sudo apt install ffmpeg")
        sys.exit(1)

    if not VIDEOS_DIR.exists():
        print(f"ERROR: {VIDEOS_DIR} not found. Run from the project root.")
        sys.exit(1)

    THUMBS_DIR.mkdir(exist_ok=True)

    videos = sorted(VIDEOS_DIR.glob("*.mp4"))
    if not videos:
        print(f"No .mp4 files found in {VIDEOS_DIR}")
        sys.exit(0)

    print(f"Found {len(videos)} video(s). Generating thumbnails...\n")

    ok, skipped, failed = 0, 0, []

    for video in videos:
        tname = thumb_filename(video.name)
        tpath = THUMBS_DIR / tname

        if tpath.exists() and not force:
            size_kb = tpath.stat().st_size // 1024
            print(f"  SKIP  {tname}  ({size_kb} KB)")
            skipped += 1
            continue

        print(f"  GEN   {video.name}")
        print(f"        -> {tname} ... ", end="", flush=True)

        if extract_thumb(video, tpath):
            size_kb = tpath.stat().st_size // 1024
            print(f"OK ({size_kb} KB)")
            ok += 1
        else:
            print("FAILED")
            failed.append(video.name)

    print(f"\n{'─'*60}")
    print(f"Done: {ok} generated, {skipped} skipped, {len(failed)} failed")

    if failed:
        print("\nFailed videos:")
        for f in failed:
            print(f"  • {f}")


if __name__ == "__main__":
    main()
