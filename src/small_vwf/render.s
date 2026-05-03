VARS_BUFFER = 0x710000

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
buffer = 0x704000
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

; tile_id in A
init_with_tile_id:
    sta.l allocated_tile_id
    rts

init:
    pha
    lda.b #0x00
    sta.l allocated_tile_id
    pla
    rts
.if BATTLE_ENABLED {
init_battle_far:
    jsr.l 0x13ff12 ; play song
    jsr.w init
    jsr.w battle_render.clear_buffer
    rtl
}
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

__var_base = 0x63
bits_left_on_tile = __var_base + 0x10
temp = bits_left_on_tile + 1
counter = temp + 1
prev_char = counter + 2
current_char = prev_char + 1

tilemap_offset = 0x1d

buffer_ptr = 0x703000
buffer_size = 0x300

last_drawn_text_ptr = buffer_ptr + buffer_size + 2

;font_ptr = assets_menu_font_dat ; moved to direct use of assets_menu_font_dat

init:
; Initialize the renderer
; clear a chunk of ram
; resets variables
.if ENABLE_KERNING_MENU {
    stz.b prev_char
}
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
    pha
    asl
    asl
    asl
    clc
    adc 1, s
    tax
    pla
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
    lda.w #0x0008
    sta.b counter
    sep #0x20

char_line_loop:
    rep #0x20
    lda.w #0x0000
    sep #0x20
.if ENABLE_KERNING_MENU {
    jsr.w _adjust_bits_left_for_kerning
}
    lda.b bits_left_on_tile

    cmp #0x08
    bne _shift

_read_8x8_char:
    lda.l assets_menu_font_dat, x

    inx
    xba
    bra _store

_shift:
    ; PPU multiplication is being used by the NMI which wrecks char lines once in a while
    phx
    lda.l assets_menu_font_dat, x
   ; bne _really_shift
   ; inx
   ; xba
   ; bra _skip_empty_pixel_line
_really_shift:
    xba
    lda #0x00
    xba

    ; make jump_table_pointer
    pha
    lda.b bits_left_on_tile
    asl
    tax
    pla

    rep #0x20
    jmp.w (_mul_table, x)
_mul_table:
    .dw _mul_0
    .dw _mul_1
    .dw _mul_2
    .dw _mul_3
    .dw _mul_4
    .dw _mul_5
    .dw _mul_6
    .dw _mul_7
    .dw _mul_8

_mul_8:
_mul_7:
    asl ; 1
_mul_6:
    asl ; 2
_mul_5:
    asl ; 3
_mul_4:
    asl ; 4
_mul_3:
    asl ; 5
_mul_2:
    asl ; 6
_mul_1:
    asl ; 7
_mul_0:
    sep #0x20
    plx
    inx
.if 0 {
_shift:
    ; expects bitsleft in A
    phx
    tax
    lda.l vwf_shift_table, x
    sta.l 0x004202


    plx
    lda.l assets_menu_font_dat, x
    bne _really_shift
    inx
    xba
    bra _skip_empty_pixel_line
_really_shift:
    inx

    sta.l 0x004203        ; MULTIPLICAND

    rep #0x20
    nop
    nop
    nop
    nop
    lda.l 0x004216    ; the result is stored in 0x4216-0x4217
    sep #0x20
}
_store:

    xba
    phx
    tyx
    ora.l buffer_ptr + 1, x
    sta.l buffer_ptr + 1, x
    xba
    ora.l buffer_ptr + 0x10 + 1, x
    sta.l buffer_ptr + 0x10 + 1, x
    txy
    plx
_skip_empty_pixel_line:
    iny
    iny
    dec.b counter
    bne char_line_loop

    rep #0x20
    stz.b temp
    lda.w #0x0000
    sep #0x20


brk_bits_left:
    lda.l assets_menu_font_dat, x

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

.if ENABLE_KERNING_MENU {
_adjust_bits_left_for_kerning:
{

    lda.b bits_left_on_tile
    cmp #8
    beq _overflow
    sta.b temp

    jsr.w get_kerning_adjustment
    bcc _adjustment
    bra _end
_adjustment:
    pha
    lda.b temp
    clc
    adc 1,s
    sta.b temp
.if 0 {
    bpl _no_adjustment

    and.b #0x80
    sta.b bits_left_on_tile
    sta.b temp
    lda.l render_allocator.allocated_tile_id
    dec
    sta.l render_allocator.allocated_tile_id
    jsr.w _refresh_destination_pointer
}
_no_adjustment:

    pla
_end:
    lda.b temp
    sta.b bits_left_on_tile
_overflow:
    pha
    lda.b current_char
    sta.b prev_char
    pla
    rts
}

get_kerning_adjustment_linear_search:
{
    phx
    phy
    rep #0x20
    jsr.w _get_kerning_adjustment_linear_search
    sep #0x20
    ply
    plx
    rts
}

_get_kerning_adjustment_linear_search:
{
    phb
    pea.w font_table >> 16
    plb

kerning_table_offset = 256 * 9
    ldy.w #kerning_table_offset
    lda.w assets_menu_font_dat, y
    beq not_found
    dec
    tax
    lda.w #0x0000

_loop:
    txa
    pha
    asl
    clc
    adc 0x01, s
    clc
    adc.w #kerning_table_offset + 2

    tay
    pla

    lda.w assets_menu_font_dat, y ; Load 16-bit char pair
    cmp.b prev_char
    beq found_pair               ; Found exact match!

    txa
    dec
    tax

    bpl _loop

not_found:
    lda.w #0x0000
    sec
    plb
    plb
    rts

found_pair:
    iny
    iny
    lda.w assets_menu_font_dat, y
    and.w #0x00FF
    clc
    plb
    plb
    rts
}

_get_kerning_adjustment_binary_search:
{
    phb
    pea.w font_table >> 16
    plb

    kerning_table_offset = 256 * 9
    ldy.w #kerning_table_offset
    lda.w assets_menu_font_dat, y
    beq not_found

    sec
    sbc.w #0x0001
    pha
    lda.w #0x0000
    pha
    pea.w 0x0000

_loop:
    lda 0x0005, s
    cmp 0x0003, s
    bcc _not_found_cleanup

    lda 0x0005, s
    sec
    sbc 0x0003, s
    lsr
    clc
    adc 0x0003, s
    sta 0x0001, s

    lda 0x0001, s
    asl
    clc
    adc 0x0001, s
    clc
    adc.w #kerning_table_offset + 2
    tay

    lda.w assets_menu_font_dat, y
    cmp.b prev_char
    beq _found
    bcc _search_upper

_search_lower:
    lda 0x0001, s
    sec
    sbc.w #0x0001
    bcc _not_found_cleanup    ; mid was 0, underflow → not found
    sta 0x0005, s
    bra _loop

_search_upper:
    lda 0x0001, s
    clc
    adc.w #0x0001
    sta 0x0003, s
    bra _loop

_not_found_cleanup:
    pla
    pla
    pla
not_found:
    lda.w #0x0000
    sec
    plb
    plb
    rts

_found:
    iny
    iny
    lda.w assets_menu_font_dat, y
    and.w #0x00FF
    ply
    ply
    ply
    clc
    plb
    plb
    rts
}

get_kerning_adjustment:
{
    phx
    phy
    rep #0x20
    jsr.w _get_kerning_adjustment_binary_search
    sep #0x20
    ply
    plx
    rts
}

small_vwf_kerning_linear_ext:
    jsr.w get_kerning_adjustment_linear_search
    rtl

small_vwf_kerning_binary_ext:
    jsr.w get_kerning_adjustment
    rtl
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


