"""Two spells learned at one level up each show once, and the battle ends.

Vanilla's level-up loop ($03:EFDE) walks the learned spells with an index in $AF and shows one message per spell; the
battle VWF kept its glyph counter at the same direct-page byte, so every message set the index back and the second
spell repeated forever (b3 playtest, 271103 #005: « Cochon appris ! » in a loop). Palom, level 10 in this savestate,
learns $21 and $1A on reaching level 11.
"""
from __future__ import annotations

from kintsuki import Button

from _ff4kintsuki import BATTLE_CHARS, kss_path, load_emu_from_kss, tap, walk_into_battle, wait_for_turn

KSS = kss_path("ff4-twins-field.kss")
PALOM_SLOT, POROM_SLOT = 1, 2
EXP = 0x37  # total experience, 3 bytes, in the battle record (128 bytes per slot)
HP = 0x07
MONSTER_SLOTS = range(5, 13)
MESSAGE = 0x7E34CA  # battle message id; $23 = "<spell> appris !"
MESSAGE_ARG = 0x7E359A  # its spell
SPELL_LEARNED = 0x23
LEVEL_UP = 0x21  # "<name> passe au niveau supérieur !"


def _shown_spells() -> list[int]:
    emu = load_emu_from_kss(KSS, settle_frames=10)
    walk_into_battle(emu)
    wait_for_turn(emu, 0)
    for slot in MONSTER_SLOTS:
        record = BATTLE_CHARS + slot * 0x80
        if emu.read16(record + HP):
            emu.write(record + HP, 1)
            emu.write(record + HP + 1, 0)
    for slot in (PALOM_SLOT, POROM_SLOT):  # enough for two levels
        emu.write_range(BATTLE_CHARS + slot * 0x80 + EXP, (4000).to_bytes(3, "little"))
    shown: list[int] = []
    # The level-up message ($21) writes its slot to the same argument before its id: drop it when the id follows.
    emu.add_write_callback(MESSAGE_ARG, MESSAGE_ARG,
                           lambda _a, v: shown.append(v) if emu.read(MESSAGE) == SPELL_LEARNED else None)
    emu.add_write_callback(MESSAGE, MESSAGE, lambda _a, v: shown.pop() if v == LEVEL_UP and shown else None)
    for _ in range(300):
        tap(emu, Button.A, gap=6)
        if len(shown) > 8 or emu.get_ppu_state().bgmode == 7:  # back on the world map
            break
    emu.close()
    return shown


def test_each_learned_spell_shows_once() -> None:
    shown = _shown_spells()
    assert shown[:2] == [0x21, 0x1A]
    assert len(shown) == len(set(shown)), f"a spell message repeated: {[hex(s) for s in shown]}"
