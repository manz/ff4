"""
Relocated battle spell-list renderer (`draw_magic_list_direct`) and per-magic-type pointer table
(`magic_list_ptrs`).
"""
.import "preamble"
.extern messages_vwf.spell_name_begin
.extern messages_vwf.draw_spell_name
.extern messages_vwf.spell_ring_flush

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
; First visible list row (vanilla scroll state).
list_top_row = 0x7EEF86
frame_bottom_row = frame_first_row + FRAME_SIDE_ROWS * 0x40


.include "../bank20.i"

.alloc battle_magic_reloc_block in bank20_reloc {
draw_magic_list_direct:
"""
Relocated battle spell-list renderer: walks the per-character spell-list
pointer table. Every row's cells point at its ring slot's tiles (see
render_defs.i), but only the visible rows render glyphs, and only those
the ring doesn't hold yet. Vanilla calls this on open and every few frames
while the list is up, so the repeat calls cost a tilemap rewrite.
"""


    {
    spell_id = 0x03
    ring_tile = 0x04
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
    jsr.w _ring_validate
    lda #0x18
; 24 spells total (12 rows x 2 columns)
    sta.b spell_counter
; spell counter
    lda #0x00
; current spell index (0-23)
    sta.b current_spell_index
    lda.b #battle_render.SPELL_TILE_BASE
    sta.b ring_tile

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
    sta.l cpu_regs.WRMPYA
    lda.b #battle_magic_length
    sta.l cpu_regs.WRMPYB
    nop
    nop
    nop
    nop
    rep #0x20
    lda.l cpu_regs.RDMPYL
;     asl                 ; spell ID * 8 (8 bytes per name)
;     asl
;     asl
    tax
    sep #0x20
; Blank the spell's cells on both tilemap rows first (one leading cell,
; the name, then the rest of the column: what the items window or a
; longer previous name left there), then point the name's cells, from
; cell 1, at its ring tiles.
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
    jsr.w _map_name_cells

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
    sep #0x20
    lda.b ring_tile
    clc
    adc.b #battle_render.SPELL_ROW_TILES
    cmp.b #battle_render.SPELL_TILE_BASE + battle_render.SPELL_RING_TILES
    bcc ring_next
    lda.b #battle_render.SPELL_TILE_BASE

ring_next:
    sta.b ring_tile

same_row:
    sep #0x20
    inc 0x0a
; next spell index
    dec.b spell_counter
; decrement spell counter
    beq render_rows
    jmp.w spell_loop

render_rows:
    lda.l list_top_row
    sta.b spell_counter
    lda.b #battle_render.SPELL_VISIBLE_ROWS
    sta.b current_spell_index

row_loop:
    lda.b spell_counter
    cmp.b #battle_render.SPELL_LIST_ROWS
    bcs draw_frame
    jsr.w render_spell_row
    inc.b spell_counter
    dec.b current_spell_index
    bne row_loop

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
    jsr.w _ring_flush
    rtl

_map_name_cells:
; Name cells 1..SPELL_NAME_TILES on the lower row of the pair -> this
; name's ring tiles (right column: the row's second name). The renderer
; writes the same cells; tiles a short name leaves blank stay blank.
    lda.b current_spell_index
    lsr
    lda.b ring_tile
    bcc map_tile
    clc
    adc.b #battle_render.SPELL_NAME_TILES

map_tile:
    ldy.w #2

map_loop:
    sta (0x34), y
    iny
    pha
    lda.b 0x36
    ora.b #0x01
    sta (0x34), y
    pla
    iny
    inc
    cpy.w #( battle_render.SPELL_NAME_TILES + 1 ) * 2
    bne map_loop
    rts
    }

_ring_validate:
; The ring caches rows of one list only, and the items window paints over
; it: start it over unless it holds glyphs of the list at $00.
    lda.l battle_render.spell_tiles_live
    cmp.b #0x01
    bne _ring_reset
    rep #0x20
    lda.b 0x00
    cmp.l battle_render.spell_list_ptr
    sep #0x20
    beq _ring_valid

_ring_reset:
    rep #0x20
    lda.b 0x00
    sta.l battle_render.spell_list_ptr
    sep #0x20
    lda.b #0xFF
    ldx.w #battle_render.SPELL_RING_ROWS - 1

_ring_reset_loop:
    sta.l battle_render.spell_ring_rows, x
    dex
    bpl _ring_reset_loop
    lda.b #0x01
    sta.l battle_render.spell_tiles_live

_ring_valid:
    rts

