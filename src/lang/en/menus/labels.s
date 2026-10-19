"""The digest's LV/HP/MP in the French layout: level in the name row's slot, HP and MP a row lower."""


.alloc at 0x0189C3 size 47 {
    {
    level_offset = 7 * 2
    lda #0xFF
    sta.w 0 + level_offset, x
    sta.w 6 + level_offset, x
    lda #0x4D  ; L
    sta.w 2 + level_offset, x
    lda #0x57  ; V
    sta.w 4 + level_offset, x

    lda #0x51  ; P
    sta.w 0x82, x
    sta.w 0xC2, x
    lda #0x49  ; H
    sta.w 0x80, x
    lda #0x4E  ; M
    sta.w 0xC0, x
    lda #0xC7  ; /
    sta.w 0x4E + 0x40, x
    sta.w 0x8E + 0x40, x
    nop  ; up to vanilla's next instruction at $01:89F2
    nop
    nop
    }
}
