.include "src/vwf.i"

dialog_get_kerning_adjustment_binary_search_ext:
"""Long-form (RTL) wrapper around `dialog_get_kerning_adjustment_binary_search` for cross-bank callers and Python tests."""
    jsr.w dialog_get_kerning_adjustment_binary_search
    rtl


dialog_get_kerning_adjustment_binary_search:
"""Binary-search the dialog font's kerning table for the pair in DP $25 (CURRENT_C)  ; returns adjustment in A or A=0+sec on miss. Trashes A/Y/flags, preserves X."""
    phx
    jsr.w _dialog_get_kerning_adjustment_binary_search
    plx
    rts

_dialog_get_kerning_adjustment_binary_search:
{
    ldy.w #0x1100
    lda.b [font_addr], y  ; NumKerningPairs (16-bit)
    beq _return_zero

    sec
    sbc.w #0x0001  ; high = count - 1
    pha  ; push high  (bottom)
    lda.w #0x0000
    pha  ; push low   (middle)
    pea.w 0x0000  ; reserve mid slot (top)

_loop:
    lda 0x0005, s  ; high
    cmp 0x0003, s  ; compare against low
    bcc _not_found  ; high < low -> no match

    lda 0x0005, s
    sec
    sbc 0x0003, s
    lsr
    clc
    adc 0x0003, s
    sta 0x0001, s  ; mid

    lda 0x0001, s
    asl
    clc
    adc 0x0001, s  ; mid * 3
    clc
    adc.w #0x1102
    tay

    lda.b [font_addr], y  ; load kerning key
    cmp.b CURRENT_C
    beq _found
    bcc _search_upper  ; table key < target -> raise low

_search_lower:
    lda 0x0001, s  ; mid - 1 becomes new high
    sec
    sbc.w #0x0001
    bcc _not_found  ; mid was 0, underflow → not found
    sta 0x0005, s
    bra _loop

_search_upper:
    lda 0x0001, s  ; mid + 1 becomes new low
    clc
    adc.w #0x0001
    sta 0x0003, s
    bra _loop

_not_found:
    pla  ; discard mid
    pla  ; discard low
    pla  ; discard high
_return_zero:
    lda.w #0x0000
    sec
    rts

_found:
    iny
    iny
    lda.b [font_addr], y
    and.w #0x00FF
    ply  ; drop mid  (PLY/X preserve A)
    ply  ; drop low
    ply  ; drop high
    clc
    rts
}
