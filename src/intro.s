"""
Boot-time splash-screen routine: imported by `ff4.s`, sets up SNES + graphics mode 3, blits the intro tilemap
and chains into the title screen.
"""
; ----------------------------------------------------------------
; Module: intro
; Splash-screen routine. Imported by ff4.s at boot time.
; ----------------------------------------------------------------

.include "libmz.i"  ; macros (dma_transfer_to_vram_call, etc.)
.import "preamble"
.include "bank20.i"
.import "libmz"
.import "assets"
.import "bank20_helpers"
.import "vanilla"


.alloc _intro_block in bank20_reloc {
start_splash_screen:
"""Boot-time splash-screen entry point."""
; initialise SNES
    jsr.w initialize_snes

; set register modes
    rep #0x10  ; make X & Y 16-bits
    sep #0x20  ; make A 8-bits

; initialise graphics hardware
    lda #0x03  ; graphics mode 3
    sta ppu.BGMODE
    lda #0x01  ; enable plane 0
    sta ppu.TM
    lda #0x00  ; set plane 0 memory to 0x0000, 32x32 chars
    sta ppu.BG1SC
    lda #0x01  ; set plane 0 character set to 0x1000
    sta ppu.BG12NBA

; copy intro map data
    dma_transfer_to_vram_call(intro_tilemap, 0x0000, sizeof(intro_tilemap), 0x1801)

; copy color palettes
    dma_transfer_to_palette_call(intro_palette, sizeof(intro_palette))

; copy intro tile set
    dma_transfer_to_vram_call(intro_tiles, 0x1000, sizeof(intro_tiles), 0x1801)

    jsr.w _splash_screen_fade_in

    lda #0x80
    jsr.w _gamepad_interruptable_loop

    jsr.w _splash_screen_fade_out

    jsr.l clear_ram
; runs the original jsl routines
    jsr.l init_hw_regs
    jsr.l field_clear_ram

    rtl

; TODO: rewrite as HDMA table would make it look less hacky.

_splash_screen_fade_out:
    {
    stz 0x00
loop:
    inc 0x00
    lda #0x0F
    sbc 0x00
    sta ppu.INIDISP
    lda 0x00
    cmp #0x0F
    beq exit
    lda 0x00
    asl
    asl
    asl
    asl
    inc
    sta ppu.MOSAIC

    jsr.w wait_for_vblank
    jsr.w wait_for_vblank
    jsr.w wait_for_vblank
    bra loop
exit:
    rts
    }


_splash_screen_fade_in:
    {
    stz 0x00
loop:
    inc 0x00
    lda 0x00
    sta ppu.INIDISP
    asl
    asl
    asl
    asl
    sta 0x01
    lda #0xF0
    sec
    sbc 0x01
    inc
    sta ppu.MOSAIC

    jsr.w wait_for_vblank
    jsr.w wait_for_vblank

    lda 0x00
    cmp #0x0F
    beq exit
    bra loop
exit:
    rts
    }


_gamepad_interruptable_loop:
; 8bit A: Number of iterations
    {
    jsr.w enable_gamepad
    jsr.w wait_for_vblank

    ldx cpu_regs.PAD1L  ; lecture depuis joystick
    bne exit  ; si on appuye sur quelque chose on sort du delay
    dec
    bne _gamepad_interruptable_loop
exit:
    jsr.w disable_gamepad
    rts
    }
}
