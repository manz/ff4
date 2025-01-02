start_splash_screen:
; initialise SNES
    jsr.w initialize_snes

; set register modes
    rep #0x10        ; make X & Y 16-bits
    sep #0x20        ; make A 8-bits

; initialise graphics hardware
    lda #0x03        ; graphics mode 3
    sta 0x2105
    lda #0x01        ; enable plane 0
    sta 0x212c
    lda #0x00        ; set plane 0 memory to 0x0000, 32x32 chars
    sta 0x2107
    lda #0x01        ; set plane 0 character set to 0x1000
    sta 0x210b

    ; copy intro map data
    dma_transfer_to_vram_call(assets_intro_map, 0x0000, assets_intro_map__size, 0x1801)

    ; copy color palettes
    dma_transfer_to_palette_call(assets_intro_col, assets_intro_col__size)

    ; copy intro tile set
    dma_transfer_to_vram_call(assets_intro_set, 0x1000, assets_intro_set__size, 0x1801)

    jsr.w splash_screen_fade_in

    lda #0x80
    jsr.w gamepad_interruptable_loop

    jsr.w splash_screen_fade_out

    jsr.l clear_ram
    ; runs the original jsl routines
    jsr.l 0x15C8DF
    jsr.l 0x15C9AA

    rtl

; TODO: rewrite as HDMA table would make it look less hacky.
splash_screen_fade_out:
{
    stz 0x00
loop:
    inc 0x00
    lda #0x0F
    sbc 0x00
    sta 0x2100
    lda 0x00
    cmp #0x0F
    beq exit
    lda 0x00
    asl
    asl
    asl
    asl
    inc
    sta 0x2106

    jsr.w wait_for_vblank
    jsr.w wait_for_vblank
    jsr.w wait_for_vblank
    bra loop
exit:
    rts
}


splash_screen_fade_in:
{
    stz 0x00
loop:
    inc 0x00
    lda 0x00
    sta 0x2100
    asl
    asl
    asl
    asl
    sta 0x01
    lda #0xF0
    sec
    sbc 0x01
    inc
    sta 0x2106

    jsr.w wait_for_vblank
    jsr.w wait_for_vblank

    lda 0x00
    cmp #0x0F
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

    ldx 0x4218    ; lecture depuis joystick
    bne exit    ; si on appuye sur quelque chose on sort du delay
    dec
    bne gamepad_interruptable_loop
exit:
    jsr.w disable_gamepad
    rts
}
