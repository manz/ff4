"""Phase 3 cleanup-on-exit contract: leaving a rolling-buffer menu must
zero the 12-byte state block, the HDMA shadow ($1BAE), and the channel
registers ($43xy) so the next menu mode starts from a clean slate.
"""
from __future__ import annotations

from kintsuki import Button

from _ff4kintsuki import (
    kss_path,
    load_emu_from_kss,
    enter_treasure_picker,
    tap,
)

FIELD_STATE_BASE = 0x7E1BA8
TREASURE_STATE_BASE = 0x7E9C00
HDMA_SHADOW = 0x7E1BAE
TREASURE_IN_MENU_FLAG = 0x7E1BC6
HDMA5_BASE = 0x004350
HDMA6_BASE = 0x004360


def _read_state(emu, base: int, n: int = 12) -> bytes:
    return bytes(emu.read(base + i) for i in range(n))


def _read_hdma_chan(emu, base: int, n: int = 5) -> bytes:
    return bytes(emu.read(base + i) for i in range(n))


def test_field_menu_exit_clears_state():
    e = load_emu_from_kss(kss_path("ff4-field-inventory-open.kss"))
    e.run_frames(60)
    # Scroll a bit so state is dirty before exit.
    for _ in range(3):
        tap(e, Button.DOWN)
    pre = _read_state(e, FIELD_STATE_BASE)
    assert any(b for b in pre), "expected non-zero state before exit"
    # Exit submenu (B back to top-level menu, then a few more to leave field menu).
    for _ in range(4):
        tap(e, Button.B, gap=20)
    e.run_frames(60)
    assert e.read(HDMA_SHADOW) == 0, "HDMA shadow should be cleared on exit"
    assert _read_state(e, FIELD_STATE_BASE) == bytes(12)
    assert _read_hdma_chan(e, HDMA5_BASE) == bytes(5)
    e.close()


def test_treasure_menu_exit_clears_state():
    e = load_emu_from_kss(kss_path("ff4-before-battle-inventory.kss"))
    enter_treasure_picker(e)
    for _ in range(3):
        tap(e, Button.DOWN)
    pre = _read_state(e, TREASURE_STATE_BASE)
    assert any(b for b in pre), "expected non-zero state before exit"
    # Back out: B leaves picker, second B leaves the treasure dialog entirely.
    for _ in range(4):
        tap(e, Button.B, gap=30)
    e.run_frames(60)
    assert e.read(HDMA_SHADOW) == 0
    assert e.read(TREASURE_IN_MENU_FLAG) == 0
    assert _read_state(e, TREASURE_STATE_BASE) == bytes(12)
    assert _read_hdma_chan(e, HDMA6_BASE) == bytes(5)
    e.close()
