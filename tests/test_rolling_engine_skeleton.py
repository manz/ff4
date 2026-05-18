"""Phase-1 smoke for the unified rolling-inventory engine.

Each entry currently RTLs immediately (plans/rolling_inventory_engine.md
phase 1 stub) so the harness only verifies:

* All eight bank-20 symbols resolve via the .adbg debug info.
* Each entry, when JSL'd from a fresh emulator with X = a sentinel
  state-ptr, returns cleanly without crashing or trashing X/Y.
* `RollingBufferState` struct accepts the phase-1 extended fields
  (visible_rows, slot_height_tiles, item_list_ptr, item_count,
  hdma_channel, vwf_cfg_ptr, dirty_mask) without breaking the
  existing field-items / treasure rolling consumers.

Phase 2+ replaces the stubs with real implementations ; the same
harness expands to drive a fake inventory and assert scroll-state
transitions, dirty-mask flush ordering, and HDMA channel arming.
"""

from __future__ import annotations

import pytest

from _ff4kintsuki import load_emu_from_kss, kss_path

# RollingBufferState field offsets (mirrors src/items.i `.struct
# RollingBufferState`). Keep in sync if the struct evolves.
RBS_SLOT_INDEX = 3
RBS_VISIBLE_ROWS = 15
RBS_DIRTY_MASK = 25

# WRAM scratch region for engine state during unit tests. Sits in the
# vanilla "$AAAA filler" area at $7E:0500 -- never touched by the rest
# of the field-menu / treasure code paths during the menu settle so
# reads + writes stay deterministic.
SCRATCH_STATE = 0x7E0500


ENGINE_ENTRIES = [
    "rolling_engine.rolling_engine_init",
    "rolling_engine.rolling_engine_tick",
    "rolling_engine.rolling_engine_vblank_flush",
    "rolling_engine.rolling_engine_cursor_up",
    "rolling_engine.rolling_engine_cursor_down",
    "rolling_engine.rolling_engine_invalidate_slot",
    "rolling_engine.rolling_engine_invalidate_all",
    "rolling_engine.rolling_engine_shutdown",
]


@pytest.fixture
def emu():
    e = load_emu_from_kss(kss_path("ff4-before-inventory-opens.kss"),
                          settle_frames=10)
    yield e
    e.close()


def test_engine_entries_resolve(emu) -> None:
    """Every phase-1 entry point is exported via the .adbg file."""
    missing = [sym for sym in ENGINE_ENTRIES
               if emu.lookup_symbol_addr(sym) is None]
    assert not missing, f"missing engine symbols: {missing}"


def test_engine_entries_in_bank_20(emu) -> None:
    """Phase-1 entries land in the bank-20 reloc region ($20:8000+)."""
    for sym in ENGINE_ENTRIES:
        addr = emu.lookup_symbol_addr(sym)
        assert addr is not None, sym
        assert (addr >> 16) == 0x20, (
            f"{sym} at ${addr:06X} should be in bank 20")


# --------------------------------------------------------------- Helpers


def _setup_state(emu, *, slot_index: int, visible_rows: int,
                 dirty_mask: int = 0) -> int:
    """Plant a sentinel `RollingBufferState` at SCRATCH_STATE and return
    the low-16 of its address (= the value that goes in X for engine
    JSLs ; the bank-$7E implied addressing in the engine reads from
    $7E:<low16> + struct-field offset).
    """
    emu.write(SCRATCH_STATE + RBS_SLOT_INDEX, slot_index)
    emu.write(SCRATCH_STATE + RBS_VISIBLE_ROWS, visible_rows)
    emu.write(SCRATCH_STATE + RBS_DIRTY_MASK, dirty_mask)
    return SCRATCH_STATE & 0xFFFF


def _read_slot_index(emu) -> int:
    return emu.read(SCRATCH_STATE + RBS_SLOT_INDEX)


def _read_dirty_mask(emu) -> int:
    return emu.read(SCRATCH_STATE + RBS_DIRTY_MASK)


