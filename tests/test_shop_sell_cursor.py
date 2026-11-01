"""The shop lists' hand points at the item's name: the sell list drew its names 8 px under vanilla's hand
(row * 16 + 0x58), where the buy list lines them up (b0 beta)."""
from __future__ import annotations

from pathlib import Path

import pytest

from _ff4kintsuki import kss_path, load_emu_from_kss, read_picture
from test_showcase import _play

LIST_X = 8  # the list hand's X; the quantity hand is the other sprite
NAMES = (30, 90)  # picture columns the first names cover
BASELINE = 6  # the name's last line under the hand's Y: on the buy list, whose hand vanilla lines up


def _hand_y(emu) -> int:
    oam = emu.oam_read_range(0, 512).tobytes()
    return next(oam[i * 4 + 1] for i in range(128) if oam[i * 4] == LIST_X and 0 < oam[i * 4 + 1] < 0xE0)


def _name_bottom(shot: Path, below: int) -> int:
    """The last line of the first name at or under `below`: its baseline, ascenders aside."""
    brightness = read_picture(shot).sum(axis=-1)

    def lit(y: int) -> bool:
        return bool((brightness[y, slice(*NAMES)] > 500).any())

    y = next(y for y in range(below, brightness.shape[0]) if lit(y))
    while lit(y + 1):
        y += 1
    return y


@pytest.mark.parametrize("plays", [[["A"], ["A"]], [["RIGHT", "A"], ["A"]]], ids=["buy", "sell"])
def test_the_hand_is_level_with_the_name(plays: list[list[str]], tmp_path: Path) -> None:
    emu = load_emu_from_kss(kss_path("ff4-buggy-item-shop-press-a.kss"))
    try:
        for steps in plays:
            _play(emu, steps, 40)
        hand = _hand_y(emu)
        emu.screenshot(str(tmp_path / "shot.png"))
    finally:
        emu.close()
    assert _name_bottom(tmp_path / "shot.png", hand - 4) - hand == BASELINE
