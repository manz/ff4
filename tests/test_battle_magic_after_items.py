"""The magic list right after the item list was scrolled.

The spell list renders only its visible rows, from the list's scroll row ($EF86). The item list leaves its own scroll
there, and vanilla zeroes it only once the cursor lands, after the list is drawn: the ring got rows 3-7, and row 0's
slot still held an item name until the periodic redraw ~60 frames later.
"""
from __future__ import annotations

from _ff4kintsuki import (
    CECIL_SLOT,
    CMD_ITEM,
    CMD_MAGIC_WHITE,
    choose_command,
    command_row,
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
SPELL_LIST = (14, 150, 170, 215)  # the spell names, right of the hand
SCROLL_ROWS = 7
OPENED_FRAMES = 30  # the opening animation is over
SETTLED_FRAMES = 90


def test_the_magic_list_opens_on_its_spells_after_a_scrolled_item_list():
    e = load_emu_from_kss(KSS, settle_frames=60)  # in the field
    try:
        walk_into_battle(e)
        wait_for_turn(e, CECIL_SLOT)
        choose_command(e, CMD_ITEM)
        e.run_frames(40)
        for _ in range(SCROLL_ROWS):
            tap(e, Button.DOWN, gap=12)
        e.run_frames(30)
        tap(e, Button.B, gap=50)  # back to the commands, the hand still on Item
        for _ in range(command_row(e, CMD_ITEM) - command_row(e, CMD_MAGIC_WHITE)):
            tap(e, Button.UP, gap=20)
        e.press(0, Button.A)
        e.run_frames(4)
        e.release(0, Button.A)
        e.run_frames(OPENED_FRAMES)
        opened = crop(frame_picture(e), SPELL_LIST).copy()
        e.run_frames(SETTLED_FRAMES)
        assert (opened == crop(frame_picture(e), SPELL_LIST)).all()
    finally:
        e.close()