# --------------------------------------------------------------- Cursor


def test_cursor_down_increments_slot_index(emu) -> None:
    """cursor_down advances slot_index by 1 while inside the window."""
    x = _setup_state(emu, slot_index=2, visible_rows=10)
    fn = emu.lookup_symbol_addr("rolling_engine.rolling_engine_cursor_down")
    emu.call(fn, x=x)
    assert _read_slot_index(emu) == 3


def test_cursor_down_wraps_to_zero(emu) -> None:
    """cursor_down on the last slot wraps back to 0."""
    x = _setup_state(emu, slot_index=9, visible_rows=10)
    fn = emu.lookup_symbol_addr("rolling_engine.rolling_engine_cursor_down")
    emu.call(fn, x=x)
    assert _read_slot_index(emu) == 0


def test_cursor_up_decrements_slot_index(emu) -> None:
    """cursor_up advances slot_index backwards by 1."""
    x = _setup_state(emu, slot_index=4, visible_rows=10)
    fn = emu.lookup_symbol_addr("rolling_engine.rolling_engine_cursor_up")
    emu.call(fn, x=x)
    assert _read_slot_index(emu) == 3


def test_cursor_up_wraps_from_zero(emu) -> None:
    """cursor_up at slot 0 wraps to (visible_rows - 1)."""
    x = _setup_state(emu, slot_index=0, visible_rows=10)
    fn = emu.lookup_symbol_addr("rolling_engine.rolling_engine_cursor_up")
    emu.call(fn, x=x)
    assert _read_slot_index(emu) == 9


# --------------------------------------------------------------- Dirty


def test_invalidate_slot_sets_bit(emu) -> None:
    """invalidate_slot sets bit (1 << A) in dirty_mask without disturbing
    bits already lit."""
    x = _setup_state(emu, slot_index=0, visible_rows=10, dirty_mask=0x01)
    fn = emu.lookup_symbol_addr(
        "rolling_engine.rolling_engine_invalidate_slot")
    emu.call(fn, a=4, x=x)
    # bit 4 set, bit 0 from setup also set
    assert _read_dirty_mask(emu) == 0x11


def test_invalidate_slot_idempotent(emu) -> None:
    """Setting an already-dirty bit leaves dirty_mask unchanged."""
    x = _setup_state(emu, slot_index=0, visible_rows=10, dirty_mask=0x20)
    fn = emu.lookup_symbol_addr(
        "rolling_engine.rolling_engine_invalidate_slot")
    emu.call(fn, a=5, x=x)
    assert _read_dirty_mask(emu) == 0x20


def test_invalidate_all_lights_full_mask(emu) -> None:
    """invalidate_all sets dirty_mask to $FF."""
    x = _setup_state(emu, slot_index=0, visible_rows=10, dirty_mask=0x00)
    fn = emu.lookup_symbol_addr("rolling_engine.rolling_engine_invalidate_all")
    emu.call(fn, x=x)
    assert _read_dirty_mask(emu) == 0xFF


# --------------------------------------------------------------- Init


# Engine-scratch bytes that init must zero (offsets within state struct).
INIT_ZERO_BYTES = [
    0,   # top_row
    1,   # buffer_pos
    2,   # edge_row
    3,   # slot_index
    6,   # hdma_enable
    7,   # _pad
    8,   # scroll_state
    9,   # scroll_remaining
    10,  # scroll_direction
    11,  # transfer_pending
    12,  # scroll_anim_offset lo
    13,  # scroll_anim_offset hi
    14,  # hdma_copy_pending
    25,  # dirty_mask
]


def _fill_state_with_pattern(emu, byte: int = 0xAA, length: int = 32) -> None:
    """Pre-fill 32 bytes at SCRATCH_STATE with a known sentinel so init's
    zero-out and base_scroll = $FFFF stamping is visible against the
    pattern."""
    for i in range(length):
        emu.write(SCRATCH_STATE + i, byte)


