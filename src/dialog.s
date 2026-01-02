
PointeurBank1de1:
    """Gets a 24bits pointer for bank 1-1"""
    rep #0x20
    lda.l assets_bank1_1_ptr, x
    sta.b dialog_ptr
    lda.w #0x0000
    sep #0x20
    lda.l assets_bank1_1_ptr + 2, x
    sta.b dialog_ptr + 2
    lda.b #0x01
    rtl

PointeurBank1de2:
    """
    Gets a 24bits pointer from bank 1-2

    > Note: the bank 1 of 1 is only 0x100 pointers long and not 0x200 as the text dump suggests.
    """
    rep #0x20
    lda.l assets_bank1_1_ptr + 0x300, x
    sta.b dialog_ptr
    lda.w #0x0000
    sep #0x20
    lda.l assets_bank1_1_ptr + 0x300 + 2, x
    sta.b dialog_ptr + 2
    lda #0x01
    rtl

; genuinely false

PointeurBank3:
    """
    Computes a ptr Npc dialogs, organized per room, then a linear
    lookup inside the room to find the start of the string.
    """
    rep #0x20
    lda.l dialog_bank_ptr_base + 0x600, x
    sta.b dialog_ptr
    lda.w #0x0000
    sep #0x20
    lda.l dialog_bank_ptr_base + 0x600 + 2, x
    sta.b dialog_ptr + 2
    lda #0x02
    rtl

CalculePositionTb:
    lda.b 0xB2
    sta.b dialog_ptr
    stz.b dialog_ptr + 1
    rep #0x20
    lda.b dialog_ptr
    clc
    asl
    adc.b dialog_ptr
    tax
    sep #0x20
    rtl

PointeurBank2:
{
    rep #0x20
    lda.b dialog_ptr
    asl
    clc
    adc.b dialog_ptr
    tax
    lda.l assets_bank2_ptr, x
    sta.b dialog_ptr
    lda.w #0x0000
    sep #0x20
    lda.l assets_bank2_ptr + 2, x
    sta.b dialog_ptr + 2
    ldx.b dialog_ptr
    lda.b 0xB2
    beq _FinBk2
    tay

    _LoopBk2:
    jsr.w ChargeLettreIncBk2
    bne _LoopBk2
    jsr.w ChargeLettreDecBk2
    pha
    jsr.w ChargeLettreIncBk2
    pla
    cmp #0x03
    beq _LoopBk2
    pha
    pla
    cmp #0x04
    beq _LoopBk2
    cmp #0xfe
    beq _LoopBk2
    dey
    bne _LoopBk2
    inx

    _FinBk2:
    stx.w 0x0772
    stz.b 0xDD
    rtl

    ChargeLettreDecBk2:
    ldx.b dialog_ptr
    dex
    bmi _OkBk2
    dec.b dialog_ptr + 2
    ldx.w #0xFFFF
    bra _OkBk2

    ChargeLettreIncBk2:
    ldx.b dialog_ptr
    inx
    bmi _OkBk2
    inc.b dialog_ptr + 2
    ldx.w #0x8000

    _OkBk2:
    stx.b dialog_ptr

    ChargeLettreBk2:
    ldx.b dialog_ptr
    phb
    lda.b dialog_ptr + 2
    pha
    plb
    lda.w 0x0000, x
    plb
    pha
    pla
    rts
}


incpointer:
{
    phx
    ldx.w 0x0772
    inx
    bne no_overflow
    inc.b dialog_ptr + 2
    ldx.w #0x8000

    no_overflow:
    stx.w 0x0772
    plx
    rts
}


ChargeLettreInc:
    """Read character from dialog, increment the pointer."""
{
    ldx.w 0x0772
    inx
    cpx.w #0x0000
    bne no_overflow
    inc.b dialog_ptr + 2
    ldx.w #0x8000

    no_overflow:
    stx.w 0x0772
}


ChargeLettre:
    """Peek a character from the dialog."""
    ldx.w 0x0772
    phb
    lda.b dialog_ptr + 2
    pha
    plb
    lda.b #0x00
    xba
    lda.b #0x00
    rep #0x20
    lda.w 0x0000, x
    sta.b CURRENT_C

    sep #0x20
    plb
    pha
    pla

    rts

