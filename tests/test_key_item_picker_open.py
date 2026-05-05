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


def test_engine_drives_picker(picker_emu):
    """Engine path runs instead of vanilla 4x4 grid. After A,A the
    engine's init-loop ends with edge_row=slot_index=BUFFER_SLOTS-1=6
    and base_scroll captured from $9F (non-zero, non-$FFFF). Vanilla
    picker doesn't touch $7E:1BF2..$7E:1BF5."""
    _open_picker(picker_emu)
    edge_row = picker_emu.read(0x7E1BF2)
    base_scroll = picker_emu.read(0x7E1BF4) | (picker_emu.read(0x7E1BF5) << 8)
    assert edge_row == 6, f"engine init didn't complete: edge_row={edge_row}"
    assert base_scroll not in (0x0000, 0xFFFF), (
        f"base_scroll not captured from $9F: ${base_scroll:04x}"
    )


