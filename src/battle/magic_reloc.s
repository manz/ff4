"""
Relocated battle spell-list renderer (`draw_magic_list_direct`) and per-magic-type pointer table
(`magic_list_ptrs`).
"""
.extern assets_magic_dat
.extern draw_letter_far

battle_magic_length = 9
destination_buffer = 0xc530 - 4
left_column_base = destination_buffer - 4
right_column_base = destination_buffer + 18 - 2

draw_magic_list_direct:
"""Relocated battle spell-list renderer: walks the per-character spell-list pointer table."""
{
    spell_id = 0x03
    spell_enabled_flag = 0x02
    current_row_offset = 0x08
    spell_counter = 0x06
    current_spell_index = 0x0a
    lda 0x00
; character slot
    asl
    tax
    rep #0x20
    lda.l magic_list_ptrs, x
; pointers to spell lists
    clc
    adc 0x06
; add magic type offset
    sta 0x00
    stz.b current_row_offset
; start at row 0 (0x0000)
    sep #0x20
    lda #0x18
; 24 spells total (12 rows x 2 columns)
    sta.b spell_counter
; spell counter
    lda #0x00
; current spell index (0-23)
    sta.b current_spell_index

spell_loop:
    phx
    pha
    rep #0x20
    lda 0x00
    tax
    sep #0x20
    lda.w 0x0000, x
    and #0x80
    sta.b spell_enabled_flag
    lda.w 0x0001, x
    sta.b spell_id
    pla
    plx
; Fast column selection using precomputed addresses
    lda.b current_spell_index
; spell index
    and #0x01
; check if odd
    beq left_column
; Right column
    rep #0x20
    lda.w #right_column_base
    clc
    adc.b current_row_offset
; add current row offset
    sta 0x32
    bra set_second_addr

left_column:
; Left column
    rep #0x20
    lda.w #left_column_base
    clc
    adc.b current_row_offset
; add current row offset
    sta 0x32

set_second_addr:
    adc.w #0x0040
    sta 0x34
    sep #0x20
    ldy.w #0x00
; Y offset
    lda #0x00
; tile flags
    sta 0x36
    lda.b spell_enabled_flag
    beq enabled_spell
    lda #0x04
    sta 0x36

enabled_spell:
; Get spell ID and load spell name
    lda.b spell_id
; read spell ID
    rep #0x20
    and.w #0x007f
; clear disabled bit
    sep #0x20
    sta.l 0x004202
    lda.b #battle_magic_length
    sta.l 0x004203
    nop
    nop
    nop
    nop
    rep #0x20
    lda.l 0x004216
;     asl                 ; spell ID * 8 (8 bytes per name)
;     asl
;     asl
    tax
    sep #0x20
    lda.b #battle_magic_length
; 8 characters to write
    sta 0x02
; draw a space before rendering the magic name to clear left overs from the items.
    lda #0xff
    jsr.l draw_letter_far


letter_loop:
    lda.l assets_magic_dat, x
    jsr.l draw_letter_far
    inx
    dec 0x02
    bne letter_loop
    lda #0x0A
    sta 0x02

clear_loop:
    lda.b #0xff
    jsr.l draw_letter_far
    dec 0x02
    bne clear_loop

next_spell:
; Advance pointer by 4 bytes like original
    rep #0x20
    lda 0x00
    clc
    adc.w #0x0004
    sta 0x00
; Increment row offset after right column (odd spell index)
    lda.b current_spell_index
; current spell index
    and.w #0x0001
; check if odd (right column)
    beq same_row
; Just finished right column - move to next row
    lda.b current_row_offset
    clc
    adc.w #0x0080
    sta.b current_row_offset

same_row:
    sep #0x20
    inc 0x0a
; next spell index
    dec.b spell_counter
; decrement spell counter
    beq exit
    jmp.w spell_loop

exit:
    rtl
}

magic_list_ptrs:
"""Per-magic-type spell-list base pointers (white, black, summon, ninja, kokan)."""
    .dw 0x2c7a, 0x2d9a, 0x2eba, 0x2fda, 0x30fa
