"""The DrawStatusText redraw gate must see every status change it would draw.

Vanilla `DrawStatusText` draws each character's 32 status bits from the
battle-graphics copy at `$7E:F015 + slot * 4`, which the battle code
refreshes from the character records (`$7E:2003 + slot * $80`, status
bytes 1-4). `gate_status_check` sets carry when the status text needs a
redraw; a change it misses leaves the window stale. The battle redraw
path calls it from the `gate_draw_status_text` trampoline (about every 9
frames in this battle),
so these tests watch the carry it returns there. ff4.kss is a battle
with a 4-char party in slots 0, 2, 3 and 4.
"""
from __future__ import annotations

import pytest

from _ff4kintsuki import kss_path, load_emu_from_kss

CHAR_STATUS = 0x7E2003  # status byte 1 of the slot-0 character record
CHAR_RECORD = 0x80
CARRY = 0x01
JSL = 4  # bytes per `jsr.l`


@pytest.fixture
def emu():
    e = load_emu_from_kss(kss_path("ff4.kss"), settle_frames=10)
    yield e
    e.close()


def _gate_results(emu, calls: int) -> list[bool]:
    """Carry returned by the next `calls` gate checks the game makes."""
    trampoline = emu.lookup_symbol_addr("gate_draw_status_text")
    assert trampoline is not None
    after_gate = trampoline + 2 * JSL  # past the palette refresh and the gate call
    results = []
    for _ in range(calls):
        assert emu.run_until(after_gate, max_frames=20), "the redraw path stopped calling the gate"
        results.append(bool(emu.get_state().p & CARRY))
        emu.step()
    return results


def _set_status(emu, slot: int, byte: int, bits: int) -> None:
    address = CHAR_STATUS + slot * CHAR_RECORD + byte
    emu.write(address, emu.read(address) | bits)


def test_gate_stays_clean_when_nothing_changes(emu) -> None:
    _gate_results(emu, 2)
    assert not any(_gate_results(emu, 4))


@pytest.mark.parametrize("slot", [0, 2, 3, 4])
def test_status_change_on_any_present_slot_is_dirty(emu, slot: int) -> None:
    _gate_results(emu, 2)
    _set_status(emu, slot, 0, 0x01)
    assert any(_gate_results(emu, 4))


def test_status_change_in_the_second_status_byte_is_dirty(emu) -> None:
    _gate_results(emu, 2)
    _set_status(emu, 0, 1, 0x01)
    assert any(_gate_results(emu, 4))


def test_same_status_on_two_slots_in_one_frame_is_dirty(emu) -> None:
    _gate_results(emu, 2)
    _set_status(emu, 3, 0, 0x01)
    _set_status(emu, 4, 0, 0x01)
    assert any(_gate_results(emu, 4))
