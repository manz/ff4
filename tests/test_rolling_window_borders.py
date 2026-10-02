"""Side borders on rolling-list windows.

The rolling lists re-blank a slot's two tilemap rows before drawing an
item into it. Blanking the full 32-cell row also wiped the window's side
borders, so the key-item picker and the shop sell list lost their left
and right edges on every item row.
"""
from __future__ import annotations

import pytest
from kintsuki import Button

from _ff4kintsuki import kss_path, load_emu_from_kss, tap

ROW_CELLS = 32

PICKER_VRAM_WORD = 0x2C00
PICKER_ITEM_ROWS = range(8)
PICKER_BORDERS = {2: 0x19, 29: 0x1A}

SELL_BUFFER = 0x7ED600
SELL_ITEM_ROWS = range(2, 18)
SELL_BORDERS = {0: 0xFA, 31: 0xFB}


@pytest.fixture
def picker_emu():
    e = load_emu_from_kss(kss_path("ff4-key-inventory.kss"))
    tap(e, Button.A, gap=30)
    tap(e, Button.A, gap=30)
    e.run_frames(60)
    yield e
    e.close()


@pytest.fixture
def sell_emu():
    e = load_emu_from_kss(kss_path("ff4-buggy-item-shop-press-a.kss"))
    tap(e, Button.RIGHT, gap=40)
    tap(e, Button.A, gap=40)
    yield e
    e.close()


def _picker_tile(emu, row: int, col: int) -> int:
    word = PICKER_VRAM_WORD + row * ROW_CELLS + col
    return bytes(emu.vram_read_range(word * 2, 1))[0]


def _sell_tile(emu, row: int, col: int) -> int:
    return emu.read(SELL_BUFFER + (row * ROW_CELLS + col) * 2)


def test_picker_item_rows_keep_side_borders(picker_emu):
    tiles = {(r, c): _picker_tile(picker_emu, r, c) for r in PICKER_ITEM_ROWS for c in PICKER_BORDERS}
    assert tiles == {(r, c): t for r in PICKER_ITEM_ROWS for c, t in PICKER_BORDERS.items()}


def test_sell_item_rows_keep_side_borders(sell_emu):
    tiles = {(r, c): _sell_tile(sell_emu, r, c) for r in SELL_ITEM_ROWS for c in SELL_BORDERS}
    assert tiles == {(r, c): t for r in SELL_ITEM_ROWS for c, t in SELL_BORDERS.items()}
