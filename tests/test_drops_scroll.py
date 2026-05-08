"""Drops list scroll regression.

Seeds 8 drops at $7E:FF28 (max), enters the treasure picker, taps
DOWN N times to drive the drops list past the visible band, snapshots
state + screenshot. Goldens live under tests/goldens/drops/.

Today drops scroll triggers aren't wired in `treasure_rolling_patches`,
so the goldens will show "no scroll" and items 5..7 stay hidden. Once
the scroll wire lands the goldens get re-recorded.
"""
from __future__ import annotations

import os
from pathlib import Path

import pytest

from kintsuki import Button

from _ff4kintsuki import (
    DROPS,
    REPO,
    assert_screenshot_matches_golden,
    enter_treasure_picker,
    load_emu_from_kss,
    tap,
)

GOLDENS = Path(__file__).parent / "goldens" / "drops"

DROPS_TOTAL_ITEMS = 8

# Drops engine state RAM. Mirrors src/ingame/drops_rolling.s.
DROPS_ROLLING_BASE = 0x7E1BE0
DROPS_TOP_ROW       = DROPS_ROLLING_BASE + 0
DROPS_BUFFER_POS    = DROPS_ROLLING_BASE + 1
DROPS_EDGE_ROW      = DROPS_ROLLING_BASE + 2
DROPS_SLOT_INDEX    = DROPS_ROLLING_BASE + 3
DROPS_BASE_SCROLL   = DROPS_ROLLING_BASE + 4   # word
DROPS_SCROLL_POS    = 0x7E1BFF


def _seed_eight_drops(emu) -> None:
    """Seed 8 drops with id D5/D1/07/DA/D2/D3/D4/D6 + qty 1..8 so each
    slot is recognisable."""
    drops = [
        (0xD5, 1), (0xD1, 2), (0x07, 3), (0xDA, 4),
        (0xD2, 5), (0xD3, 6), (0xD4, 7), (0xD6, 8),
    ]
    assert len(drops) == DROPS_TOTAL_ITEMS
    for i, (item, qty) in enumerate(drops):
        emu.write(DROPS + i * 2, item)
        emu.write(DROPS + i * 2 + 1, qty)


@pytest.fixture
def drops_emu():
    """KSS at end-of-battle, paused. Seed drops at the JSR-DrawTreasureList
    callsite, run the engine init, then enter the exchange picker so DOWN
    drives the drops cursor."""
    e = load_emu_from_kss(settle_frames=0)
    drops_init = e.lookup_symbol_addr("drops_init")
    assert drops_init is not None, "drops_init symbol missing in .adbg"
    assert e.run_until(drops_init, max_frames=600), \
        "drops_init never reached during transition"
    _seed_eight_drops(e)
    enter_treasure_picker(e)
    yield e
    e.close()


def _capture_drops_state(emu) -> bytes:
    """Snapshot rolling-buffer state bytes used by golden compares."""
    return bytes([
        emu.read(DROPS_SCROLL_POS),
        emu.read(DROPS_BUFFER_POS),
        emu.read(DROPS_EDGE_ROW),
        emu.read(DROPS_SLOT_INDEX),
        emu.read(DROPS_BASE_SCROLL),
        emu.read(DROPS_BASE_SCROLL + 1),
        emu.read(DROPS_TOP_ROW),
    ])


def _check_or_record(name: str, snapshot: bytes) -> None:
    path = GOLDENS / f"{name}.bin"
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or os.environ.get("UPDATE_GOLDENS") == "1":
        path.write_bytes(snapshot)
        pytest.xfail(f"recorded golden at {path.relative_to(REPO)} — verify + commit")
    expected = path.read_bytes()
    assert snapshot == expected, (
        f"snapshot mismatch vs {path.relative_to(REPO)} "
        f"({len(snapshot)} bytes vs {len(expected)} expected). "
        f"Re-record with UPDATE_GOLDENS=1 if intended."
    )


@pytest.mark.parametrize("steps,name", [
    (0, "scroll_0"),
    (1, "scroll_1"),
    (3, "scroll_3"),
    (5, "scroll_5"),
])
def test_drops_scroll_state(drops_emu, steps: int, name: str) -> None:
    """Press DOWN `steps` times then snapshot drops rolling state.

    Records on first run; subsequent runs assert byte-for-byte equality.
    Catches regressions in scroll_pos / buffer_pos rotation, edge_row
    drift, base_scroll capture.
    """
    for _ in range(steps):
        tap(drops_emu, Button.DOWN)
    _check_or_record(name, _capture_drops_state(drops_emu))


@pytest.mark.parametrize("steps,name", [
    (0, "scroll_0"),
    (1, "scroll_1"),
    (3, "scroll_3"),
    (5, "scroll_5"),
])
def test_drops_scroll_screenshot(drops_emu, steps: int, name: str) -> None:
    """Visual drops-band screenshot regression. Catches BG3 layout drift
    that the byte goldens miss (palette swaps, sprite cursor position,
    drops/inventory seam)."""
    for _ in range(steps):
        tap(drops_emu, Button.DOWN)
    assert_screenshot_matches_golden(drops_emu, GOLDENS / f"{name}.png")
