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


def _open_picker(emu):
    """First A tap opens the NPC dialog ; second advances past it and
    reaches the F7 (item selection) command, which pops the picker."""
    tap(emu, Button.A, gap=30)
    tap(emu, Button.A, gap=30)
    emu.run_frames(60)


def test_a_tap_opens_picker(picker_emu):
    """A,A through NPC dialog; expect $7E:0712 filter buffer populated
    after InitItemList runs."""
    _open_picker(picker_emu)
    filter_buf = bytes(picker_emu.read(0x7E0712 + i) for i in range(16))
    assert any(b != 0 for b in filter_buf), (
        f"$7E:0712 filter buffer still empty after A,A: {filter_buf.hex()}"
    )


def test_picker_single_col_layout(picker_emu):
    """Single-col patches force UpdateItemText to write each item on
    a fresh text-buffer row (Y stride 24). After A,A the text buffer
    at $0774 should have non-$FF bytes at row offsets 0, 24, 48 — at
    least one of which has a recognizable item name char."""
    _open_picker(picker_emu)
    row0 = picker_emu.read(0x7E0774)
    row1 = picker_emu.read(0x7E0774 + 0x18)
    row2 = picker_emu.read(0x7E0774 + 0x30)
    rendered = [r for r in (row0, row1, row2) if r != 0xFF and r != 0]
    assert len(rendered) >= 1, (
        f"text buffer unrendered: row0=${row0:02x} row1=${row1:02x} row2=${row2:02x}"
    )


