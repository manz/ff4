"""
Small-VWF menu text: whole string blocks drawn in the 8-pixel VWF instead of the 8x8 font.

The menu text thunks (menus/system_menus_text.s) offer every string here first. A string inside one of `_blocks`
gets the tiles at its byte offset in its block: a glyph is at most 8 pixels wide, so no two strings of a block
share a tile and nothing is allocated. Blocks on screen together need disjoint tiles.
  - `newgame` (load and save screens): tiles $180-$1FF, the item-description region, unused there.
  - `status`: tiles $200-$2FE, VRAM $6000-$6FEF, free in every menu (ingame/menu_vram.s saves the field's copy).
"""
.import "vanilla"
.import "vwf_ram"
.import "libmz"
.import "menus/start_screen_text"
.import "menus/in_game_text"
.import "small_vwf/render"
.include "config.i"
.include "src/vwf.i"
.include "../bank20.i"
.include "src/libmz.i"

_GLYPH_ROW := 0x40  ; menu text puts the dakuten at +0 and the glyph one row down
_BLANK_TILE := 0xFF

.assert newgame.strings_end - newgame.new_game <= 0x80, "the newgame strings outgrow tiles $180-$1FF"
.assert status.strings_end - status.status <= 0xFF, "the status strings outgrow tiles $200-$2FE"

.alloc _small_vwf_menu_text in bank20_reloc {
    .include "src/vwf_state.i"

    .scope menu_text_vwf {
    """Entry points called by the menu text thunks, D = $0100, the vanilla routine's frame on the stack."""
draw_pos:
"""
DrawPosText ($01:8301): Y = string - $8000, the position word first. Carry clear: not a VWF string, nothing
touched.
"""
    jsr.w _claim
    bcs _draw_pos
    rts
_draw_pos:
    phk
    plb
    rep #0x20
    tya
    ora.w #0x8000
    tay
    lda.w 0x0000, y
    clc
    adc.b menu_dp.tilemap_offset
    tax
    iny
    iny
    sep #0x20
    bra _draw
draw_at:
"""
DrawMenuText ($01:82CD): X = tilemap offset ($29 added), Y = string - $8000. Carry clear: not a VWF string,
nothing touched.
"""
    jsr.w _claim
    bcs _draw_at
    rts
_draw_at:
    phk
    plb
    rep #0x20
    tya
    ora.w #0x8000
    tay
    sep #0x20
_draw:
    phx
    phy
    jsr.w render.init
    rep #0x20
    lda.l vwf_cfg.tile_id_base
    jsr.w render_allocator.init_with_tile_id_wide
    sep #0x20
    ply
    plx
    jsr.w _begin_line
_char_loop:
    lda.w 0x0000, y
    beq _done
    iny
    cmp #0x01
    beq _move_to
    phx
    phy
    jsr.w render.display_char
    ply
    plx
    bra _char_loop
_move_to:
    jsr.w _pad
    rep #0x20
    lda.w 0x0000, y
    clc
    adc.b menu_dp.tilemap_offset
    tax
    iny
    iny
    sep #0x20
    lda.b #0x08
    sta.b render.bits_left_on_tile
    jsr.w render_allocator.increment
    jsr.w _begin_line
    bra _char_loop
_done:
    jsr.w _pad
    jsr.w _upload
    jsr.w render.deinit
    sec
    rts

_claim:
"""
Carry set when Y (string - $8000) lies in a block of `_blocks`: vwf_cfg then holds the string's first tile, its
attribute bits and the rest of the region to clear. Keeps A, X, Y.
"""
    php
    rep #0x30
    pha
    phx
    ldx.w #0x0000
_next_block:
    lda.l _blocks, x
    beq _unclaimed
    tya
    ora.w #0x8000
    cmp.l _blocks, x
    bcc _skip_block
    cmp.l _blocks + 2, x
    bcs _skip_block
    sec
    sbc.l _blocks, x
    clc
    adc.l _blocks + 4, x
    sta.l vwf_cfg.tile_id_base
    eor.w #0x00FF
    sep #0x20
    sta.l vwf_cfg.slot_budget
    lda.l _blocks + 6, x
    sta.l vwf_cfg.flags
    rep #0x20
; The item description must not trust its cache: its tiles may be ours now.
    lda.w #0x0000
    sta.l render.last_drawn_text_ptr
    plx
    pla
    plp
    sec
    rts
_skip_block:
    txa
    clc
    adc.w #8
    tax
    bra _next_block
_unclaimed:
    plx
    pla
    plp
    clc
    rts

_blocks:
; first string, end, allocator id of the first tile, attribute bits (tile id bits 8-9)
    .dw newgame.new_game & 0xFFFF, newgame.strings_end & 0xFFFF, 0x80, 0x01
    .dw status.status & 0xFFFF, status.strings_end & 0xFFFF, 0x00, 0x02
    .dw 0x0000

_begin_line:
"""Start a line at tilemap offset X (its dakuten row); the line ends where the 8x8 font would have ended it."""
    rep #0x20
    txa
    clc
    adc.w #_GLYPH_ROW
    sta.l render.tilemap_offset
    tax
    sep #0x20
    phy
_count:
    lda.w 0x0000, y
    beq _counted
    cmp #0x01
    beq _counted
    iny
    inx
    inx
    bra _count
_counted:
    rep #0x20
    txa
    sta.l vwf_cfg.tilemap_base
    sep #0x20
    ply
    rts

_pad:
"""
Blank the VWF cells between the text and the line's 8x8 end: a shorter text hides the longer one drawn
before. Cells without a VWF tile (attribute bit 0 clear) stay as they are, a narrowed window's outside too.
"""
    php
    phx
    rep #0x30
    lda.l render.tilemap_offset
    tax
    sep #0x20
    lda.b render.bits_left_on_tile
    cmp #0x08
    beq _pad_check  ; the current cell holds no pixel yet
    inx
    inx
_pad_check:
    rep #0x20
    txa
    cmp.l vwf_cfg.tilemap_base
    sep #0x20
    bcs _padded
    lda.l 0x7E0001, x
    bit.b #0x01
    beq _pad_next
    and.b #0xFE
    sta.l 0x7E0001, x
    lda.b #_BLANK_TILE
    sta.l 0x7E0000, x
_pad_next:
    inx
    inx
    bra _pad_check
_padded:
    plx
    plp
    rts

_upload:
"""DMA the string's tiles at the next vblank: buffer tile N goes to VRAM tile (attribute bits << 8) + N."""
    php
    phb
    sep #0x20
    lda.b #0x00
    pha
    plb
    rep #0x20
    pea.w _uploaded - 1
    lda.l vwf_cfg.tile_id_base
    asl
    asl
    asl
    asl
    clc
    adc.w #VWF_CHR_BUFFER & 0xFFFF
    pha
    pea.w VWF_CHR_BUFFER >> 16
    lda.l vwf_cfg.flags
    and.w #0x0003
    xba
    ora.l vwf_cfg.tile_id_base
    asl
    asl
    asl
    clc
    adc.w #0x4000 >> 1
    pha
    lda.l render_allocator.allocated_tile_id
    sec
    sbc.l vwf_cfg.tile_id_base
    inc
    asl
    asl
    asl
    asl
    pha
    pea.w 0x1801
    sep #0x20  ; wait_for_vblank reads $4212 alone
    jsr.w wait_for_vblank
    jmp.w dma_transfer_to_vram
_uploaded:
    plb
    plp
    rts
    }
}
