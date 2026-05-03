.include "src/definitions.s"
.include "src/libmz.i"
.table "text/ff4_menus.tbl"
.import "libmz"
.import "dialog"
.extern assets_items_dat
.extern assets_font_dat
.extern font_table
.include "src/kerning.s"

wait_for_action_button:
    """RTL trampoline that polls the gamepad until any action button is pressed (delegates to vanilla `waitpad`)."""
    jsr.w waitpad
    rtl

.if ENABLE_BUTTON_DISPLAY {
get_action_button_id:
    lda.l 0x0016A9
    bne custom_mapping
    lda.b #0x00
    xba
    lda.b #0x00
    rts
custom_mapping:
    lda.b #0x00
    xba
    lda.l 0x001A37  ; action button id location
    rts
}

.macro make_color(r, g, b) {
    red := ( r >> 3 ) & 0b11111
    blue := ( b >> 3 ) & 0xb11111
    green := ( g >> 3 ) & 0xb11111
    .dw ( blue << 10 ) + ( green << 5 ) + red
}

.macro hex_color(color) {
    make_color(color & 0xff, ( color >> 8 ) & 0xff, ( color >> 16 ))
}


button_colors:
    ; 0
    ; A Button
    make_color(0xeb, 0x1a, 0x1d)
    make_color(120, 10, 12)
    ; 1
    ; B Button
    make_color(0xfe, 0xce, 0x15)
    make_color(136, 108, 0)
    ; 2
    ; X Button
    make_color(0x07, 0x49, 0xb4)
    make_color(0, 53, 144)
    ; 3
    ; Y Button
    make_color(0x00, 0x8d, 0x45)
    make_color(0, 70, 34)
    ; 4
    ; Select Buttons
    .dw 0b0011110111101111
    .dw 0b0001110011100111


update_palette:
    """
    Refresh menu/dialog palette entries from the configured colour at $16AA.
    With ENABLE_BUTTON_DISPLAY, also pulls the action-button id and writes
    the matching colour + shadow pair from `button_colors` into $0CEF/$0CF1.
    """
    ldx.w 0x16AA
    stx.w 0x0CDD
    stx.w 0x0CE5
.if ENABLE_BUTTON_DISPLAY {
    stx.w 0x0CED
; black for the shadow but it could be a darker version of the color
    ldx.w #0x0000
    stx.w 0x0CEF
    pha
    jsr.w get_action_button_id

    cmp #0x04
    bcc _proceed
    ldx.w #5
_proceed:
    asl
    asl
    tax

    rep #0x20
    lda.l button_colors, x  ; color
    sta.w 0x0CF1
    lda.l button_colors + 2, x  ; shadow color
    sta.w 0x0CEF
    sep #0x20
    lda #0x00
    xba
    pla
}
rtl

window_palette:
    ; Menu color palette I probably need to add one color
    ; Palette 1, normal text
    .db 0x00, 0x00
    .db 0x00, 0x40
    .db 0xCE, 0x39
    .db 0xFF, 0x7F

; Palette 2, greyed out text patched replaced the grey with black
    .db 0x00, 0x00
    .db 0x00, 0x40
    .db 0x00, 0x00
    .db 0xff, 0x7f

; Palette  3, yellow
    .db 0x00, 0x00
    .db 0x00, 0x40
    .db 0x80, 0x02
    .db 0x7F, 0x03

; Palette 4, red
    .db 0x00, 0x00
    .db 0x00, 0x40
    .db 0xFF, 0x40
    .db 0x7F, 0x2E

;current_pos = 0x3d
;current_text_pointer = 0x0772
; 0x07 used for loop counter

; ******************
; ** Declarations **
; ******************
    vram_tile_set_pointer = 0x6800
    vram_tile_map_pointer = 0x2C00
    WRAM = field_vwf.tile_buffer

    WRAMPTR = 0x2108

vwfinit:
    """
    One-shot dialog VWF initialisation: clear the WRAM scratch area,
    DMA the VWF tile buffer + the original font tileset into VRAM,
    and point BG3 at the new $6000 tile-set base.
    """
    jsr.w clr  ; on efface un peu de Wram

    jsr.w wait_for_vblank
    dma_transfer_to_vram_call(WRAM, vram_tile_set_pointer, 0x0690, 0x1801)
    jsr.w wait_for_vblank
    dma_transfer_to_vram_call(WRAM, vram_tile_set_pointer + 0x348, 0x0690, 0x1801)

