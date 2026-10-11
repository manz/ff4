"""A monster with nothing to do for its condition ends its command list.

Vanilla's monster action builder ($03:B53A) writes "do nothing" ($E1) for an empty script ($FF first) but no end
after it, so its walk ($03:B582) reads on through whatever the buffer held: zeros on a fresh boot, each turned into
"cast spell 0", a party cast animation that waits forever for a party sprite to step forward ($02:EA41).
"""
from __future__ import annotations

from _ff4kintsuki import kss_path, load_emu_from_kss

COMMANDS = 0x7E361D  # monster_action_commands
EMPTY_SCRIPT_PATH = 0x03B553  # vanilla's "do nothing" write


def test_an_empty_script_writes_do_nothing_and_its_end() -> None:
    emu = load_emu_from_kss(kss_path("ff4-battle-monsters-item.kss"), settle_frames=1)
    try:
        for i in range(8):
            emu.write(COMMANDS + i, 0x00)  # a fresh boot's buffer
        assert bytes(emu.read(EMPTY_SCRIPT_PATH + i) for i in range(4))[0] == 0x22, "the path calls the fix (jsl)"
        emu.call(emu.lookup_symbol_addr("end_empty_monster_script"), y=0, max_frames=1)
        assert bytes(emu.read(COMMANDS + i) for i in range(2)) == b"\xe1\xff"
    finally:
        emu.close()
