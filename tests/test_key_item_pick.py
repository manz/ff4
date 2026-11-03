"""The key-item picker hands the event the item under the hand: its index ran through a 16-bit `tax` with B left
at $06 by the hooks, so past the first row it read outside the list (b3 playtest: the Lumière du désert did nothing
for Rosa)."""
from __future__ import annotations

import pytest
from kintsuki import Button

from _ff4kintsuki import kss_path, load_emu_from_kss, tap

PICKED = 0x7E08FB  # the item EventCmd_f7 hands the event
FILTER = 0x7E0712  # the picker's list: (item, count) pairs


@pytest.mark.parametrize("downs", [0, 5, 13], ids=["first", "scrolled", "desert-light"])
def test_the_pick_is_the_item_under_the_hand(downs: int) -> None:
    emu = load_emu_from_kss(kss_path("ff4-key-inventory.kss"))
    try:
        tap(emu, Button.A, gap=30)
        tap(emu, Button.A, gap=30)
        emu.run_frames(60)
        for _ in range(downs):
            tap(emu, Button.DOWN, gap=20)
        expected = emu.read(FILTER + 2 * downs)
        tap(emu, Button.A, gap=30)
        picked = emu.read(PICKED)
    finally:
        emu.close()
    assert picked == expected
