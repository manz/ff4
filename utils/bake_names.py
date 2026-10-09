"""
Names baked into small-VWF tiles at build time: the game DMAs a name's tiles from ROM instead of rendering it.

Each name is set with katsuji in the menu font (`menu_font.dat`, the font the runtime renderer reads, kerning
included, so a baked name is byte for byte what the renderer would draw) and encoded 2bpp in the menus' colours:
ink 3 on paper 1. The blob packs every name's tiles back to back, no name across a 32 KB LoROM bank (a DMA source
cannot wrap one); the table gives each name its offset in the blob and its tile count.
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
ENTRY = struct.Struct("<HBx")  # offset in the blob, tile count


def name_tiles(font: VwfFont, codes: bytes) -> bytes:
    """`codes` set in `font`, 2bpp tiles; no tile for an empty name."""
    codes = codes.rstrip(bytes([SPACE]))
    if not codes:
        return b""
    return encode_tiles(pad_to_tiles(colourize(render(font, list(codes)), INK, PAPER), fill=PAPER), 2)


def bake(font: VwfFont, names: Sequence[bytes]) -> tuple[bytes, bytes]:
    """The blob of every name's tiles and its table, one entry per name."""
    runs = [name_tiles(font, codes) for codes in names]
    blob, offsets = pack_runs(runs, bank_size=LOROM_BANK)
    table = b"".join(ENTRY.pack(offset, len(run) // 16) for offset, run in zip(offsets, runs, strict=True))
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
