"""Baked monster names keep their first tile when the count column follows them.

The monster window's lines are 10 cells; a 10-tile baked name ended on a cell boundary, so the space and count glyphs
after it wrote their top row over the next line's first cell. Names now leave the renderer inside their last tile, as
the runtime renderer did.
"""
from __future__ import annotations

from _ff4kintsuki import kss_path, load_emu_from_kss, walk_into_battle

SECOND_NAME_FIRST_CELL = 0x7EBB5A  # "Mousse blanche" in ff4-before-field-inventory.kss's first battle
BLANK = 0xFF


def test_the_second_monster_name_keeps_its_first_tile():
    e = load_emu_from_kss(kss_path("ff4-before-field-inventory.kss"), settle_frames=60)
    try:
        walk_into_battle(e)
        e.run_frames(120)
        assert e.read(SECOND_NAME_FIRST_CELL) != BLANK
    finally:
        e.close()
