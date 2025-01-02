*=0x13d7ef
	ldx.w #assets_credits_text_bin & 0xffff
*=0x13d7f5
	lda.b #assets_credits_text_bin >> 16

; Augments cutscene duration to show the additional text.
*=0x13d61d
	lda.b #0x20
*=0x13d623
	lda.b #0x0b

*=0x13f016
	.incbin 'assets/the_end_gfx.bin'