; copy the old font tileset
    jsr.w wait_for_vblank
    dma_transfer_to_vram_call(0x0AF000, 0x6000, 0x800, 0x1801)
    jsr.w wait_for_vblank
    dma_transfer_to_vram_call(0x0AF000 + 0x800, 0x6000 + 0x400, 0x800, 0x1801)
    jsr.w wait_for_vblank

; Sets the BG3 vram pointer to 0x6000
    lda 0x210C
    and #0xF0
    clc
    adc #0x06
    sta 0x210C

    rtl
    ;** routine principale

vwfstart:
    """Main entry for dialog VWF rendering: sets 8-bit A / 16-bit X-Y, enables HDMA, and falls into the parser loop that consumes the dialog text stream."""
    sep #0x20
    rep #0x10

    lda.b #0x01
    sta.w 0x420D

; 0x04-0x4F
    var_base = 0x23
    CNTR = var_base
    CURRENT_C = var_base + 2
    BITSLEFT = var_base + 4
    font_addr = var_base + 6  ; 7 8
    oldtilepos = var_base + 9
    TILEPOS = var_base + 11
    dialog_ptr = 0x20

    no_wait_for_action = 0xcb

    lda #0
    jsr.w setup_font

    php
    sep #0x20
.macro clear_16_bit(var) {
    stz.b var
    stz.b var + 1
}
clear_16_bit(CNTR)
clear_16_bit(CURRENT_C)
clear_16_bit(BITSLEFT)
clear_16_bit(oldtilepos)
clear_16_bit(TILEPOS)
plp

lda.b #0x08
sta.b BITSLEFT

jsr.l vwfinit

jsr.w load_letter
bra firstrun

main:
    jsr.w load_letter_inc

firstrun:
    jmp.w parse
    bra main

fin:
    ; this fixes a subtle issue where NPCs sprites positions and their collision table would be corrupted
    xba
    lda.b #0
    xba
    rtl

;******************
;** Parsing code **
;******************

parse:

; Message Break
    cmp #0x00
    bne _nxt1
    lda #0x01
    sta 0xDE
.if ENABLE_BUTTON_DISPLAY {
    jsr.w draw_button
}
jmp.w fin

_nxt1:
    cmp #0x01
    bne _nxt2
    jmp.w newline

_nxt2:
    cmp #0x02
    bne _nxt3
    jmp.w space

_nxt3:
    ;Changement de Musique
    cmp #0x03
    bne _nxt4
    jmp.w musique

_nxt4:
    ; Nom des personages
    cmp #0x04
    bne _nxt5
    jmp.w display_character_name

_nxt5:

; wait
    cmp #0x05
    bne _nxt6
    jmp.w _code05

_nxt6:
    ; Close window after dialog end
    cmp #0x06
    bne _nxt7
    lda #0x02
    sta 0xde
    jmp.w fin
    ; Display item

_nxt7:
    cmp #0x07
    bne _nxt8
    jmp.w _code07

; display gils count

_nxt8:
    cmp #0x08
    bne _nxt_fb
    jmp.w _code08

_nxt_fb:
    cmp #0xFC
    bne _nxt_fc
    jmp.w suit3

_nxt_fc:
    cmp #0xFE
    bne _nxt_fe
    jsr.w load_letter_inc
    jsr.w setup_font
    jmp.w main

_nxt_fe:

    jsr.w makeptr
    jsr.w shift_new
    jsr.w wdisplay

    jmp.w main


;***********
;** Space **
;***********

space:
    jsr.w load_letter_inc
    clc
    adc.b TILEPOS
    jmp.w main

;******************
;Cout en gils
;******************

_code08:
    lda.w 0x08F8
    sta.b 0x30
    lda.w 0x08F9
    sta.b 0x31
    lda.w 0x08FA
    sta.b 0x32
    jsr.l 0x15C324

    ldx.w #0x0000

