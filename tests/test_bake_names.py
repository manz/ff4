"""utils/bake_names.py: baked name tiles, the blob's bank rule and its table."""

from pathlib import Path

import pytest
from katsuji import VwfFont

from utils.bake_names import ENTRY, LOROM_BANK, bake, fixed_records, last_tile_columns, name_tiles, pointed_records

FONT = Path("build/gen/menu_font.dat")
MAGIC = Path("build/gen/magic.dat")
MAGIC_POINTERS = Path("build/gen/magic.ptr")


@pytest.fixture(scope="module")
def font() -> VwfFont:
    if not FONT.exists():
        pytest.skip("menu_font.dat not built")
    return VwfFont.decode(FONT.read_bytes())


def entries(table: bytes) -> list[tuple[int, int, int]]:
    return [ENTRY.unpack_from(table, i) for i in range(0, len(table), ENTRY.size)]


def test_an_empty_name_takes_no_tile(font: VwfFont) -> None:
    assert name_tiles(font, b"\xff" * 9) == b""


def test_trailing_spaces_take_no_tile(font: VwfFont) -> None:
    soin = bytes(pointed_records(MAGIC.read_bytes(), MAGIC_POINTERS.read_bytes())[0x0E])
    assert name_tiles(font, soin) == name_tiles(font, soin.rstrip(b"\xff"))


def test_tiles_are_two_bpp_on_paper_colour_one(font: VwfFont) -> None:
    tiles = name_tiles(font, bytes(pointed_records(MAGIC.read_bytes(), MAGIC_POINTERS.read_bytes())[0x0E]))
    plane0 = tiles[0::2]
    assert len(tiles) % 16 == 0
    assert set(plane0) == {0xFF}  # every pixel is colour 1 (paper) or 3 (ink)


def test_each_entry_points_at_its_name(font: VwfFont) -> None:
    names = pointed_records(MAGIC.read_bytes(), MAGIC_POINTERS.read_bytes())
    blob, table = bake(font, names)
    for codes, (offset, tiles, _columns) in zip(names, entries(table), strict=True):
        assert blob[offset : offset + tiles * 16] == name_tiles(font, codes)


def test_no_name_straddles_a_lorom_bank(font: VwfFont) -> None:
    long_name = bytes(range(0x42, 0x4A))
    blob, table = bake(font, [long_name] * 600)
    for offset, tiles, _columns in entries(table):
        assert offset // LOROM_BANK == (offset + tiles * 16 - 1) // LOROM_BANK


def test_records_drop_their_leading_symbol() -> None:
    assert fixed_records(bytes(range(34)), 17, skip=1) == [bytes(range(1, 17)), bytes(range(18, 34))]


def test_pointed_records_stop_at_the_nul():
    strings = b"\x29AB\x00\xff\x00"
    assert pointed_records(strings, b"\x00\x00\x04\x00", skip=1) == [b"AB", b""]


def test_the_last_tile_columns_complete_the_width(font: VwfFont) -> None:
    """Tiles before the last are full: the last one holds the rest of the name's advance, 1 to 8 columns."""
    names = pointed_records(MAGIC.read_bytes(), MAGIC_POINTERS.read_bytes())
    _blob, table = bake(font, names)
    for codes, (_offset, tiles, columns) in zip(names, entries(table), strict=True):
        assert columns == last_tile_columns(font, codes)
        assert (tiles == 0) == (columns == 0)
        assert 0 <= columns <= 8
