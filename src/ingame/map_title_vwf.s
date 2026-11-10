"""
Map titles (the location window on entering a map) in the small VWF, the way the dialogue VWF draws its window.

Vanilla fills a glyph row (dialog_text_buffer) and a dakuten row (+ _TITLE_CELLS) that TfrMapTitle ($00:B948,
NMI) writes to BG3's tilemap. Like `vwfinit`, the title copies the font to $6000, points BG3 there and renders
into tiles $100 on ($6800, attr bit 0). LoadMapTitle runs screen off, so uploads are direct.

The field menu's BG2 tilemap overwrites those tiles and its exit points BG3 back at $2000, so `restore` redraws
an open title.
"""
.import "core/preamble"
.import "core/vanilla"
.import "core/assets"
.import "core/vwf_ram"
.import "core/libmz"
.import "small_vwf/render"
.import "ingame/places_names_window"
.import "core/sram_layout"
.include "core/vwf_state.i"
.include "core/libmz.i"
.include "core/bank20.i"

_TITLE_BLANK := 0x100  ; a blank tile: the glyph row's cells outside the title
_TITLE_TILE := 0x101  ; the title's first tile
_TITLE_CELLS := PLACE_NAME_LENGTH
_TITLE_TILES := _TITLE_CELLS  ; at most one tile a cell
_TITLE_ATTR := 0x21  ; vanilla's $20 (priority) with tile bit 8
_FONT := 0x0AF000  ; the 8x8 font, as vwfinit copies it
_FONT_WORD := 0x6000  ; BG3 tiles while a title or a dialogue shows
_BG34NBA := 0x06  ; BG3 tiles at $6000, BG4 at 0 as the field sets it
_BLANK_CODE := 0xFF  ; the font's space
_TILES_SOURCE := VWF_CHR_BUFFER + _TITLE_BLANK * 0x10
_TILES_WORD := _FONT_WORD + _TITLE_BLANK * 8
_TILES_BYTES := ( _TITLE_TILES + 1 ) * 0x10  ; the blank tile, then the title's

.alloc at 0x00B8FD {
; MapTitle's setup, X = the title's offset in place_names: `stx $3d / stz $07`, then the row fill
    jml map_title_vwf.setup
}

.alloc at 0x008A40 {
; FadeInMenu, back from the field menu: `jsl InitHWRegs`
    jsl map_title_vwf.restore
}

.alloc at 0x00B9CC {
; TfrMapTitle's glyph row: `lda #$20` before each cell's attribute
    .db _TITLE_ATTR
}