def test_init_zeroes_engine_scratch(emu) -> None:
    """rolling_engine_init clears the 14 engine-scratch + dirty_mask bytes."""
    _fill_state_with_pattern(emu)
    fn = emu.lookup_symbol_addr("rolling_engine.rolling_engine_init")
    emu.call(fn, x=SCRATCH_STATE & 0xFFFF)
    for off in INIT_ZERO_BYTES:
        val = emu.read(SCRATCH_STATE + off)
        assert val == 0x00, (
            f"offset {off} expected zero after init, got ${val:02X}")


def test_init_stamps_base_scroll_sentinel(emu) -> None:
    """rolling_engine_init writes $FFFF into base_scroll (offsets 4 + 5)."""
    _fill_state_with_pattern(emu)
    fn = emu.lookup_symbol_addr("rolling_engine.rolling_engine_init")
    emu.call(fn, x=SCRATCH_STATE & 0xFFFF)
    assert emu.read(SCRATCH_STATE + 4) == 0xFF
    assert emu.read(SCRATCH_STATE + 5) == 0xFF


def test_init_preserves_config_fields(emu) -> None:
    """Caller-managed config fields (visible_rows + dirty_mask aside)
    must NOT be touched by init : engine_init clears scratch only."""
    _fill_state_with_pattern(emu)
    fn = emu.lookup_symbol_addr("rolling_engine.rolling_engine_init")
    emu.call(fn, x=SCRATCH_STATE & 0xFFFF)
    # visible_rows (offset 15) + item_list_ptr 17..19 + item_count 20 +
    # hdma_channel 21 + vwf_cfg_ptr 22..24 should keep the pattern.
    for off in [15, 16, 17, 18, 19, 20, 21, 22, 23, 24]:
        val = emu.read(SCRATCH_STATE + off)
        assert val == 0xAA, (
            f"config offset {off} got clobbered by init: ${val:02X}")


# --------------------------------------------------------------- Shutdown


def test_shutdown_clears_runtime_flags(emu) -> None:
    """rolling_engine_shutdown clears hdma_enable / dirty_mask /
    scroll_state / transfer_pending / hdma_copy_pending and restamps
    the base_scroll sentinel."""
    _fill_state_with_pattern(emu)
    fn = emu.lookup_symbol_addr("rolling_engine.rolling_engine_shutdown")
    emu.call(fn, x=SCRATCH_STATE & 0xFFFF)
    assert emu.read(SCRATCH_STATE + 6) == 0x00   # hdma_enable
    assert emu.read(SCRATCH_STATE + 8) == 0x00   # scroll_state
    assert emu.read(SCRATCH_STATE + 11) == 0x00  # transfer_pending
    assert emu.read(SCRATCH_STATE + 14) == 0x00  # hdma_copy_pending
    assert emu.read(SCRATCH_STATE + 25) == 0x00  # dirty_mask
    assert emu.read(SCRATCH_STATE + 4) == 0xFF   # base_scroll lo
    assert emu.read(SCRATCH_STATE + 5) == 0xFF   # base_scroll hi


def test_shutdown_leaves_cursor_alone(emu) -> None:
    """Shutdown does not nuke slot_index / buffer_pos / edge_row /
    top_row ; those are caller's UI state."""
    _setup_state(emu, slot_index=4, visible_rows=10)
    emu.write(SCRATCH_STATE + 0, 0x07)  # top_row
    emu.write(SCRATCH_STATE + 1, 0x03)  # buffer_pos
    emu.write(SCRATCH_STATE + 2, 0x02)  # edge_row
    fn = emu.lookup_symbol_addr("rolling_engine.rolling_engine_shutdown")
    emu.call(fn, x=SCRATCH_STATE & 0xFFFF)
    assert emu.read(SCRATCH_STATE + 0) == 0x07
    assert emu.read(SCRATCH_STATE + 1) == 0x03
    assert emu.read(SCRATCH_STATE + 2) == 0x02
    assert emu.read(SCRATCH_STATE + 3) == 0x04  # slot_index
