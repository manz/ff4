"""The battle status text is drawn when, and only when, a status it shows changes.

UpdateObjBuf copies each character's status bytes (`$7E:2003 + slot * $80`, bytes 1-4) into the battle-graphics
copy DrawStatusText draws from (`$7E:F015 + slot * 4`). Its copy now raises SIG_STATUS on a change
(battle/tasks_patches.s), and the status task, waiting on that signal, runs DrawStatusText. A change the copy misses
leaves the window stale; a signal without a change redraws for nothing.
"""
from __future__ import annotations

import pytest

from _ff4kintsuki import kss_path, load_emu_from_kss, walk_into_battle

CHAR_STATUS = 0x7E2003  # status byte 1 of the slot-0 character record
CHAR_RECORD = 0x80
WAIT_FRAME_MAIN = 0x028295  # one battle-graphics pass: RedrawMainMenu, then the tasks
PASSES = 6  # battle-graphics passes to run after a change


@pytest.fixture
def battle():
    e = load_emu_from_kss(kss_path("ff4-before-field-inventory.kss"), settle_frames=60)
    walk_into_battle(e)
    _passes(e, 12)  # past the opening: the status task has drawn once and waits
    draws = [0]
    task_draw = e.lookup_symbol_addr("draw_status_text_far")  # the status task's DrawStatusText; UpdateStatusTiles has its own
    e.add_exec_callback(task_draw, task_draw, lambda *_: draws.__setitem__(0, draws[0] + 1))
    yield e, draws
    e.close()


def _passes(emu, count: int) -> None:
    """Run `count` battle-graphics passes (a command menu waiting for input makes none)."""
    for _ in range(count):
        assert emu.run_until(WAIT_FRAME_MAIN, max_frames=600), "the battle loop stopped passing through WaitFrameMain"
        emu.step()


def _flip_status(emu, slot: int, byte: int, bits: int) -> None:
    address = CHAR_STATUS + slot * CHAR_RECORD + byte
    emu.write(address, emu.read(address) ^ bits)


def test_nothing_changes_nothing_is_drawn(battle) -> None:
    e, draws = battle
    _passes(e, PASSES)
    assert draws[0] == 0


@pytest.mark.parametrize("slot", [0, 1, 2, 3, 4])
def test_a_status_change_on_any_slot_redraws(battle, slot: int) -> None:
    e, draws = battle
    _flip_status(e, slot, 0, 0x01)
    _passes(e, PASSES)
    assert draws[0] >= 1


def test_a_change_in_the_fourth_status_byte_redraws(battle) -> None:
    e, draws = battle
    _flip_status(e, 0, 3, 0x01)
    _passes(e, PASSES)
    assert draws[0] >= 1


def test_two_slots_changing_together_draw_once(battle) -> None:
    e, draws = battle
    _flip_status(e, 0, 0, 0x01)
    _flip_status(e, 2, 0, 0x01)
    _passes(e, PASSES)
    assert draws[0] == 1
