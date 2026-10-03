"""Battle inventory VWF golden.

Pins the battle item list as rendered by the VWF: names, icons, the
quantity column and greyed-out entries, at the top of the list and one
page down (rows rendered at the scroll edge).

The list is built at battle start (`InitInventoryTextBuf`, $02:9E9C),
so a savestate saved mid-battle would show an older build's rows: the
fixture starts a fresh encounter from the world map instead.
"""
from __future__ import annotations

from pathlib import Path

import pytest
from kintsuki import Button

from _ff4kintsuki import assert_screenshot_matches_golden, kss_path, load_emu_from_kss, tap

KSS = kss_path("ff4-before-field-inventory.kss")
GOLDENS = Path(__file__).parent / "goldens" / "battle_inventory"
PAGE = 5


@pytest.fixture(scope="module")
def items_emu():
    e = load_emu_from_kss(KSS, settle_frames=60)
    tap(e, Button.B, gap=20)
    for i in range(7):
        button = (Button.LEFT, Button.RIGHT)[i % 2]
        e.press(0, button)
        e.run_frames(40)
        e.release(0, button)
    e.run_frames(200)  # Cecil's command menu is up
    for _ in range(3):
        tap(e, Button.DOWN, gap=20)
    tap(e, Button.A, gap=20)  # Objets
    e.run_frames(30)
    yield e
    e.close()


def test_top_of_list(items_emu):
    assert_screenshot_matches_golden(items_emu, GOLDENS / "top.png")


def test_one_page_down(items_emu):
    for _ in range(PAGE):
        tap(items_emu, Button.DOWN, gap=12)
    items_emu.run_frames(20)
    assert_screenshot_matches_golden(items_emu, GOLDENS / "page_down.png")
