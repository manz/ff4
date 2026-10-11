"""The battle NMI leaves the glyph renderer's state as it found it.

The rolling battle inventory and the spell list's scroll hook render names from the NMI, in the middle of whatever
the main thread draws. The main thread's glyph blitter checks `bits_left_on_tile` (direct page) for the aligned
case, then reloads it to index its 8-entry shift table: an NMI render that left it at 8 sent the dispatch past the
table into a BRK (betaplayer, Potion on a monster). A spell name's tile clear ran to an end the NMI's own spell
render had moved behind it, through the whole CHR buffer into BATTLE_FLAGS: the next char dispatch jumped through
$FF into a BRK (betaplayer, Life 2 on a monster). The NMI renderers now save the glyph state and the tile allocator
around their draw, and the clear keeps its end on the stack.
"""
from __future__ import annotations

import re
from pathlib import Path

from _ff4kintsuki import choose_command, kss_path, load_emu_from_kss, tap, wait_for_turn
from kintsuki import Button

ITEM = 0x01  # the Item command
CURSOR_TYPE = 0x7E1823  # 5: inventory
NMI_RTI = 0x0283E0  # vanilla battle NMI's rti
GLYPH_STATE = range(0x0000A9, 0x0000B3)  # bits_left_on_tile .. current_char
ALLOCATOR = range(0x702F00, 0x702F04)  # allocated_tile_id, slot_limit_low
ADBG = Path(__file__).resolve().parents[1] / "build/ff4.ips.adbg"
BATTLE_FLAGS = 0x704F00  # right after the CHR buffer: indexes battle_display_dakuten_char's 4-entry table
ROSA_SLOT, WHITE_MAGIC = 3, 0x02  # ff4-late-field.kss: Rosa, a long white magic list
FORMATION, BATTLE_PENDING = 0x7E1800, 0x7E0685  # the field starts the battle in $1800 once $0685 is set


def _private(emu, name: str) -> int:
    """A module-private label's address: the .adbg keeps it under its scope's mangled name."""
    mangled = re.search(rb"__sc\d+__" + name.encode() + rb"\b", ADBG.read_bytes())
    assert mangled, f"{name} not in the .adbg"
    return emu.lookup_symbol_addr(mangled.group().decode())


def _state(emu) -> bytes:
    return bytes(emu.read(a) for a in (*GLYPH_STATE, *ALLOCATOR))


class _Watch:
    """At each entry to `renderer` (from the NMI), the glyph state; at the NMI's rti, whether it changed."""

    def __init__(self, emu, renderer: int) -> None:
        self.emu, self.renders, self.changed, self.bad_flags = emu, 0, [], set()
        self._entered: list[bytes] = []
        emu.add_exec_callback(renderer, renderer, self._enter)
        emu.add_exec_callback(NMI_RTI, NMI_RTI, self._leave)

    def _enter(self, *_) -> None:
        self.renders += 1
        if not self._entered:
            self._entered.append(_state(self.emu))

    def _leave(self, *_) -> None:
        if self.emu.read(BATTLE_FLAGS) > 3:
            self.bad_flags.add(self.emu.read(BATTLE_FLAGS))
        if self._entered:
            before = self._entered.pop()
            if _state(self.emu) != before:
                self.changed.append((before, _state(self.emu)))


def test_the_nmi_render_keeps_the_glyph_state() -> None:
    emu = load_emu_from_kss(kss_path("ff4-battle-monsters-item.kss"), settle_frames=10)
    watch = _Watch(emu, _private(emu, "_render_item_to_circular_slot"))
    choose_command(emu, ITEM)
    for _ in range(60):
        if emu.read(CURSOR_TYPE) == 5:
            break
        emu.run_frames(2)
    for _ in range(24):  # scroll down the list: every new row is rendered from the NMI
        tap(emu, Button.DOWN, gap=4)
    emu.close()
    assert watch.renders > 0, "the inventory never rendered from the NMI"
    assert watch.changed == []


def test_the_spell_scroll_render_keeps_the_glyph_state() -> None:
    emu = load_emu_from_kss(kss_path("ff4-late-field.kss"), settle_frames=10)  # a save room: no encounters
    emu.write(FORMATION, 0x85)  # two demon soldiers: they last until Rosa's turn
    emu.write(FORMATION + 1, 0x00)
    emu.write(BATTLE_PENDING, 1)
    wait_for_turn(emu, ROSA_SLOT)
    watch = _Watch(emu, emu.lookup_symbol_addr("spell_list_scroll_render"))
    choose_command(emu, WHITE_MAGIC)
    emu.run_frames(50)
    for _ in range(16):  # down the list and back: the rows sliding in render from the NMI
        tap(emu, Button.DOWN, gap=4)
    for _ in range(16):
        tap(emu, Button.UP, gap=4)
    emu.close()
    assert watch.renders > 0, "the spell list never scrolled"
    assert (watch.changed, watch.bad_flags) == ([], set())
