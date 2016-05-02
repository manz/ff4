.macro wait_for_vblank_inline() {
    pha
negative:
	lda.l 0x004212
	bmi negative
positive:
	lda.l 0x004212
	bpl positive
	pla
}


.macro dma_transfer_to_vram_nofunk(source_address, vram_pointer, count, dma_mode) {
    channel = 7
    PHP
	PHA
	PHX
	phb
	lda #0x00
	pha
	plb

	LDA.B #0x80
	STA.W 0x2115

	LDX.W #vram_pointer
	STX.W 0x2116

	LDX.W #dma_mode
	STX.W 0x4300+(channel<<4)

	LDA.B #source_address >> 16
	STA.W 0x4304+(channel<<4)

	LDX.W #source_address
	STX.W 0x4302+(channel<<4)

	LDX.W #count
	STX.W 0x4305+(channel<<4)
	LDA.B #0x01<<channel
	STA 0x420B

	NOP
	NOP

	plb

	PLX
	PLA
	PLP
}

.macro dma_transfer_to_vram_call(source, vramptr, count, mode)
{
    php
    pha
    phx
    pea.w return_addr-1
    pea.w source & 0xFFFF
    pea.w  0x00FF & (source >> 16)
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
    pea.w 0x00FF & (source >> 16)
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

