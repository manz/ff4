"""The map title (the location window on entering a map) is drawn in the small VWF, the way dialogues are.

The setup (ingame/map_title_vwf.s) renders the title into BG3 tiles $101 on, the dialogue VWF's region, and fills
the glyph row with their low bytes, centred, around blank tile $100 (TfrMapTitle writes that row with tile bit 8); the
dakuten row is the font's space. The field menu's BG2 tilemap covers those tiles; its exit draws the title again.
"""
from __future__ import annotations

import pytest

from kintsuki import Button

from _ff4kintsuki import kss_path, load_emu_from_kss, tap

STUB = 0x1E00  # bank-0 WRAM: rep #$10, sep #$20, D = $0600 and DB = 0 as in the field, jsr the setup, rtl
STUB_CODE = bytes([0xC2, 0x10, 0xE2, 0x20, 0xF4, 0x00, 0x06, 0x2B, 0xF4, 0x00, 0x00, 0xAB, 0xAB, 0x20, 0xD9, 0xB8, 0x6B])
TITLE_INDEX = 0x7E0FE6
GLYPH_ROW = 0x7E0774
DAKUTEN_ROW = GLYPH_ROW + 18
CELLS = 18
FIRST_SLOT = 0x01  # tile $101
TITLE_TILES_VRAM = 0x6808 * 2  # byte address of tile $101 (BG3 tiles at word $6000)
BLANK_SLOT = 0x00  # tile $100


@pytest.fixture
def titled():
    e = load_emu_from_kss(kss_path("ff4-before-field-inventory.kss"), settle_frames=30)
    for i, b in enumerate(STUB_CODE):
        e.write(0x7E0000 + STUB + i, b)
    e.write(TITLE_INDEX, 3)
    e.write(0x7E06C5, 0)  # no title suppression
    e.write(0x7E06D1, 0)
    e.call(STUB)
    yield e
    e.close()


def _row(emu, address: int) -> list[int]:
    return [emu.read(address + i) for i in range(CELLS)]


def test_the_glyph_row_holds_consecutive_slots_centred(titled) -> None:
    row = _row(titled, GLYPH_ROW)
    used = [i for i, tile in enumerate(row) if tile != BLANK_SLOT]
    assert used, "no title slot in the glyph row"
    assert [row[i] for i in used] == list(range(FIRST_SLOT, FIRST_SLOT + len(used)))
    assert abs(used[0] - (CELLS - 1 - used[-1])) <= 1


def test_the_dakuten_row_is_blank(titled) -> None:
    assert _row(titled, DAKUTEN_ROW) == [0xFF] * CELLS


def test_bg3_reads_the_dialogue_tiles(titled) -> None:
    assert titled.get_ppu_state().bg34nba & 0x0F == 0x06  # BG3 tiles at $6000, as vwfinit sets them


def test_the_title_survives_the_field_menu() -> None:
    e = load_emu_from_kss(kss_path("ff4-with-town-name.kss"), settle_frames=10)
    try:
        before = bytes(e.vram_read_range(0))[TITLE_TILES_VRAM:TITLE_TILES_VRAM + 0x100]
        tap(e, Button.X, gap=90)  # the field menu
        tap(e, Button.B, gap=90)  # back to the field, title window still open
        after = bytes(e.vram_read_range(0))[TITLE_TILES_VRAM:TITLE_TILES_VRAM + 0x100]
        assert after == before
        assert e.get_ppu_state().bg34nba & 0x0F == 0x06
    finally:
        e.close()
