"""The shop's quantity picker draws its "1" in the 8x8 font, like the "10" beside it: the small VWF drew it thinner and
off the baseline (b0 beta)."""
from __future__ import annotations

import pytest
from _ff4kintsuki import kss_path, load_emu_from_kss
from kintsuki.tilemap import read_bg_tilemap
from test_showcase import _play

ONE, ZERO = 0x81, 0x80  # the 8x8 font's digits
ROW = 6  # the quantity line: "1" at column 17, "10" at 19-20 (BG4 when buying, BG1 when selling)


@pytest.mark.parametrize(("steps", "bg"), [(["A", "A"], 4), (["RIGHT", "A", "A"], 1)], ids=["buy", "sell"])
def test_the_one_is_an_8x8_digit_like_the_ten(steps: list[str], bg: int) -> None:
    emu = load_emu_from_kss(kss_path("ff4-buggy-item-shop-press-a.kss"))
    try:
        _play(emu, steps, 40)
        emu.run_frames(30)
        tilemap = read_bg_tilemap(emu, bg)
        tiles = [tilemap.cell(ROW, column).tile & 0x3FF for column in (17, 19, 20)]
    finally:
        emu.close()
    assert tiles == [ONE, ONE, ZERO]
