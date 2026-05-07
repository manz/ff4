"""
Reusable assembly helpers (`dma_transfer_to_*` macros, `_wait_for_vblank_inline`, save/restore variable
mirrors, padding macros) shared across the patch sources.
"""
.macro _wait_for_vblank_inline() {
    pha
_negative:
    lda.l 0x004212
    bmi _negative
_positive:
    lda.l 0x004212
    bpl _positive
    pla
}


.macro _dma_transfer_to_vram_nofunk(source_address, vram_pointer, count, dma_mode) {
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
    """Call the shared dma_transfer_to_vram helper."""
    php
    pha
    phx
    phb
    lda #0x00
    pha
    plb
    pea.w _return_addr - 1
    pea.w source & 0xFFFF
    pea.w 0x00FF & ( source >> 16 )
    pea.w vramptr
    pea.w count
    pea.w mode
    jmp.w dma_transfer_to_vram
_return_addr:
    plb
    plx
    pla
    plp
}


.macro dma_transfer_to_palette_call(source, count) {
    """Call the shared dma_transfer_to_palette helper."""
    php
    pha
    phx
    pea.w _return_addr - 1
    pea.w source & 0xFFFF
    pea.w 0x00FF & ( source >> 16 )
    pea.w count
    jmp.w dma_transfer_to_palette
_return_addr:
    plx
    pla
    plp
}

.macro _save_8_bit_var(var, mirror_addr) {
    lda.b var
    sta.l mirror_addr + var
    stz.b var
}

.macro _restore_8_bit_var(var, mirror_addr) {
    lda.l mirror_addr + var
    sta.b var
}

.macro _save_16_bit_var(var, mirror_addr) {
;    lda.b var
;    sta.l mirror_addr + var
;    lda.b var + 1
;    sta.l mirror_addr + var + 1
    stz.b var
    stz.b var + 1
}

.macro _restore_16_bits_var(var, mirror_addr) {
    lda.l mirror_addr + var
    sta.b var
    lda.l mirror_addr + var + 1
    sta.b var + 1
}

.macro _set_ax_8bit() {
    sep #0x30
}

.macro _set_ax_16() {
    rep #0x30
}

.macro _set_a_8_x_16() {
    sep #0x10
    rep #0x20
}

.macro fill_value(value, count) {
    """Emit `count` 16-bit words of `value`."""
    .for k := 0, count {
    .dw value
    }
}
.macro zero(count) {
    """Emit `count` zero-words."""
    fill_value(0, count)
}

.macro pad_nop(count) {
    """
    Emit `count` NOP bytes. Used after surgical patches that replace a longer instruction sequence with a
    shorter one — keeps downstream call-sites and addresses anchored.
    """
    .for k := 0, count {
    nop
    }
}
