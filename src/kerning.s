CharPair:= 0x08

; trashes A
GetKerningAdjustmentLinearSearch:
    php
    phx
    phy
    jsr.w _GetKerningAdjustmentLinearSearch
    ply
    plx
    plp
    rts

_GetKerningAdjustmentLinearSearch:
{
    ldy.w #0x1100
    lda.b [font_addr], y   ; right = NumKerningPairs
    beq NotFound
    dec
    tax
    lda.w #0x0000
_loop:
    txa
    pha
    asl
    clc
    adc 0x01, s
    clc
    adc.w #0x1102

    tay
    pla

    lda.b [font_addr], y ; Load 16-bit char pair
    cmp.b CURRENT_C
    beq FoundPair               ; Found exact match!

    txa
    dec
    tax

    bpl _loop

NotFound:
    lda.w #0x0000
    sec
    rts

FoundPair:
    iny
    iny
    lda.b [font_addr], y
    and.w #0x00FF
    clc
    rts
}


