"""Battle-init smoke test.

Regression guard for the bank-20 relocation work: the `.alloc
bank20_modules` wrap once shifted bank-20 symbols so the engine hit BRK /
STP during the first battle redraw, while the build and IPS coverage
looked normal. This starts a fresh encounter from the world map, forces
every redraw gate dirty, lets the battle run, and asserts the CPU never
halted.

It also pins what the old full-screen golden was meant to catch: the
monster and character name windows draw real glyphs. A render-state byte
living inside the CHR buffer once left black name blocks for the whole
fight; here every name cell has to point at a non-empty VWF tile.
"""
from __future__ import annotations

import pytest
from kintsuki import Button

from _ff4kintsuki import kss_path, load_emu_from_kss, tap

KSS = kss_path("ff4-before-field-inventory.kss")

BATTLE_MENU_DIRTY = 0x7EEF9A  # bit 5 cmd window, bit 6 status, 0-4 char rows
BATTLE_MONSTER_DIRTY = 0x7EEF9B  # per-monster-slot name redraw
REGION_DIRTY_BITS = 0x707101  # BATTLE_RENDER_STATE + 1, slice-2 queue

# Battle VWF regions (src/battle/message.s): tile t is BG3 tile $100 + t,
# CHR at VRAM $B000; 48 tile ids per region.
VWF_CHR = 0xB000
REGION_SIZE = 48
MONSTER_NAMES = range(0x100 + REGION_SIZE * 1, 0x100 + REGION_SIZE * 2)
CHAR_NAMES = range(0x100 + REGION_SIZE * 2, 0x100 + REGION_SIZE * 3)


@pytest.fixture(scope="module")
def battle_emu():
    e = load_emu_from_kss(KSS, settle_frames=60)
    tap(e, Button.B, gap=20)
    for i in range(7):
        button = (Button.LEFT, Button.RIGHT)[i % 2]
        e.press(0, button)
        e.run_frames(40)
        e.release(0, button)
    e.run_frames(200)  # fresh encounter, first command menu up
    e.write(BATTLE_MENU_DIRTY, 0xFF)
    e.write(BATTLE_MONSTER_DIRTY, 0xFF)
    e.write(REGION_DIRTY_BITS, 0xFF)
    e.run_frames(600)
    yield e
    e.close()


def _bg3_tiles(emu) -> list[int]:
    base = (emu.get_ppu_state().bg3sc >> 2) << 10
    raw = bytes(emu.vram_read_range(base * 2, 0x1000))
    return [(raw[i] | raw[i + 1] << 8) & 0x3FF for i in range(0, len(raw), 2)]


def _blank_glyphs(emu, region: range) -> list[int]:
    used = sorted({t for t in _bg3_tiles(emu) if t in region})
    assert used, "no tilemap cell points into the region"
    return [t for t in used if not any(bytes(emu.vram_read_range(VWF_CHR + (t - 0x100) * 16, 16)))]


def test_battle_init_no_stp(battle_emu):
    s = battle_emu.get_state()
    assert s.stp == 0, (
        f"CPU halted via STP during battle init: PC=${s.pc:04X} PB=${s.b:02X} A=${s.a:04X}. "
        "The bank-20 reloc patch likely corrupted bank-02 code; check allocator or *= changes."
    )


def test_monster_names_draw_glyphs(battle_emu):
    assert _blank_glyphs(battle_emu, MONSTER_NAMES) == []


def test_char_names_draw_glyphs(battle_emu):
    assert _blank_glyphs(battle_emu, CHAR_NAMES) == []
