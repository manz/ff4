"""utils/battle_labels.py: the battle's 8x8 labels baked into the 8x8 font's free kana slots, and the battle screens
showing them."""
from __future__ import annotations

from pathlib import Path

import pytest
from katsuji import VwfFont
from katsuji import config as katsuji_config
from katsuji.script import Table

from _ff4kintsuki import PICTURE, assert_screenshot_matches_golden, fresh_late_battle, tap
from kintsuki import Button
from utils import battle_labels
from utils.bake_names import Glyphs

GOLDENS = Path(__file__).parent / "goldens" / "battle_labels"
FONT = Path("build/gen/menu_font.dat")


@pytest.fixture(scope="module", params=["fr", "en"])
def baked(request) -> tuple[bytes, str]:
    if not FONT.exists():
        pytest.skip("menu_font.dat not built")
    glyphs = Glyphs.of(katsuji_config.load(Path("katsuji.toml")).fonts["menu"])
    return battle_labels.bake(Path("fonts/8x8.bin").read_bytes(), VwfFont.decode(FONT.read_bytes()), glyphs,
                              Table("build/gen/ff4_menus_small_vwf.tbl"), request.param)


def test_only_the_slots_change(baked) -> None:
    font = Path("fonts/8x8.bin").read_bytes()
    changed = {i // battle_labels.TILE_BYTES for i, (a, b) in enumerate(zip(font, baked[0], strict=True)) if a != b}
    assert changed and changed <= set(battle_labels.SLOTS)


def test_every_label_has_its_macro(baked) -> None:
    assert all(f"battle_label_{name}()" in baked[1] for name in battle_labels.LABELS)


def test_a_used_slot_is_refused() -> None:
    font = bytes(256 * battle_labels.TILE_BYTES)  # no blank cell anywhere
    glyphs = Glyphs.of(katsuji_config.load(Path("katsuji.toml")).fonts["menu"])
    with pytest.raises(ValueError, match="not blank"):
        battle_labels.bake(font, VwfFont.decode(FONT.read_bytes()), glyphs, Table("build/gen/ff4_menus_small_vwf.tbl"))


@pytest.mark.parametrize(("presses", "region", "golden"), [
    ((Button.LEFT,), (0, 128, 96, 176), "rang.png"),
    ((Button.RIGHT, Button.RIGHT), (64, 128, 160, 176), "garde.png"),
    ((Button.DOWN, Button.A), (168, 136, 256, 224), "mp_cost.png"),
])
def test_the_label_golden(presses, region, golden) -> None:
    emu = fresh_late_battle()
    try:
        emu.run_frames(30)
        for button in presses:
            tap(emu, button, gap=30)
        emu.run_frames(10)
        assert_screenshot_matches_golden(emu, GOLDENS / golden, region=region)
    finally:
        emu.close()
