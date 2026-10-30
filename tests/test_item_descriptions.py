"""Field-menu item descriptions: every item from $B0 has one, found past the two-line strings' line breaks.

Run with:
    pytest tests/test_item_descriptions.py -v
    UPDATE_GOLDENS=1 pytest tests/test_item_descriptions.py -v
"""
from __future__ import annotations

from pathlib import Path

import pytest

from kintsuki import Button

from _ff4kintsuki import INVENTORY, assert_screenshot_matches_golden, kss_path, load_emu_from_kss, tap

GOLDENS = Path(__file__).parent / "goldens" / "item_descriptions"
DESCRIPTION_WINDOW = (72, 0, 256, 48)


@pytest.mark.parametrize("item,name", [
    (0xB0, "bomb_fragment"),  # a battle item, without one in vanilla
    (0xC0, "red_fang"),  # two lines
    (0xDF, "gold_apple"),  # past Tent's line break: showed the Soma Drop's
    (0xF9, "pink_tail"),  # a key item, the last two-line string
])
def test_item_description_golden(item: int, name: str) -> None:
    e = load_emu_from_kss(kss_path("ff4-late-field.kss"), settle_frames=10)
    e.write(INVENTORY, item)
    e.write(INVENTORY + 1, 1)
    tap(e, Button.X, gap=60)
    tap(e, Button.A, gap=90)
    assert_screenshot_matches_golden(e, GOLDENS / f"{name}.png", region=DESCRIPTION_WINDOW)
