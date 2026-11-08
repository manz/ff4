"""Every byte of the patch's SRAM state is written before it is read, from a cold boot.

The cart's battery SRAM keeps what the last power-off left there, or what an older build (another layout) wrote: a
read before our first write is junk on real hardware. The savestate tests can't see it (`clear_patch_sram` zeroes the
state, and kintsuki powers on clean), so this boots, loads a save and plays through (menus, a battle and its treasure
screen), tracking every patch SRAM byte written since the reset and recording any read of one that wasn't.
"""
from __future__ import annotations

from collections.abc import Callable, Iterator

import pytest
from _ff4kintsuki import (
    DROPS,
    PATCH_SRAM,
    PATCH_SRAM_LOW,
    enter_treasure_picker,
    kss_path,
    load_emu_from_kss,
    sram_junk,
    tap,
)
from kintsuki import Button, Emu

SAVE_ALLOWED = 0x7E1A02
MONSTERS = 0x7E2280  # 8 battle records of $80; current HP at +7
MONSTER_STRIDE = 0x80
MONSTER_HP = 7
SAVE_ROW = 7  # Sauver in the main menu
FORMATION, BATTLE_PENDING = 0x7E1800, 0x7E0685  # the field starts the battle in $1800 once $0685 is set
GOBLINS = 0x85


def _offset(address: int) -> int:
    return ((address >> 16) - 0x70) * 0x8000 + (address & 0x7FFF)


class UnwrittenReads:
    """Reads of patch SRAM bytes no write has reached since `arm`: address -> the reading PC."""

    def __init__(self, emu: Emu) -> None:
        self.emu = emu
        self.written = bytearray(0x10000)
        self.reads: dict[int, int] = {}
        for block in (PATCH_SRAM_LOW, PATCH_SRAM):
            emu.add_write_callback(block.start, block.stop - 1, self._write)
            emu.add_read_callback(block.start, block.stop - 1, self._read)

    def _write(self, address: int, _value: int) -> None:
        self.written[_offset(address)] = 1

    def _read(self, address: int, _value: int) -> None:
        if not self.written[_offset(address)] and address not in self.reads:
            self.reads[address] = self.emu.get_state().pc & 0xFFFFFF

    def describe(self) -> Iterator[str]:
        for address, pc in sorted(self.reads.items()):
            label = self.emu.lookup_label_containing(address)
            name = f"{label[0]}+{label[1]:#x}" if label else "?"
            yield f"${address:06X} {name} read at ${pc:06X}"


def _cold_boot(emu: Emu, seed: int) -> UnwrittenReads:
    """Junk our SRAM as a cart's battery may hold it, reset into the title screen and load the first save, tracking
    from the reset on."""
    for block in (PATCH_SRAM_LOW, PATCH_SRAM):
        emu.write_range(block.start, sram_junk(len(block), seed))
    emu.reset()
    reads = UnwrittenReads(emu)
    for step in range(40):
        emu.run_frames(30)
        if step % 3 == 2:
            tap(emu, Button.A, gap=2)
    assert emu.read(SAVE_ALLOWED), "not in the field of the loaded save"
    return reads


def _visit_menus(emu: Emu) -> None:
    tap(emu, Button.X, gap=60)
    tap(emu, Button.A, gap=60)  # Objets
    for _ in range(12):
        tap(emu, Button.DOWN, gap=6)
    tap(emu, Button.B, gap=60)
    for _ in range(SAVE_ROW):
        tap(emu, Button.DOWN, gap=10)
    tap(emu, Button.A, gap=90)  # Sauver
    for _ in range(3):  # back to the main menu, then the field (a B there does nothing)
        tap(emu, Button.B, gap=60)


def _monsters_alive(emu: Emu) -> int:
    """Monsters still standing, each brought down to 1 HP so the next hit ends it."""
    alive = 0
    for monster in range(8):
        hp = MONSTERS + monster * MONSTER_STRIDE + MONSTER_HP
        if emu.read(hp) | emu.read(hp + 1):
            emu.write(hp, 1)
            emu.write(hp + 1, 0)
            alive += 1
    return alive


def _win_a_battle(emu: Emu) -> None:
    """Fight goblins and win; the dev build's TREASURE_DEBUG_ALWAYS_DROP makes them drop, so the treasure screen
    comes up: scroll its exchange picker, then leave it for the field."""
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
    else:
        pytest.fail("the goblins never fell")
    for _ in range(12):  # the gil and experience messages
        if emu.read(DROPS):
            break
        emu.run_frames(50)
        tap(emu, Button.A, gap=40)
    else:
        pytest.fail("no treasure screen")
    enter_treasure_picker(emu, settle_frames=60)
    for _ in range(10):
        tap(emu, Button.DOWN, gap=6)
    tap(emu, Button.B, gap=40)  # back on the drops
    tap(emu, Button.B, gap=40)  # the top bar
    tap(emu, Button.RIGHT, gap=10)
    tap(emu, Button.A, gap=40)  # Quitter
    _wait(emu, lambda: emu.get_ppu_state().bgmode == field_mode, "never back in the field")
    emu.run_frames(60)


def _wait(emu: Emu, done: Callable[[], bool], failure: str) -> None:
    for _ in range(60):
        if done():
            return
        emu.run_frames(10)
    pytest.fail(failure)


@pytest.mark.parametrize("seed", [1, 2])
def test_patch_sram_is_written_before_it_is_read(seed: int) -> None:
    emu = load_emu_from_kss(kss_path("ff4-before-field-inventory.kss"), settle_frames=0)  # its saves in SRAM
    try:
        reads = _cold_boot(emu, seed)
        _visit_menus(emu)
        _win_a_battle(emu)
        _visit_menus(emu)
        assert not reads.reads, "patch SRAM read before any write:\n" + "\n".join(reads.describe())
    finally:
        emu.close()
