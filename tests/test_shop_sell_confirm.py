"""The sell confirm window keeps its right border: the item name's top-row blank ran 17 cells, one past the
window (b3 playtest)."""
from __future__ import annotations

from _ff4kintsuki import kss_path, load_emu_from_kss
from kintsuki.tilemap import read_bg_tilemap
from test_showcase import _play

CONFIRM = ["RIGHT", "A", "*90", "A", "*40", "A", "*30"]  # sell list, first row, then the confirm window
RIGHT_EDGE = 0xFB  # the window's right border tile
ROW, COLUMN = 11, 23  # the name's top row, at the window's right border (BG2)


def test_the_confirm_window_keeps_its_right_border() -> None:
    emu = load_emu_from_kss(kss_path("ff4-buggy-item-shop-press-a.kss"))
    try:
        _play(emu, CONFIRM, 40)
        emu.run_frames(30)
        tile = read_bg_tilemap(emu, 2).cell(ROW, COLUMN).tile & 0x3FF
    finally:
        emu.close()
    assert tile == RIGHT_EDGE
