"""A battle message reads its own text, not the battle inventory's rows.

The message window's DrawText reads its string from $EF50. Vanilla points it at the message buffer ($74FD) once, in
graphics command $F8, and ShowMsg_03 keeps it across a run of messages; the rolling battle inventory points it at its
row format buffer meanwhile. The next message then decoded inventory rows: using the Monsters item a second time
(its x/y HP readout) hung in DrawCharVar's invalid-variable loop.
"""
from __future__ import annotations

from kintsuki import Button

from _ff4kintsuki import BATTLE_MENU_OPEN, choose_command, kss_path, load_emu_from_kss, tap

ITEM = 0x01  # the Item command
MONSTERS_ENTRY = 18  # the inventory entry holding Monsters; Cecil used one before this savestate
CURSOR_TYPE = 0x7E1823  # 1 command list, 5 inventory, 4/7/$0C/$0F target select
LIST_INDEX = 0x7E0063
DRAW_CHAR_VAR_TRAP = 0x02A722  # vanilla: an invalid character variable loops here forever


def _wait_cursor(emu, accepted: tuple[int, ...], limit: int = 120) -> int:
    for _ in range(limit // 2):
        if emu.read(CURSOR_TYPE) in accepted:
            break
        emu.run_frames(2)
    return emu.read(CURSOR_TYPE)


def _use_monsters(emu) -> None:
    """Cain's turn: Item, the Monsters entry, use it, on the default target."""
    choose_command(emu, ITEM)
    assert _wait_cursor(emu, (5,)) == 5, "the inventory never opened"
    for _ in range(60):
        here = emu.read(LIST_INDEX)
        if here == MONSTERS_ENTRY:
            break
        tap(emu, Button.DOWN if here < MONSTERS_ENTRY else Button.UP, gap=6)
    assert emu.read(LIST_INDEX) == MONSTERS_ENTRY
    tap(emu, Button.A, gap=20)  # pick
    tap(emu, Button.A, gap=20)  # use
    assert _wait_cursor(emu, (4, 7, 0x0C)) in (4, 7, 0x0C), "no target select"
    tap(emu, Button.A, gap=12)


def test_the_monsters_message_does_not_hang() -> None:
    emu = load_emu_from_kss(kss_path("ff4-battle-monsters-item.kss"), settle_frames=10)
    _use_monsters(emu)
    assert not emu.run_until(DRAW_CHAR_VAR_TRAP, 900), "DrawText decoded the inventory's rows as a message"
    emu.close()


def test_the_battle_goes_on_after_the_message() -> None:
    emu = load_emu_from_kss(kss_path("ff4-battle-monsters-item.kss"), settle_frames=10)
    _use_monsters(emu)
    for _ in range(150):
        emu.run_frames(10)
        if emu.read(BATTLE_MENU_OPEN) and emu.read(CURSOR_TYPE) == 1:
            break
    assert emu.read(BATTLE_MENU_OPEN) and emu.read(CURSOR_TYPE) == 1, "no command menu after the message"
    emu.close()
