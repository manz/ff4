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

# Visible inventory rows in the treasure exchange picker.
TREASURE_VISIBLE_ROWS = 5


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


def test_one_scroll_step_per_press(picker_emu) -> None:
    """A single DOWN press past the last visible row scrolls exactly one
    item.

    The debounce counter (`treasure_scroll_cooldown`) used to be
    decremented from the treasure main-loop check, which vanilla spins
    many times within a single frame while the scroll animation
    finishes, draining a 24-frame cooldown in one frame and letting
    the same press fire a second scroll. Ticking it once per vblank
    keeps one press to one item.
    """
    e = picker_emu
    scroll_pos = 0x7E1BB7
    # Walk the cursor down to the last visible row; nothing scrolls yet.
    for _ in range(TREASURE_VISIBLE_ROWS - 1):
        tap(e, Button.DOWN)
    assert e.read(scroll_pos) == 0

    for expected in (1, 2, 3):
        tap(e, Button.DOWN)
        e.run_frames(30)
        assert e.read(scroll_pos) == expected, (
            f"press advanced scroll_pos to {e.read(scroll_pos)}, "
            f"expected {expected}")


def test_scroll_keeps_window_bottom_border(picker_emu) -> None:
    """Scrolling must not render a slot over the window's bottom border.

    The engine derives `buffer_slots = visible_rows + 1`, so the profile
    must publish the VISIBLE row count. Treasure published
    TREASURE_BUFFER_SLOTS (6) instead, giving the engine 7 slots: the
    prefetch slot rendered one row pair too low, wiping the border at
    BG3 row 13 and leaking item text into row 14 the first time the
    list scrolled.
    """
    e = picker_emu
    bg3_staging = 0x7ED600
    border_row = 13

    def row(r: int) -> bytes:
        return bytes(e.read(bg3_staging + r * 64 + c * 2) for c in range(28))

    before = row(border_row)
    assert before.count(0xFD) > 20, (
        f"expected the bottom border row to be border tiles, got {before.hex()}")

    for _ in range(TREASURE_VISIBLE_ROWS):
        tap(e, Button.DOWN)
    e.run_frames(30)

    assert row(border_row) == before, "scrolling overwrote the window's bottom border"
    assert all(b in (0x00, 0xFF) for b in row(border_row + 1)), (
        "item text leaked past the window's bottom border")
