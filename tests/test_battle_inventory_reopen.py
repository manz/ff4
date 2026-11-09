"""Battle inventory reopened on a later turn.

Each Item command opens the list at the top: vanilla's open path ($02:BA07 -> $02:AAE4) zeroes the cursor, the list
scroll and our rolling top row / buffer position. The slots still hold the rows of the last scroll, so they must be
painted again, or the window shows the old page while the cursor picks from the top one.
"""
from __future__ import annotations

from collections.abc import Iterator

import pytest
from _ff4kintsuki import (
    BATTLE_MENU_OPEN,
    CECIL_SLOT,
    CMD_ITEM,
    choose_command,
    kss_path,
    load_emu_from_kss,
    tap,
    wait_for_turn,
    walk_into_battle,
)
from kintsuki import Button, Emu

KSS = kss_path("ff4-before-field-inventory.kss")
VISIBLE_ROWS = 5
FIRST_ROW = 34  # BG3 tilemap row of the top item's name
SCROLL_ROWS = 7  # past the first page: the list scrolls three rows
TILE_BYTES = 16  # 2bpp
MENU_WINDOWS_OPEN = 0x7E004A
INVENTORY_WINDOW = 0x04


def _row_glyphs(emu: Emu, row: int) -> bytes:
    """The pixels of a BG3 tilemap row, palette left out: greying depends on who acts."""
    ppu = emu.get_ppu_state()
    tilemap = (ppu.bg3sc >> 2) << 10
    chars = (ppu.bg34nba & 0x0F) << 12
    raw = bytes(emu.vram_read_range((tilemap + row * 32) * 2, 64))
    cells = [raw[i] | raw[i + 1] << 8 for i in range(0, 64, 2)]
    return b"".join(bytes(emu.vram_read_range((chars + (c & 0x3FF) * 8) * 2, TILE_BYTES)) for c in cells)


def _visible_rows(emu: Emu) -> list[bytes]:
    return [_row_glyphs(emu, FIRST_ROW + 2 * i) for i in range(VISIBLE_ROWS)]


def _open_items(emu: Emu) -> None:
    choose_command(emu, CMD_ITEM)
    emu.run_frames(30)
    assert emu.read(MENU_WINDOWS_OPEN) & INVENTORY_WINDOW, "the item list did not open"


def _wait_menu(emu: Emu, is_open: bool) -> None:
    for _ in range(300):
        if bool(emu.read(BATTLE_MENU_OPEN)) == is_open:
            return
        emu.run_frames(10)
    pytest.fail(f"command menu never {'opened' if is_open else 'closed'}")


def _next_turn(emu: Emu) -> None:
    """The item is in flight; the next command menu is someone else's turn."""
    _wait_menu(emu, is_open=False)
    _wait_menu(emu, is_open=True)
    emu.run_frames(40)


@pytest.fixture(scope="module")
def reopened() -> Iterator[tuple[list[bytes], list[bytes]]]:
    e = load_emu_from_kss(KSS, settle_frames=60)  # in the field
    try:
        walk_into_battle(e)
        wait_for_turn(e, CECIL_SLOT)
        _open_items(e)
        first_page = _visible_rows(e)
        for _ in range(SCROLL_ROWS):
            tap(e, Button.DOWN, gap=12)
        e.run_frames(40)
        tap(e, Button.A, gap=40)  # pick the item
        tap(e, Button.A, gap=60)  # the target picker
        tap(e, Button.A, gap=60)  # on its default target
        _next_turn(e)
        _open_items(e)
        yield first_page, _visible_rows(e)
    finally:
        e.close()


@pytest.mark.parametrize("row", range(VISIBLE_ROWS))
def test_reopened_list_shows_the_first_page(reopened, row):
    first_page, again = reopened
    assert again[row] == first_page[row]
