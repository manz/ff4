"""
Debug patch (gated by `TREASURE_DEBUG_ALWAYS_DROP`, a816.toml: on in dev builds, off in `make release`) that forces
every battle to roll a successful drop by NOPing the random-roll gate at $03:ED0D.
"""

; Drop classes $40 / $80 / $C0 always drop. Class $00 exits earlier ($03:ED02) and stays so: forcing it pulls
; drop-table index 0 (empty), a "no item" prompt.

.if TREASURE_DEBUG_ALWAYS_DROP {
    .alloc at 0x03ED0D {
        nop
        nop
    }
}
