"""
Names baked into small-VWF tiles at build time: the game DMAs a name's tiles from ROM instead of rendering it.

Each name is set with katsuji in the menu font (`menu_font.dat`, the font the runtime renderer reads) and encoded
2bpp in the menus' colours: ink 3 on paper 1. Every pair a name puts side by side is kerned on the glyphs themselves
(the font's atlas, `auto_kern`), not only the font's few candidate pairs: a baked name never goes through the runtime
renderer, so it can be set as tight as its letters allow (the font's own pairs still win). The blob packs every name's tiles back to back, no name across a 32 KB LoROM bank (a DMA source
cannot wrap one); the table gives each name its offset in the blob, its tile count and how many pixel columns its last tile uses, so a
renderer can carry on drawing inside that tile.
"""

from __future__ import annotations

import dataclasses
import struct
from collections.abc import Mapping, Sequence
from pathlib import Path

from katsuji import VwfFont, colourize, encode_tiles, render
from katsuji.atlas import Atlas
from katsuji.config import FontConfig
from katsuji.kerning import find_kerning
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


@dataclasses.dataclass(frozen=True)
class Glyphs:
    """A font's glyph sheet and its width overrides (katsuji.toml `widths`): what `auto_kern` measures on."""

    atlas: Atlas
    widths: Mapping[int, int]

    @classmethod
    def of(cls, font: FontConfig) -> Glyphs:
        return cls(Atlas.open(font.png, font.cell_width, font.cell_height, font.grid), font.widths)


def auto_kern(font: VwfFont, glyphs: Glyphs, names: Sequence[bytes]) -> VwfFont:
    """`font` with every pair the `names` put side by side kerned on the glyphs, the font's own pairs kept. A glyph
    with a width override keeps its spacing: its declared width is not on the sheet (the space is blank, so measured
    on the glyphs its gap was kerned away: "Ver desabysses")."""
    codes = [codes.rstrip(bytes([SPACE])) for codes in names]
    pairs = {pair for name in codes for pair in zip(name, name[1:]) if not set(pair) & glyphs.widths.keys()}
    return dataclasses.replace(font, kerning={**find_kerning(glyphs.atlas, pairs), **font.kerning})


def fixed_records(data: bytes, size: int, skip: int = 0) -> list[bytes]:
    """The `size`-byte records of `data`, each without its first `skip` bytes (an icon, a symbol)."""
    return [data[i + skip : i + size] for i in range(0, len(data), size)]


def bake_file(
    font_file: Path, names_file: Path, record_size: int, blob_file: Path, table_file: Path, skip: int = 0,
    glyphs: Glyphs | None = None,
) -> None:
    """`glyphs`: the font's glyph sheet, to kern every pair the names contain (see `auto_kern`)."""
    font = VwfFont.decode(font_file.read_bytes())
    names = fixed_records(names_file.read_bytes(), record_size, skip)
    blob, table = bake(auto_kern(font, glyphs, names) if glyphs else font, names)
    blob_file.write_bytes(blob)
    table_file.write_bytes(table)


def pointed_records(strings: bytes, pointers: bytes, skip: int = 0) -> list[bytes]:
    """The NUL-terminated strings `pointers` (16-bit offsets) point at in `strings`, without their first `skip` bytes."""
    offsets = [int.from_bytes(pointers[i : i + 2], "little") for i in range(0, len(pointers), 2)]
    return [strings[offset : strings.index(0, offset)][skip:] for offset in offsets]


def bake_pointed_file(
    font_file: Path, strings_file: Path, pointers_file: Path, blob_file: Path, table_file: Path, skip: int = 0,
    glyphs: Glyphs | None = None,
) -> None:
    """`glyphs`: the font's glyph sheet, to kern every pair the names contain (see `auto_kern`)."""
    font = VwfFont.decode(font_file.read_bytes())
    names = pointed_records(strings_file.read_bytes(), pointers_file.read_bytes(), skip)
    blob, table = bake(auto_kern(font, glyphs, names) if glyphs else font, names)
    blob_file.write_bytes(blob)
    table_file.write_bytes(table)
