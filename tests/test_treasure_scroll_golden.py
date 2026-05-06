"""Treasure-menu scroll regression — drives DOWN through the rolling
buffer and compares the resulting WRAM rolling-buffer state + BG3
inventory tilemap against checked-in golden snapshots.

On first run (or `UPDATE_GOLDENS=1`), the test writes the captured
state to `tests/goldens/treasure/<scenario>.bin` and xfails so the
golden gets committed alongside the test.

Run with:
    pytest tests/test_treasure_scroll_golden.py -v
    UPDATE_GOLDENS=1 pytest tests/test_treasure_scroll_golden.py -v
"""
from __future__ import annotations

import os
from pathlib import Path

import pytest

from kintsuki import Button

from _ff4kintsuki import (
    REPO,
    assert_screenshot_matches_golden,
    capture_treasure_state,
    enter_treasure_picker,
    load_emu_from_kss,
    tap,
)

GOLDENS = Path(__file__).parent / "goldens" / "treasure"


@pytest.fixture
def picker_emu():
    e = load_emu_from_kss()
    enter_treasure_picker(e)
    yield e
    e.close()


def _check_or_record(name: str, snapshot: bytes) -> None:
    path = GOLDENS / f"{name}.bin"
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or os.environ.get("UPDATE_GOLDENS") == "1":
        path.write_bytes(snapshot)
        pytest.xfail(f"recorded golden at {path.relative_to(REPO)} — "
                     f"verify visually then commit")
    expected = path.read_bytes()
    assert snapshot == expected, (
        f"snapshot mismatch vs {path.relative_to(REPO)} "
        f"({len(snapshot)} bytes vs {len(expected)} expected). "
        f"Re-record with UPDATE_GOLDENS=1 if the change is intended."
    )


@pytest.mark.parametrize("steps,name", [
    (0, "scroll_0"),
    (1, "scroll_1"),
    (3, "scroll_3"),
    (5, "scroll_5"),
])
def test_scroll_matches_golden(picker_emu, steps: int, name: str) -> None:
    """Press DOWN `steps` times then snapshot rolling state + tilemap.

    Records on first run; subsequent runs assert byte-for-byte equality
    so regressions in scroll_pos / buffer_pos rotation, slot rendering,
    or footer scroll value all surface as a diff.
    """
    for _ in range(steps):
        tap(picker_emu, Button.DOWN)
    _check_or_record(name, capture_treasure_state(picker_emu))


@pytest.mark.parametrize("steps,name", [
    (0, "scroll_0"),
    (1, "scroll_1"),
    (3, "scroll_3"),
    (5, "scroll_5"),
])
def test_scroll_screenshot_golden(picker_emu, steps: int, name: str) -> None:
    """Visual treasure-picker screenshot regression. Catches BG3 layout
    drift that the byte goldens miss (palette swaps, sprite cursor
    position, drops-band parallax)."""
    for _ in range(steps):
        tap(picker_emu, Button.DOWN)
    assert_screenshot_matches_golden(picker_emu,
                                     GOLDENS / f"{name}.png")
