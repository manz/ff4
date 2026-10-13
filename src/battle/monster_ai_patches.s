"""
Monster AI fixes in vanilla's battle logic (bank $03).
"""

.import "core/preamble"
.import "core/vanilla"
.include "core/bank20.i"

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

; An attacker dead, stone, paralysed or asleep at its turn does nothing: vanilla ($03:B00D) puts "do nothing" in its
; command but not in its graphics script, so a monster that had queued a spell still plays it: $C2, the party cast
; animation, waits for a party sprite to step forward that never does ($02:EA41) and the battle hangs. The no-target
; path ($03:AF4E) writes both; this one now does too.
.alloc at 0x03B00D size 15 {
    jsl do_nothing_on_turn
    bra _execute_command  ; $B01C, as vanilla
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
}
.label _execute_command = 0x03B01C

.alloc _do_nothing_on_turn in bank20_reloc {
do_nothing_on_turn:
"""
Vanilla's "do nothing" for the attacker ($21 a character, $E1 a monster) in its command ($2051,X; X = $A6) and as its
whole graphics script ($33C2, then the end $FF), as $03:AF4E writes it. M = 8, X = 16, D = 0.
"""
    lda.b 0xD2  ; the attacker: 0-4 characters, 5- monsters
    cmp.b #0x05
    bcs _monster
    lda.b #0x21
    bra _store
_monster:
    lda.b #0xE1
_store:
    sta.l 0x7E2051, x
    sta.l 0x7E33C2
    lda.b #0xFF
    sta.l 0x7E33C3
    rtl
}
