.include 'src/vwf.i'

; Long-form (RTL) wrapper for cross-bank callers and Python tests.
; Same calling convention as the RTS entry: A in/out, trashes A.
GetKerningAdjustmentLinearSearch_Ext:
    jsr.w GetKerningAdjustmentLinearSearch
    rtl

; trashes A, Y, flags. Preserves X (only register the caller relies on).
GetKerningAdjustmentLinearSearch:
    phx
    jsr.w _GetKerningAdjustmentLinearSearch
    plx
    rts

_GetKerningAdjustmentLinearSearch:
{
    ldy.w #0x1100
    lda.b [font_addr], y   ; right = NumKerningPairs
    beq _NotFound
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
    beq _FoundPair               ; Found exact match!

    txa
    dec
    tax

    bpl _loop

_NotFound:
    lda.w #0x0000
    sec
    rts

_FoundPair:
    iny
    iny
    lda.b [font_addr], y
    and.w #0x00FF
    clc
    rts
}

; Long-form (RTL) wrapper for cross-bank callers and Python tests.
GetKerningAdjustmentBinarySearch_Ext:
    jsr.w GetKerningAdjustmentBinarySearch
    rtl

; trashes A, Y, flags. Preserves X (only register the caller relies on).
GetKerningAdjustmentBinarySearch:
    phx
    jsr.w _GetKerningAdjustmentBinarySearch
    plx
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
    lda 0x0005, s          ; high
    cmp 0x0003, s          ; compare against low
    bcc _not_found         ; high < low -> no match

    lda 0x0005, s
    sec
    sbc 0x0003, s
    lsr
    clc
    adc 0x0003, s
    sta 0x0001, s          ; mid

    lda 0x0001, s
    asl
    clc
    adc 0x0001, s           ; mid * 3
    clc
    adc.w #0x1102
    tay

    lda.b [font_addr], y    ; load kerning key
    cmp.b CURRENT_C
    beq _found
    bcc _search_upper       ; table key < target -> raise low

_search_lower:
    lda 0x0001, s           ; mid - 1 becomes new high
    sec
    sbc.w #0x0001
    bcc _not_found          ; mid was 0, underflow → not found
    sta 0x0005, s
    bra _loop

_search_upper:
    lda 0x0001, s           ; mid + 1 becomes new low
    clc
    adc.w #0x0001
    sta 0x0003, s
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
    ply                     ; drop mid  (PLY/X preserve A)
    ply                     ; drop low
    ply                     ; drop high
    clc
    rts
}