_loop_b5c3:
    lda.b 0x36, x
    cmp #0x80
    bne _loop_b5d2
    inx
    cpx.w #0x0005
    beq _loop_b5d2
    jmp.w _loop_b5c3

_loop_b5d2:
    lda #0x00
    xba
    lda.b 0x36, x
    ; Old code
    ;00B5D4 STA 0x0774,Y
    ;00B5D7 LDA #0xFF
    ;00B5D9 STA 0x0834,Y
    ;00B5DC INY
    phx
    phy

    sta.b CURRENT_C  ; appel de la vwf

    jsr.w makeptr
    jsr.w shift_new
    jsr.w wdisplay

    ply
    plx

    inx
    cpx.w #0x0006
    bne _loop_b5d2

    jmp.w main

;****************
;** printfname **
;****************

display_character_name:
{
    jsr.w load_letter_inc
    xba
    lda #0x00
    xba

    asl
    pha
    asl
    clc
    adc 1, s
    tax
    pla

    ldy.w #0x0000
next:
    lda #0x00
    xba
    lda 0x1500, x
    sta.b CURRENT_C
    cmp #0xFF
    beq exit

    phx
    phy
    jsr.w makeptr
    jsr.w shift_new
    jsr.w wdisplay
    ply
    plx

suite:
    inx

    iny
    cpy.w #0x0006
    beq exit
    jmp.w next
exit:
    jmp.w main
}
;********************
;** Nouvelle ligne **
;********************

newline:
    rep #0x20
    lda.w #8
    sep #0x20

    sta.b BITSLEFT

    lda.b TILEPOS
    clc
    ;Second line
    cmp #0x1A + 1
    bcs suit

    lda.b #0x1A
    sta.b TILEPOS
    bra end

suit:

;Third Line
    cmp #0x34 + 1
    bcs suit2
    lda.b #0x34
    sta.b TILEPOS
    bra end

suit2:

;Forth Line
    cmp #0x4E + 1
    bcs suit3

    lda.b #0x4E
    sta.b TILEPOS
    bra end

suit3:
    ; that's where new ends up

.if ENABLE_BUTTON_DISPLAY {
    jsr.w draw_button
}
lda.b #0x08
sta.b BITSLEFT

stz.b CURRENT_C
stz.b TILEPOS
jsr.w clr
jsr.w waitpad
jsr.w wdisplay

end:

    jmp.w main

draw_button:
{
    jsr.w get_action_button_id
    cmp #4  ; select
    bne _normal_button
    lda #0xa5
    bra _store
_normal_button:
    lda #0xa4
_store:
    sta.b CURRENT_C
    jsr.w draw_ending_symbol

    rts
}

draw_ending_symbol:
    pha

    lda #0x08
    sta.b BITSLEFT
    lda #0x4E + 24
    sta.b oldtilepos

    lda #0x4E + 25
    sta.b TILEPOS


    ldx.w #0xa2 * 17
    ldy.w #0xcc0
    jsr.w makeptr
    jsr.w shift_new
    jsr.w wdisplay

    pla
    rts


;*************
;** Musique **
;*************

musique:
    jsr.w load_letter_inc
    sta 0x1E01
    lda.b #0x01
    sta 0x1E00

    jsr.l 0x048004
    jmp.w main

_code05:
    jsr.w load_letter_inc
    xba
    lda #0x00
    xba
    asl
    asl
    asl
    tax
    stx 0x08F4
    ldx 0x0000
    stx 0x08F6
{
    ldx 0x08f4
    beq skip
loop:
    cpx 0x08f6

    bne loop
skip:
    ldx.w #0x0000
    stx 0x08f4
}
jmp.w main


.macro vwf_putchar() {
    phx
    phy
    sta.b CURRENT_C
    jsr.w makeptr
    jsr.w shift_new
    jsr.w wdisplay
    ply
    plx
}

; display item or magic

_code07:
{
    lda 0x08FB

    rep #0x20
    and.w #0x00FF
    pha
    clc
    adc 0x01, s  ; x2
    adc 0x01, s  ; x3
    asl
    asl  ; x12
    tax
    pla
    sep #0x20

; skip first char (usually a space or a symbol.)
    inx
    lda #0x0b  ; 11 characters

loop:
    pha
    lda.b #0x00
    xba
    lda.l assets_items_dat, x
    cmp #0xFF
    beq cleanup
    vwf_putchar()

    inx

    pla
    dec
    bne loop
    bra end
cleanup:
    pla
end:
    lda #0x00
    jmp.w main
}

