"""
The battle ATB gauge's tiles, merged into the 8x8 font at build time: `fonts/atb_gauge.png` holds them side by side
(fill 0-8 px, left cap, right cap; palette indices 0-3 are the 2bpp colours), the font gets them in old kana slots
that are blank and unmapped (battle/atb_gauge.s draws with the same codes).
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

TILE_BYTES = 16
BLANK = bytes([0xFF, 0x00] * 8)  # the font's empty cell: colour 1 all over
FILL_TILES = range(0xE1, 0xEA)  # 0-8 px of fill
CAP_LEFT, CAP_RIGHT = 0xEB, 0xEC
SLOTS = [*FILL_TILES, CAP_LEFT, CAP_RIGHT]  # the PNG's tiles, left to right


def encode_tile(image: Image.Image, index: int) -> bytes:
    """Tile `index` of the strip as 2bpp: per row, bit plane 0 then bit plane 1."""
    out = bytearray()
    for y in range(8):
        planes = [0, 0]
        for x in range(8):
            colour = image.getpixel((index * 8 + x, y))
            for plane in (0, 1):
                planes[plane] |= (colour >> plane & 1) << (7 - x)
        out += bytes(planes)
    return bytes(out)


def merge(font: bytes, png: Path) -> bytes:
    """`font` with the gauge tiles in their slots; every slot must be blank in `font`."""
    image = Image.open(png)
    if image.mode != "P" or image.size != (8 * len(SLOTS), 8):
        raise ValueError(f"{png}: an indexed {8 * len(SLOTS)}x8 strip expected, got {image.mode} {image.size}")
    merged = bytearray(font)
    for index, slot in enumerate(SLOTS):
        cell = slice(slot * TILE_BYTES, (slot + 1) * TILE_BYTES)
        if merged[cell] != BLANK:
            raise ValueError(f"font tile {slot:#04x} is not blank: the gauge would overwrite a glyph")
        merged[cell] = encode_tile(image, index)
    return bytes(merged)


def build(font: Path, png: Path, destination: Path) -> None:
    destination.write_bytes(merge(font.read_bytes(), png))
