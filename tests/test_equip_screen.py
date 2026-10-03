"""Field equip screen: equipped item names in the VWF.

`DrawEquipItemName` ($01:9013) renders each equipped name through the
field VWF helper in its own caller context: the names borrow the drops
tile window ($16E.., idle outside the treasure popup) and its flush
descriptor, icon first, from col 20 past the six-cell slot labels.

The screen pushes several 4K tilemaps the frame it draws, so the CHR
flush can land after vblank; it has to wait for the next one instead of
being dropped.
"""
from __future__ import annotations

import pytest
from kintsuki import Button
from kintsuki.tilemap import read_bg_tilemap

from _ff4kintsuki import kss_path, load_emu_from_kss, tap

KSS = kss_path("ff4-before-field-inventory.kss")

CHR_BASE = 0x4000
CHR_BUFFER = 0x703000
EQUIP_TILES = range(0x16E, 0x16E + 6 * 10)
NAME_ROWS = (2, 4, 6, 8, 10)
NAME_COLS = range(20, 32)


@pytest.fixture(scope="module")
def equip_emu():
    e = load_emu_from_kss(KSS, settle_frames=60)
    tap(e, Button.DOWN, gap=20)
    tap(e, Button.DOWN, gap=20)
    tap(e, Button.A, gap=60)  # Equiper
    tap(e, Button.A, gap=120)  # first character
    yield e
    e.close()


def _bg2_cells(emu):
    tm = read_bg_tilemap(emu, 2)
    return [[tm.cell(r, c).tile for c in NAME_COLS] for r in NAME_ROWS]


def test_names_use_the_equip_tile_window(equip_emu):
    glyphs = {t for row in _bg2_cells(equip_emu) for t in row if t >= 0x100}
    assert glyphs and glyphs <= set(EQUIP_TILES)


def test_name_glyphs_reach_vram(equip_emu):
    glyphs = sorted({t for row in _bg2_cells(equip_emu) for t in row if t >= 0x100})
    stale = [
        t
        for t in glyphs
        if bytes(equip_emu.vram_read_range(CHR_BASE + t * 16, 16))
        != bytes(equip_emu.read(CHR_BUFFER + t * 16 + i) for i in range(16))
    ]
    assert stale == []
