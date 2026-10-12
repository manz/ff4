"""The target window's status column (battle/status_names.s): baked status names in the rows' kana-slot windows.

Vanilla cut a name to 8 letters of the 8x8 font ("Confusio"); each row now shows its name's baked tiles from a
window of its own (tiles $90-$AD), uploaded by the NMI.
"""
from __future__ import annotations

from pathlib import Path

import pytest
from _ff4kintsuki import (
    BATTLE_MENU_PANEL,
    CMD_ITEM,
    assert_screenshot_matches_golden,
    choose_command,
    fresh_late_battle,
    tap,
)
from kintsuki import Button

GOLDENS = Path(__file__).parent / "goldens" / "battle_status_names"
ACTING = 0x7E1822
CURSOR_TYPE = 0x7E1823  # 5 the inventory list, $0C a party target
STATUS_BYTES = 0x7E2003  # per slot (0x80 apart): 4 status bytes
# per slot: (byte, bit): Paralysie, Confusion, Poison, Lévite, Silence
STATUSES = ((1, 0x20), (1, 0x08), (0, 0x01), (1, 0x40), (0, 0x04))
STATUS_TILEMAP = 0x7ED710  # a row a $80: the dakuten row, then the glyph row
FIRST_TILE, TILES = 0x90, 6
BG3_CHR = 0xA000
BLANK_TILE = bytes([0xFF, 0x00] * 8)


@pytest.fixture
def target_window():
    emu = fresh_late_battle()
    try:
        actor = emu.read(ACTING)
        for slot, (byte, bit) in enumerate(STATUSES):
            if slot != actor:
                address = STATUS_BYTES + slot * 0x80 + byte
                emu.write(address, emu.read(address) | bit)
        emu.run_frames(4)
        choose_command(emu, CMD_ITEM)
        for _ in range(60):
            if emu.read(CURSOR_TYPE) == 5:
                break
            emu.run_frames(2)
        emu.run_frames(10)
        tap(emu, Button.DOWN, gap=16)  # Ether
        tap(emu, Button.A, gap=30)
        tap(emu, Button.A, gap=40)
        assert emu.read(CURSOR_TYPE) == 0x0C
        yield emu
    finally:
        emu.close()


def test_the_status_column_golden(target_window) -> None:
    assert_screenshot_matches_golden(target_window, GOLDENS / "statuses.png", region=BATTLE_MENU_PANEL)


def test_a_row_points_at_its_window(target_window) -> None:
    for row in range(5):
        cell = STATUS_TILEMAP + row * 0x80 + 0x40
        first = target_window.read(cell)
        assert first == 0xFF or FIRST_TILE + row * TILES <= first < FIRST_TILE + (row + 1) * TILES


def test_the_windows_hold_the_names_tiles(target_window) -> None:
    tiles = bytes(target_window.vram_read_range(BG3_CHR + FIRST_TILE * 16, TILES * 16 * 5))
    assert any(tiles[i : i + 16] != BLANK_TILE for i in range(0, len(tiles), 16))
