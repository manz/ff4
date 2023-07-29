sram_base = 0x700000
.macro long_sram_store(src) {
	phy
	phx

	php
	rep #0x20
	pha
	tya
	clc
	adc.b src
	tax
	pla
	sep #0x20
	plp
	sta.l sram_base, x

	plx
	ply
}


copy_battle_char:
	lda.l sram_base + 0x2E00, x
	sta (0x00),Y
	lda.l sram_base + 0x2E00 + 0x30, x
	sta (0x02),Y
	rtl


battle_display_char:
{
	pha
	lda.l 0x7FFFFF
	cmp #0x85
	beq sram_store
wram_store:
	pla
	phx
	sta (0x34),Y
	lda #0xFF
	sta (0x32),Y
	iny
	lda 0x36
	sta (0x32),Y
	sta (0x34),Y
	iny
	plx
	rtl
sram_store:
	pla
	phx
	long_sram_store(0x34)
	lda #0xFF
	long_sram_store(0x32)
	iny
	lda 0x36
	long_sram_store(0x32)
	long_sram_store(0x34)
	iny
	plx
	rtl
}

battle_display_dakuten_char:
{
	pha
	lda.l 0x7FFFFF
	cmp #0x85
	beq sram_store
wram_store:
	pla
	phx
	sec
	sbc #0xF
	asl
	tax
	lda 0x16FA40, x
	sta (0x32), y
	lda 0x16FA41, x
	sta (0x34), y
	iny
	lda 0x36
	sta (0x32), y
	sta (0x34), y
	iny
	plx
	rtl

sram_store:
	pla
	phx
	sec
	sbc #0x0F
	asl
	tax
	lda 0x16FA40, x
	long_sram_store(0x32)
	lda 0x16FA41, x
	long_sram_store(0x34)
	iny
	lda 0x36
	long_sram_store(0x32)
	long_sram_store(0x34)
	iny
	plx
	rtl

}
