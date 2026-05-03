; Debug: force every battle to drop an item.
;
; Vanilla `WinUpdate` ($03:ED06) loads the drop chance into $B4, calls
; Rand99 ($03:858B), then `bcs $ED5F` (skip drop if random >= chance).
; NOP the BCS so any monster with a non-zero drop top-bit class still
; drops 100% of the time. Monsters with $00 in their drop-byte top bits
; (no drop entry) are still skipped earlier at $03:ED02 — those carry
; no drop table at all so forcing them would point at item 0 (empty).

.if TREASURE_DEBUG_ALWAYS_DROP {
    *=0x03ED0D
    nop
    nop
}