;*******************
;** Shift Routine **
;*******************

shift_new:
    rep #0x20
    lda.w #0x0010
    sta.b CNTR
    sep #0x20

boucle2:
    rep #0x20
    lda.w #0x0000
    sep #0x20
    phx
    lda.b BITSLEFT

    cmp #0x08
    bne _shift
    plx
    ; LDA.L assets_font_dat,X
    phy
    txy
    lda.b [font_addr], y
    tyx
    ply
    inx
    xba
    bra _store

_shift:
.if 1 {
    plx
    phy
    txy
    lda.b [font_addr], y
    tyx
    ply

    xba
    lda #0x00
    xba

; make jump_table_pointer
    phx
    pha
    lda.b BITSLEFT
    asl
    tax
    pla

    rep #0x20
    jmp.w (_mul_table, x)
_mul_table:
    .dw _mul_0
    .dw _mul_1
    .dw _mul_2
    .dw _mul_3
    .dw _mul_4
    .dw _mul_5
    .dw _mul_6
    .dw _mul_7
    .dw _mul_8

_mul_8:
_mul_7:
    asl  ; 1
_mul_6:
    asl  ; 2
_mul_5:
    asl  ; 3
_mul_4:
    asl  ; 4
_mul_3:
    asl  ; 5
_mul_2:
    asl  ; 6
_mul_1:
    asl  ; 7
_mul_0:
    plx
    sep #0x20
    inx
} else {
    tax  ; using math multiplication
    lda.l vwf_shift_table, x
    sta.l 0x004202  ; MULTPILIER


    plx

    phy
    txy
    lda.b [font_addr], y
    tyx
    ply
    inx

    sta.l 0x004203  ; MULTIPLICAND

    rep #0x20
    nop
    nop
    nop
    nop
    lda.l 0x004216  ; the result is stored in 0x4216-0x4217
    sep #0x20
}

_store:

; ff
; notre bidule
; 0b11111111 A
; 0b00000001 B
; roll B and B xor A ?
; 0b11 = white
; 0b10 = black
; 0b01 = window background
; 0b00 = transparent
TEXT_SHADOW := 1

xba
phx
tyx


pha
ora.l WRAM, x
sta.l WRAM, x
pla

pha
ora.l WRAM + 1, x
sta.l WRAM + 1, x
pla

.if TEXT_SHADOW {
    pha
    eor.l WRAM + 3, x
    sta.l WRAM + 3, x
    pla
    pha
    eor.l WRAM + 2, x
    sta.l WRAM + 2, x
    pla
}
xba

pha
ora.l WRAM + 0x20, x
sta.l WRAM + 0x20, x
pla

pha
ora.l WRAM + 0x20 + 1, x
sta.l WRAM + 0x20 + 1, x
pla

.if TEXT_SHADOW {
    pha
    eor.l WRAM + 3 + 0x20, x
    sta.l WRAM + 3 + 0x20, x
    pla

    pha
    eor.l WRAM + 2 + 0x20, x
    sta.l WRAM + 2 + 0x20, x
    pla
}
txy
plx

iny
iny

dec.b CNTR
beq _exit
jmp.w boucle2

_exit:

    rep #0x20
.if ENABLE_KERNING {
; Routine reads the pair from CURRENT_C (DP), no need to load A.
    jsr.w dialog_get_kerning_adjustment_binary_search
    pha
} else {
    lda.w #0x0000
    pha
}

txy
lda.b [font_addr], y
tyx


sep #0x20
pha

lda.b BITSLEFT

clc
sbc.b 0x01, s

clc
adc.b 0x02, s

loopdec:
    cmp #0x00
    bmi coupe
    beq coupe

    sta.b BITSLEFT
    pla
    pla
    pla
    rts

coupe:
    clc
    adc #0x08
    inc.b TILEPOS
    bra loopdec


