"""The command window after the equipped-hands popup.

The popup draws the hands' glyphs into the command list's tiles, and the command list renders them back once the
popup closes. That render skips while the item list is open ($4A bit 2), and B from the popup closes the list a few
frames later: when the menu task's last pass came first, nothing redrew the commands and the window kept the hand
names. Scrolling the list before going up into the popup shifts the timing into that window.
"""
from __future__ import annotations

from _ff4kintsuki import (
    CECIL_SLOT,
    CMD_ITEM,
    choose_command,
    crop,
    frame_picture,
    kss_path,
    load_emu_from_kss,
    tap,
    wait_for_turn,
    walk_into_battle,
)
from kintsuki import Button

KSS = kss_path("ff4-before-field-inventory.kss")
COMMAND_TEXT = (48, 148, 100, 212)  # the command names, right of the hand
SCROLL_ROWS = 7
UP_TO_HANDS = 9  # back to the top of the list, then into the popup


def test_commands_come_back_after_the_hands_popup():
    e = load_emu_from_kss(KSS, settle_frames=60)  # in the field
    try:
        walk_into_battle(e)
        wait_for_turn(e, CECIL_SLOT)
        commands = crop(frame_picture(e), COMMAND_TEXT).copy()
        choose_command(e, CMD_ITEM)
        e.run_frames(40)
        for _ in range(SCROLL_ROWS):
            tap(e, Button.DOWN, gap=20)
        for _ in range(UP_TO_HANDS):
            tap(e, Button.UP, gap=20)
        e.run_frames(40)
        tap(e, Button.B, gap=30)
        e.run_frames(60)
        assert (crop(frame_picture(e), COMMAND_TEXT) == commands).all()
    finally:
        e.close()
