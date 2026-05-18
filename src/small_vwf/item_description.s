"""Small-VWF item-description renderer."""
.include "src/vwf_state.i"
.include "src/items.i"

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
    sta.b render.tilemap_offset
    tax
    sep #0x20
    iny
    iny
    bra draw_string
draw:
; +x: destination offset
; +y: source address
;  a: source bank
    phb
    phd
    phx
    phx
    ldx.w #0x0100
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
    sta.b render.tilemap_offset
    plx
    sep #0x20
draw_string:
; Region config: description CHR lives in tile_id range $180..$1FF
; (allocator base $80, with attr-byte OR $01 -> effective tile_id
; $180 ; VRAM byte $5800..$5FF0). Disjoint from the field-items
; window at $100..$169 -> VRAM $5000..$56A0 ; the two regions used
; to fight for VRAM $5000 (both DMAs targeted there) and the last
; render stomped the other.
;
;   Region map (BG3 CHR at VRAM $4000)
;     $00..$FF   static menu font ($4000..$4FF0)
;     $100..$169 field-menu items ($5000..$56A0)
;     $180..$1FF item description  ($5800..$5FF0)
    rep #0x20
    lda.w #0x0080
    sta.l VWF_CONFIG_BASE + VwfConfig.tile_id_base
    sep #0x20
    lda.b #0x80
    sta.l VWF_CONFIG_BASE + VwfConfig.slot_budget
    lda.b #0x01
    sta.l VWF_CONFIG_BASE + VwfConfig.flags
; Description flush descriptor uses the SECONDARY slot so the
; description region ($5800..$5FF0) gets its own DMA independent of
; the primary descriptor that items_menu_vwf rewrites every per-slot
; call. Without this, items_menu_vwf's tight $400 primary window
; (treasure region only) caused the description CHR to never flush
; once items + description coexisted in the field menu.
;
;   src offset = $180 * 16            = $1800 buffer bytes
;   vram dest  = ($5000 + $800) / 2   = $2C00 word
;   size       = $80 tiles * 16       = $800 bytes
;
; DIRTY_B is set at the tail of draw_string ; display_char also sets
; primary DIRTY which the field-items renderer covers in its own
; flush, so no clearing is needed here.
    rep #0x20
    lda.w #0x1800
    sta.l VWF_CHR_SRC_OFFSET_B
    lda.w #0x2C00
    sta.l VWF_CHR_VRAM_WORD_B
    lda.w #0x0800
    sta.l VWF_CHR_BYTE_COUNT_B
    sep #0x20
; Preserve Y across render.init: the per-region CHR clear loop
; tays the budget word count and lands Y=$0000 on exit, which
; collapsed _char_loop into an immediate _char_loop_exit (the loop
; reads `lda.w $0000,y` -> $20:0000 = $00 terminator) and the
; description never rendered a single glyph.
    phy
    jsr.w render.init
    rep #0x20
    lda.w #0x0080
    jsr.w render_allocator.init_with_tile_id_wide
    sep #0x20  ; _char_loop reads bytes one at a time ; M=16 here
; would lda two source bytes per char and soft-lock
; in wait_for_vblank.
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
; Description finished writing to buffer ; raise the secondary
; dirty flag so the NMI flush DMAs $5800..$5FF0 next vblank.
    lda.b #0x01
    sta.l VWF_CHR_DIRTY_B
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
    sta.b render.tilemap_offset
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
    sta.b render.tilemap_offset
    sep #0x20
_reset_render:
    lda #0x08
    sta.b render.bits_left_on_tile
    jsr.w render_allocator.increment
    bra _char_loop
_transfer_item_description:
    jsr.w wait_for_vblank
; DMA description's CHR slice only: SRAM $703800 (= buffer + $80*16
; for tile_id_base $80) to VRAM word $2C00 (= byte $5800), $800
; bytes covering 128 tile_ids. Keeps the upload disjoint from the
; field-items DMA at byte $5000 / word $2800.
    dma_transfer_to_vram_call(render.buffer_ptr + 0x800, 0x5800 >> 1, 0x800, 0x1801)
    rts
}
