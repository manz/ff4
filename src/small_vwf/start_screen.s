"""
Small-VWF start-screen text: the `newgame` strings (save slots, load / save prompts) drawn in the 8-pixel VWF.

The menu text thunks (menus/system_menus_text.s) send a `newgame` string here instead of the 8x8 font. The strings
share the item-description region, unused on these screens: a string's tiles start at its byte offset in the
`newgame` block, and a glyph is at most 8 pixels wide, so no two strings share a tile and nothing is allocated.
"""
.import "vanilla"
.import "vwf_ram"
.import "libmz"
.import "menus/start_screen_text"
.import "small_vwf/render"
.include "config.i"
.include "src/vwf.i"
.include "../bank20.i"
.include "src/libmz.i"

_REGION_FIRST_TILE := 0x80  ; allocator id: with the $01 attribute bit, tiles $180..$1FF (VRAM $5800..$5FFF)
_REGION_TILES := 0x80
_GLYPH_ROW := 0x40  ; menu text puts the dakuten at +0 and the glyph one row down
_BLANK_TILE := 0xFF

.assert newgame.strings_end - newgame.new_game <= _REGION_TILES, "the newgame strings outgrow the VWF region"

.alloc _small_vwf_start_screen in bank20_reloc {
    .include "src/vwf_state.i"

    .scope start_screen_text {
    """Entry points called by the menu text thunks, D = $0100, the vanilla routine's frame on the stack."""
draw_pos:
"""DrawPosText ($01:8301) for a `newgame` string: Y = string - $8000, the position word first."""
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
"""DrawMenuText ($01:82CD) for a `newgame` string: X = tilemap offset ($29 added), Y = string - $8000."""
    phk
    plb
    rep #0x20
    tya
    ora.w #0x8000
    tay
    sep #0x20
_draw:
    jsr.w _configure
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
    rts

_configure:
"""
Region for the string at Y: its first tile at its byte offset in the `newgame` block, the rest of the region
cleared. The item description drawn next must not trust its cache: its tiles are ours now.
"""
    rep #0x20
    tya
    sec
    sbc.w #newgame.new_game & 0xFFFF
    clc
    adc.w #_REGION_FIRST_TILE
    sta.l vwf_cfg.tile_id_base
    eor.w #0x00FF
    inc
    sep #0x20
    sta.l vwf_cfg.slot_budget
    lda.b #0x01
    sta.l vwf_cfg.flags
    rep #0x20
    lda.w #0x0000
    sta.l render.last_drawn_text_ptr
    sep #0x20
    rts

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
"""DMA the string's tiles at the next vblank: buffer tile N goes to VRAM tile $100 + N."""
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
    lda.l vwf_cfg.tile_id_base
    asl
    asl
    asl
    clc
    adc.w #( 0x4000 + 0x100 * 0x10 ) >> 1
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
