"""The equip screen's arrow count sits clear of the widest arrow name: it ran over the name at cols 27-28 (b3
playtest), and now sits at cols 28-29 with the window's content one column left."""
from __future__ import annotations

from kintsuki import Button
from kintsuki.tilemap import read_bg_tilemap

from _ff4kintsuki import kss_path, load_emu_from_kss, tap

FIRST_SHOWN = 0x7E1040  # the savestate's first character (Cain) record
RIGHT_HAND, RIGHT_COUNT = 0x33, 0x34
BLINDING_ARROW = 0x59  # Flèche aveuglante, the widest arrow name (76 px)
NINE = 0x89  # the 8x8 font's digit 9
COUNT_ROW, COUNT_COLS = 2, (28, 29)


def test_the_count_shows_beside_the_widest_arrow() -> None:
    emu = load_emu_from_kss(kss_path("ff4-before-field-inventory.kss"), settle_frames=60)
    try:
        emu.write(FIRST_SHOWN + RIGHT_HAND, BLINDING_ARROW)
        emu.write(FIRST_SHOWN + RIGHT_COUNT, 99)
        for button, gap in ((Button.X, 150), (Button.DOWN, 20), (Button.DOWN, 20), (Button.A, 60), (Button.A, 120)):
            tap(emu, button, gap=gap)
        tilemap = read_bg_tilemap(emu, 2)
        digits = [tilemap.cell(COUNT_ROW, column).tile & 0x3FF for column in COUNT_COLS]
    finally:
        emu.close()
    assert digits == [NINE, NINE]
