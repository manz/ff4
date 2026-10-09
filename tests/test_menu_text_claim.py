"""menu_text_vwf only takes ff4's own strings (bank $20, passed as string - $8000).

A vanilla string pointer (Y >= $8000, bank $01 text) can share its low 16 bits with a bank-$20 string block; the
magic screen's $01:B246 lands inside the newgame strings, and drawing it through the small VWF put "Cette partie?"
tiles on BG4 above the character window.
"""
from __future__ import annotations

import pytest

from _ff4kintsuki import kss_path, load_emu_from_kss

CARRY = 0x01


@pytest.fixture(scope="module")
def menu():
    e = load_emu_from_kss(kss_path("ff4-field-inventory-open.kss"), settle_frames=60)
    yield e, e.save_state()
    e.close()


def _claims(menu, y: int) -> bool:
    e, state = menu
    e.load_state(state)  # draw_pos returns through a BRK sentinel that ff4's brk_handler stops on
    return bool(e.call(e.lookup_symbol_addr("menu_text_vwf.draw_pos"), y=y, max_frames=5).p & CARRY)


def test_a_vanilla_pointer_is_left_to_vanilla(menu):
    assert not _claims(menu, 0xB246)


def test_an_ff4_string_is_drawn_in_the_vwf(menu):
    e, _ = menu
    assert _claims(menu, (e.lookup_symbol_addr("newgame.load_this_save") & 0xFFFF) - 0x8000)
