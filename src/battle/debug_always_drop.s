; Debug: force every battle to drop an item.
;

; Two patches into `WinUpdate`:
;
;   1. $03:ECF6 `beq $ED0F` (drop-class $C0 = guaranteed) → `bra $ED0F`,
;      so every monster takes the guaranteed-drop path regardless of its
;      drop-class top bits.
;   2. $03:ED0D `bcs $ED5F` (random roll skip) → NOP NOP, in case the
;      BRA is ever reverted but the random gate still needs disabling.
;
; The drop table index still uses the monster's drop-byte low 6 bits, so
; truly drop-less monsters will pull whatever item lives at table index 0.

.if TREASURE_DEBUG_ALWAYS_DROP {
    *=0x03ECF6
    .db 0x80
    *=0x03ED0D
    nop
    nop
}
