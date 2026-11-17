"""The Chocobo Forest's smell spot (A facing it: «Il y a comme une odeur de chocobo...», then the key-item picker
where the Gysahl goes). b5 playtest note 006: scrolled down, the hand sat on a row other than the cursor's, so A
handed over another item than the one it pointed at. Opened a second time, the window was empty.

ff4-chocobo-smell.kss: the party in the Mysidia Chocobo Forest (map $D1) at (7, 4), right under the spot, three
Gysahl in the bag.
"""
from __future__ import annotations

import pytest
from _ff4kintsuki import frame_picture, kss_path, load_emu_from_kss, tap
from kintsuki import Button

PICKER_OPEN = 0x7E06DA
CURSOR_ROW = 0x7E068C  # the cursor's row on screen (0-3)
VISIBLE_ROWS = 4
FIRST_ROW_TOP = 148  # picture line where the first row's band starts
ROW_HEIGHT = 16
HAND_COLUMNS = slice(20, 33)  # the hand, left of the item names
LIT = 500  # an R+G+B sum: the hand's white, not the window's blue
NAMES = slice(33, 120)  # the item names' columns
BODY = slice(142, 213)  # the window's body lines, inside its borders


def _open_picker(emu) -> None:
    tap(emu, Button.UP, gap=20)  # face the spot
    tap(emu, Button.A, gap=90)  # the smell
    tap(emu, Button.A, gap=90)  # past it to the picker
    assert emu.read(PICKER_OPEN)


def _lit(emu):
    return frame_picture(emu).astype(int).sum(axis=2) > LIT


def _hand_rows(emu) -> list[int]:
    picture = _lit(emu)
    bands = [picture[FIRST_ROW_TOP + row * ROW_HEIGHT:FIRST_ROW_TOP + (row + 1) * ROW_HEIGHT, HAND_COLUMNS]
             for row in range(VISIBLE_ROWS)]
    return [row for row, band in enumerate(bands) if band.any()]


@pytest.mark.parametrize("moves", [
    [],
    ["DOWN"] * 3,
    ["DOWN"] * 4,
    ["DOWN"] * 5,
    ["DOWN"] * 6,
    ["DOWN"] * 6 + ["UP"] * 3,
    ["DOWN"] * 6 + ["UP"] * 5,
], ids=["opened", "last-row", "scrolled-1", "scrolled-2", "scrolled-3", "back-to-top-row", "scrolled-back"])
def test_the_hand_is_on_the_cursor_s_row(moves: list[str]) -> None:
    emu = load_emu_from_kss(kss_path("ff4-chocobo-smell.kss"))
    try:
        _open_picker(emu)
        for move in moves:
            tap(emu, getattr(Button, move), gap=20)
        emu.run_frames(10)
        assert _hand_rows(emu) == [emu.read(CURSOR_ROW)]
    finally:
        emu.close()


def test_a_second_opening_lists_the_items() -> None:
    emu = load_emu_from_kss(kss_path("ff4-chocobo-smell.kss"))
    try:
        _open_picker(emu)
        tap(emu, Button.B, gap=90)  # put nothing down
        emu.run_frames(60)
        tap(emu, Button.A, gap=90)  # the smell again
        tap(emu, Button.A, gap=90)
        assert emu.read(PICKER_OPEN)
        assert _lit(emu)[BODY, NAMES].any()
    finally:
        emu.close()

