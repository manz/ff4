"""
Battle monster-slot helpers: blank a slot, the tab escape.
"""


.import "assets"
.import "vanilla"


.include "../bank20.i"

.alloc _battle_monsters_reloc_block in bank20_reloc {
initialize_monster_slot:
"""Cross-bank (RTL) entry that clears a monster's display slot to spaces."""
    jsr.w _initialize_monster_slot_near
    rtl

tab_escape_code:
"""Text-stream escape that draws a column of spaces to advance the cursor."""
    jsr.w _draw_spaces
    rtl

_initialize_monster_slot_near:

; clear monster slot with spaces
    lda #11
    sta 0x00

_draw_spaces:
    lda.b #0xff
    sta.b (btlgfx_dp.dakuten_row_ptr), y
    sta.b (btlgfx_dp.kana_row_ptr), y
    iny
    lda.b btlgfx_dp.text_tile_flags
    sta.b (btlgfx_dp.dakuten_row_ptr), y
    sta.b (btlgfx_dp.kana_row_ptr), y
    iny
    dec 0x00
    bne _draw_spaces

    rts
}