vwf_shift_table:
    .db 0b00000000  ; dummy entrie =0
    .db 0b00000010  ; 1
    .db 0b00000100  ; 2
    .db 0b00001000  ; 3
    .db 0b00010000  ; 4
    .db 0b00100000  ; 5
    .db 0b01000000  ; 6
    .db 0b10000000  ; 7
    .db 0b10000000  ; 8

; Long-form (RTL) wrapper for cross-bank callers and Python tests.

setup_font_ext:
    jsr.w setup_font
    rtl

setup_font:
    ; A: font index
{
    phx
    pha
    asl
    clc
    adc 0x01, s
    xba
    lda #0
    xba
    tax
    pla

    rep #0x20
    lda.l font_table, x
    sta.b font_addr
    sep #0x20

    lda.l font_table + 2, x
    sta.b font_addr + 2
    plx
    rts
}

;************************
;** build font pointer **
;************************

makeptr:
    pha

    ldx.w #0x0000
    ldy.w #0x0000
    lda.b CURRENT_C
    xba
    lda #0x00
    xba
    rep #0x20
    pha
    asl
    asl
    asl
    asl
    adc.b 0x01, s
    tax
    pla
    lda.w #0x0000
    sep #0x20

    lda.b TILEPOS
    sta.b oldtilepos
    rep #0x20
    asl
    asl
    asl
    asl
    asl
    sta.b oldtilepos
    tay
    sep #0x20
    pla
    rts


;===================================
;Clear Wram
;
;===================================

clr:
{
    phx
    ldx.w #0x0000
solid_bg_loop:
    lda.b #0xff
    sta.l WRAM, x
    inx

    lda.b #0x00
    sta.l WRAM, x
    inx
    cpx.w #0x0D10

    bne solid_bg_loop


transparent_bg_loop:
    lda.b #0x00
    sta.l WRAM, x
    inx
    cpx.w #0x0D20
    bne transparent_bg_loop

    plx
    rts
}

wait_key_up:
    lda.l 0x000602
    bne wait_key_up
    lda.l 0x000603
    bne wait_key_up
    rts

wait_key_down:
{
    ACTION_BUTTON := 0x80
    lda.l 0x000602
    bit #ACTION_BUTTON  ; Action button
    bne exit
    wai
    bra wait_key_down
exit:
    rts
}

;Wait for joypad 1

waitpad:
{
    pha
    lda.b no_wait_for_action
    bne nowaitpad

    .if ENABLE_DIALOG_SKIP {
    jsr.w wait_key_up
    }
    jsr.w wait_key_down
    bra end


nowaitpad:
    lda.b #0x30
    {
loop:
    jsr.w wait_for_vblank
    dec
    bne loop
    }
end:
    pla
    jsr.w clr
    jsr.w wait_for_vblank
    dma_transfer_to_vram_call(WRAM, vram_tile_set_pointer, 0x0690, 0x1801)
    jsr.w wait_for_vblank
    dma_transfer_to_vram_call(WRAM + 0x348, vram_tile_set_pointer + 0x348, 0x0690, 0x1801)
    rts
}

wdisplay:
    ; wait for vblank to transfer
    jsr.w wait_for_vblank

    sep #0x20


;macro expansion

    php
    pha
    phx

    lda.b #0x80
    sta.w 0x2115

    rep #0x20
    pha

    lda.b oldtilepos
    lsr  ; addresse vram /2
    clc
    adc.w #vram_tile_set_pointer
    sta.w 0x2116


    lda.b oldtilepos
    clc
    adc.w #WRAM & 0xFFFF
    sta.w 0x4372

    pla
    sep #0x20

    channel = 7

    ldx.w #0x1801
    stx.w 0x4370
    lda.b #0xFF & ( WRAM >> 16 )
    sta.w 0x4374

    ldx.w #0x0040
    stx.w 0x4375
    lda.b #0x01 << 7
    sta 0x420B

    nop
    nop

    plx
    pla
    plp


    lda.b no_wait_for_action
    bne nowindow

    dma_transfer_to_vram_call(winmap, vram_tile_map_pointer, endwinmap - winmap, 0x1801)
    bra window

nowindow:
    dma_transfer_to_vram_call(intromap, vram_tile_map_pointer, endintromap - intromap, 0x1801)

