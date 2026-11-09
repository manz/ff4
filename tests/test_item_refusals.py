"""The item menu's target window and refusals (ingame/items.s).

The refusals, "Ça ne marche pas..." and "Ce n'est pas nécessaire.", are in the small VWF: vanilla points Y at kana
strings in bank $01; the menu text thunks read every string from bank $20, so the unrepointed ones drew whatever
bank $20 holds at that offset. The target window's blocks have a status row under the name: the hand points at the
name, and a KO character's block is grey down to MP.
"""
from __future__ import annotations

from pathlib import Path

import pytest
from _ff4kintsuki import (
    FULL_PICTURE,
    assert_screenshot_matches_golden,
    kss_path,
    load_emu_from_kss,
    tap,
)
from kintsuki import Button

GOLDENS = Path(__file__).parent / "goldens" / "item_refusals"
INVENTORY = 0x7E1440  # item id, count: 2 bytes a slot
POTION = 0xCE
PHOENIX_DOWN = 0xD4
CECIL = 0x7E1000  # status byte 1 at +3 (bit 7 KO), HP at +7; the third row of the target window
CECIL_ROW = 2


def _pick_target(item: int, *, on_ko_cecil: bool):
    emu = load_emu_from_kss(kss_path("ff4-late-field.kss"), settle_frames=10)
    emu.write(INVENTORY, item)
    emu.write(INVENTORY + 1, 5)
    if on_ko_cecil:
        emu.write(CECIL + 3, emu.read(CECIL + 3) | 0x80)
        emu.write_range(CECIL + 7, bytes(2))
    tap(emu, Button.X, gap=60)
    tap(emu, Button.A, gap=60)  # Objets
    tap(emu, Button.A, gap=30)  # the first slot
    tap(emu, Button.A, gap=60)  # use it
    for _ in range(CECIL_ROW if on_ko_cecil else 0):
        tap(emu, Button.DOWN, gap=12)
    return emu


def _use(item: int, *, on_ko_cecil: bool):
    emu = _pick_target(item, on_ko_cecil=on_ko_cecil)
    tap(emu, Button.A, gap=12)
    return emu


def test_the_target_window_golden() -> None:
    emu = _pick_target(POTION, on_ko_cecil=True)
    try:
        assert_screenshot_matches_golden(emu, GOLDENS / "target_window.png", region=FULL_PICTURE)
    finally:
        emu.close()


@pytest.mark.parametrize(
    ("item", "on_ko_cecil", "golden"),
    [(PHOENIX_DOWN, False, "not_needed.png"), (POTION, True, "no_effect.png")],
)
def test_the_refusal_golden(item: int, on_ko_cecil: bool, golden: str) -> None:
    emu = _use(item, on_ko_cecil=on_ko_cecil)
    try:
        assert_screenshot_matches_golden(emu, GOLDENS / golden, region=FULL_PICTURE)
    finally:
        emu.close()
