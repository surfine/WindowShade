#!/usr/bin/env python3
"""Generate synthetic RGBA8 PNG aspect-ratio fixtures for design QA.

Usage:
    python3 tools/design-qa/make-window-image-fixtures.py ABS_OUTPUT

Writes five opaque RGBA8 PNG files plus manifest.json into ABS_OUTPUT.
No UI frameworks, no CGImage, no screenshots, no permissions: pure stdlib.
"""

from __future__ import annotations

import hashlib
import json
import struct
import sys
import zlib
from pathlib import Path

# ---------------------------------------------------------------- spec table

SPECS = [
    ("landscape16x9", 640, 360),
    ("landscape4x3", 480, 360),
    ("square360x360", 360, 360),
    ("portrait9x16", 360, 640),
    ("ultrawide3x1", 900, 300),
]

# Neutral dark grey background.
BG = (32, 32, 32, 255)
# White outer border thickness in pixels.
BORDER = 8
BORDER_RGBA = (255, 255, 255, 255)
# Central light grey cross.
CROSS_RGBA = (200, 200, 200, 255)
CROSS_ARM = 4  # half-thickness of each cross arm in pixels

# Corner blocks: fraction of the smaller image dimension, kept inside border.
CORNER_FRACTION = 0.12
CORNERS = {
    "top_left": (255, 0, 0, 255),      # red
    "top_right": (0, 255, 0, 255),     # green
    "bottom_left": (0, 0, 255, 255),   # blue
    "bottom_right": (255, 255, 0, 255) # yellow
}


def corner_size(width: int, height: int) -> int:
    """Size (px, square) of each corner block, expressed from the short side."""
    shorter = min(width, height)
    size = int(round(shorter * CORNER_FRACTION))
    return max(size, 1)


def build_pixels(width: int, height: int) -> bytearray:
    """Build a raw top-down RGBA8 pixel buffer (no PNG framing)."""
    # Start with the neutral background everywhere.
    pixels = bytearray()
    for _ in range(height):
        pixels.extend(bytes(BG) * width)

    def put(x: int, y: int, rgba) -> None:
        if 0 <= x < width and 0 <= y < height:
            off = (y * width + x) * 4
            pixels[off:off + 4] = bytes(rgba)

    # 8px white border, fully inside the image on every side.
    b = min(BORDER, width // 2, height // 2)
    for y in range(height):
        for x in range(width):
            if x < b or x >= width - b or y < b or y >= height - b:
                put(x, y, BORDER_RGBA)

    # Corner blocks, placed inside the border so they never clip it.
    cs = corner_size(width, height)
    cs = min(cs, width - 2 * b if width - 2 * b > 0 else cs)
    cs = min(cs, height - 2 * b if height - 2 * b > 0 else cs)
    cs = max(cs, 1)
    positions = {
        "top_left": (b, b),
        "top_right": (width - b - cs, b),
        "bottom_left": (b, height - b - cs),
        "bottom_right": (width - b - cs, height - b - cs),
    }
    for name, (bx, by) in positions.items():
        rgba = CORNERS[name]
        for dy in range(cs):
            for dx in range(cs):
                put(bx + dx, by + dy, rgba)

    # Light grey cross through the centre.
    cx = width // 2
    cy = height // 2
    for y in range(b, height - b):
        for x in range(b, width - b):
            if abs(x - cx) <= CROSS_ARM or abs(y - cy) <= CROSS_ARM:
                put(x, y, CROSS_RGBA)

    assert len(pixels) == width * height * 4, "raw RGBA buffer size mismatch"
    return pixels


# ------------------------------------------------------------------ PNG bits

def png_chunk(tag: bytes, payload: bytes) -> bytes:
    assert len(tag) == 4, "chunk tag must be 4 bytes"
    crc = zlib.crc32(tag + payload) & 0xFFFFFFFF
    return (
        struct.pack(">I", len(payload))
        + tag
        + payload
        + struct.pack(">I", crc)
    )


def encode_png(width: int, height: int, pixels: bytes) -> bytes:
    """Encode top-down RGBA8 into a PNG using filter type 0 everywhere."""
    assert len(pixels) == width * height * 4, "raw RGBA buffer size mismatch"

    stride = width * 4
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter type 0 (None)
        raw.extend(pixels[y * stride:(y + 1) * stride])
    assert len(raw) == height * (stride + 1), "scanline buffer size mismatch"

    ihdr = struct.pack(
        ">IIBBBBB",
        width,
        height,
        8,  # bit depth
        6,  # color type: RGBA
        0,  # compression
        0,  # filter
        0,  # interlace
    )

    return (
        b"\x89PNG\r\n\x1a\n"
        + png_chunk(b"IHDR", ihdr)
        + png_chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + png_chunk(b"IEND", b"")
    )


# ---------------------------------------------------------------- manifest

def sample_rgba(pixels: bytes, width: int, x: int, y: int) -> list:
    off = (y * width + x) * 4
    return list(pixels[off:off + 4])


def corner_centers(width: int, height: int) -> dict:
    cs = corner_size(width, height)
    b = min(BORDER, width // 2, height // 2)
    cs = max(min(cs, max(width - 2 * b, 1), max(height - 2 * b, 1)), 1)
    half = cs // 2
    return {
        "top_left": (b + half, b + half),
        "top_right": (width - b - cs + half, b + half),
        "bottom_left": (b + half, height - b - cs + half),
        "bottom_right": (width - b - cs + half, height - b - cs + half),
    }


def main(argv: list) -> int:
    if len(argv) != 2:
        print("usage: make-window-image-fixtures.py ABS_OUTPUT", file=sys.stderr)
        return 2

    out_dir = Path(argv[1])
    out_dir.mkdir(parents=True, exist_ok=True)

    manifest = {
        "generator": "tools/design-qa/make-window-image-fixtures.py",
        "colorType": "RGBA8",
        "images": [],
    }

    for name, width, height in SPECS:
        pixels = build_pixels(width, height)
        png_bytes = encode_png(width, height, bytes(pixels))

        file_name = f"{name}_{width}x{height}.png"
        path = out_dir / file_name
        path.write_bytes(png_bytes)

        centers = corner_centers(width, height)
        corners = {}
        for corner_name, (cx, cy) in centers.items():
            corners[corner_name] = {
                "center": {"x": cx, "y": cy, "coordinateOrigin": "top-left"},
                "rgba": sample_rgba(bytes(pixels), width, cx, cy),
            }

        manifest["images"].append(
            {
                "name": name,
                "file": file_name,
                "width": width,
                "height": height,
                "sha256": hashlib.sha256(png_bytes).hexdigest(),
                "cornerBlocks": corners,
            }
        )

    manifest_path = out_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    for image in manifest["images"]:
        print(f"{image['file']}: {image['width']}x{image['height']} sha256={image['sha256'][:16]}...")
    print(f"manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
