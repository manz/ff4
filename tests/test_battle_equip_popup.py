"""The battle equip popup (UP at the top of the item list) shows its hand labels and item names in the VWF.

Vanilla draws them in the 8x8 font, "Bouclier dragon" cut to "Dragon". The popup renders them into the command
list's tiles ($190-$1BF: the command window is hidden under the inventory while the popup shows), and the command
list renders its own glyphs again once the popup closes.
"""
from __future__ import annotations

from pathlib import Path

import pytest
from _ff4kintsuki import BATTLE_MENU_PANEL, assert_screenshot_matches_golden, choose_command, fresh_late_battle, tap
from kintsuki import Button

GOLDENS = Path(__file__).parent / "goldens" / "battle_equip"
ITEM = 0x01
CURSOR_TYPE = 0x7E1823  # 1 command list, 5 inventory list
WINDOWS_OPEN = 0x7E004A  # bit 3: the equip popup
EQUIP_TEXT = 0x16FEC1  # per character: EquipBuf, 60 bytes a hand (two rows of 15 cells, the glyphs on the second)
HAND_LABEL_TEXT = 0x16FF25  # per character: the label cells, 10 a hand
COMMAND_TILES = (0x190, 0x1C0)
BG3_CHR = 0xA000  # VRAM byte address of BG3 tile 0
MENU_OPEN = 0x7E00D7


def _wait(emu, done, frames: int = 120) -> bool:
    for _ in range(frames // 2):
        if done():
            return True
        emu.run_frames(2)
    return done()


def _open_popup(emu) -> None:
    choose_command(emu, ITEM)
    assert _wait(emu, lambda: emu.read(CURSOR_TYPE) == 5)
    for _ in range(4):
        if emu.read(WINDOWS_OPEN) & 0x08:
            break
        tap(emu, Button.UP, gap=12)
    assert emu.read(WINDOWS_OPEN) & 0x08
    emu.run_frames(20)


def _cells(emu, address: int, count: int) -> list[int]:
    return [emu.read(address + 2 * i) | emu.read(address + 2 * i + 1) << 8 for i in range(count)]


def _tiles(cells: list[int]) -> set[int]:
    """BG3 tile numbers of the non-blank cells (attribute bit 0 is the tile number's bit 8)."""
    return {(c & 0xFF) | (c & 0x100) for c in cells if c & 0xFF != 0xFF}


def _command_chr(emu) -> bytes:
    lo, hi = COMMAND_TILES
    return bytes(emu.vram_read_range(BG3_CHR + lo * 16, (hi - lo) * 16))


@pytest.fixture
def popup():
    emu = fresh_late_battle()
    try:
        _open_popup(emu)
        yield emu
    finally:
        emu.close()


def test_the_popup_golden(popup) -> None:
    assert_screenshot_matches_golden(popup, GOLDENS / "popup.png", region=BATTLE_MENU_PANEL)


@pytest.mark.parametrize("hand", [0, 1])
def test_the_item_name_is_drawn_in_the_command_tiles(popup, hand: int) -> None:
    rows = popup.read(EQUIP_TEXT) | popup.read(EQUIP_TEXT + 1) << 8  # Cain's
    glyphs = _tiles(_cells(popup, 0x7E0000 + rows + hand * 60 + 30, 15))
    vwf = {t for t in glyphs if t & 0x100}
    assert vwf and all(COMMAND_TILES[0] <= t < COMMAND_TILES[1] for t in vwf)


@pytest.mark.parametrize("hand", [0, 1])
def test_the_hand_label_is_drawn_in_the_command_tiles(popup, hand: int) -> None:
    cells = popup.read(HAND_LABEL_TEXT) | popup.read(HAND_LABEL_TEXT + 1) << 8
    glyphs = _tiles(_cells(popup, 0x7E0000 + cells + hand * 20, 10))
    assert glyphs and all(COMMAND_TILES[0] <= t < COMMAND_TILES[1] for t in glyphs)


def test_the_command_list_gets_its_tiles_back() -> None:
    emu = fresh_late_battle()
    try:
        before = _command_chr(emu)
        _open_popup(emu)
        assert _command_chr(emu) != before
        tap(emu, Button.B, gap=30)  # back to the item list
        tap(emu, Button.B, gap=40)  # back to the command list
        assert _wait(emu, lambda: emu.read(CURSOR_TYPE) == 1)
        emu.run_frames(10)
        assert _command_chr(emu) == before
    finally:
        emu.close()


HAND = 0x7E005F  # the popup cursor's hand
PICKED = 0x7EEF94  # non-zero once A picked a hand (vanilla's swap: cursor 2 stays on it)
TARGET_SELECT = (4, 7, 0x0C, 0x0F)


def test_a_picks_the_hand_instead_of_using_it(popup) -> None:
    """Vanilla's item menu reads $EF9A on A: non-zero uses the hand's item. The redraw gates' dirty byte sat there."""
    tap(popup, Button.A, gap=20)
    assert (popup.read(PICKED), popup.read(CURSOR_TYPE)) == (1, 0x0B)


def test_up_and_down_move_between_the_hands(popup) -> None:
    assert popup.read(HAND) == 0
    tap(popup, Button.DOWN, gap=16)
    assert popup.read(HAND) == 1
    tap(popup, Button.RIGHT, gap=16)
    assert popup.read(HAND) == 1
    tap(popup, Button.UP, gap=16)
    assert popup.read(HAND) == 0


def test_down_from_the_lower_hand_goes_back_to_the_list(popup) -> None:
    tap(popup, Button.DOWN, gap=16)
    tap(popup, Button.DOWN, gap=30)
    assert (popup.read(CURSOR_TYPE), popup.read(WINDOWS_OPEN) & 0x08, popup.read(HAND)) == (5, 0, 0)
