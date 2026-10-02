"""Battle magic window frame.

The two-column spell list fills BG3 page 1 rows 1-24 of the shared menu
buffer, and the list's scroll HDMA shows tilemap row 25 as the window's
bottom edge. The renderer has to draw that frame itself: the buffer
only carries the items window's shorter frame from battle start.

Starts a fresh encounter from the world map so nothing comes from a
battle an older build already set up.
"""
from __future__ import annotations

import pytest
from kintsuki import Button

from _ff4kintsuki import kss_path, load_emu_from_kss, tap

KSS = kss_path("ff4-before-field-inventory.kss")

BG3_PAGE1 = 0x7400
BOTTOM_ROW = 25
SIDE_ROWS = range(1, BOTTOM_ROW)
BORDER_LEFT, BORDER_RIGHT = 0x000B, 0x000C
BOTTOM = [0x000D, *([0x000E] * 30), 0x000F]


def _row(emu, row: int) -> list[int]:
    raw = bytes(emu.vram_read_range((BG3_PAGE1 + row * 32) * 2, 64))
    return [raw[c * 2] | raw[c * 2 + 1] << 8 for c in range(32)]


@pytest.fixture(scope="module")
def magic_emu():
    e = load_emu_from_kss(KSS, settle_frames=60)
    tap(e, Button.B, gap=20)
    for i in range(7):
        button = (Button.LEFT, Button.RIGHT)[i % 2]
        e.press(0, button)
        e.run_frames(40)
        e.release(0, button)
    e.run_frames(200)  # Cecil's command menu is up
    tap(e, Button.DOWN, gap=20)
    tap(e, Button.A, gap=20)  # Magie
    e.run_frames(50)
    yield e
    e.close()


def test_bottom_border_row_is_drawn(magic_emu):
    assert _row(magic_emu, BOTTOM_ROW) == BOTTOM


def test_side_borders_run_down_to_the_bottom_row(magic_emu):
    edges = {(row[0], row[31]) for row in (_row(magic_emu, r) for r in SIDE_ROWS)}
    assert edges == {(BORDER_LEFT, BORDER_RIGHT)}
