.macro wait_for_vblank_inline() {
    pha
_negative:
    lda.l 0x004212
    bmi _negative
_positive:
    lda.l 0x004212
    bpl _positive
    pla
}


.macro dma_transfer_to_vram_nofunk(source_address, vram_pointer, count, dma_mode) {
    channel = 7
    php
    pha
    phx
    phb
    lda #0x00
    pha
    plb
    lda.b #0x80
    sta.w 0x2115
    ldx.w #vram_pointer
    stx.w 0x2116
    ldx.w #dma_mode
    stx.w 0x4300 + ( channel << 4 )
    lda.b #source_address >> 16
    sta.w 0x4304 + ( channel << 4 )
    ldx.w #source_address
    stx.w 0x4302 + ( channel << 4 )
    ldx.w #count
    stx.w 0x4305 + ( channel << 4 )
    lda.b #0x01 << channel
    sta 0x420B
    nop
    nop
    plb
    plx
    pla
    plp
}

.macro dma_transfer_to_vram_call(source, vramptr, count, mode) {
    php
    pha
    phx
    phb
    lda #0x00
    pha
    plb
    pea.w return_addr - 1
    pea.w source & 0xFFFF
    pea.w 0x00FF & ( source >> 16 )
    pea.w vramptr
    pea.w count
    pea.w mode
    jmp.w dma_transfer_to_vram
return_addr:
    plb
    plx
    pla
    plp
}


.macro dma_transfer_to_palette_call(source, count) {
    php
    pha
    phx
    pea.w return_addr - 1
    pea.w source & 0xFFFF
    pea.w 0x00FF & ( source >> 16 )
    pea.w count
    jmp.w dma_transfer_to_palette
return_addr:
    plx
    pla
    plp
}

.macro save_8_bit_var(var, mirror_addr) {
    lda.b var
    sta.l mirror_addr + var
    stz.b var
}

.macro restore_8_bit_var(var, mirror_addr) {
    lda.l mirror_addr + var
    sta.b var
}

.macro save_16_bit_var(var, mirror_addr) {
;    lda.b var
;    sta.l mirror_addr + var
;    lda.b var + 1
;    sta.l mirror_addr + var + 1
    stz.b var
    stz.b var + 1
}

.macro restore_16_bits_var(var, mirror_addr) {
    lda.l mirror_addr + var
    sta.b var
    lda.l mirror_addr + var + 1
    sta.b var + 1
}

.macro set_ax_8bit() {
    sep #0x30
}

.macro set_ax_16() {
    rep #0x30
}

.macro set_a_8_x_16() {
    sep #0x10
    rep #0x20
}

.macro fill_value(value, count) {
    .for k := 0, count {
    .dw value
    }
}
.macro zero(count) {
    fill_value(0, count)
}