.alloc _map_title_vwf in bank20_reloc {
    .scope map_title_vwf {
setup:
"""
Render the title at place_names + X, upload it with the font, point BG3 at them and fill the rows. Screen off (map
load). Ends in vanilla's `lda #1 / sta $e9`.
"""
        php
        phb
        sep #0x20
        rep #0x10
        jsr.w _draw
        jsr.w _fill_rows
        plb
        plp
        jml 0x00B943

restore:
"""
FadeInMenu's InitHWRegs, then the map's title again while its window is open: the menu's BG2 tilemap took its
tiles and BG3 is back on $2000. A title LoadMapTitle skipped is drawn for nothing: no cell shows its tiles, and BG3
reads the same font at $6000. Screen off, NMI still disabled.
"""
        jsl.l init_hw_regs
        php
        phb
        sep #0x20
        rep #0x10
        lda.l map_title_state
        bne _restored
        lda.l map_title_index
        bmi _restored  ; a map without a title
        lda.b #0x00
        pha
        plb
        rep #0x20
        lda.l map_title_index
        and.w #0x00FF
        tay
        sep #0x20
        ldx.w #0x0000
_find:
; X past Y titles, as LoadMapTitle finds it
        cpy.w #0x0000
        beq _found
_skip:
        lda.l place_names, x
        inx
        cmp.b #0x00
        bne _skip
        dey
        bra _find
_found:
        jsr.w _draw
_restored:
        plb
        plp
        rtl

_draw:
"""Render the title at place_names + X, upload it with the font and point BG3 at them. M = 8 bits, X = 16 bits."""
        ldy.w #0x0000
_copy:
        lda.l place_names, x
        inx
        phx
        tyx
        sta.l vwf_text_buffer, x
        plx
        iny
        cmp.b #0x00
        bne _copy
        rep #0x20
        lda.w #_TITLE_BLANK
        sta.l vwf_cfg.tile_id_base
        lda.w #dialog_text_buffer & 0xFFFF  ; display_char's own tilemap writes land in the rows, overwritten below
        sta.l vwf_cfg.tilemap_base
        sep #0x20
        lda.b #_TITLE_TILES + 1
        sta.l vwf_cfg.slot_budget
        lda.b #0x01
        sta.l vwf_cfg.flags
        jsr.w render.init  ; clears _TITLE_BLANK on, keeps the field's direct-page bytes the renderer borrows
        rep #0x20
        lda.w #_TITLE_TILE
        sta.l vwf_cfg.tile_id_base
        sep #0x20
        lda.b #_TITLE_TILES
        sta.l vwf_cfg.slot_budget
        jsr.w render.render_with_config
        jsr.w _centre
        jsr.w render.render_with_config
        lda.b #0x00
        sta.l render_lead
        jsr.w render.deinit
        lda.b #0x00
        sta.l vwf_engine.chr_dirty  ; no menu flush: uploaded below
        dma_transfer_to_vram_call(_FONT, _FONT_WORD, 0x800, 0x1801)
        dma_transfer_to_vram_call(_FONT + 0x800, _FONT_WORD + 0x400, 0x800, 0x1801)
        dma_transfer_to_vram_call(_TILES_SOURCE, _TILES_WORD, _TILES_BYTES, 0x1801)
        lda.b #_BG34NBA
        sta.l ppu.BG34NBA
        rts

_centre:
"""
From the render just made, the pixels the name takes (the pen after its last glyph, less the glyph's trailing
column), and the lead that centres it in the glyph row: its whole cells in map_title_cells, for `_fill_rows`, its
remainder in render_lead, where the next render starts its first glyph. M = 8 bits, X = 16 bits.
"""
        rep #0x20
        lda.l render_allocator.allocated_tile_id
        sec
        sbc.w #_TITLE_TILE - 1  ; the tiles the pen reached, the one it is in counted
        asl
        asl
        asl
        sep #0x20
        sec
        sbc.b render.glyph.bits_left_on_tile  ; the pen
        sta.l render_lead
        lda.b #_TITLE_CELLS * 8 + 1  ; the row, and the glyph's trailing column
        sec
        sbc.l render_lead
        lsr  ; the lead: (row - width) / 2
        pha
        lsr
        lsr
        lsr
        sta.l map_title_cells
        pla
        and.b #0x07
        sta.l render_lead
        rts

_fill_rows:
"""
Blank both rows, then the tiles the name used, from the lead `_centre` left in map_title_cells. M = 8 bits,
X = 16 bits.
"""
        ldx.w #0x0000
_blank:
        lda.b #_TITLE_BLANK & 0xFF
        sta.l dialog_text_buffer, x
        lda.b #_BLANK_CODE
        sta.l dialog_text_buffer + _TITLE_CELLS, x
        inx
        cpx.w #_TITLE_CELLS
        bne _blank
        rep #0x20
        lda.l render_allocator.allocated_tile_id
        sec
        sbc.w #_TITLE_TILE - 1  ; the tile the last glyph ended in counts
        tay
        lda.l map_title_cells
        and.w #0x00FF
        tax
        sep #0x20
        lda.b #_TITLE_TILE & 0xFF
_tile:
        sta.l dialog_text_buffer, x
        inx
        inc
        dey
        bne _tile
        rts
    }
}
