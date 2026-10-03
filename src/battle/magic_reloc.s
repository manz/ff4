"""
.include "../bank20.i"

Relocated battle spell-list renderer (`draw_magic_list_direct`) and per-magic-type pointer table
(`magic_list_ptrs`).
"""


.extern messages_vwf.spell_list_begin
.extern messages_vwf.draw_spell_name
.extern messages_vwf.spell_list_end

.scope battle_render {
    """Render-state bytes shared with the battle items window."""
    .include "render_defs.i"
}

; Spell name length in assets_magic_dat; magic/patches.s imports it too.
battle_magic_length = battle_render.SPELL_NAME_LENGTH
destination_buffer = 0xc530 - 4
left_column_base = destination_buffer - 4
right_column_base = destination_buffer + 18 - 2
; Window frame in the BG3 page-1 menu buffer: row 1 starts at $7E:C526,
; 64 bytes per row. Spell rows cover rows 1-24, the bottom edge is row 25.
FRAME_SIDE_ROWS = 24
frame_first_row = 0x7EC526
; Cells each spell clears from its column base: a leading blank, the
; 9-cell name field and the rest of the column up to the next one.
SPELL_CELLS = 20
frame_bottom_row = frame_first_row + FRAME_SIDE_ROWS * 0x40


.include "../bank20.i"

.alloc battle_magic_reloc_block in bank20_reloc {
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
    jsr.l messages_vwf.spell_list_begin

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
; Blank the spell's cells on both tilemap rows first (one leading cell,
; the name, then the rest of the column: what the items window or a
; longer previous name left there), then render the name from cell 1.
    ldy.w #0

clear_loop:
    lda.b #0xff
    sta (0x32), y
    sta (0x34), y
    iny
    lda.b 0x36
    sta (0x32), y
    sta (0x34), y
    iny
    cpy.w #SPELL_CELLS * 2
    bne clear_loop
    ldy.w #2
    jsr.l messages_vwf.draw_spell_name

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
    beq draw_frame
    jmp.w spell_loop

draw_frame:
; The 12 spell rows fill buffer rows 1-24, past the 15-row frame the
; shared menu buffer carries from battle start, and the list's scroll
; HDMA shows row 25 as the window's bottom edge. Draw that frame here.
    rep #0x20
    ldx.w #0

side_loop:
    lda.w #0x000B
    sta.l frame_first_row, x
    lda.w #0x000C
    sta.l frame_first_row + 0x3E, x
    txa
    clc
    adc.w #0x0040
    tax
    cpx.w #FRAME_SIDE_ROWS * 0x40
    bne side_loop
    lda.w #0x000D
    sta.l frame_bottom_row
    ldx.w #0x0002
    lda.w #0x000E

bottom_loop:
    sta.l frame_bottom_row, x
    inx
    inx
    cpx.w #0x003E
    bne bottom_loop
    lda.w #0x000F
    sta.l frame_bottom_row + 0x3E
    sep #0x20
; The items window shares this buffer and only draws its frame at
; battle start; have its next transfer rebuild it.
    lda.b #0x01
    sta.l battle_render.items_frame_dirty
    jsr.l messages_vwf.spell_list_end
    rtl
    }

magic_cursor_rows:
"""
    Spell-list hand Y per visible row, read at $02:B7B9 instead of the
    $16:FC5B table it shares with the battle item list. VWF names sit on
    each 16-px row's bottom tile line, lower in the cell than the 8x8
    font's glyphs, so the hand comes down MAGIC_CURSOR_Y_NUDGE pixels to
    point at the middle of the name.
"""


    MAGIC_CURSOR_Y_FIRST := 0x9C  ; vanilla $16:FC5B[0]
    MAGIC_CURSOR_Y_PITCH := 12  ; vanilla row step
    MAGIC_CURSOR_Y_NUDGE := 2
    .for row := 0, 5 {
    .db MAGIC_CURSOR_Y_FIRST + MAGIC_CURSOR_Y_NUDGE + row * MAGIC_CURSOR_Y_PITCH
    }

magic_list_ptrs:
"""Per-magic-type spell-list base pointers (white, black, summon, ninja, kokan)."""
    .dw 0x2c7a, 0x2d9a, 0x2eba, 0x2fda, 0x30fa
}
