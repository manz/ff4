.macro dma_transfer_to_vram_call(source, vramptr, count, mode)
{
    php
    pha
    phx
    pea.w return_addr-1
    pea.w source & 0xFFFF
    pea.w source >> 16
    pea.w vramptr
    pea.w count
    pea.w mode
    jmp.w dma_transfer_to_vram
return_addr:
    plx
    pla
    plp
}
.macro dma_transfer_to_vram_call(source, vramptr, count, mode) 
{
    php 
    pha 
    phx 
    pea.w return_addr-1 
    pea.w source & 0xFFFF 
    pea.w source >> 16 
    pea.w vramptr 
    pea.w count 
    pea.w mode 
    jmp.w dma_transfer_to_vram 
    return_addr: 
    plx 
    pla 
    plp 
}

.macro dma_transfer_to_palette_call(source, count)
{
    php 
    pha 
    phx 
    pea.w return_addr-1 
    pea.w source & 0xFFFF 
    pea.w source >> 16 
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
    lda.b var
    sta.l mirror_addr + var
    lda.b var - 1
    sta.l mirror_addr + var + 1
    stz.b var
    stz.b var + 1
}

.macro restore_16_bits_var(var, mirror_addr) {
    lda.l mirror_addr + var
    sta.b var
    lda.l mirror_addr + var + 1
    sta.b var + 1
}
