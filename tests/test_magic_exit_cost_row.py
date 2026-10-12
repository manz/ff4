"""Leaving the magic screen clears its "Coût PM" row (ClearText, $01:8779) down to the tile bits.

Vanilla's ClearText stores the low bytes only: the small-VWF cells kept attribute bits 0-1 and showed tiles
$200-$3FF over the main menu's second character row ("MMMMMM:" on Rosa's PV and PM)."""
from __future__ import annotations

from _ff4kintsuki import kss_path, load_emu_from_kss, tap
from kintsuki import Button

COST_ROWS = 0x7EC600 + 0x20A  # BG buffer of the magic screen's top windows: the cost row's two rows
ROW_BYTES = 0x40 * 2
ROSA = 1


def _cost_rows(emu) -> bytes:
    return bytes(emu.read(COST_ROWS + i) for i in range(ROW_BYTES))


def test_the_main_menu_is_as_before_the_magic_screen() -> None:
    emu = load_emu_from_kss(kss_path("ff4-late-field.kss"), settle_frames=10)
    try:
        tap(emu, Button.X, gap=60)
        fresh = _cost_rows(emu)
        tap(emu, Button.DOWN, gap=16)
        tap(emu, Button.A, gap=60)  # Magie
        for _ in range(ROSA):
            tap(emu, Button.DOWN, gap=16)
        tap(emu, Button.A, gap=80)
        tap(emu, Button.B, gap=90)
        assert _cost_rows(emu) == fresh
    finally:
        emu.close()
