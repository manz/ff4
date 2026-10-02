"""Active-character name highlight in the battle status window.

`set_active_char_palette` stamps palette 2 on the acting character's
name row and palette 0 on every other row, matching vanilla
`UpdateCharNames`: rows are display-ordered and compacted (an absent
char emits no row), and nothing is lit while the battle menu ($D7) is
closed. ff4.kss is a 4-char party (Rydia, Cecil, Rosa, Edward) with
Cecil's command menu open, so slot 1 is absent and Cecil (slot 0)
sits on row 1.
"""
from __future__ import annotations

import pytest
from kintsuki import Button

from _ff4kintsuki import kss_path, load_emu_from_kss, tap

KSS = kss_path("ff4.kss")

ACTIVE_SLOT = 0x7E1822
MENU_OPEN = 0x7E00D7
MAIN_VIEW = 0x7EBEA6
MAIN_VIEW_VRAM_WORD = 0x7020
NAME_LINE = 0xBEC2 - 0xBEA6 + 0x40
ROW_STRIDE = 0x80
NAME_TILES = 6
HIGHLIGHT = 2


def _palette(hi: int) -> int:
    return (hi >> 2) & 7


def _row_palettes(read, base: int) -> list[set[int]]:
    """Palette set over the six name tiles of each of the five rows."""
    return [
        {_palette(read(base + NAME_LINE + r * ROW_STRIDE + 1 + 2 * i)) for i in range(NAME_TILES)}
        for r in range(5)
    ]


def _wram_rows(emu) -> list[set[int]]:
    return _row_palettes(emu.read, MAIN_VIEW)


def _vram_rows(emu) -> list[set[int]]:
    vram = bytes(emu.vram_read_range(MAIN_VIEW_VRAM_WORD * 2, 0x400))
    return _row_palettes(vram.__getitem__, 0)


def _expected(row: int | None) -> list[set[int]]:
    return [{HIGHLIGHT} if r == row else {0} for r in range(5)]


@pytest.fixture
def emu():
    e = load_emu_from_kss(KSS, settle_frames=10)
    yield e
    e.close()


def _run_until(emu, predicate, limit: int = 600) -> None:
    for _ in range(limit):
        if predicate():
            return
        emu.run_frames(1)
    pytest.fail("condition never reached")


def test_open_menu_lights_whole_active_row(emu):
    assert _wram_rows(emu) == _expected(1)


def test_highlight_reaches_vram(emu):
    assert _vram_rows(emu) == _expected(1)


def test_closed_menu_clears_highlight(emu):
    tap(emu, Button.A)
    tap(emu, Button.A)
    _run_until(emu, lambda: emu.read(MENU_OPEN) == 0 and _wram_rows(emu) == _expected(None))
    assert _vram_rows(emu) == _expected(None)


def test_next_turn_lights_compacted_row(emu):
    """Edward is slot 2, display index 4: with slot 1 absent he lands on row 3."""
    tap(emu, Button.A)
    tap(emu, Button.A)
    _run_until(emu, lambda: emu.read(ACTIVE_SLOT) == 2 and emu.read(MENU_OPEN) != 0)
    _run_until(emu, lambda: _wram_rows(emu) == _expected(3), limit=60)
    assert _vram_rows(emu) == _expected(3)
