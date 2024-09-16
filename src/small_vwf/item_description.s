.scope items_description {
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
    ldx     #0x0100
    phx
    pld
    phk
    plb
    rep #0x20
    lda.w 0x0000,y
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

;    cpy.b render.last_drawn_text_ptr
;    beq _already_drawn
;    sty.b render.last_drawn_text_ptr

draw_string:
    jsr.w render.init

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
_already_drawn:
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
    dma_transfer_to_vram_call(render.buffer_ptr, 0x5000>>1, render.buffer_size, 0x1801)
    rts
}
