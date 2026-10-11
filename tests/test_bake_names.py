"""utils/bake_names.py: baked name tiles, the blob's bank rule and its table."""

from pathlib import Path

import pytest
from katsuji import VwfFont

from utils.bake_names import (
    ENTRY,
    LOROM_BANK,
    bake,
    fixed_records,
    last_tile_columns,
    name_tiles,
    pointed_records,
)

FONT = Path("build/gen/menu_font.dat")
MAGIC = Path("build/gen/magic.dat")
MAGIC_POINTERS = Path("build/gen/magic.ptr")


@pytest.fixture(scope="module")
def glyphs():
    from katsuji import config

    from utils.bake_names import Glyphs

    return Glyphs.of(config.load(Path("katsuji.toml")).fonts["menu"])


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


def test_auto_kerning_keeps_the_fonts_own_pairs(font: VwfFont, glyphs) -> None:
    from utils.bake_names import auto_kern

    names = pointed_records(MAGIC.read_bytes(), MAGIC_POINTERS.read_bytes())
    kerned = auto_kern(font, glyphs, names)
    assert all(kerned.kerning[pair] == value for pair, value in font.kerning.items())


def test_auto_kerning_never_widens_a_name(font: VwfFont, glyphs) -> None:
    from katsuji import render

    from utils.bake_names import auto_kern

    names = [n.rstrip(b"\xff") for n in pointed_records(MAGIC.read_bytes(), MAGIC_POINTERS.read_bytes()) if n.strip(b"\xff")]
    kerned = auto_kern(font, glyphs, names)
    widths = [(render(kerned, list(n)).shape[1], render(font, list(n)).shape[1]) for n in names]
    assert all(tight <= plain for tight, plain in widths) and any(tight < plain for tight, plain in widths)


MONSTERS = Path("build/gen/monsters_long.dat")
MONSTER_POINTERS = Path("build/gen/monsters_long.ptr")
ROM = Path("build/ff4.sfc")
FORMATIONS = 0x0E8000  # 512 * 8 bytes: monster types at +1..+3, their counts 2 bits each at +4
MONSTER_LINE_PX = 72  # the battle monster window clips a line past 9 tiles
WIDEST_COUNT = bytes([0x10, 0x89])  # thin space, "9": what the window appends to a group


def _grouped_monsters() -> set[int]:
    """Monster types some formation shows two or more of: their window line carries a count."""
    rom = ROM.read_bytes()
    start = (FORMATIONS >> 16) * 0x8000 + (FORMATIONS & 0x7FFF)
    grouped = set()
    for at in range(start, start + 512 * 8, 8):
        types, counts = rom[at + 1 : at + 4], rom[at + 4]
        grouped |= {t for i, t in enumerate(types) if t != 0xFF and (counts >> (6 - 2 * i)) & 3 >= 2}
    return grouped


def test_every_monster_name_fits_its_line_with_a_count(font: VwfFont, glyphs) -> None:
    from katsuji import render

    from utils.bake_names import SPACE, auto_kern

    names = [n.rstrip(bytes([SPACE])) for n in pointed_records(MONSTERS.read_bytes(), MONSTER_POINTERS.read_bytes())]
    kerned = auto_kern(font, glyphs, names)
    count = render(font, list(WIDEST_COUNT)).shape[1]
    grouped = _grouped_monsters()
    width = {i: render(kerned, list(n)).shape[1] for i, n in enumerate(names) if n}
    too_wide = [i for i, w in width.items() if w + (count if i in grouped else 0) > MONSTER_LINE_PX]
    assert too_wide == []


def test_auto_kerning_keeps_the_spaces(font: VwfFont, glyphs) -> None:
    from utils.bake_names import SPACE, auto_kern

    names = pointed_records(MONSTERS.read_bytes(), MONSTER_POINTERS.read_bytes())
    kerned = auto_kern(font, glyphs, names)
    assert not [pair for pair in kerned.kerning if SPACE in pair and pair not in font.kerning]
