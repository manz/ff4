"""The sell list sells the item under the hand: vanilla's two-column index ((row + scroll) * 2 + column) sold
another slot of the single-column list, and a sale redrew the list from the top while the scroll stayed put (b3
playtest)."""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pytest
from _ff4kintsuki import (
    INVENTORY,
    crop,
    kss_path,
    load_emu_from_kss,
    screenshot_picture,
)
from test_showcase import _play

SELL_LIST = ["RIGHT", "A", "*90", "A", "*40"]  # into the sell list, the hand on its first row
SCROLL_POS = 0x7E1B96
LIST_WINDOW = (8, 80, 248, 216)  # the rows, in picture coordinates


def _inventory(emu) -> list[tuple[int, int]]:
    return [(emu.read(INVENTORY + 2 * slot), emu.read(INVENTORY + 2 * slot + 1)) for slot in range(48)]


@pytest.mark.parametrize("downs", [1, 10], ids=["first-page", "scrolled"])
def test_the_sale_takes_the_item_under_the_hand(downs: int) -> None:
    emu = load_emu_from_kss(kss_path("ff4-buggy-item-shop-press-a.kss"))
    try:
        _play(emu, [*SELL_LIST, *["DOWN"] * downs], 40)
        before = _inventory(emu)
        _play(emu, ["A", "*20", "A"], 30)
        after = _inventory(emu)
    finally:
        emu.close()
    changed = [slot for slot in range(48) if before[slot] != after[slot]]
    assert changed == [downs]


def test_a_sale_keeps_the_list_scrolled(tmp_path: Path) -> None:
    emu = load_emu_from_kss(kss_path("ff4-buggy-item-shop-press-a.kss"))
    try:
        _play(emu, [*SELL_LIST, *["DOWN"] * 10], 40)
        assert emu.read(SCROLL_POS) == 3
        before = crop(screenshot_picture(emu, tmp_path / "before.png"), LIST_WINDOW)
        _play(emu, ["A", "*20", "A", "*60"], 30)
        after = crop(screenshot_picture(emu, tmp_path / "after.png"), LIST_WINDOW)
    finally:
        emu.close()
    # The sold row (the hand's, the last) shows one fewer; every row above it stays the same.
    assert np.array_equal(before[:96], after[:96])
