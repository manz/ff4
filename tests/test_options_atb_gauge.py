"""The options screen's "Jauge ATB  Oui  Non" row (ingame/options.s): row 10, under the colour sliders.

Its setting is $16B3 bit 0, a byte of the saved block vanilla leaves unused: 0 in every save, so the gauge is off by
default. The row has its own toggle cursor (sprite 11, 16x16 like vanilla's) and its own text block (tiles $100-).
"""
from __future__ import annotations

from pathlib import Path

import pytest
from _ff4kintsuki import (
    PICTURE,
    assert_screenshot_matches_golden,
    kss_path,
    load_emu_from_kss,
    tap,
)
from kintsuki import Button

GOLDENS = Path(__file__).parent / "goldens" / "options"
SETTING = 0x7E16B3
ROW = 0x7E1BA7  # the options cursor's row
GAUGE_ROW = 10
CURSOR = 0x00032C  # sprite 11: x, y, tile, attributes
CURSOR_HIGH = 0x000502  # sprites 8-11's high bits: sprite 11's size is bit 7
OUI_X, NON_X = 0x68, 0xA0


def _open_options():
    emu = load_emu_from_kss(kss_path("ff4-late-field.kss"), settle_frames=10)
    tap(emu, Button.X, gap=60)
    for _ in range(6):
        tap(emu, Button.DOWN, gap=16)
    tap(emu, Button.A, gap=80)
    return emu


@pytest.fixture
def options():
    emu = _open_options()
    try:
        yield emu
    finally:
        emu.close()


def test_the_options_golden(options) -> None:
    assert_screenshot_matches_golden(options, GOLDENS / "options.png", region=PICTURE)


def test_up_from_the_first_row_reaches_the_gauge_row(options) -> None:
    assert options.read(ROW) == 0
    tap(options, Button.UP, gap=20)
    assert options.read(ROW) == GAUGE_ROW
    tap(options, Button.DOWN, gap=20)
    assert options.read(ROW) == 0


def test_left_and_right_toggle_the_setting(options) -> None:
    tap(options, Button.UP, gap=20)
    assert options.read(SETTING) & 1 == 0
    tap(options, Button.RIGHT, gap=20)
    assert options.read(SETTING) & 1 == 1
    tap(options, Button.LEFT, gap=20)
    assert options.read(SETTING) & 1 == 0


def test_the_toggle_cursor_points_at_the_choice(options) -> None:
    assert options.read(CURSOR) == NON_X
    assert options.read(CURSOR_HIGH) & 0xC0 == 0x80  # 16x16, x bit 8 clear
    tap(options, Button.UP, gap=20)
    tap(options, Button.RIGHT, gap=20)
    assert options.read(CURSOR) == OUI_X


def test_the_slider_rows_still_change_the_colour(options) -> None:
    for _ in range(7):
        tap(options, Button.DOWN, gap=16)
    assert options.read(ROW) == 7
    before = options.read(0x7E1BA8)  # the red component
    tap(options, Button.RIGHT, gap=20)
    assert options.read(0x7E1BA8) == min(before + 1, 0x1F)
    assert options.read(SETTING) & 1 == 0
