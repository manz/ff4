"""Smoke test for the key-item picker entry path.

Loads ff4-key-inventory.kss (gitignored — drop one at the repo root),
taps A to fire whatever EventCmd_f7-bearing dialog the kss is parked
in front of, settles, and snapshots picker-related state for golden
locking once Phase 5b real impls land.
"""
from __future__ import annotations

from pathlib import Path

import pytest
from kintsuki import Button

from _ff4kintsuki import (
    kss_path,
    load_emu_from_kss,
    tap,
)

KSS = kss_path("ff4-key-inventory.kss")
GOLDENS = Path(__file__).parent / "goldens" / "key_item_picker"


@pytest.fixture
def picker_emu():
    e = load_emu_from_kss(KSS)
    yield e
    e.close()


def test_kss_loads(picker_emu):
    """Sanity: kss loads, framebuffer has non-zero content."""
    fb = picker_emu.framebuffer()
    assert any(fb), "framebuffer empty after kss load"


def test_a_tap_opens_picker(picker_emu):
    """Tap A; expect the picker filtered buffer at $7E:0712 to populate
    after InitItemList runs (first non-zero entry inside 60 frames)."""
    tap(picker_emu, Button.A, gap=30)
    picker_emu.run_frames(60)
    filter_buf = bytes(picker_emu.read(0x7E0712 + i) for i in range(16))
    assert any(b != 0 for b in filter_buf), (
        f"$7E:0712 filter buffer still empty after A tap: {filter_buf.hex()}"
    )


def test_picker_screenshot_baseline(picker_emu):
    """Vanilla 4x4 grid picker baseline. Re-record with UPDATE_GOLDENS=1
    once Phase 5b replaces the grid render with the engine's single-col
    rolling buffer."""
    from _ff4kintsuki import assert_screenshot_matches_golden
    tap(picker_emu, Button.A, gap=30)
    picker_emu.run_frames(60)
    assert_screenshot_matches_golden(picker_emu, GOLDENS / "vanilla_open.png")
