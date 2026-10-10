"""
Map titles (the location window on entering a map) in the small VWF.

Vanilla fills two rows of font codes from MapTitle (places_names.dat): the glyph row ($0774) and its dakuten row
(dialog_text_buffer + _TITLE_CELLS), and TfrMapTitle ($00:B948, in the NMI) writes them into BG3's tilemap. The field
keeps BG3's tilemap at word $2800, right after the font's 256 tiles at $2000, so there are no spare tiles: the title
draws into font slots _TITLE_TILE.._TITLE_TILE + _TITLE_TILES - 1, kana no French text uses. The setup renders the
name there, fills the glyph row with those slots, centred, and blanks the dakuten row; TfrMapTitle uploads the
slots before writing the rows.
"""
.import "preamble"
.import "vanilla"
.import "assets"
.import "vwf_ram"
.import "small_vwf/render"
.include "src/vwf_state.i"
.include "../bank20.i"

_TITLE_TILE := 0xD8  ; font slots from $D8 (to $F1): no entry in text/ff4_menus.tbl
_TITLE_CELLS := 0x1A  ; ingame/places_names.s place_name_length
_TITLE_TILES := _TITLE_CELLS  ; at most one tile a cell
_BG3_CHR_WORD := 0x2000  ; the field's BG3 tiles
_BLANK := 0xFF
_TITLE_SHOWN := 0xE9  ; DP: TfrMapTitle has a title to write

.alloc at 0x00B8FD {
; MapTitle's setup, X = the title's offset in place_names: `stx $3d / stz $07`, then the row fill
    jml map_title_vwf.setup
}

.alloc at 0x00B94D {
; TfrMapTitle: `stz $e9 / stz $2112`
    jsl map_title_vwf.upload
    nop
}

.alloc _map_title_vwf in bank20_reloc {
    .scope map_title_vwf {
setup:
"""Render the title at place_names + X into the title slots and fill the rows. Ends in vanilla's `lda #1 / sta $e9`."""
    php
    phb
    sep #0x20
    rep #0x10
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
    lda.w #_TITLE_TILE
    sta.l vwf_cfg.tile_id_base
    lda.w #dialog_text_buffer & 0xFFFF  ; display_char's own tilemap writes land in the rows, overwritten below
    sta.l vwf_cfg.tilemap_base
    sep #0x20
    lda.b #_TITLE_TILES
    sta.l vwf_cfg.slot_budget
    lda.b #0x00
    sta.l vwf_cfg.flags
    jsr.w render.init  ; keeps the field's direct-page bytes the renderer borrows, until deinit
    jsr.w render.render_with_config
    jsr.w render.deinit
    lda.b #0x00
    sta.l vwf_engine.chr_dirty  ; no menu flush: TfrMapTitle uploads the slots
    jsr.w _fill_rows
    plb
    plp
    jml 0x00B943

_fill_rows:
"""Blank both rows, then the slots the name used, centred in the glyph row. M = 8 bits, X = 16 bits."""
    ldx.w #0x0000
    lda.b #_BLANK
_blank:
    sta.l dialog_text_buffer, x
    sta.l dialog_text_buffer + _TITLE_CELLS, x
    inx
    cpx.w #_TITLE_CELLS
    bne _blank
    rep #0x20
    lda.l render_allocator.allocated_tile_id
    sec
    sbc.w #_TITLE_TILE - 1  ; the slot the last glyph ended in counts
    tay
    eor.w #0xFFFF
    sec
    adc.w #_TITLE_CELLS
    lsr  ; centred: (cells - slots) / 2 blanks first
    tax
    sep #0x20
    lda.b #_TITLE_TILE
_slot:
    sta.l dialog_text_buffer, x
    inx
    inc
    dey
    bne _slot
    rts

upload:
"""TfrMapTitle's first stores (`stz $e9 / stz $2112`), after the title slots go to BG3's tiles. In the NMI."""
    php
    sep #0x20
    rep #0x10
    stz.b _TITLE_SHOWN
    lda.b #0x01  ; DMAP: word transfer (VMDATAL / VMDATAH)
    sta.l dma_ch3.DMAP
    lda.b #PPU.VMDATAL
    sta.l dma_ch3.BBAD
    rep #0x20
    lda.w #( VWF_CHR_BUFFER + _TITLE_TILE * 0x10 ) & 0xFFFF
    sta.l dma_ch3.A1TL
    lda.w #_TITLE_TILES * 0x10
    sta.l dma_ch3.DASL
    lda.w #_BG3_CHR_WORD + _TITLE_TILE * 8
    sta.l ppu.VMADDL
    sep #0x20
    lda.b #VWF_CHR_BUFFER >> 16
    sta.l dma_ch3.A1B
    lda.b #0x80
    sta.l ppu.VMAIN
    lda.b #0x08
    sta.l cpu_regs.MDMAEN
    lda.b #0x00
    sta.l ppu.BG3VOFS
    plp
    rtl
    }
}
