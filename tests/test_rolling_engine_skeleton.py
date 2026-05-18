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