window:
{
    lda.b CURRENT_C
    cmp #0xFF
    beq no_char_wait
    wai  ; wait for interrupts
    lda.b no_wait_for_action  ; add extra wait when in "story telling".
    beq no_char_wait
    jsr.w wait_for_vblank
    jsr.w wait_for_vblank
no_char_wait:
}
rts


winmap:
.if TEXT_SHADOW {
    .if ENABLE_BUTTON_DISPLAY {
    last_character_palette := 2
    } else {
    last_character_palette := 1
    }
    .dw 0x2000, 0x2000, 0x2019, 0x2500, 0x2502, 0x2504, 0x2506, 0x2508, 0x250A, 0x250C, 0x250E, 0x2510, 0x2512, 0x2514, 0x2516, 0x2518, 0x251A, 0x251C, 0x251E, 0x2520, 0x2522, 0x2524, 0x2526, 0x2528, 0x252A, 0x252C, 0x252E, 0x2530, 0x2532, 0x201A, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2019, 0x2501, 0x2503, 0x2505, 0x2507, 0x2509, 0x250B, 0x250D, 0x250F, 0x2511, 0x2513, 0x2515, 0x2517, 0x2519, 0x251B, 0x251D, 0x251F, 0x2521, 0x2523, 0x2525, 0x2527, 0x2529, 0x252B, 0x252D, 0x252F, 0x2531, 0x2533, 0x201A, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2019, 0x2534, 0x2536, 0x2538, 0x253A, 0x253C, 0x253E, 0x2540, 0x2542, 0x2544, 0x2546, 0x2548, 0x254A, 0x254C, 0x254E, 0x2550, 0x2552, 0x2554, 0x2556, 0x2558, 0x255A, 0x255C, 0x255E, 0x2560, 0x2562, 0x2564, 0x2566, 0x201A, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2019, 0x2535, 0x2537, 0x2539, 0x253B, 0x253D, 0x253F, 0x2541, 0x2543, 0x2545, 0x2547, 0x2549, 0x254B, 0x254D, 0x254F, 0x2551, 0x2553, 0x2555, 0x2557, 0x2559, 0x255B, 0x255D, 0x255F, 0x2561, 0x2563, 0x2565, 0x2567, 0x201A, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2019, 0x2568, 0x256A, 0x256C, 0x256E, 0x2570, 0x2572, 0x2574, 0x2576, 0x2578, 0x257A, 0x257C, 0x257E, 0x2580, 0x2582, 0x2584, 0x2586, 0x2588, 0x258A, 0x258C, 0x258E, 0x2590, 0x2592, 0x2594, 0x2596, 0x2598, 0x259A, 0x201A, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2019, 0x2569, 0x256B, 0x256D, 0x256F, 0x2571, 0x2573, 0x2575, 0x2577, 0x2579, 0x257B, 0x257D, 0x257F, 0x2581, 0x2583, 0x2585, 0x2587, 0x2589, 0x258B, 0x258D, 0x258F, 0x2591, 0x2593, 0x2595, 0x2597, 0x2599, 0x259B, 0x201A, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2019, 0x259C, 0x259E, 0x25A0, 0x25A2, 0x25A4, 0x25A6, 0x25A8, 0x25AA, 0x25AC, 0x25AE, 0x25B0, 0x25B2, 0x25B4, 0x25B6, 0x25B8, 0x25BA, 0x25BC, 0x25BE, 0x25C0, 0x25C2, 0x25C4, 0x25C6, 0x25C8, 0x25CA, 0x25CC, ( 0x21CE + ( last_character_palette << 10 ) ), 0x201A, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2019, 0x259D, 0x259F, 0x25A1, 0x25A3, 0x25A5, 0x25A7, 0x25A9, 0x25AB, 0x25AD, 0x25AF, 0x25B1, 0x25B3, 0x25B5, 0x25B7, 0x25B9, 0x25BB, 0x25BD, 0x25BF, 0x25C1, 0x25C3, 0x25C5, 0x25C7, 0x25C9, 0x25CB, 0x25CD, ( 0x21CF + ( last_character_palette << 10 ) ), 0x201A, 0x2000, 0x2000
} else {
    .dw 0x2000, 0x2000, 0x2019, 0x2100, 0x2102, 0x2104, 0x2106, 0x2108, 0x210A, 0x210C, 0x210E, 0x2110, 0x2112, 0x2114, 0x2116, 0x2118, 0x211A, 0x211C, 0x211E, 0x2120, 0x2122, 0x2124, 0x2126, 0x2128, 0x212A, 0x212C, 0x212E, 0x2130, 0x2132, 0x201A, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2019, 0x2101, 0x2103, 0x2105, 0x2107, 0x2109, 0x210B, 0x210D, 0x210F, 0x2111, 0x2113, 0x2115, 0x2117, 0x2119, 0x211B, 0x211D, 0x211F, 0x2121, 0x2123, 0x2125, 0x2127, 0x2129, 0x212B, 0x212D, 0x212F, 0x2131, 0x2133, 0x201A, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2019, 0x2134, 0x2136, 0x2138, 0x213A, 0x213C, 0x213E, 0x2140, 0x2142, 0x2144, 0x2146, 0x2148, 0x214A, 0x214C, 0x214E, 0x2150, 0x2152, 0x2154, 0x2156, 0x2158, 0x215A, 0x215C, 0x215E, 0x2160, 0x2162, 0x2164, 0x2166, 0x201A, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2019, 0x2135, 0x2137, 0x2139, 0x213B, 0x213D, 0x213F, 0x2141, 0x2143, 0x2145, 0x2147, 0x2149, 0x214B, 0x214D, 0x214F, 0x2151, 0x2153, 0x2155, 0x2157, 0x2159, 0x215B, 0x215D, 0x215F, 0x2161, 0x2163, 0x2165, 0x2167, 0x201A, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2019, 0x2168, 0x216A, 0x216C, 0x216E, 0x2170, 0x2172, 0x2174, 0x2176, 0x2178, 0x217A, 0x217C, 0x217E, 0x2180, 0x2182, 0x2184, 0x2186, 0x2188, 0x218A, 0x218C, 0x218E, 0x2190, 0x2192, 0x2194, 0x2196, 0x2198, 0x219A, 0x201A, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2019, 0x2169, 0x216B, 0x216D, 0x216F, 0x2171, 0x2173, 0x2175, 0x2177, 0x2179, 0x217B, 0x217D, 0x217F, 0x2181, 0x2183, 0x2185, 0x2187, 0x2189, 0x218B, 0x218D, 0x218F, 0x2191, 0x2193, 0x2195, 0x2197, 0x2199, 0x219B, 0x201A, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2019, 0x219C, 0x219E, 0x21A0, 0x21A2, 0x21A4, 0x21A6, 0x21A8, 0x21AA, 0x21AC, 0x21AE, 0x21B0, 0x21B2, 0x21B4, 0x21B6, 0x21B8, 0x21BA, 0x21BC, 0x21BE, 0x21C0, 0x21C2, 0x21C4, 0x21C6, 0x21C8, 0x21CA, 0x21CC, 0x21CE, 0x201A, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2019, 0x219D, 0x219F, 0x21A1, 0x21A3, 0x21A5, 0x21A7, 0x21A9, 0x21AB, 0x21AD, 0x21AF, 0x21B1, 0x21B3, 0x21B5, 0x21B7, 0x21B9, 0x21BB, 0x21BD, 0x21BF, 0x21C1, 0x21C3, 0x21C5, 0x21C7, 0x21C9, 0x21CB, 0x21CD, 0x21CF, 0x201A, 0x2000, 0x2000
}

