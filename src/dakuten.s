"""
Dakuten composite-glyph table + `lookup_dakuten` helper that maps a (prev_char, current_char) pair to the
dakuten/handakuten composite tile pair.
"""


.incbin "assets/dakuten.bin"

lookup_dakuten:
"""
input: A 8bit: current char
output: A 16bits: the resolved char
"""
{
    php
    sep #0x20
    cmp.l assets_dakuten_bin
    bmi _char_out_of_range
    cmp.l assets_dakuten_bin + 2
    bpl _char_out_of_range

    phx
    rep #0x20
    and.w #0x00ff
    sec
    sbc.l assets_dakuten_bin
    asl
    tax

    lda.l assets_dakuten_bin + 4, x

    sep #0x20
    plx
    bra _exit
_char_out_of_range:
    xba
    lda #0xff

_exit:
    plp
    rtl
}

_store_char_with_dakuten:
{
    jsr.l lookup_dakuten
    cmp #0xff
    beq _skip
    sta.l 0x7E0000, x
_skip:

    sta.l 0x7E0040, x

;0187A9  9F 00 00 7E    STA $7E0000,X
;0187AD  E8             INX
;0187AE  E8             INX
;0187AF  C8             INY
    rtl
}
