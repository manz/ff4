"""The battle inventory pins its window's bottom border only while the item list has the cursor.

BG3's scroll HDMA is shared by every battle window. With the item list up, ff4 scrolls the two rows below the list
body ($7E:8068-$8081, scanlines 213-219) to the window's border instead of vanilla's black; that pinning ran on the
inventory flag alone, which stays set through the item's target select, and an "idle" branch forced the command
menu's values every other frame: the target window showed the inventory's footer and, with the menus closed, the
bottom rows of the command menu showed. Elsewhere the entries are vanilla's own (it writes them on every window
change).
"""
from __future__ import annotations

from _ff4kintsuki import command_row, choose_command, fresh_late_battle, tap
from kintsuki import Button

ITEM = 0x01
CURSOR_TYPE = 0x7E1823  # 1 command list, 5 inventory list, 4/7/$0C/$0F target select
FOOTER = 0x7E8064  # 8 HDMA entries (4 bytes each), V scroll at +0
VANILLA_COMMAND_MENU = [0x1F7] * 4 + [0x026, 0x025, 0x024, 0x023]
VANILLA_ITEM_TARGET = [0x2DF] * 4 + [0x2E3] + [0x2E7] * 3
VANILLA_MENUS_CLOSED = [0x18F] * 4 + [0x026, 0x025, 0x024, 0x023]
PINNED_LIST = [0x187] + [0x193] * 3 + [0x19B] * 4
MENU_OPEN = 0x7E00D7  # non-zero while a character's command menu is up
WINDOW_SWAPPING = 0x7E1820  # menu_hdma_pending: 1 while a window change swaps its rows in, one a frame
ROWS_LEFT = 0x7E1843  # menu_hdma_rows


def _footer(emu) -> list[int]:
    return [emu.read(FOOTER + i * 4) | emu.read(FOOTER + i * 4 + 1) << 8 for i in range(8)]


def _wait(emu, types: tuple[int, ...], frames: int = 120) -> int:
    for _ in range(frames // 2):
        if emu.read(CURSOR_TYPE) in types:
            break
        emu.run_frames(2)
    return emu.read(CURSOR_TYPE)


def test_the_footer_is_vanilla_with_the_command_menu() -> None:
    emu = fresh_late_battle()
    try:
        assert _footer(emu) == VANILLA_COMMAND_MENU
    finally:
        emu.close()


def test_the_list_pins_its_border_and_its_target_select_does_not() -> None:
    emu = fresh_late_battle()
    try:
        choose_command(emu, ITEM)
        assert _wait(emu, (5,)) == 5
        emu.run_frames(10)
        assert _footer(emu) == PINNED_LIST
        tap(emu, Button.DOWN, gap=8)  # Ether: targets an ally
        tap(emu, Button.A, gap=20)
        tap(emu, Button.A, gap=20)
        assert _wait(emu, (4, 7, 0x0C, 0x0F)) in (4, 7, 0x0C, 0x0F)
        emu.run_frames(10)
        assert _footer(emu) == VANILLA_ITEM_TARGET
        tap(emu, Button.A, hold=2, gap=0)  # use it: every menu closes while it plays
        for _ in range(300):
            emu.run_frames(1)
            if not emu.read(MENU_OPEN):
                break
        emu.run_frames(3)
        assert _footer(emu) == VANILLA_MENUS_CLOSED
    finally:
        emu.close()


def test_back_from_the_list_the_command_menu_gets_its_footer_back() -> None:
    """B from the item list: vanilla swaps the table's copies right after the unpin ($02:A943); the swap copy's values
    from before the list ($02BB) scrolled a stale party row into the bottom lines."""
    emu = fresh_late_battle()
    try:
        choose_command(emu, ITEM)
        assert _wait(emu, (5,)) == 5
        emu.run_frames(10)
        tap(emu, Button.B, gap=20)
        assert _wait(emu, (1,)) == 1
        emu.run_frames(10)
        assert _footer(emu) == VANILLA_COMMAND_MENU
    finally:
        emu.close()


def test_the_list_pins_its_border_once_its_window_is_up() -> None:
    """Opening the list, vanilla swaps the window's rows in one a frame: pinned before, the footer rows showed the
    party window's PV header and a stray border under a window not yet there."""
    emu = fresh_late_battle()
    try:
        for _ in range(command_row(emu, ITEM)):
            tap(emu, Button.DOWN, gap=20)
        tap(emu, Button.A, hold=2, gap=0)
        growing = 0
        for _ in range(60):
            emu.run_frames(1)
            if emu.read(WINDOW_SWAPPING) == 1 and emu.read(ROWS_LEFT) >= 2:
                growing += 1
                assert _footer(emu) == VANILLA_COMMAND_MENU
        assert growing > 0
        assert _footer(emu) == PINNED_LIST
    finally:
        emu.close()
