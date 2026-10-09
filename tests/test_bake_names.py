"""utils/bake_names.py: baked name tiles, the blob's bank rule and its table."""

from pathlib import Path

import pytest
from katsuji import VwfFont

from utils.bake_names import ENTRY, LOROM_BANK, bake, fixed_records, name_tiles

FONT = Path("build/gen/menu_font.dat")
MAGIC = Path("build/gen/magic.dat")


@pytest.fixture(scope="module")
def font() -> VwfFont:
    if not FONT.exists():
        pytest.skip("menu_font.dat not built")
    return VwfFont.decode(FONT.read_bytes())


def entries(table: bytes) -> list[tuple[int, int]]:
    return [ENTRY.unpack_from(table, i) for i in range(0, len(table), ENTRY.size)]


def test_an_empty_name_takes_no_tile(font: VwfFont) -> None:
    assert name_tiles(font, b"\xff" * 9) == b""


def test_trailing_spaces_take_no_tile(font: VwfFont) -> None:
    soin = bytes(fixed_records(MAGIC.read_bytes(), 9)[0x0E])
    assert name_tiles(font, soin) == name_tiles(font, soin.rstrip(b"\xff"))


def test_tiles_are_two_bpp_on_paper_colour_one(font: VwfFont) -> None:
    tiles = name_tiles(font, bytes(fixed_records(MAGIC.read_bytes(), 9)[0x0E]))
    plane0 = tiles[0::2]
    assert len(tiles) % 16 == 0
    assert set(plane0) == {0xFF}  # every pixel is colour 1 (paper) or 3 (ink)


def test_each_entry_points_at_its_name(font: VwfFont) -> None:
    names = fixed_records(MAGIC.read_bytes(), 9)
    blob, table = bake(font, names)
    for codes, (offset, tiles) in zip(names, entries(table), strict=True):
        assert blob[offset : offset + tiles * 16] == name_tiles(font, codes)


def test_no_name_straddles_a_lorom_bank(font: VwfFont) -> None:
    long_name = bytes(range(0x42, 0x4A))
    blob, table = bake(font, [long_name] * 600)
    for offset, tiles in entries(table):
        assert offset // LOROM_BANK == (offset + tiles * 16 - 1) // LOROM_BANK


def test_records_drop_their_leading_symbol() -> None:
    assert fixed_records(bytes(range(34)), 17, skip=1) == [bytes(range(1, 17)), bytes(range(18, 34))]
