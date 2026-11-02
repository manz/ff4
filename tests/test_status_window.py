"""The status window fills the screen: at vanilla's size the field menu's window edges showed around it (b3
playtest)."""
from __future__ import annotations

from kintsuki import Button
from kintsuki.tilemap import read_bg_tilemap

from _ff4kintsuki import kss_path, load_emu_from_kss, tap

CORNERS = {(0, 0): 0xF7, (0, 31): 0xF9, (27, 0): 0xFC, (27, 31): 0xFE}  # the window's corner tiles (BG1)


def test_the_status_window_fills_the_screen() -> None:
    emu = load_emu_from_kss(kss_path("ff4-before-field-inventory.kss"), settle_frames=60)
    try:
        tap(emu, Button.X, gap=150)
        for _ in range(3):
            tap(emu, Button.DOWN, gap=20)
        tap(emu, Button.A, gap=60)  # Statut
        tap(emu, Button.A, gap=150)  # first character
        tilemap = read_bg_tilemap(emu, 1)
        corners = {cell: tilemap.cell(*cell).tile & 0x3FF for cell in CORNERS}
    finally:
        emu.close()
    assert corners == CORNERS
