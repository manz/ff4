"""Battle inventory VWF golden.

Pins the battle item list as rendered by the VWF: names, icons, the
quantity column and greyed-out entries, at the top of the list and one
page down (rows rendered at the scroll edge). Only the menu panel is
compared: the battlefield runs on the ATB, whose pace moves with how
much work the battle loop does.

The list is built at battle start (`InitInventoryTextBuf`, $02:9E9C),
so a savestate saved mid-battle would show an older build's rows: the
fixture starts a fresh encounter from the world map instead.
"""
from __future__ import annotations

from pathlib import Path

import pytest
from kintsuki import Button

from _ff4kintsuki import CECIL_SLOT, CMD_ITEM, CMD_MAGIC_WHITE, choose_command, walk_into_battle, wait_for_turn, BATTLE_MENU_PANEL, assert_screenshot_matches_golden, kss_path, load_emu_from_kss, tap

KSS = kss_path("ff4-before-field-inventory.kss")
GOLDENS = Path(__file__).parent / "goldens" / "battle_inventory"
PAGE = 5
VISIBLE_ROWS = 5
BATTLE_ITEMS = 0x7E321A  # 4-byte slots: flags (bit 7 = disabled), id, qty, -
FIRST_ROW = 34  # BG3 tilemap row of the top item's name
ITEM_TILES = range(0x1C0, 0x200)


@pytest.fixture(scope="module")
def items_emu():
    e = load_emu_from_kss(KSS, settle_frames=60)  # in the field
    walk_into_battle(e)
    wait_for_turn(e, CECIL_SLOT)
    choose_command(e, CMD_ITEM)
    e.run_frames(30)
    yield e
    e.close()


def test_top_of_list(items_emu):
    assert_screenshot_matches_golden(items_emu, GOLDENS / "top.png", region=BATTLE_MENU_PANEL)


def test_one_page_down(items_emu):
    for _ in range(PAGE):
        tap(items_emu, Button.DOWN, gap=12)
    items_emu.run_frames(60)  # let the scroll animation settle
    assert_screenshot_matches_golden(items_emu, GOLDENS / "page_down.png", region=BATTLE_MENU_PANEL)


def _row_palettes(emu, row: int) -> set[int]:
    base = (emu.get_ppu_state().bg3sc >> 2) << 10
    raw = bytes(emu.vram_read_range((base + row * 32) * 2, 64))
    cells = [raw[i] | raw[i + 1] << 8 for i in range(0, 64, 2)]
    return {(c >> 10) & 7 for c in cells if (c & 0x3FF) in ITEM_TILES}


def test_disabled_items_are_grey_at_first_open():
    """The turn's usability update lands after the rows were rendered."""
    e = load_emu_from_kss(KSS, settle_frames=60)  # in the field
    try:
        walk_into_battle(e)
        wait_for_turn(e, CECIL_SLOT)
        choose_command(e, CMD_ITEM)
        e.run_frames(30)
        expected = [{1 if e.read(BATTLE_ITEMS + 4 * i) & 0x80 else 0} for i in range(VISIBLE_ROWS)]
        assert [_row_palettes(e, FIRST_ROW + 2 * i) for i in range(VISIBLE_ROWS)] == expected
    finally:
        e.close()