endwinmap:

intromap:
    .dw 0x2000, 0x2000, 0x2000, 0x2100, 0x2102, 0x2104, 0x2106, 0x2108, 0x210A, 0x210C, 0x210E, 0x2110, 0x2112, 0x2114, 0x2116, 0x2118, 0x211A, 0x211C, 0x211E, 0x2120, 0x2122, 0x2124, 0x2126, 0x2128, 0x212A, 0x212C, 0x212E, 0x2130, 0x2132, 0x2000, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2000, 0x2101, 0x2103, 0x2105, 0x2107, 0x2109, 0x210B, 0x210D, 0x210F, 0x2111, 0x2113, 0x2115, 0x2117, 0x2119, 0x211B, 0x211D, 0x211F, 0x2121, 0x2123, 0x2125, 0x2127, 0x2129, 0x212B, 0x212D, 0x212F, 0x2131, 0x2133, 0x2000, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2000, 0x2134, 0x2136, 0x2138, 0x213A, 0x213C, 0x213E, 0x2140, 0x2142, 0x2144, 0x2146, 0x2148, 0x214A, 0x214C, 0x214E, 0x2150, 0x2152, 0x2154, 0x2156, 0x2158, 0x215A, 0x215C, 0x215E, 0x2160, 0x2162, 0x2164, 0x2166, 0x2000, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2000, 0x2135, 0x2137, 0x2139, 0x213B, 0x213D, 0x213F, 0x2141, 0x2143, 0x2145, 0x2147, 0x2149, 0x214B, 0x214D, 0x214F, 0x2151, 0x2153, 0x2155, 0x2157, 0x2159, 0x215B, 0x215D, 0x215F, 0x2161, 0x2163, 0x2165, 0x2167, 0x2000, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2000, 0x2168, 0x216A, 0x216C, 0x216E, 0x2170, 0x2172, 0x2174, 0x2176, 0x2178, 0x217A, 0x217C, 0x217E, 0x2180, 0x2182, 0x2184, 0x2186, 0x2188, 0x218A, 0x218C, 0x218E, 0x2190, 0x2192, 0x2194, 0x2196, 0x2198, 0x219A, 0x2000, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2000, 0x2169, 0x216B, 0x216D, 0x216F, 0x2171, 0x2173, 0x2175, 0x2177, 0x2179, 0x217B, 0x217D, 0x217F, 0x2181, 0x2183, 0x2185, 0x2187, 0x2189, 0x218B, 0x218D, 0x218F, 0x2191, 0x2193, 0x2195, 0x2197, 0x2199, 0x219B, 0x2000, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2000, 0x219C, 0x219E, 0x21A0, 0x21A2, 0x21A4, 0x21A6, 0x21A8, 0x21AA, 0x21AC, 0x21AE, 0x21B0, 0x21B2, 0x21B4, 0x21B6, 0x21B8, 0x21BA, 0x21BC, 0x21BE, 0x21C0, 0x21C2, 0x21C4, 0x21C6, 0x21C8, 0x21CA, 0x21CC, 0x21CE, 0x2000, 0x2000, 0x2000
    .dw 0x2000, 0x2000, 0x2000, 0x219D, 0x219F, 0x21A1, 0x21A3, 0x21A5, 0x21A7, 0x21A9, 0x21AB, 0x21AD, 0x21AF, 0x21B1, 0x21B3, 0x21B5, 0x21B7, 0x21B9, 0x21BB, 0x21BD, 0x21BF, 0x21C1, 0x21C3, 0x21C5, 0x21C7, 0x21C9, 0x21CB, 0x21CD, 0x21CF, 0x2000, 0x2000, 0x2000

