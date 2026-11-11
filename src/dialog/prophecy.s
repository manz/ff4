"""
Mysidia's prophecy (event special $32), told like the prologue.

Vanilla decodes the prophecy's lines with NMI off (InitHWRegs), then fades in and reveals them row by row through
the palettes. The dialogue VWF replaces that decoder with a page renderer that waits a vblank per letter, so with
NMI off it waited forever on a black screen. The special keeps its setup (window graphics, the blank BG3 tilemap)
and its ending (BG3 scroll, palettes), and in between runs the prologue's sequence: NMI on, the message in whole
pages (WHOLE_PAGES: each faded in, held, faded out), window-less, on BG3 alone with black paper; the screen dark
again, the field gets its screens back. The text sits where the prologue's does: the dialogue window's raster
code sets BG3's scroll each frame.
"""
.import "core/preamble"
.include "dialog/vwf.i"

.label _get_dialog_pointer_bank1_high = 0x00B41D
.label _open_dialog_window = 0x00B30D
.label _close_dialog_window = 0x00B3A0
.label _prophecy_end = 0x00C871  ; the special's ending after its `lda #3 / jsr FadeOut`: BG3 scroll, palettes, NMI
_PROPHECY := 0x6A  ; bank 1 high: the prophecy's message
_NMI_ON := 0x81  ; NMI and the joypad read
_BG3_ONLY := 0x04  ; the main screen: the text alone, not the field behind it
_FIELD_TM := 0x17  ; InitHWRegs' main screen (BG1-3, sprites), which vanilla's ending leaves for the field
_FIELD_TS := 0x11  ; its sub screen
_BG3_PALETTES := 0x7E0CDB  ; the CGRAM shadow's BG3 palettes, 4 colours each (vanilla's reveal writes them too)
_PAPER := 2  ; colour 1, the window's fill, in bytes
_PALETTE := 8  ; bytes

.alloc at 0x00C7AD {
; Special_32 after the BG3 tilemap clear: `lda #$6a / sta $b2 / jsr GetDlgPtr1H`, the decode, the reveal
    lda.b #_BG3_ONLY
    sta.w ppu.TM
    stz.w ppu.TS
    rep #0x20
    lda.w #0x0000  ; black paper: no window under the text, palette 0 for the blanks, 1 for the letters
    sta.l _BG3_PALETTES + _PAPER
    sta.l _BG3_PALETTES + _PALETTE + _PAPER
    sep #0x20
    lda.b #_NMI_ON
    sta.w cpu_regs.NMITIMEN
    lda.b #WHOLE_PAGES
    sta.b no_wait_for_action
    lda.b #_PROPHECY
    sta.b 0xB2
    jsr.w _get_dialog_pointer_bank1_high
    jsr.w _open_dialog_window
    jsr.w _close_dialog_window
    stz.b no_wait_for_action
    lda.b #_FIELD_TM
    sta.w ppu.TM
    lda.b #_FIELD_TS
    sta.w ppu.TS
    jmp.w _prophecy_end
}
