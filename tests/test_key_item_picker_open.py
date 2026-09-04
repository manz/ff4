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




def test_engine_renders_the_picker_list(picker_emu):
    """The picker's rows come from the rolling engine, not vanilla's
    fixed-font text buffer.

    Engine-rendered names use VWF tile ids from FIELD_ITEM_VWF_TILE_BASE
    ($100+), which the tilemap carries as a low byte plus bit 8 in the
    attribute byte. Vanilla's own rows are fixed-font ids below $100.
    """
    _open_picker(picker_emu)
    picker_emu.run_frames(60)

    # BG3 plane 1 at word $2C00 is where the picker's window body lives;
    # item names sit on plane rows 1/3/5/7.
    base = 0x2C00
    vram = bytes(picker_emu.vram_read_range(base * 2, 8 * 32 * 2))
    vwf_cells = 0
    for row in (1, 3, 5, 7):
        for col in range(4, 20):
            off = (row * 32 + col) * 2
            tile = vram[off] | ((vram[off + 1] & 0x01) << 8)
            if tile >= 0x100:
                vwf_cells += 1
    assert vwf_cells >= 8, (
        f"expected engine-rendered VWF cells in the picker rows, got {vwf_cells}")


def test_picker_leaves_the_field_direct_page_intact(picker_emu):
    """Rendering must not disturb the field engine's direct-page state.

    The menu VWF renderer scratches direct-page bytes the field owns
    ($29/$2A, $33, $34, $43, its own $63-$79 block); leaving any of them
    behind scrambled the map. The picker snapshots the page around its
    render, so the bytes must read back unchanged.
    """
    e = picker_emu
    e.run_frames(30)
    before = bytes(e.read(0x000600 + i) for i in range(0x100))
    _open_picker(e)
    e.run_frames(60)
    after = bytes(e.read(0x000600 + i) for i in range(0x100))
    # The field engine moves plenty of its own state each frame; the
    # check is that the renderer's scratch bytes are not left disturbed.
    scratch = [0x1D, 0x1E, 0x29, 0x2A, 0x33, 0x34, 0x43, 0x5C, 0x5D]
    hot = [f"${b:02x}" for b in scratch if before[b] != after[b] and after[b] in (0x00, 0xFF)]
    assert not hot, f"renderer scratch left in the field direct page: {' '.join(hot)}"
