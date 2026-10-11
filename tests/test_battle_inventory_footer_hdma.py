"""The battle inventory pins its window's bottom border only while the item list has the cursor.

BG3's scroll HDMA is shared by every battle window. With the item list up, ff4 scrolls the two rows below the list
body ($7E:8068-$8081, scanlines 213-219) to the window's border instead of vanilla's black; that pinning ran on the
inventory flag alone, which stays set through the item's target select, and an "idle" branch forced the command
menu's values every other frame: the target window showed the inventory's footer and, with the menus closed, the
bottom rows of the command menu showed. Elsewhere the entries are vanilla's own (it writes them on every window
change).
"""
from __future__ import annotations

from _ff4kintsuki import choose_command, kss_path, load_emu_from_kss, tap, wait_for_turn
from kintsuki import Button

ITEM = 0x01
CAIN_SLOT = 0  # ff4-late-field.kss: the first command menu up
FORMATION, BATTLE_PENDING = 0x7E1800, 0x7E0685  # the field starts the battle in $1800 once $0685 is set
CURSOR_TYPE = 0x7E1823  # 1 command list, 5 inventory list, 4/7/$0C/$0F target select
FOOTER = 0x7E8064  # 8 HDMA entries (4 bytes each), V scroll at +0
VANILLA_COMMAND_MENU = [0x1F7] * 4 + [0x026, 0x025, 0x024, 0x023]
VANILLA_ITEM_TARGET = [0x2DF] * 4 + [0x2E3] + [0x2E7] * 3
VANILLA_MENUS_CLOSED = [0x18F] * 4 + [0x026, 0x025, 0x024, 0x023]
PINNED_LIST = [0x187] + [0x193] * 3 + [0x19B] * 4
MENU_OPEN = 0x7E00D7  # non-zero while a character's command menu is up


def _footer(emu) -> list[int]:
    return [emu.read(FOOTER + i * 4) | emu.read(FOOTER + i * 4 + 1) << 8 for i in range(8)]


def _fresh_battle():
    """A battle started from the field: its BG3 tables come from battle init, not from an older build's savestate."""
    emu = load_emu_from_kss(kss_path("ff4-late-field.kss"), settle_frames=10)  # a save room: no encounters
    emu.write(FORMATION, 0x85)
    emu.write(FORMATION + 1, 0x00)
    emu.write(BATTLE_PENDING, 1)
    wait_for_turn(emu, CAIN_SLOT)
    return emu


def _wait(emu, types: tuple[int, ...], frames: int = 120) -> int:
    for _ in range(frames // 2):
        if emu.read(CURSOR_TYPE) in types:
            break
        emu.run_frames(2)
    return emu.read(CURSOR_TYPE)


def test_the_footer_is_vanilla_with_the_command_menu() -> None:
    emu = _fresh_battle()
    try:
        assert _footer(emu) == VANILLA_COMMAND_MENU
    finally:
        emu.close()


def test_the_list_pins_its_border_and_its_target_select_does_not() -> None:
    emu = _fresh_battle()
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
