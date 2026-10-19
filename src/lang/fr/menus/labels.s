"""Vanilla's English 8x8 labels in French: the digest's NV/PV/PM, RVB in the options, PM in battle's MP cost window."""


; Level, HP, MP: NV, PV, PM, HP and MP a row lower
.alloc at 0x0189C3 size 47 {
    {
    level_offset = 7 * 2
    lda #0xFF
    sta.w 0 + level_offset, x
    lda #0x4F  ; N
    sta.w 2 + level_offset, x
    lda #0x57  ; V
    sta.w 4 + level_offset, x
    lda #0xFF
    sta.w 6 + level_offset, x
    nop

    lda #0x57  ; H 49 V 57
    sta.w 0x40 + 2 + 0x40, x
    lda #0x51  ; P
    sta.w 0x42 - 2 + 0x40, x
    sta.w 0x82 - 2 + 0x40, x
    lda #0x4E  ; M
    sta.w 0x80 + 2 + 0x40, x
    lda #0xC7  ; /
    sta.w 0x4E + 0x40, x
    sta.w 0x8E + 0x40, x
    }
}
; RGB -> RVB
.alloc at 0x01D1BB {
    lda.b #0x57
}
; MP cost window: small "MP" swapped to "PM"
.alloc at 0x02a1e3 {
    lda #0xdc
    sta 0xba94, y
    dec
    sta 0xba96, y
}
