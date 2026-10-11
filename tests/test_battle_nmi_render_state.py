"""The battle NMI leaves the glyph renderer's state as it found it.

The rolling battle inventory renders item names from the NMI, in the middle of whatever the main thread draws. The
main thread's glyph blitter checks `bits_left_on_tile` (direct page) for the aligned case, then reloads it to index
its 8-entry shift table: an NMI render that left it at 8 sent the dispatch past the table into a BRK (betaplayer,
Potion on a monster). The NMI renderer now saves the glyph state and the tile allocator around its draw.
"""
from __future__ import annotations

import re
from pathlib import Path

from kintsuki import Button

from _ff4kintsuki import choose_command, kss_path, load_emu_from_kss, tap

ITEM = 0x01  # the Item command
CURSOR_TYPE = 0x7E1823  # 5: inventory
NMI_RTI = 0x0283E0  # vanilla battle NMI's rti
GLYPH_STATE = range(0x0000A9, 0x0000B3)  # bits_left_on_tile .. current_char
ALLOCATOR = range(0x702F00, 0x702F04)  # allocated_tile_id, slot_limit_low
ADBG = Path(__file__).resolve().parents[1] / "build/ff4.ips.adbg"


def _private(emu, name: str) -> int:
    """A module-private label's address: the .adbg keeps it under its scope's mangled name."""
    mangled = re.search(rb"__sc\d+__" + name.encode() + rb"\b", ADBG.read_bytes())
    assert mangled, f"{name} not in the .adbg"
    return emu.lookup_symbol_addr(mangled.group().decode())


def _state(emu) -> bytes:
    return bytes(emu.read(a) for a in (*GLYPH_STATE, *ALLOCATOR))


def test_the_nmi_render_keeps_the_glyph_state() -> None:
    emu = load_emu_from_kss(kss_path("ff4-battle-monsters-item.kss"), settle_frames=10)
    entered: list[bytes] = []
    changed: list[tuple[bytes, bytes]] = []
    renders = [0]

    def enter(*_) -> None:
        renders[0] += 1
        if not entered:
            entered.append(_state(emu))

    def leave(*_) -> None:
        if entered:
            before = entered.pop()
            if _state(emu) != before:
                changed.append((before, _state(emu)))

    emu.add_exec_callback(_private(emu, "_render_item_to_circular_slot"), _private(emu, "_render_item_to_circular_slot"),
                          enter)
    emu.add_exec_callback(NMI_RTI, NMI_RTI, leave)
    choose_command(emu, ITEM)
    for _ in range(60):
        if emu.read(CURSOR_TYPE) == 5:
            break
        emu.run_frames(2)
    for _ in range(24):  # scroll down the list: every new row is rendered from the NMI
        tap(emu, Button.DOWN, gap=4)
    emu.close()
    assert renders[0] > 0, "the inventory never rendered from the NMI"
    assert changed == []
