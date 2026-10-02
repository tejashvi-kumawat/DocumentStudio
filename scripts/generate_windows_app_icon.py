#!/usr/bin/env python3
"""Regenerate Windows app_icon.ico from the Linux brand mark PNG.

  python3 scripts/generate_windows_app_icon.py
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "linux/packaging/icons/hicolor/256x256/apps/document-studio.png"
OUT = ROOT / "windows/runner/resources/app_icon.ico"
SIZES = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]


def main() -> None:
    src = Image.open(SRC).convert("RGBA")
    images = [src.resize(s, Image.Resampling.LANCZOS) for s in SIZES]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    images[-1].save(OUT, format="ICO", sizes=SIZES, append_images=images[:-1])
    print(f"Wrote {OUT} ({OUT.stat().st_size} bytes) from {SRC}")


if __name__ == "__main__":
    main()