endintromap:


gils_window_size := 10

gils_window_tilemap_1:
    .dw 0, 0
    .db 0x16, 0x20
    fill_value(0x2017, gils_window_size - 2)
    .db 0x18, 0x20

gils_window_tilemap_2:
    .dw 0, 0

    .db 0x19, 0x20
    fill_value(0x20ff, gils_window_size - 2)
    .db 0x1a, 0x20

gils_window_tilemap_3:
    .dw 0, 0

    .db 0x19, 0x20
    fill_value(0x20ff, gils_window_size - 2)
    .db 0x1a, 0x20

gils_window_tilemap_4:
    .dw 0, 0

    .db 0x19, 0x20
    fill_value(0x20ff, gils_window_size - 2)
    .db 0x1a, 0x20

    fill_value(0x0000, 0x16)

    .db 0x19, 0x20
    fill_value(0x20ff, gils_window_size - 2 - 4)
    .text "G"
    .db 0x20
    .text "i"
    .db 0x20
    .text "l"
    .db 0x20
    .text "s"
    .db 0x20

    .db 0x1a, 0x20  ; "gil"
    fill_value(0x0000, 0x16)
    .db 0x1b, 0x20
    fill_value(0x201c, gils_window_size - 2)
    .db 0x1d, 0x20

gils_window_tilemap_4_end:
