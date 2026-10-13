"""Small-VWF item-description renderer."""
.import "core/preamble"
.import "core/vwf_ram"
.import "core/assets"
.import "core/items"
.import "battle/render_state"
.import "core/libmz"
.include "dialog/vwf.i"
.include "core/bank20.i"
.include "core/libmz.i"
.import "small_vwf/render"

.alloc _small_vwf_item_description in bank20_reloc {
    .include "core/vwf_state.i"

    .scope items_description {
    """Small-VWF item-description renderer entry-points."""
draw_trampoline:
    jsr.w draw
    rtl
draw_trampoline_pos:
    jsr.w draw_pos
    rtl
draw_pos:
    phb
    phd
    phx
    ldx #0x0100
    phx
    pld
    phk
    plb
    rep #0x20
    lda.w 0x0000, y
    clc
    adc 0x29
    sta.l render.tilemap_offset
    tax
    sep #0x20
    iny
    iny
    bra draw_string
draw:
; X = destination offset, Y = source address, A = source bank
    phb
    phd
    phx
    phx
    ldx #0x0100
    phx
    pld
    plx
    pha
    plb
    rep #0x20
    phx
    txa
    clc
    adc 0x29
    sta.l render.tilemap_offset
    plx
    sep #0x20
draw_string:
; Description tiles $180..$1FF (allocator base $80 + attribute bit 8), VRAM $5800..$5FF0, disjoint from the field
; items at $100..$169 ($5000..$56A0).
    rep #0x20
    lda.w #0x0080
    sta.l vwf_cfg.tile_id_base
    sep #0x20
    lda.b #0x80
    sta.l vwf_cfg.slot_budget
    lda.b #0x01
    sta.l vwf_cfg.flags
; Its own flush through the secondary slot (the primary is rewritten per item slot). CHR sits at buffer offset
; $80 * 16 = $800, not $1800.
;   src offset = $0800, vram dest = ($5000 + $800) / 2 = $2C00, size = $80 tiles * 16 = $0800 bytes
    rep #0x20
    lda #0x0800
    sta.l vwf_engine.flush_b.src_offset
    lda #0x2C00
    sta.l vwf_engine.flush_b.vram_word
    lda #0x0800
    sta.l vwf_engine.flush_b.byte_count
    sep #0x20
; Keep Y: render.init's CHR clear leaves Y = 0, and the loop would read the $00 at $20:0000 and draw nothing.
    phy
    jsr.w render.init
    rep #0x20
    lda.w #0x0080
    jsr.w render_allocator.init_with_tile_id_wide
    sep #0x20  ; M = 16 would read two bytes per char and soft-lock in wait_for_vblank
    ply
_char_loop:
    lda.w 0x0000, y
    beq _char_loop_exit
    iny
    cmp #0x01
    beq _move_to
    cmp #0x02
    beq _newline
    phx
    phy
    jsr.w render.display_char
    ply
    plx
    bra _char_loop
_char_loop_exit:
    jsr.w _transfer_item_description
    jsr.w render.deinit
; NMI flushes $5800..$5FF0 next vblank.
    lda.b #0x01
    sta.l vwf_engine.flush_b.dirty
    plx
    pld
    plb
    rts
_move_to:
    rep #0x20
    lda.w 0x0000, y
    iny
    iny
    tax
    clc
    adc 0x29
    sta.l render.tilemap_offset
    sep #0x20
    bra _reset_render
_newline:
    rep #0x20
    txa
    clc
    adc.w #0x0040
    tax
    clc
    adc 0x29
    sta.l render.tilemap_offset
    sep #0x20
_reset_render:
    lda #0x08
    sta.b render.bits_left_on_tile
    jsr.w render_allocator.increment
    bra _char_loop
_transfer_item_description:
    jsr.w wait_for_vblank
; Description CHR only: buffer + $800 to VRAM byte $5800, 128 tiles, disjoint from the field items at $5000.
    dma_transfer_to_vram_call(render.buffer_ptr + 0x800, 0x5800 >> 1, 0x800, 0x1801)
    rts
    }
}
