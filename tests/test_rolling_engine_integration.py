"""Integration test : drive the bank-20 rolling-inventory engine against
real in-game state, not synthetic SCRATCH_STATE.

Opens the field-menu items submenu (state base = $7E:1BA8) and the
treasure popup state (base = $7E:1BD0), then JSLs through
`rolling_engine_invalidate_all` + `rolling_engine_vblank_flush` to
verify the dirty_mask gate works on live WRAM.

Phase 1 entries are profile-agnostic ; this confirms they don't trip
on the existing macro-driven scroll FSM that owns the same struct.
"""
from __future__ import annotations

import pytest

from kintsuki import Button

from _ff4kintsuki import load_emu_from_kss, kss_path, tap


FIELD_MENU_ROLLING_BASE = 0x7E1BA8
TREASURE_ROLLING_BASE = 0x7E1BD0

# RollingBufferState offsets (mirrors src/items.i).
DIRTY_MASK_OFFSET = 25


@pytest.fixture
def field_menu():
    """Field menu Items submenu open, cursor on Aiguille d'or."""
    e = load_emu_from_kss(kss_path("ff4-before-inventory-opens.kss"),
                          settle_frames=60)
    tap(e, Button.A)
    e.run_frames(60)
    yield e
    e.close()


def test_invalidate_all_lights_live_field_menu_state(field_menu) -> None:
    """`rolling_engine_invalidate_all` on the live field-menu state base
    sets dirty_mask = $FF without disturbing the rest of the struct."""
    e = field_menu
    # Snapshot the engine-scratch bytes (top_row..hdma_copy_pending) so
    # we can confirm the engine entry leaves them alone.
    pre = bytes(e.read(FIELD_MENU_ROLLING_BASE + i) for i in range(15))

    fn = e.lookup_symbol_addr("rolling_engine.rolling_engine_invalidate_all")
    assert fn is not None
    e.call(fn, x=FIELD_MENU_ROLLING_BASE & 0xFFFF)

    dirty = e.read(FIELD_MENU_ROLLING_BASE + DIRTY_MASK_OFFSET)
    assert dirty == 0xFF, f"dirty_mask expected $FF, got ${dirty:02X}"

    post = bytes(e.read(FIELD_MENU_ROLLING_BASE + i) for i in range(15))
    assert pre == post, (
        "engine-scratch bytes were touched by invalidate_all "
        f"(pre={pre.hex()} post={post.hex()})")


def test_vblank_flush_clears_live_dirty_mask(field_menu) -> None:
    """Plant dirty_mask = $FF directly (no preceding engine call so the
    field-menu NMI hooks can't intercept), then call vblank_flush and
    verify the mask is cleared on live state."""
    e = field_menu
    e.write(FIELD_MENU_ROLLING_BASE + DIRTY_MASK_OFFSET, 0xFF)
    assert e.read(FIELD_MENU_ROLLING_BASE + DIRTY_MASK_OFFSET) == 0xFF

    flush = e.lookup_symbol_addr("rolling_engine.rolling_engine_vblank_flush")
    e.call(flush, x=FIELD_MENU_ROLLING_BASE & 0xFFFF)
    assert e.read(FIELD_MENU_ROLLING_BASE + DIRTY_MASK_OFFSET) == 0x00


def test_field_menu_init_populates_engine_config(field_menu) -> None:
    """init_menu_rolling_buffer_impl writes the phase-2 engine config +
    hook far-ptrs into the field-menu state struct.

    Confirms the per-menu init now arms the bank-20 engine entries with
    everything they need (visible_rows, item_list_ptr, hdma_channel,
    vwf_cfg_ptr, render/hdma/draw hooks) even though the macro is still
    driving the actual scroll machinery.
    """
    e = field_menu
    base = FIELD_MENU_ROLLING_BASE
    assert e.read(base + 15) == 0x0A           # visible_rows = 10
    assert e.read(base + 16) == 0x02           # slot_height_tiles = 2
    assert e.read(base + 17) == 0x40           # item_list_ptr low
    assert e.read(base + 18) == 0x14           # item_list_ptr mid
    assert e.read(base + 19) == 0x7E           # item_list_ptr bank
    assert e.read(base + 20) == 0x30           # item_count = 48
    assert e.read(base + 21) == 0x05           # hdma_channel = 5
    assert e.read(base + 22) == 0x80           # vwf_cfg_ptr low
    assert e.read(base + 23) == 0x70           # vwf_cfg_ptr mid
    assert e.read(base + 24) == 0x70           # vwf_cfg_ptr bank
    # Hook far-ptrs land in bank-20 reloc region.
    for hook_off in (26, 29, 32):
        bank = e.read(base + hook_off + 2)
        assert bank == 0x20, (
            f"hook at +{hook_off} bank=${bank:02X}, expected $20")


def test_cursor_down_on_field_menu_advances_slot_index(field_menu) -> None:
    """`rolling_engine_cursor_down` advances slot_index on live state.

    Plants visible_rows = 11 (MENU_BUFFER_SLOTS), slot_index = 3 ; calls
    cursor_down ; expects 4. visible_rows + slot_index live in the
    engine-extended portion of the struct so we can poke them
    independently of the live engine state."""
    e = field_menu
    e.write(FIELD_MENU_ROLLING_BASE + 3, 3)   # slot_index
    e.write(FIELD_MENU_ROLLING_BASE + 15, 11) # visible_rows

    fn = e.lookup_symbol_addr("rolling_engine.rolling_engine_cursor_down")
    e.call(fn, x=FIELD_MENU_ROLLING_BASE & 0xFFFF)

    assert e.read(FIELD_MENU_ROLLING_BASE + 3) == 4
