"""A field menu gives the map back whole: the item-description cache lived in the VRAM save window, so the menu
zeroed one saved word and closing it punched a black hole in the world map (b3 playtest, near Kaipo)."""
from __future__ import annotations

from kintsuki import Button

from _ff4kintsuki import kss_path, load_emu_from_kss, tap

MODE7_BYTES = 0x8000  # VRAM words $0000-$3FFF: the world map's tilemap and CHR, interleaved


def test_the_world_map_survives_a_menu() -> None:
    emu = load_emu_from_kss(kss_path("ff4-before-field-inventory.kss"), settle_frames=60)
    try:
        before = bytes(emu.vram_read_range(0, MODE7_BYTES))
        tap(emu, Button.X, gap=120)
        tap(emu, Button.B, gap=200)
        emu.run_frames(60)
        after = bytes(emu.vram_read_range(0, MODE7_BYTES))
    finally:
        emu.close()
    assert [hex(i) for i in range(MODE7_BYTES) if before[i] != after[i]] == []
