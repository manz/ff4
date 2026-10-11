"""
Monster AI fixes in vanilla's battle logic (bank $03).
"""

.import "preamble"
.import "vanilla"
.include "config.i"
.include "../bank20.i"

.if BATTLE_ENABLED {
; A monster whose script for the chosen condition is empty ($FF first) gets one "do nothing" command ($E1) in
; monster_action_commands, but no end: the walk at $03:B582 runs on through whatever the buffer held. Late in a
; session that is an older script's $FF; on a fresh boot (zeroed WRAM) it is zeros, each read as "cast spell 0"
; ($C2 00), a party cast animation that waits forever for a party sprite to step forward ($02:EA41).
    .alloc at 0x03B553 size 7 {
    jsr.l end_empty_monster_script
    bra _monster_script_built  ; $B56C, as vanilla
    nop
    }
    .label _monster_script_built = 0x03B56C

    .alloc _end_empty_monster_script in bank20_reloc {
end_empty_monster_script:
"""Vanilla's "do nothing" and an end after it. Y = the command index (0 here); A, X and P kept as vanilla needs."""
    php
    sep #0x20
    phx
    tyx
    lda.b #0xE1
    sta.l monster_action_commands, x
    lda.b #0xFF
    sta.l monster_action_commands + 1, x
    plx
    plp
    rtl
    }
}