_ring_flush:
; Queue the ring's CHR flush if a render touched it. M=8.
    lda.l battle_render.spell_ring_dirty
    beq _ring_clean
    lda.b #0x00
    sta.l battle_render.spell_ring_dirty
    jsr.l messages_vwf.spell_ring_flush

_ring_clean:
    rts

render_spell_row:
"""
Render list row A's two names into its ring slot, unless the slot holds
that row already. Needs spell_list_ptr and DBR = $7E. M=8, X=16  ;
clobbers $32-$36, X, Y.
"""


    sta.l battle_render.spell_row
    sec

_rsr_mod:
    sbc.b #battle_render.SPELL_RING_ROWS
    bcs _rsr_mod
    adc.b #battle_render.SPELL_RING_ROWS
    sta.l battle_render.spell_slot
    rep #0x20
    and.w #0x00FF
    tax
    sep #0x20
    lda.l battle_render.spell_ring_rows, x
    cmp.l battle_render.spell_row
    beq _rsr_done
    lda.l battle_render.spell_row
    sta.l battle_render.spell_ring_rows, x
    lda.b #0x01
    sta.l battle_render.spell_ring_dirty
    lda.b #0x00
    jsr.w _rsr_name
    lda.b #0x01
    jsr.w _rsr_name

_rsr_done:
    rts

_rsr_name:
; A = column (0 left, 1 right).
    rep #0x20
    and.w #0x0001
    pha
; List entry: spell_list_ptr + row * 8 + column * 4.
    lda.l battle_render.spell_row
    and.w #0x00FF
    asl
    asl
    asl
    sta.b 0x32
    lda 1, s
    asl
    asl
    clc
    adc.b 0x32
    clc
    adc.l battle_render.spell_list_ptr
    tax
; Row pair: column base + row * $80.
    lda.b 0x32
    asl
    asl
    asl
    asl
    sta.b 0x32
    lda 1, s
    beq _rsr_left
    lda.w #right_column_base
    bra _rsr_base

_rsr_left:
    lda.w #left_column_base

_rsr_base:
    clc
    adc.b 0x32
    sta.b 0x32
    clc
    adc.w #0x0040
    sta.b 0x34
    sep #0x20
    lda.l 0x7E0000, x
    and.b #0x80
    beq _rsr_palette
    lda.b #0x04

_rsr_palette:
    sta.b 0x36
; Name offset in assets_magic_dat: (spell id & $7F) * 9.
    lda.l 0x7E0001, x
    rep #0x20
    and.w #0x007F
    pha
    asl
    asl
    asl
    clc
    adc 1, s
    sta 1, s
; Ring tiles: the slot's base, plus a name's worth for the right column.
    lda.l battle_render.spell_slot
    and.w #0x00FF
    tax
    sep #0x20
    lda.l ring_slot_tiles, x
    pha
    lda 4, s
    beq _rsr_tile
    pla
    clc
    adc.b #battle_render.SPELL_NAME_TILES
    pha

_rsr_tile:
    pla
    jsr.l messages_vwf.spell_name_begin
    rep #0x20
    pla
    tax
    pla
    sep #0x20
    ldy.w #2
    jsr.l messages_vwf.draw_spell_name
    rts

spell_list_scroll_render:
"""
Scroll hooks: render list row A into the ring before it slides in. Rows
past the list end are skipped. M=8, X=16  ; preserves all of A (vanilla
goes on to TAX an 8-bit read with X=16), X, Y and $32-$37.
"""


    php
    rep #0x30
    pha
    phx
    phy
    phb
    sep #0x20
    cmp.b #battle_render.SPELL_LIST_ROWS
    bcs _slsr_out
    lda.l battle_render.spell_tiles_live
    cmp.b #0x01
    bne _slsr_out
    lda.b #0x7E
    pha
    plb
    rep #0x20
    lda.b 0x32
    pha
    lda.b 0x34
    pha
    lda.b 0x36
    pha
    sep #0x20
; row: under 3 words, DBR, Y and X
    lda 12, s
    jsr.w render_spell_row
    jsr.w _ring_flush
    rep #0x20
    pla
    sta.b 0x36
    pla
    sta.b 0x34
    pla
    sta.b 0x32

_slsr_out:
    plb
    rep #0x30
    ply
    plx
    pla
    plp
    rtl

ring_slot_tiles:
"""First tile of each ring slot."""
    .for slot := 0, battle_render.SPELL_RING_ROWS {
    .db battle_render.SPELL_TILE_BASE + slot * battle_render.SPELL_ROW_TILES
    }

magic_list_ptrs:
"""Per-magic-type spell-list base pointers (white, black, summon, ninja, kokan)."""
    .dw 0x2c7a, 0x2d9a, 0x2eba, 0x2fda, 0x30fa
}
