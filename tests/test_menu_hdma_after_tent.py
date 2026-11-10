"""The field menus' shared HDMA enable (`field_menu_rolling.hdma_enable`, written to HDMAEN by their NMI) after a
Tente used from Objets.

The Tente closes the whole menu through InitMainMenu's saved stack, past Objets' exit hook: its channel 5 stayed set.
The treasure screen after the next battle ORs its own channels into the byte, so channel 5 ran there too, with
whatever its registers held: holes in the names and a staircase down the border (Analogue Pocket, Super NT).
"""
from __future__ import annotations

from _ff4kintsuki import DROPS, kss_path, load_emu_from_kss, tap
from kintsuki import Button
from test_sram_boot_init import (
    BATTLE_PENDING,
    FORMATION,
    GOBLINS,
    _monsters_alive,
    _wait,
)

INVENTORY = 0x7E1440  # item id, count: 2 bytes a slot
TENT = 0xE2
SAVE_ENABLED = 0x7E1A02  # set on save points: where a Tente can be used
HDMA_ENABLE = 0x7E9C96
OBJETS_CHANNEL = 0x20  # channel 5, the field item list's scroll


def test_the_treasure_screen_runs_no_hdma_left_by_a_tent() -> None:
    emu = load_emu_from_kss(kss_path("ff4-before-field-inventory.kss"), settle_frames=60)
    try:
        emu.write(INVENTORY, TENT)
        emu.write(INVENTORY + 1, 1)
        emu.write(SAVE_ENABLED, 1)
        tap(emu, Button.X, gap=60)
        tap(emu, Button.A, gap=60)  # Objets
        for _ in range(3):
            tap(emu, Button.A, gap=60)  # the Tente, used: the party rests on the field
        emu.run_frames(900)
        field_mode = emu.get_ppu_state().bgmode
        emu.write(FORMATION, GOBLINS)
        emu.write(FORMATION + 1, 0x00)
        emu.write(BATTLE_PENDING, 1)
        _wait(emu, lambda: emu.get_ppu_state().bgmode != field_mode, "no battle started")
        emu.run_frames(120)
        for _ in range(100):
            if not _monsters_alive(emu):
                break
            tap(emu, Button.A, gap=4)
        for _ in range(12):  # the gil and experience messages
            if emu.read(DROPS):
                break
            tap(emu, Button.A, gap=40)
        emu.run_frames(200)
        assert emu.read(HDMA_ENABLE) & OBJETS_CHANNEL == 0
    finally:
        emu.close()
