"""
Names baked into small-VWF tiles at build time: the game DMAs a name's tiles from ROM instead of rendering it.

Each name is set with katsuji in the menu font (`menu_font.dat`, the font the runtime renderer reads, kerning
included, so a baked name is byte for byte what the renderer would draw) and encoded 2bpp in the menus' colours:
ink 3 on paper 1. The blob packs every name's tiles back to back, no name across a 32 KB LoROM bank (a DMA source
cannot wrap one); the table gives each name its offset in the blob, its tile count and how many pixel columns its last tile uses, so a
renderer can carry on drawing inside that tile.
"""

import struct
from collections.abc import Sequence
from pathlib import Path

from katsuji import VwfFont, colourize, encode_tiles, render
from katsuji.strings import pack_runs
from katsuji.tiles import pad_to_tiles

LOROM_BANK = 0x8000
INK, PAPER = 3, 1
SPACE = 0xFF
ENTRY = struct.Struct("<HBB")  # offset in the blob, tile count, pixel columns the last tile uses (1-8)


def name_tiles(font: VwfFont, codes: bytes) -> bytes:
    """`codes` set in `font`, 2bpp tiles; no tile for an empty name."""
    codes = codes.rstrip(bytes([SPACE]))
    if not codes:
        return b""
    return encode_tiles(pad_to_tiles(colourize(render(font, list(codes)), INK, PAPER), fill=PAPER), 2)


def last_tile_columns(font: VwfFont, codes: bytes) -> int:
    """The pixel columns `codes` covers in its last tile (1-8), 0 for an empty name."""
    codes = codes.rstrip(bytes([SPACE]))
    if not codes:
        return 0
    return (render(font, list(codes)).shape[1] - 1) % 8 + 1


def bake(font: VwfFont, names: Sequence[bytes]) -> tuple[bytes, bytes]:
    """The blob of every name's tiles and its table, one entry per name."""
    runs = [name_tiles(font, codes) for codes in names]
    blob, offsets = pack_runs(runs, bank_size=LOROM_BANK)
    table = b"".join(
        ENTRY.pack(offset, len(run) // 16, last_tile_columns(font, codes))
        for offset, run, codes in zip(offsets, runs, names, strict=True)
    )
    return blob, table


def fixed_records(data: bytes, size: int, skip: int = 0) -> list[bytes]:
    """The `size`-byte records of `data`, each without its first `skip` bytes (an icon, a symbol)."""
    return [data[i + skip : i + size] for i in range(0, len(data), size)]


def bake_file(
    font_file: Path, names_file: Path, record_size: int, blob_file: Path, table_file: Path, skip: int = 0
) -> None:
    font = VwfFont.decode(font_file.read_bytes())
    blob, table = bake(font, fixed_records(names_file.read_bytes(), record_size, skip))
    blob_file.write_bytes(blob)
    table_file.write_bytes(table)


def pointed_records(strings: bytes, pointers: bytes, skip: int = 0) -> list[bytes]:
    """The NUL-terminated strings `pointers` (16-bit offsets) point at in `strings`, without their first `skip` bytes."""
    offsets = [int.from_bytes(pointers[i : i + 2], "little") for i in range(0, len(pointers), 2)]
    return [strings[offset : strings.index(0, offset)][skip:] for offset in offsets]


def bake_pointed_file(
    font_file: Path, strings_file: Path, pointers_file: Path, blob_file: Path, table_file: Path, skip: int = 0
) -> None:
    font = VwfFont.decode(font_file.read_bytes())
    blob, table = bake(font, pointed_records(strings_file.read_bytes(), pointers_file.read_bytes(), skip))
    blob_file.write_bytes(blob)
    table_file.write_bytes(table)
