VARS_BUFFER = 0x702F02

.macro initialize(var) {
    lda.b var
    sta.l VARS_BUFFER + var
}

.macro initialize_long(var) {
    initialize(var)
    initialize(var + 1)
    initialize(var + 2)
}

.macro restore(var) {
    lda.b VARS_BUFFER + var
    sta.b var
}

.macro restore_long(var) {
    restore(var)
    restore(var + 1)
    restore(var + 2)
}

.macro set_var_value(var, value) {
    lda.b #value
    sta.b var
}

.scope vram_copy {
buffer = 0x703200
save_dialog_vram_far:
    jsr.l 0x14fd0f ; original save
    jsr.l wait_for_vblank_long
    phb
    tdc
    pha
    plb
    lda #0x80
    sta 0x2115
    ldx #0x2800
    stx 0x2116
    ldx 0x2139
    lda #0x81
    sta 0x4300
    lda #0x39
    sta 0x4301
    ldx.w #buffer & 0xffff
    stx 0x4302
    lda.b #buffer >> 16
    sta 0x4304
    ldx.w #render.buffer_size
    stx 0x4305
    lda #0x01
    sta 0x420b
    plb
    rtl
restore_dialog_gfx_far:
    lda #0x00
    pha
    plb
    ldx #0x2800
    stx 0x011d
    ldx.w #buffer & 0xffff
    stx 0x011f
    lda.b #buffer >> 16
    sta 0x0121
    ldx.w #render.buffer_size
    stx 0x0122
    jsr.w _transfer_to_vram
    jsr.l wait_for_vblank_long
    jsr.l 0x14ffd6 ; original restore
    rtl

; clone of the original copy to be able to call it from the 0x20 bank.
_transfer_to_vram:
    phb
    tdc
    pha
    plb
    lda #0x80
    sta 0x2115
    tdc
    sta 0x420c
    ldy 0x011d
    sty 0x2116
    lda #0x01
    sta 0x4300
    rep #0x20

    lda #0x2118
    sta 0x4301

    lda 0x011f
    sta 0x4302
    lda 0x0121
    sta 0x4304
    sep #0x20
    lda 0x0123
    sta 0x4306
    lda #0x01
    sta 0x420b
    plb
    rts
}

.scope render_allocator {
allocated_tile_id = 0x702F00
init:
    pha
    lda.b #0x00
    sta.l allocated_tile_id
    pla
    rts

init_battle_far:
    jsr.l 0x13ff12 ; play song
    jsr.w init
    jsr.w battle_render.clear_buffer
    rtl

increment:
    pha
    lda.l allocated_tile_id
    inc
    and #0xff
    sta.l allocated_tile_id
    pla
    rts

get:
    lda.l allocated_tile_id
    rts
}

.scope render {
; variables

__var_base = 0x00
bits_left_on_tile = __var_base + 0x10
temp = bits_left_on_tile + 1
counter = temp + 1
current_char = counter + 2

tilemap_offset = 0x1d

buffer_ptr = 0x703000
buffer_size = 0x200

last_drawn_text_ptr = buffer_ptr + buffer_size + 2

font_ptr = assets_menu_font_dat
length_table_ptr = assets_menu_font_length_table_dat

init:
; Initialize the renderer
; clear a chunk of ram
; resets variables
    initialize(bits_left_on_tile)
    jsr.w render_allocator.init
    pha
    set_var_value(bits_left_on_tile, 0x08)
    lda.b bits_left_on_tile
_brk_init_bits:
    pla
    initialize(temp)
    stz.b temp
    pha
    lda #0x00
    phx
    ldx.w #buffer_size
_clear_loop:
    lda.b #0xFF
    sta.l buffer_ptr, x
    lda.b #0x00
    sta.l buffer_ptr + 1, x
    dex
    dex
    bne _clear_loop
    plx
    pla

    initialize(counter)
rts

deinit:
{
    restore_long(buffer_ptr)
    restore(bits_left_on_tile)
    restore(temp)
    restore(counter)
    rts
}

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

    sta.b oldtilepos
    rep #0x20
    asl
    asl
    asl
    asl
    sta.b oldtilepos
    tay
    sep #0x20
    pla
    rts
}

display_char:
{
    sta.b current_char

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

_store:

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

.macro save_a(code) {
    pha
    {{code}}
    pla
}

.macro with_long_a(code) {
    rep #0x20
    {{ code }}
    sep #0x20
}

tilemap_write_no_inc:
    _base_addr = 0x7e0000
    lda.l render_allocator.allocated_tile_id

    ldx.b tilemap_offset

    sta.l _base_addr,x
    lda.l _base_addr + 1,x
    ora.b #0x01
    sta.l _base_addr + 1,x

    rts

tilemap_write:
    pha
    jsr.w tilemap_write_no_inc
    jsr.w render_allocator.increment
    with_long_a({
        inc.b tilemap_offset
        inc.b tilemap_offset
    })
    pla
    rts
}


