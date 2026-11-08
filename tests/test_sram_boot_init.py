"""Every byte of the patch's SRAM state is written before it is read, from a cold boot.

The cart's battery SRAM keeps what the last power-off left there, or what an older build (another layout) wrote: a
read before our first write is junk on real hardware. The savestate tests can't see it (`clear_patch_sram` zeroes the
state, and kintsuki powers on clean), so this boots, loads a save and plays through, tracking every patch SRAM byte
written since the reset and recording any read of one that wasn't.
"""
from __future__ import annotations

from collections.abc import Iterator

import pytest
from _ff4kintsuki import (
    PATCH_SRAM,
    PATCH_SRAM_LOW,
    kss_path,
    load_emu_from_kss,
    sram_junk,
    tap,
    walk_into_battle,
)
from kintsuki import Button, Emu

SAVE_ALLOWED = 0x7E1A02
MONSTERS = 0x7E2280  # 8 battle records of $80; current HP at +7
MONSTER_STRIDE = 0x80
MONSTER_HP = 7
SAVE_ROW = 7  # Sauver in the main menu


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


def _win_a_battle(emu: Emu) -> None:
    """Walk into a battle and win it: every monster down to 1 HP, then attack until the field is back."""
    field_mode = emu.get_ppu_state().bgmode
    walk_into_battle(emu)
    emu.run_frames(120)
    for _ in range(400):
        for monster in range(8):
            hp = MONSTERS + monster * MONSTER_STRIDE + MONSTER_HP
            if emu.read(hp) | emu.read(hp + 1):
                emu.write(hp, 1)
                emu.write(hp + 1, 0)
        tap(emu, Button.A, gap=4)
        if emu.get_ppu_state().bgmode == field_mode:
            break
    else:
        pytest.fail("the battle never ended")
    emu.run_frames(200)


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
