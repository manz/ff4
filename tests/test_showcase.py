"""Whole screens the README shows that no other golden covers: the opening dialogue, the field menu, the key-item
picker and a shop. Pinned like any golden, so the README never shows a stale screen."""
from __future__ import annotations

from pathlib import Path

import pytest
from _ff4kintsuki import _new_emu, assert_screenshot_matches_golden, kss_path, load_emu_from_kss
from kintsuki import Button, Emu

GOLDENS = Path(__file__).parent / "goldens" / "showcase"
# Cold boot: START through the title, then A through the Red Wings intro, one press every 3 seconds, stopping on a
# three-line soldier's line.
INTRO = [step for i in range(58) for step in ["*60", *(["START" if i < 12 else "A"] if i % 3 == 0 and i < 57 else [])]]


def _play(emu: Emu, steps: list[str], gap: int) -> None:
    """Each step taps a button (held 6 frames, then `gap` idle frames) or, as `"*N"`, idles N frames."""
    for step in steps:
        if step.startswith("*"):
            emu.run_frames(int(step[1:]))
            continue
        button = getattr(Button, step)
        emu.press(0, button)
        emu.run_frames(6)
        emu.release(0, button)
        emu.run_frames(gap)
    emu.run_frames(20)


def test_the_opening_dialogue() -> None:
    emu = _new_emu()
    try:
        _play(emu, INTRO, gap=0)
        assert_screenshot_matches_golden(emu, GOLDENS / "dialogue.png")
    finally:
        emu.close()


@pytest.mark.parametrize(("name", "kss", "steps", "gap"), [
    ("field_menu", "ff4-before-field-inventory.kss", ["X", "*60"], 20),
    ("key_item_picker", "ff4-key-inventory.kss", ["A", "A", "*60"], 30),
    ("shop_sell", "ff4-buggy-item-shop-press-a.kss", ["RIGHT", "A"], 40),
])
def test_the_screen(name: str, kss: str, steps: list[str], gap: int) -> None:
    emu = load_emu_from_kss(kss_path(kss))
    try:
        _play(emu, steps, gap)
        assert_screenshot_matches_golden(emu, GOLDENS / f"{name}.png")
    finally:
        emu.close()
