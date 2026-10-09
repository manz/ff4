"""The item target window keeps its names on their small-VWF tiles.

Vanilla SetTextColor ($01:8C47) stored the palette byte whole into each cell's attribute, clearing the tile-id bits
8-9: the names at tiles $300+ showed the 8x8 font's tiles $0xx instead.
"""
from __future__ import annotations

from _ff4kintsuki import kss_path, load_emu_from_kss, tap
from kintsuki import Button

FIRST_NAME_CELL = 0x7EA600 + (7 * 32 + 16) * 2  # the target window's first name, in its tilemap buffer
NAME_TILES = 0x300


def test_target_window_names_keep_their_tiles():
    e = load_emu_from_kss(kss_path("ff4-before-field-inventory.kss"), settle_frames=60)
    try:
        tap(e, Button.X, gap=60)
        tap(e, Button.A, gap=60)
        for _ in range(4):  # Plume de phénix: usable on a character
            tap(e, Button.DOWN, gap=15)
        tap(e, Button.A, gap=20)
        tap(e, Button.A, gap=60)
        tile = e.read(FIRST_NAME_CELL) | (e.read(FIRST_NAME_CELL + 1) & 0x03) << 8
        assert tile >= NAME_TILES
    finally:
        e.close()
