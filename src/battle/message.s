.scope battle_render {
    buffer_ptr = 0x703000
    buffer_size = 8*128*2

    bits_left_on_tile = 0xA9
    tilemap_offset = bits_left_on_tile + 2
    temp = bits_left_on_tile + 4
    counter = bits_left_on_tile + 6
    current_char = bits_left_on_tile + 8

    font_ptr = assets_menu_font_dat
    length_table_ptr = assets_menu_font_length_table_dat

init:
    jsr.w clear_buffer
    pha
    lda.b #0x08
    sta.b bits_left_on_tile
    pla

    stz.b temp

    stz.b counter
    jsr.w render_allocator.init
    rts

clear_buffer:
    pha
    phx
    ldx.w #0
_clear_loop:
    lda.b #0xFF
    sta.l buffer_ptr, x
    lda.b #0x00
    sta.l buffer_ptr + 1, x
    inx
    inx
    cpx.w #buffer_size + 2
    bne _clear_loop
    plx
    pla
    rts

clear_buffer_far:
    jsr.w clear_buffer
    rtl

make_pointers:
{
    pha

    ldx.w #0x0000
    ldy.w #0x0000
    lda.b current_char
    xba
    lda.b #0x00
    xba
    rep #0x20
    asl
    asl
    asl
    asl
    tax
    lda.w #0x0000
    sep #0x20

    lda.l render_allocator.allocated_tile_id

    rep #0x20
    asl
    asl
    asl
    asl
    tay
    sep #0x20
    pla
    rts
}

display_char:
    pha
    phx
    phy
    jsr.w _display_char
    ply
    plx
    pla
    ldy.b tilemap_offset

    rts

_display_char:
{
    sta.b current_char
    sty.b tilemap_offset

    jsr.w make_pointers

    rep #0x20
    lda.w #0x0010
    sta.b counter
    sep #0x20

char_line_loop:
    rep #0x20
    lda.w #0x0000
    sep #0x20

    lda.b bits_left_on_tile

    cmp #0x08
    bne _shift

_read_8x8_char:
    lda.l font_ptr, x
    xba
    lda.b #0x00
    xba
    inx
    xba
    bra _store

_shift:
    ; expects bitsleft in A
    phx
    tax
    lda.l vwf_shift_table, x
    sta.l 0x004202


    plx
    lda.l font_ptr, x

    inx

    sta.l 0x004203        ; MULTIPLICAND

    rep #0x20
    nop
    nop
    nop
    nop
    lda.l 0x004216    ; the result is stored in 0x4216-0x4217
    sep #0x20
_and_store:
    xba
    phx
    tyx
    ora.l buffer_ptr, x
    sta.l buffer_ptr, x
    xba
    ora.l buffer_ptr + 0x10, x
    sta.l buffer_ptr + 0x10, x
    txy
    plx
    iny
    bra _next_line
_store:

    xba
    phx
    tyx
    ;ora.l buffer_ptr, x
    sta.l buffer_ptr, x
    xba
    ;ora.l buffer_ptr + 0x10, x
    sta.l buffer_ptr + 0x10, x
    txy
    plx
    iny

_next_line:
    dec.b counter
    bne char_line_loop

    rep #0x20
    stz.b temp
    lda.w #0x0000
    ldx.w #0x0000
    sep #0x20

    lda.b current_char
    tax

brk_bits_left:
    lda.l length_table_ptr, x

    sta.b temp

    rep #0x20
    clc

    lda.w #0x0000
    sep #0x20

    lda.b bits_left_on_tile

    clc
    sbc.b temp

loopdec:
    cmp #0x00
    bmi coupe
    beq coupe

    sta.b bits_left_on_tile
    jsr.w tilemap_write_no_inc

    rts

coupe:
    clc
    adc.b #0x08
    jsr.w tilemap_write
    bra loopdec
}

tilemap_write_no_inc:
    lda.l render_allocator.allocated_tile_id

    phy
    ldy.b tilemap_offset
    sta (0x34), y
    lda #0xff
    sta (0x32), y
    iny
    lda 0x36
    sta (0x32), y
    ora.b #0x01
    sta (0x34), y
    ply
    rts


tilemap_write:
    pha
    jsr.w tilemap_write_no_inc
    jsr.w render_allocator.increment
    rep #0x20
        inc.b tilemap_offset
        inc.b tilemap_offset
    sep #0x20
    pla
    rts
}

.scope messages_vwf {
    dakuten_table = 0x16fa40
        ; put char
        ; write to the tilemap if needed
        ; maintain counters
    put_fixed_char:
        cmp #0x42
        bcc put_fixed_char_dakuten

    put_fixed_char_no_dakuten:
        jmp.w battle_render.display_char

    put_fixed_char_dakuten:
        jmp.w battle_render.display_char

    ; far calls for the new implementation
    put_fixed_char_far:
        jsr.w put_fixed_char
        rtl

    put_fixed_char_dakuten_far:
        jsr.w put_fixed_char_dakuten
        rtl

    put_fixed_char_no_dakuten_far:
        jsr.w put_fixed_char_no_dakuten
        rtl

    ; inits the renderer for the messages window
    ; flips the flag for enabling the messages renderer.
    init:
        jsr.l battle_flags.set_vwf_render
        jsr.w battle_render.init
        rtl

    ; deinit the renderer
    ; disables messages renderer falling back to fixed mode.
    deinit:
        jsr.l battle_flags.clear_vwf_render
        ; vram transfer was moved to a trampoline in the battle nmi.
        rtl

    _wait_for_vblank: {
        inc     0x1811
    _wait:
        lda     0x1811
        bne     _wait
        rts
    }

DMA_TRANSFER:
    dma_transfer_to_vram_call(battle_render.buffer_ptr, 0xb000>>1, battle_render.buffer_size, 0x1801)
    jsr.l 0x03fe03
    rtl
}



