"""Drops list with all 8 slots populated.

Seeds the drops array at $7E:FF28 with 8 valid items, enters the
treasure menu, and screenshots the full drops band. Catches layout
regressions like the "0x20 stride instead of 0x40" bug where slot
offsets are off-by-asl.
"""
from __future__ import annotations

from pathlib import Path

import pytest

from _ff4kintsuki import (
    DROPS,
    assert_screenshot_matches_golden,
    enter_treasure_picker,
    load_emu_from_kss,
)

GOLDENS = Path(__file__).parent / "goldens" / "treasure"
DROPS_TOTAL_ITEMS = 8


def _seed_eight_drops(emu) -> None:
    """Plant 8 distinct items so the rendered band is full and each
    slot's tile content is recognisably different."""
    drops = [
        (0xD5, 1), (0xD1, 2), (0x07, 3), (0xDA, 4),
        (0xD2, 5), (0xD3, 6), (0xD4, 7), (0xD6, 8),
    ]
    assert len(drops) == DROPS_TOTAL_ITEMS
    for i, (item, qty) in enumerate(drops):
        emu.write(DROPS + i * 2, item)
        emu.write(DROPS + i * 2 + 1, qty)


@pytest.fixture
def full_drops_emu():
    """KSS sits on the field map at end-of-battle. The battle→treasure
    transition writes monster-drop items into $7E:FF28 before any draw
    happens, so we run until DrawTreasureList ($01:A15C) is about to
    execute, then overwrite $FF28 with our 8-item seed and let the
    draw consume it."""
    e = load_emu_from_kss(settle_frames=0)
    # Stop right at our drops_init bank-$01 trampoline (replaces the
    # original JSR DrawTreasureList at $01:D80E). $FF28 has already been
    # zeroed and refilled by the monster-drop computation by the time
    # we land here; seeding now lets the engine consume our 8-item
    # array.
    drops_init = e.lookup_symbol_addr("drops_init")
    assert drops_init is not None, "drops_init symbol missing in .adbg"
    assert e.run_until(drops_init, max_frames=600), \
        f"drops_init (${drops_init:06X}) never reached during transition"
    _seed_eight_drops(e)
    e.run_frames(60)  # let the draw + post-draw VRAM transfers settle
    yield e
    e.close()


@pytest.fixture
def picker_drops_emu():
    """Same fixture, then walk DOWN+A to enter the exchange picker."""
    e = load_emu_from_kss(settle_frames=0)
    _seed_eight_drops(e)
    enter_treasure_picker(e)
    yield e
    e.close()


def test_full_drops_layout(full_drops_emu) -> None:
    """All 8 drops populated; screenshot the visible band so each item
    is rendered 2 tile rows tall (16 px) with no overlap."""
    # Sanity: confirm seed survived menu entry.
    survivors = [
        (full_drops_emu.read(DROPS + i * 2),
         full_drops_emu.read(DROPS + i * 2 + 1))
        for i in range(DROPS_TOTAL_ITEMS)
    ]
    assert all(qty > 0 for _, qty in survivors), (
        f"drops seed wiped on menu entry: {survivors}")
    assert_screenshot_matches_golden(full_drops_emu,
                                     GOLDENS / "drops_full_8.png")
