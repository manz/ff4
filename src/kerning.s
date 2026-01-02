
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

; trashes A
GetKerningAdjustmentBinarySearch:
    php
    phx
    phy
    jsr.w _GetKerningAdjustmentBinarySearch
    ply
    plx
    plp
    rts

_GetKerningAdjustmentBinarySearch:
{
    ldy.w #0x1100
    lda.b [font_addr], y   ; NumKerningPairs (16-bit)
    beq _return_zero

    sec
    sbc.w #0x0001          ; high = count - 1
    pha                    ; push high  (bottom)
    lda.w #0x0000
    pha                    ; push low   (middle)
    pea.w 0x0000           ; reserve mid slot (top)

_loop:
    lda 0x0004, s          ; high
    cmp 0x0002, s          ; compare against low
    bcc _not_found         ; high < low -> no match

    lda 0x0004, s
    sec
    sbc 0x0002, s
    lsr
    clc
    adc 0x0002, s
    sta 0x0000, s          ; mid

    lda 0x0000, s
    asl
    clc
    adc 0x0000, s           ; mid * 3
    clc
    adc.w #0x1102
    tay

    lda.b [font_addr], y    ; load kerning key
    cmp.b CURRENT_C
    beq _found
    bcc _search_upper       ; table key < target -> raise low

_search_lower:
    lda 0x0000, s           ; mid - 1 becomes new high
    sec
    sbc.w #0x0001
    sta 0x0004, s
    bra _loop

_search_upper:
    lda 0x0000, s           ; mid + 1 becomes new low
    clc
    adc.w #0x0001
    sta 0x0002, s
    bra _loop

_not_found:
    pla                     ; discard mid
    pla                     ; discard low
    pla                     ; discard high
_return_zero:
    lda.w #0x0000
    sec
    rts

_found:
    iny
    iny
    lda.b [font_addr], y
    and.w #0x00FF
    pla                     ; drop mid
    pla                     ; drop low
    pla                     ; drop high
    clc
    rts
}
