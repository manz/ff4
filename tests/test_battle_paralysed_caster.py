"""A monster paralysed (or asleep, dead, stone) after it queued a spell does nothing on its turn: vanilla turns its
command into "do nothing" ($03:B00D) but kept the spell's graphics script ($C2: the party cast animation), which waits
for a party sprite to step forward that never does ($02:EA41): the battle hung."""
from __future__ import annotations

from _ff4kintsuki import fresh_late_battle

MONSTER = 0x7E2280  # monster records, $80 each: status byte 2 at +4 (bit 5 paralysis), command at +$51
SCRIPTS = 0x7E3659  # each monster's graphics script for its next action, 60 bytes
CAST_SPELL = (0xC2, 0x00, 0xFF)  # cast spell 0, end
PARALYSED = 0x20
CAST_WAIT = 0x02EA41  # the party cast animation's wait for the caster's sprite


def test_a_paralysed_caster_does_not_hang_the_battle() -> None:
    emu = fresh_late_battle()
    try:
        waits = [0]
        emu.add_exec_callback(CAST_WAIT, CAST_WAIT, lambda *_: waits.__setitem__(0, waits[0] + 1))
        for frame in range(2400):
            # monster 0 keeps a queued spell (its command and script) and stays paralysed until its turn comes
            if frame % 30 == 0:
                emu.write(MONSTER + 0x51, CAST_SPELL[0])
                emu.write_range(SCRIPTS, bytes(CAST_SPELL))
                emu.write(MONSTER + 4, emu.read(MONSTER + 4) | PARALYSED)
            emu.run_frames(1)
        assert waits[0] < 1000
    finally:
        emu.close()
