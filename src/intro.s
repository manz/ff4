start_splash_screen:
; initialise SNES
    jsr.w initialize_snes

; set register modes
	rep #$10        ; make X & Y 16-bits
	sep #$20        ; make A 8-bits

; initialise graphics hardware
	lda #$03        ; graphics mode 3
	sta $2105
	lda #$01        ; enable plane 0
	sta $212c
	lda #$00        ; set plane 0 memory to $0000, 32x32 chars
	sta $2107
	lda #$01        ; set plane 0 character set to $1000
	sta $210b

    ; copy intro map data
    dma_transfer_to_vram_call(assets_intro_map, 0x0000, assets_intro_map__size, 0x1801)

    ; copy color palettes
    dma_transfer_to_palette_call(assets_intro_col, assets_intro_col__size)

    ; copy intro tile set
    dma_transfer_to_vram_call(assets_intro_set, 0x1000, assets_intro_set__size, 0x1801)

    jsr.w splash_screen_fade_in

	lda #$80
	jsr.w gamepad_interruptable_loop

    jsr.w splash_screen_fade_out

    ; runs the original jsl routines
	jsr.l $15C8DF
	jsr.l $15C9AA

	rtl

splash_screen_fade_out:
{
    stz $00
loop:
	inc $00
	lda #$0F
	sbc $00
	sta $2100
	lda $00
	cmp #$0F
	beq exit
	lda $00
	asl
	asl
	asl
	asl
	inc
	sta $2106

	jsr.w wait_for_vblank
	jsr.w wait_for_vblank
	jsr.w wait_for_vblank
	bra loop
exit:
    rts
}


splash_screen_fade_in:
{
    stz $00
loop:
	inc $00
	lda $00
	sta $2100
	asl
	asl
	asl
	asl
	sta $01
	lda #$F0
	sec
	sbc $01
    inc
	sta $2106

	jsr.w wait_for_vblank
	jsr.w wait_for_vblank

	lda $00
	cmp #$0F
	beq exit
    bra loop
exit:
    rts
}


gamepad_interruptable_loop:
; 8bit A: Number of iterations
{
    jsr.w enable_gamepad
	jsr.w wait_for_vblank

	ldx $4218	; lecture depuis joystick
	bne exit	; si on appuye sur quelque chose on sort du delay
	dec
	bne gamepad_interruptable_loop
exit:
    jsr.w disable_gamepad
	rts
}
