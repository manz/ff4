"""The treasure popup's exchange label ($01:D95E): "Echange" over the header's Tout prendre while the cursor is in the
drop list, as vanilla's こうかん over 全部とる, and Tout prendre back on the header."""
from __future__ import annotations

from pathlib import Path

import pytest
from _ff4kintsuki import assert_screenshot_matches_golden, load_emu_from_kss, tap
from kintsuki import Button

GOLDENS = Path(__file__).parent / "goldens" / "treasure"
HEADER = (0, 0, 256, 24)


@pytest.fixture
def popup():
    emu = load_emu_from_kss(settle_frames=300)  # the treasure popup, on Tout prendre
    yield emu
    emu.close()


def test_the_exchange_header(popup) -> None:
    tap(popup, Button.DOWN, gap=20)  # the drops
    tap(popup, Button.A, gap=40)  # pick one to exchange
    assert_screenshot_matches_golden(popup, GOLDENS / "exchange_header.png", region=HEADER)


def test_the_header_back_on_the_header(popup) -> None:
    tap(popup, Button.DOWN, gap=20)
    tap(popup, Button.A, gap=40)
    tap(popup, Button.B, gap=40)  # out of the pick
    tap(popup, Button.B, gap=40)  # out of the drop list
    assert_screenshot_matches_golden(popup, GOLDENS / "header_after_exchange.png", region=HEADER)
