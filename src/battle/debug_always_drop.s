"""
Debug patch (gated by `TREASURE_DEBUG_ALWAYS_DROP`) that forces every battle to roll a successful drop by
NOPing the random-roll gate at $03:ED0D.
"""
; Debug: force every battle to drop an item.
;

; NOP the random-roll gate at $03:ED0D so any monster with a non-zero
; drop class ($40 / $80 / $C0) always drops. Monsters with drop class
; $00 fall through earlier at $03:ED02 — that path stays untouched
; because forcing it pulls drop-table index 0 (empty) and produces an
; "no item" treasure prompt instead of an actual drop.

.include "config.i"
.if TREASURE_DEBUG_ALWAYS_DROP {
.alloc at 0x03ED0D {
        nop
        nop
}
}
