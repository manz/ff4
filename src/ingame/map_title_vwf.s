"""
Map titles (the location window on entering a map) in the small VWF, the way the dialogue VWF draws its window.

Vanilla fills two rows of font codes from MapTitle (places_names.dat): the glyph row (dialog_text_buffer) and its
dakuten row (dialog_text_buffer + _TITLE_CELLS), and TfrMapTitle ($00:B948, in the NMI) writes them into BG3's
tilemap. The field keeps BG3's tiles at $2000, the font only, so the title does what `vwfinit` does for a dialogue:
the font copied to $6000, BG3 pointed there, and the text in tiles $100 on ($6800), reached with attribute bit 0.
LoadMapTitle runs while the map loads, screen off, so the setup uploads directly. Glyph row cells are tile
_TITLE_BLANK (blank) or the title's tiles; TfrMapTitle writes that row with _TITLE_ATTR.

The field menu's BG2 tilemap sits on those tiles and its exit (FadeInMenu's InitHWRegs) points BG3 back at $2000: a
title still open is drawn and uploaded again there, screen still off.
"""
.import "preamble"
.import "vanilla"
.import "assets"
.import "vwf_ram"
.import "libmz"
.import "small_vwf/render"
.import "ingame/places_names_window"
.include "src/vwf_state.i"
.include "src/libmz.i"
.include "../bank20.i"

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
    jsr.w render.deinit
    lda.b #0x00
    sta.l vwf_engine.chr_dirty  ; no menu flush: uploaded below
    dma_transfer_to_vram_call(_FONT, _FONT_WORD, 0x800, 0x1801)
    dma_transfer_to_vram_call(_FONT + 0x800, _FONT_WORD + 0x400, 0x800, 0x1801)
    dma_transfer_to_vram_call(_TILES_SOURCE, _TILES_WORD, _TILES_BYTES, 0x1801)
    lda.b #_BG34NBA
    sta.l ppu.BG34NBA
    rts

_fill_rows:
"""Blank both rows, then the tiles the name used, centred in the glyph row. M = 8 bits, X = 16 bits."""
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
    eor.w #0xFFFF
    sec
    adc.w #_TITLE_CELLS
    lsr  ; centred: (cells - tiles) / 2 blanks first
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
