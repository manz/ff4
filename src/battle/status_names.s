"""
The target window's status column (DrawStatusText, $02:A2A1) in baked tiles: each status name is set at build time
(utils/bake_names.py) and a row shows it from a window of its own in the 8x8 font page's blank kana slots, which battle
never draws. Vanilla copied the name, cut to 8 letters ("Paralysi"), in the 8x8 font.

A row's window is `STATUS_TILES` tiles from `STATUS_FIRST_TILE + row * STATUS_TILES`: drawing a row copies its
name's tiles from ROM into `status_name_tiles` and flags the NMI's CHR pass (battle/message.s), which uploads the
whole staging block. DrawStatusText's own name copy ($02:A32A, pointers into battle_statuses) is never reached.
"""
.import "core/preamble"
.import "core/wram_layout"
.import "battle/render_state"
.import "small_vwf/baked_names"
.include "core/bank20.i"

STATUS_ROWS := 5
STATUS_TILES := 6  ; build.py STATUS_NAME_TILES: the build fails on a wider name
STATUS_FIRST_TILE := 0x90  ; blank kana slots $90-$AD in the 8x8 font (fonts/8x8.bin)
_TILE_BYTES := 0x10
_BG3_CHR := 0xA000  ; VRAM byte address of BG3 tile 0 in battle
STATUS_VRAM_WORD := ( _BG3_CHR + STATUS_FIRST_TILE * _TILE_BYTES ) >> 1
STATUS_STAGING_BYTES := STATUS_ROWS * STATUS_TILES * _TILE_BYTES

_ROW_BUFFER := 0xD710  ; DrawStatusText's status tilemap: a row is 2 tilemap rows, the glyphs on the second
_ROW_BYTES := 0x80
_GLYPH_ROW := 0x40
_CELLS := 8
_BLANK_CELL := 0x20FF  ; vanilla's: tile $FF, priority
_ATTRIBUTE := 0x20
_NO_STATUS := 0x20  ; DrawStatusText's bit index when no shown status is set

.reserve status_name_tiles STATUS_STAGING_BYTES in battle_text_ram
.reserve _row_tiles 2 in battle_text_ram  ; the row's first tile id
.reserve _count 2 in battle_text_ram

.alloc at 0x02A322 {
; no shown status: draw the row blank through the same routine (X = 32)
    bra _found
}
.label _found = 0x02A327
.label _next_row = 0x02A36D

.alloc at 0x02A327 {
; X = the row's first shown status bit; $EF52 = its tilemap row
    jsr.l status_names.draw_row
    jmp.w _next_row
}

.alloc _status_names_block in bank20_reloc {
    .scope status_names {
draw_row:
"""
The status-tilemap row at $EF52: status X's baked name (X < 32 with tiles), blank cells otherwise. The name's tiles
go into the row's window in `status_name_tiles`, uploaded at the next NMI.
"""
        php
        rep #0x30
        phx
        phy
        lda.l 0x7EEF52
        tay  ; the row's dakuten row
        sec
        sbc.w #_ROW_BUFFER
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr
        lsr  ; the row: (address - buffer) / $80
        sta.l _count
        asl
        adc.l _count  ; row * 3
        asl  ; row * 6
        clc
        adc.w #STATUS_FIRST_TILE | _ATTRIBUTE << 8
        sta.l _row_tiles
        phx
        jsr.w _blank_row
        plx
        cpx.w #_NO_STATUS
        bcs _done
        txa
        asl
        asl
        tax  ; table entry: word offset, byte tile count, byte last columns
        lda.l status_names_vwf_tbl + 2, x
        and.w #0x00FF
        beq _done
        sta.l _count
        jsr.w _point_cells
        lda.l status_names_vwf_tbl, x
        jsr.w _copy_tiles
        sep #0x20
        lda.l battle_render_state.pending_transfer_mask
        ora.b #ChrTransferBits.pending.mask | ChrTransferBits.status.mask
        sta.l battle_render_state.pending_transfer_mask
_done:
        rep #0x30
        ply
        plx
        plp
        rtl

_blank_row:
"""Y = the row's tilemap address: both its tilemap rows blank."""
        phy
        ldx.w #_CELLS
        lda.w #_BLANK_CELL
_blank:
        sta.w 0x0000, y
        sta.w _GLYPH_ROW, y
        iny
        iny
        dex
        bne _blank
        ply
        rts

_point_cells:
"""The glyph row's first `_count` cells at the row's window tiles. Y = the row's tilemap address."""
        phx
        phy
        lda.l _count
        tax
        lda.l _row_tiles
_cell:
        sta.w _GLYPH_ROW, y
        inc
        iny
        iny
        dex
        bne _cell
        ply
        plx
        rts

_copy_tiles:
"""A = the name's offset in status_names_vwf: its `_count` tiles into the row's window in the staging block."""
        phx
        tax
        lda.l _row_tiles
        and.w #0x00FF
        sec
        sbc.w #STATUS_FIRST_TILE
        asl
        asl
        asl
        asl
        tay  ; the window's offset in status_name_tiles
        lda.l _count
        asl
        asl
        asl  ; words: 8 a tile
        sta.l _count
_copy:
        lda.l status_names_vwf, x
        phx
        tyx
        sta.l status_name_tiles, x
        plx
        inx
        inx
        iny
        iny
        lda.l _count
        dec
        sta.l _count
        bne _copy
        plx
        rts
    }
}
