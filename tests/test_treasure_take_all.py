"""Tout prendre empties the drops window on screen, colon and count included.

The drops draw into BG4's buffer ($7E:C600); the redraw after Tout prendre ($01:D929) only sent BG1 and BG3, so
the emptied rows kept ": 1" in VRAM.
"""
from __future__ import annotations

from _ff4kintsuki import kss_path, load_emu_from_kss
from kintsuki import Button

BG4_TILEMAP = 0x7800 * 2  # VRAM byte address
COLON = 0xC8
DROPS_ROWS = range(2, 12)  # the drops window's rows, under the Butin / Tout prendre bar


def _colons(e) -> int:
    tilemap = bytes(e.vram_read_range(BG4_TILEMAP, 0x800))
    cells = [tilemap[i] | (tilemap[i + 1] & 3) << 8 for i in range(0, len(tilemap), 2)]
    return sum(cells[row * 32 + col] == COLON for row in DROPS_ROWS for col in range(32))


def test_tout_prendre_clears_the_colons():
    e = load_emu_from_kss(kss_path("ff4-before-battle-inventory.kss"), settle_frames=600)
    try:
        assert _colons(e) > 0  # the drops are listed
        e.press(0, Button.A)
        e.run_frames(6)
        e.release(0, Button.A)
        e.run_frames(60)
        assert _colons(e) == 0
    finally:
        e.close()
