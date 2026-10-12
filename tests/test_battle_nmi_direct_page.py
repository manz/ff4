"""The battle NMI's VWF transfers (battle/message.s `dma_transfer`, called at $02:836E) keep the main loop's direct
page: the NMI lands anywhere in it, and the inventory CHR upload staged its addresses in $0A-$0D, wiping the monster
draw's type index (a zero-width block, then 64K words written over RAM and a crash)."""
from __future__ import annotations

from _ff4kintsuki import fresh_late_battle
from _rolling_state import addr

HOOK, RETURN = 0x02836E, 0x028372  # jsl messages_vwf.dma_transfer, the instruction after it
SCRATCH = range(0x00, 0x0E)  # $0E is vanilla's own NMI scratch (its transfers set it)
INVENTORY_SLOTS = 0x3F  # dma_dirty_slots: every inventory CHR slice pending


def test_the_vwf_transfers_leave_the_direct_page() -> None:
    emu = fresh_late_battle()
    try:
        dirty = addr("battle_render_state", "dma_dirty_slots")
        before: list[bytes] = []
        changed: list[tuple[bytes, bytes]] = []

        def at_hook(*_) -> None:
            before.append(bytes(emu.read(a) for a in SCRATCH))

        def at_return(*_) -> None:
            after = bytes(emu.read(a) for a in SCRATCH)
            if before and after != before[-1]:
                changed.append((before[-1], after))

        emu.add_exec_callback(HOOK, HOOK, at_hook)
        emu.add_exec_callback(RETURN, RETURN, at_return)
        for _ in range(30):
            emu.write(dirty, INVENTORY_SLOTS)
            emu.run_frames(1)
        assert before
        assert changed == []
    finally:
        emu.close()
