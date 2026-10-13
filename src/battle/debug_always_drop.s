"""
Debug patch (gated by `TREASURE_DEBUG_ALWAYS_DROP`, a816.toml: on in dev builds, off in `make release`) that forces
every battle to roll a successful drop by NOPing the random-roll gate at $03:ED0D.
"""

; NOP the random-roll gate at $03:ED0D so any monster with a non-zero
; drop class ($40 / $80 / $C0) always drops. Monsters with drop class
; $00 fall through earlier at $03:ED02. That path stays untouched:
; forcing it pulls drop-table index 0 (empty) and produces a "no item"
; treasure prompt instead of an actual drop.

.if TREASURE_DEBUG_ALWAYS_DROP {
    .alloc at 0x03ED0D {
    nop
    nop
    }
}
