#!/usr/bin/env python3
"""Render the original FrameTrail film-and-conversation app icon."""

from pathlib import Path
import struct
import zlib

SIZE = 1024
SCALE = 2
DESTINATION = Path(__file__).resolve().parents[1] / "FrameTrail/Assets.xcassets/AppIcon.appiconset/AppIcon.png"


def rounded_box(x, y, left, top, right, bottom, radius):
    dx = max(left + radius - x, 0, x - right + radius)
    dy = max(top + radius - y, 0, y - bottom + radius)
    return left <= x <= right and top <= y <= bottom and dx * dx + dy * dy <= radius * radius


def color(x, y):
    blend = (x + y) / (2 * SIZE)
    result = (int(24 + 22 * blend), int(20 + 16 * blend), int(57 + 39 * blend))
    if rounded_box(x, y, 174, 280, 850, 752, 88):
        result = (239, 238, 255)
    if 640 < x < 787 and 714 < y < 841 and y < x + 54:
        result = (239, 238, 255)
    if rounded_box(x, y, 216, 369, 808, 663, 40):
        result = (42, 33, 82)
    if 308 <= y <= 340 or 692 <= y <= 724:
        if any(left <= x <= left + 52 for left in (247, 343, 439, 535, 631, 727)):
            result = (83, 68, 130)
    if 449 <= x <= 615 and abs(y - 516) <= (615 - x) * 0.65:
        result = (255, 198, 93)
    if abs(x - 772) / 52 + abs(y - 204) / 76 <= 1:
        result = (255, 198, 93)
    return result


def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def main():
    rows = bytearray()
    for y in range(SIZE):
        rows.append(0)
        for x in range(SIZE):
            samples = [color(x + (sx + 0.5) / SCALE, y + (sy + 0.5) / SCALE)
                       for sy in range(SCALE) for sx in range(SCALE)]
            rows.extend(sum(sample[channel] for sample in samples) // (SCALE * SCALE)
                        for channel in range(3))
    header = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0)
    image = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
    image += chunk(b"IDAT", zlib.compress(rows, level=9)) + chunk(b"IEND", b"")
    DESTINATION.parent.mkdir(parents=True, exist_ok=True)
    DESTINATION.write_bytes(image)
    print(f"Created {DESTINATION.name}: {len(image)} bytes")


if __name__ == "__main__":
    main()
