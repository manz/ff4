"""
Dialog-text plumbing: 24-bit pointer resolver for translated bank 1-1/1-2/2 strings, used by the dialog VWF
parser to load the next message.
"""
.include "src/vwf.i"
.include "bank20.i"

.import "assets"
.import "vanilla"


.alloc _dialog_block in bank20_reloc {
get_bank1_1_pointer:
"""Get a 24-bit dialog pointer for bank 1-1."""
    rep #0x20
    lda.l dialog_pointers, x
    sta.b dialog_ptr
    lda.w #0x0000
    sep #0x20
    lda.l dialog_pointers + 2, x
    sta.b dialog_ptr + 2
    lda.b #0x01
    rtl

get_bank1_2_pointer:
"""
    Get a 24-bit dialog pointer for bank 1-2.

    > Note: bank 1-1 is only 0x100 pointers long, not 0x200 as the text dump suggests.
"""


    rep #0x20
    lda.l dialog_pointers + 0x300, x
    sta.b dialog_ptr
    lda.w #0x0000
    sep #0x20
    lda.l dialog_pointers + 0x300 + 2, x
    sta.b dialog_ptr + 2
    lda #0x01
    rtl

get_bank3_pointer:
"""
    Compute pointer for NPC dialogs.

    Organized per room  ; a linear lookup inside the room finds the start of the string.
"""


    rep #0x20
    lda.l dialog_pointers + 0x600, x
    sta.b dialog_ptr
    lda.w #0x0000
    sep #0x20
    lda.l dialog_pointers + 0x600 + 2, x
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
    lda.l dialog_bank2_pointers, x
    sta.b dialog_ptr
    lda.w #0x0000
    sep #0x20
    lda.l dialog_bank2_pointers + 2, x
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
    stx.w dialog_text_ptr
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
    ldx.w dialog_text_ptr
    inx
    bne _no_overflow
    inc.b dialog_ptr + 2
    ldx.w #0x8000

_no_overflow:
    stx.w dialog_text_ptr
    plx
    rts
    }


load_letter_inc:
"""Advance dialog cursor by one character."""
    {
    ldx.w dialog_text_ptr
    inx
    cpx.w #0x0000
    bne _no_overflow
    inc.b dialog_ptr + 2
    ldx.w #0x8000

_no_overflow:
    stx.w dialog_text_ptr
    }


load_letter:
"""Peek the current character from the dialog stream into CURRENT_C."""
    ldx.w dialog_text_ptr
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
}
