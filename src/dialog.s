.include "src/vwf.i"

.extern assets_bank1_1_ptr
.extern assets_bank2_ptr
.extern dialog_bank_ptr_base

get_bank1_1_pointer:
    """Get a 24-bit dialog pointer for bank 1-1."""
    rep #0x20
    lda.l assets_bank1_1_ptr, x
    sta.b dialog_ptr
    lda.w #0x0000
    sep #0x20
    lda.l assets_bank1_1_ptr + 2, x
    sta.b dialog_ptr + 2
    lda.b #0x01
    rtl

get_bank1_2_pointer:

    """
    Get a 24-bit dialog pointer for bank 1-2.

    > Note: bank 1-1 is only 0x100 pointers long, not 0x200 as the text dump suggests.
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

get_bank3_pointer:

    """
    Compute pointer for NPC dialogs.

    Organized per room                  ; a linear lookup inside the room finds the start of the string.
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

compute_dialog_text_offset:
    """Compute index into dialog pointer table from current text id ($B2)."""
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

get_bank2_pointer:

    """
    Get a 24-bit dialog pointer for bank 2.

    Walks the string character-by-character to handle variable-length encoding.
    """
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
    beq _end
    tay

    _loop:
    jsr.w _load_letter_inc
    bne _loop
    jsr.w _load_letter_dec
    pha
    jsr.w _load_letter_inc
    pla
    cmp #0x03
    beq _loop
    pha
    pla
    cmp #0x04
    beq _loop
    cmp #0xfe
    beq _loop
    dey
    bne _loop
    inx

    _end:
    stx.w 0x0772
    stz.b 0xDD
    rtl

    _load_letter_dec:
    ldx.b dialog_ptr
    dex
    bmi _ok
    dec.b dialog_ptr + 2
    ldx.w #0xFFFF
    bra _ok

    _load_letter_inc:
    ldx.b dialog_ptr
    inx
    bmi _ok
    inc.b dialog_ptr + 2
    ldx.w #0x8000

    _ok:
    stx.b dialog_ptr

    _load_letter:
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


_incpointer:
{
    phx
    ldx.w 0x0772
    inx
    bne _no_overflow
    inc.b dialog_ptr + 2
    ldx.w #0x8000

    _no_overflow:
    stx.w 0x0772
    plx
    rts
}


load_letter_inc:
    """Advance dialog cursor by one character."""
{
    ldx.w 0x0772
    inx
    cpx.w #0x0000
    bne _no_overflow
    inc.b dialog_ptr + 2
    ldx.w #0x8000

    _no_overflow:
    stx.w 0x0772
}


load_letter:
    """Peek the current character from the dialog stream into CURRENT_C."""
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

