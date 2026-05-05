"""Treasure-menu swap regression — drives the rolling-buffer treasure
exchange picker and verifies that swapping a drop with various
inventory rows actually moves the items as the cursor positions imply.

Skipped when the kintsuki ff4-before-battle-inventory.kss savestate
isn't sitting at the repo root (gitignored fixture)."""
from __future__ import annotations

import pytest

from kintsuki import Button

from _ff4kintsuki import (
    DROPS,
    INVENTORY,
    enter_treasure_picker,
    load_emu_from_kss,
    tap,
)


@pytest.fixture
def picker_emu():
    e = load_emu_from_kss()
    e.run_frames(300)  # let menu settle on Tout prendre
    yield e
    e.close()


def _seed(emu) -> None:
    """Plant deterministic content for both lists. Item IDs taken from
    the existing kss inventory so the localized name table has matching
    glyph strings."""
    drops = [
        (0xD5, 1), (0xD1, 1), (0x07, 1), (0xDA, 1),
        (0x00, 0), (0x00, 0), (0x00, 0), (0x00, 0),
    ]
    for i, (item, qty) in enumerate(drops):
        emu.write(DROPS + i * 2, item)
        emu.write(DROPS + i * 2 + 1, qty)
    inv = [
        (0xB0, 1), (0xB1, 1), (0xB2, 1), (0xB3, 1),
        (0xB4, 1), (0xB5, 1), (0xB6, 1), (0xB7, 1),
    ] + [(0, 0)] * 40
    for i, (item, qty) in enumerate(inv):
        emu.write(INVENTORY + i * 2, item)
        emu.write(INVENTORY + i * 2 + 1, qty)


def _do_swap(emu, *, top_row: int, bottom_row: int) -> None:
    """DOWN to drops list → UP `top_row` times → A (Echange) → DOWN
    `bottom_row` times → A (confirm swap)."""
    tap(emu, Button.DOWN)               # cursor on drops list, row 0
    for _ in range(top_row):
        tap(emu, Button.DOWN)           # walk down through drops
    tap(emu, Button.A)                  # select drop, jump to inventory row 0
    for _ in range(bottom_row):
        tap(emu, Button.DOWN)           # walk down through inventory
    tap(emu, Button.A)                  # confirm swap
    emu.run_frames(30)                  # let the post-swap redraw settle


@pytest.mark.parametrize("bottom_row", [0, 2, 4])
def test_swap_drop0_with_inventory_row(picker_emu, bottom_row: int) -> None:
    """Swap drop slot 0 with inventory slot `bottom_row`. Both bytes
    should swap atomically: drop[0] ↔ inv[bottom_row]."""
    _seed(picker_emu)
    drop0_before = picker_emu.read(DROPS + 0)
    inv_before   = picker_emu.read(INVENTORY + bottom_row * 2)
    _do_swap(picker_emu, top_row=0, bottom_row=bottom_row)
    drop0_after = picker_emu.read(DROPS + 0)
    inv_after   = picker_emu.read(INVENTORY + bottom_row * 2)
    assert (drop0_after, inv_after) == (inv_before, drop0_before), (
        f"swap drop[0] ↔ inv[{bottom_row}] left a different pair: "
        f"before drop=${drop0_before:02X} inv=${inv_before:02X}, "
        f"after drop=${drop0_after:02X} inv=${inv_after:02X}"
    )
