"""Battle-init smoke test.

Regression guard for the bank-20 relocation work. The
`.alloc bank20_modules` wrap (overflow Q#13 / Q#14 era) shifted bank-20
symbol addresses in a way that caused the engine to BRK / STP during
battle redraw on the first menu interaction. The build still succeeded
and the IPS coverage looked normal, so a pure build-side check would
have missed it. This test boots the patched ROM into a battle-running
savestate, lets a few frames settle, asserts the CPU never halted, and
records a PNG golden of the framebuffer.

Recorded once via UPDATE_GOLDENS=1; replays as a pixel-match thereafter.
"""
from __future__ import annotations

from pathlib import Path

import pytest

from _ff4kintsuki import (
    assert_screenshot_matches_golden,
    kss_path,
    load_emu_from_kss,
)

GOLDENS = Path(__file__).parent / "goldens" / "battle_init"
KSS = kss_path("ff4-battle-ext.kss")


@pytest.fixture
def battle_emu():
    emu = load_emu_from_kss(KSS, settle_frames=0)
    # Force every redraw gate dirty before settling so the smoke test
    # exercises DrawCharNames / DrawMonsterNames / DrawCmdWindow on the
    # first frame. Without this the slice-2 gates stay clean (the gate
    # state only re-arms on writer-side state changes like ATB rotation
    # or HP delta) and the golden captures an empty header strip.
    emu.write(0x7EEF9A, 0xFF)  # battle_menu_dirty: all chars + cmd + status
    emu.write(0x7EEF9B, 0xFF)  # battle_monster_dirty: all monster slots
    emu.write(0x703F01, 0xFF)  # region_dirty_bits: slice-2 queue (moved past inventory tiles)
    emu.run_frames(600)
    yield emu
    emu.close()


def test_battle_init_no_stp(battle_emu):
    """If the CPU executed STP during the settle frames, the patch is
    broken: the BRK trap (or any rogue opcode) halted the emulator.
    Catches the bank20_modules wrap regression that fired
    `brk_handler -> STP` from $02:A455 during DrawText."""
    s = battle_emu.get_state()
    assert s.stp == 0, (
        f"CPU halted via STP during battle init: PC=${s.pc:04X} "
        f"PB=${s.b:02X} A=${s.a:04X}. The bank-20 reloc patch likely "
        "corrupted bank-02 code; check `git log -- ff4.s` for recent "
        "allocator or *= changes."
    )


def test_battle_init_screen_golden(battle_emu):
    """Pixel-match the framebuffer 600 frames into the battle state.
    Sensitive to any rendering regression that survives the no-STP
    check (garbled tiles, wrong palette, broken text)."""
    assert_screenshot_matches_golden(battle_emu, GOLDENS / "battle_init.png")
