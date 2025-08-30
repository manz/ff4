.include 'src/definitions.s'

;current_pos = 0x3d
;current_text_pointer = 0x0772
; 0x07 used for loop counter

; ******************
; ** Declarations **
; ******************
    vram_tile_set_pointer = 0x6800
    vram_tile_map_pointer = 0x2C00
    newline_offset = 0
    WRAM = field_vwf.tile_buffer

    WRAMPTR = 0x2108

vwfinit:
    JSR.W clr        ; on efface un peu de Wram

    jsr.w wait_for_vblank
    dma_transfer_to_vram_call(WRAM,vram_tile_set_pointer,0x0690,0x1801)
    jsr.w wait_for_vblank
    dma_transfer_to_vram_call(WRAM,vram_tile_set_pointer+0x348,0x0690,0x1801)

    ; copy the old font tileset
    jsr.w wait_for_vblank
    dma_transfer_to_vram_call(0x0AF000,0x6000, 0x800, 0x1801)
    jsr.w wait_for_vblank
    dma_transfer_to_vram_call(0x0AF000+0x800,0x6000+0x400, 0x800, 0x1801)

    ; Sets the BG3 vram pointer to 0x6000
    lda 0x210C
    and #0xF0
    clc
    adc #0x06
    sta 0x210C

    rtl
;** routine principale
vwfstart:

    SEP #0x20
    REP #0x10

    LDA.B #0x01
    STA.W 0x420D

    ; $04-$4F
    var_base = 0x00
    CNTR        = var_base
    CURRENT_C   = var_base + 2
    BITSLEFT    = var_base + 4
    CNTR2       = var_base + 6
    temp        = var_base + 8
    font_addr   = var_base + 10 ; 11 12
;    scroll      = var_base + 10
;    vsize       = var_base + 12
    font_length  = var_base + 13 ; 14 15
    winstate     = var_base + 16
    nchars       = var_base + 18
    pixel_c      = var_base + 20
    oldtilepos   = var_base + 22
    TILEPOS      = var_base + 24
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
    clear_16_bit(CNTR2)
    clear_16_bit(temp)
    clear_16_bit(winstate)
    clear_16_bit(nchars)
    clear_16_bit(pixel_c)
    clear_16_bit(oldtilepos)
    clear_16_bit(TILEPOS)
    plp


    LDA.B #0x01
    STA.B winstate

    LDA.B #0x08
    STA.B BITSLEFT

    jsr.l vwfinit

    JSR.W ChargeLettre
    BRA firstrun

main:
    JSR.W ChargeLettreInc

firstrun:
    JMP.W parse
    BRA main
fin:
    lda #0x01
    sta 0xDE
    rtl

;******************
;** Parsing code **
;******************

parse:

    ; Message Break
    CMP #0x00
    BNE _nxt1
    JMP.W fin

_nxt1:
    CMP #0x01
    BNE _nxt2
    JMP.W newline

_nxt2:
    CMP #0x02
    BNE _nxt3
    JMP.W space

_nxt3:
    ;Changement de Musique
    CMP #0x03
    BNE _nxt4
    JMP.W musique

_nxt4:
    ; Nom des personages
    CMP #0x04
    BNE _nxt5
    JMP.W display_character_name
_nxt5:

    ; Delay avant de fermer ?
    CMP #0x05
    BNE _nxt6
    JMP.W _code05
_nxt6:

    cmp #0x06
    bne _nxt7

    _nxt7:
    cmp #0x07
    bne _nxt8
    jmp.w _code07

    _nxt8:
    CMP #0x08
    BNE _nxt9
    JMP.W _code08

_nxt9:
    CMP #0xFB
    BNE _nxtFB
    STZ.B winstate
    jmp.w main
_nxtFB:
    CMP #0xFC
    BNE _nxtFC
    JMP.W suit3
_nxtFC:
    cmp #0xFE
    bne _nxtFE
    jsr.w ChargeLettreInc
    jsr.w setup_font
    jmp.w main
_nxtFE:
;    CMP #0xFF
;    BNE _nxtFF
;    JMP.W retour_auto


_nxtFF:
    ; on fabrique le pointeur de font et le pointeur vers la wram
    ;retour auto a ajouter ici

return_a:
    JSR.W makeptr
    JSR.W ShiftNew
    JSR.W wdisplay

    JMP.W main


;***********
;** Space **
;***********
space:
    JSR.W ChargeLettreInc
    CLC
    ADC.B TILEPOS
    JMP.W main

;******************
;Cout en gils
;******************

_code08:
    LDA.W 0x08F8
    STA.B 0x30
    LDA.W 0x08F9
    STA.B 0x31
    LDA.W 0x08FA
    STA.B 0x32
    JSR.L 0x15C324

    LDX.W #0x0000

_loop_B5C3:
    LDA.B 0x36,X
    CMP #0x80
    BNE _loop_B5D2
    INX
    CPX.W #0x0005
    BEQ _loop_B5D2
    JMP.W _loop_B5C3

_loop_B5D2:
    LDA.B 0x36,X
        ; Old code
        ;00B5D4 STA 0x0774,Y
        ;00B5D7 LDA #0xFF
        ;00B5D9 STA 0x0834,Y
        ;00B5DC INY
    PHX
    PHY

    STA.B CURRENT_C            ;appel de la vwf

    JSR.W makeptr
    JSR.W ShiftNew
    JSR.W wdisplay

    PLY
    PLX

    INX
    CPX.W #0x0006
    BNE _loop_B5D2

    JMP.W main

;================================
;Nouveau Cadre
;================================

;nouveau_cadre:
;    dma_transfer_to_vram_call(winmap, vram_tile_map_pointer, 0x2C0, 0x1801)
;    STZ.B TILEPOS
;    JSR.W incpointer
;    RTL


;****************
;** printfname **
;****************
display_character_name:
{
;    pha
;    lda.b #3
;    jsr.w setup_font
;    pla
    JSR.W ChargeLettreInc
    ASL
    STA.B 0x30
    ASL
    CLC
    ADC 0x30
    STA.B 0x30
    STZ.B 0x31
    LDX.B 0x30

    LDY.W #0x0000

next:
    LDX.B 0x30
    LDA 0x1500,X
    STA.B CURRENT_C
    CMP #0xFF
    BEQ exit
    INX
    PHX
    PHY
    JSR.W makeptr
    JSR.W ShiftNew
    JSR.W wdisplay
    PLY
    PLX

suite:
    INC.B 0x30

    INY
    CPY.W #0x0006
    BEQ exit
    JMP.W next
exit:
;    pha
;    lda.b #0
;    jsr.w setup_font
;    pla
    JMP.W main
}
;********************
;** Nouvelle ligne **
;********************
newline:
    STZ.B pixel_c
    STZ.B pixel_c+1

    REP #0x20
    LDA.W #8-newline_offset
    SEP #0x20

    STA.B BITSLEFT

    LDA.B TILEPOS
    CLC
    ;Second line
    CMP #0x1A+1
    BCS suit

    LDA.B #0x1A
    STA.B TILEPOS
    BRA end
suit:

    ;Third Line
    CMP #0x34+1
    BCS suit2
    LDA.B #0x34
    STA.B TILEPOS
    BRA end
suit2:

    ;Forth Line
    CMP #0x4E+1
    BCS suit3

    LDA.B #0x4E
    STA.B TILEPOS
    BRA end

suit3:

    STZ.B CURRENT_C
    STZ.B TILEPOS
    STZ.B CNTR2
    STZ.B temp
    STZ.B pixel_c
    STZ.B pixel_c+1

    LDA.B #0x08
    STA.B BITSLEFT

    JSR.W clr
    JSR.W waitpad
    JSR.W wdisplay
end:

    JMP.W main

;*************
;** Musique **
;*************

musique:
    JSR.W ChargeLettreInc
    STA 0x1E01
    LDA.B #0x01
    STA 0x1E00

    JSR.L 0x048004
    JMP.W main

_code05:
    JSR.W ChargeLettreInc
    STZ.b temp+1
    ASL
    ROL.b temp+1
    ASL
    ROL.b temp+1
    ASL
    ROL.b temp+1
    STA.b temp
    LDX.b temp
    STX 0x08F4
    LDX 0x0000
    STX 0x08F6
    JMP.W main


.macro vwf_putchar() {
    phx
    phy

    sta.b CURRENT_C

    jsr.w makeptr
    jsr.w ShiftNew
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
    sta.b temp
    asl
    asl
    asl
    adc.b temp
    tax
    sep #0x20

    ; skip first char (usually a space or a symbol.)
    inx
    lda #0x09

loop:
    pha
    lda 0x0F8000, x
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

ShiftNew:
    REP #0x20
    LDA.W #0x0010
    STA.B CNTR
    SEP #0x20

    PHB
    LDA.B #0x7E
    PHA
    PLB

Boucle2:
    REP #0x20
    LDA.W #0x0000
    STZ.B CNTR2
    SEP #0x20
    PHX
    LDA.B BITSLEFT

    CMP #0x08
    BNE _shift
    PLX
   ; LDA.L assets_font_dat,X
    phy
    txy
    lda.b [font_addr], y
    tyx
    ply
    INX
    XBA
    BRA _store

_shift:
    TAX            ; using math multiplication
    LDA.L vwf_shift_table,X
    STA.L 0x004202        ; MULTPILIER


    PLX

    phy
    txy
    lda.b [font_addr], y
    tyx
    ply
    INX

    STA.L 0x004203        ; MULTIPLICAND

    REP #0x20
    NOP
    NOP
    NOP
    NOP
    LDA.L 0x004216    ; the result is stored in 0x4216-0x4217
    SEP #0x20

_store:
    INY
    XBA
    PHX
    TYX
    ORA.L WRAM,x
    STA.L WRAM,x
    XBA
    STA.L WRAM+0x20,x
    TXY
    PLX
    INY

    DEC.B CNTR
    BNE Boucle2

    PLB
    PHA
    PLA

    REP #0x20
    STZ.B temp
    LDA.W #0x0000
    LDX.W #0x0000
    SEP #0x20

    LDA.B CURRENT_C
    TAX

;    LDA.L assets_font_length_table_dat,X
    txy
    lda.b [font_length], y
    tyx
    STA.B temp

    REP #0x20
    CLC

    ADC.B pixel_c
    INC
    CLC
    STA.B pixel_c
    LDA.W #0x0000
    SEP #0x20

    LDA.B BITSLEFT

    CLC
    SBC.B temp

loopdec:
    CMP #0x00
    BMI coupe
    BEQ coupe

    STA.B BITSLEFT
    RTS

coupe:
    CLC
    ADC #0x08
    INC.B TILEPOS
    BRA loopdec


vwf_shift_table:
.db 0b00000000                ; dummy entrie =0
.db 0b00000010                ;1
.db 0b00000100                ;2
.db 0b00001000                ;3
.db 0b00010000                ;4
.db 0b00100000                ;5
.db 0b01000000                ;6
.db 0b10000000                ;7
.db 0b10000000                ;8

setup_font:
; A: font index
{
    phx
    pha
    asl
    sta.b temp
    pla
    clc
    adc.b temp
    tax

    rep #0x20
    lda.l font_table, x
    sta.b font_addr
    lda.l length_table,x
    sta.b font_length
    sep #0x20

    lda.l font_table+2, x
    sta.b font_addr+2
    lda.l length_table+2,x
    sta.b font_length+2

    plx
    rts
}

;************************
;** build font pointer **
;************************

makeptr:
    PHA

    LDX.W #0x0000
    LDY.W #0x0000
    LDA.B CURRENT_C
    XBA
    LDA #0x00
    XBA
    REP #0x20
    ASL
    ASL
    ASL
    ASL
    TAX
    LDA.W #0x0000
    SEP #0x20

    LDA.B TILEPOS
    sta.b oldtilepos
    REP #0x20
    ASL
    ASL
    ASL
    ASL
    ASL
    sta.b oldtilepos
    TAY
    SEP #0x20
    PLA
    RTS



;===================================
;Clear Wram
;
;===================================
clr:
{
    phx
    ldx.w #0x0000
solid_bg_loop:
    lda.b #0xFF
    sta.l WRAM,X
    inx

    lda.b #0x00
    sta.l WRAM,X
    inx
    cpx.w #0x0D10

    bne solid_bg_loop


transparent_bg_loop:
    lda.b #0x00
    sta.w WRAM,X
    inx
    cpx.w #0x0D20
    bne transparent_bg_loop

    plx
    rts
}
;*****************
;** Retour auto **
;*****************
;on cherche l'espace suivant
retour_auto:

    PHX
    LDX.W #0x0000
    LDY.W 0x0772    ;on sauve la position de lecture dans Y
    STZ.B temp
    STZ.B temp+1
    LDA.B 0x3F
    ;LDA.B CURRENT_C
    PHA
    BRA firstrun2
loopchr:
    JSR.W ChargeLettreInc

    CMP #0x04
    bne normal_char
    lda #6 * 8
    bra add_accumulator_value_to_temp
    normal_char:
;règles de césure
    BEQ chrfound    ;Message Break \n<end>\n\n
    CMP #0xFF    ;espace
    BEQ chrfound
    CMP #0xFC    ;<new>
    BEQ chrfound
    CMP #0x01    ;\n
    BEQ chrfound

firstrun2:
    TAX
    phy
    txy
    lda.b [font_length], y
    tyx
    ply
    INC

add_accumulator_value_to_temp:
    REP #0x20
    CLC
    ADC.B temp
    STA.B temp
    SEP #0x20

    ;else
    BRA loopchr

    chrfound:

    REP #0x20
    LDA.W #0x0000
    LDA.B pixel_c
    CLC
    ADC.B temp

    CMP.W #0x00CD-newline_offset    ;largeur max en pixel
    BMI noreturn
retour:
    SEP #0x20
    PLA
    STA.B 0x3F
    STY.W 0x0772    ; restoration de la position du texte
    PLX
    JMP.W newline

    noreturn:
    SEP #0x20
    PLA
    STA.B 0x3F
    STY.W 0x0772    ; restauration de la position du texte
    JSR.W ChargeLettre ; ça evite a certains caractères de passer à la trappe
    PLX
    JMP.W return_a


wait_key_up:
    lda 0x02
    bne wait_key_up
    lda 0x03
    bne wait_key_up
    rts

wait_key_down:
{
    lda 0x02
    bne exit
    lda 0x03
    beq wait_key_down
exit:
    rts
}

;Wait for joypad 1
waitpad:
{
    PHA
    LDA.B no_wait_for_action
    BNE nowaitpad

.if ENABLE_DIALOG_SKIP {
    jsr.w wait_key_up
}
    jsr.w wait_key_down
    bra end



nowaitpad:
    lda.b #0x20
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
    dma_transfer_to_vram_call(WRAM,vram_tile_set_pointer,0x0690,0x1801)
    jsr.w wait_for_vblank
    dma_transfer_to_vram_call(WRAM + 0x348,vram_tile_set_pointer + 0x348,0x0690,0x1801)
    rts
}

wdisplay:
;wait for vblank to transfer
    jsr.w wait_for_vblank

    sep #0x20


    ;macro expansion

    PHP
    PHA
    PHX

    LDA.B #0x80
    STA.W 0x2115

    rep #0x20
    pha

    lda.b oldtilepos
    lsr            ; addresse vram /2
    clc
    adc.w #vram_tile_set_pointer
    sta.w 0x2116


    lda.b oldtilepos
    clc
    adc.w #WRAM & 0xFFFF
    sta.w 0x4372

    pla
    sep #0x20

    channel=7

    LDX.W #0x1801
    STX.W 0x4370
    LDA.B #0xFF & (WRAM >> 16)
    STA.W 0x4374

    LDX.W #0x0040
    STX.W 0x4375
    LDA.B #0x01<<7
    STA 0x420B

    NOP
    NOP

    PLX
    PLA
    PLP


    LDA.B no_wait_for_action
    BNE nowindow

    dma_transfer_to_vram_call(winmap, vram_tile_map_pointer, endwinmap-winmap, 0x1801)
    BRA window

nowindow:
    dma_transfer_to_vram_call(intromap, vram_tile_map_pointer, endintromap-intromap, 0x1801)

window:
{
    LDA.B CURRENT_C
    CMP #0xFF
    BEQ no_char_wait
    WAI            ;wait for interrupts
    no_char_wait:
}
    RTS


winmap:
.dw 0x2000,0x2000,0x2019,0x2100,0x2102,0x2104,0x2106,0x2108,0x210A,0x210C,0x210E,0x2110,0x2112,0x2114,0x2116,0x2118,0x211A,0x211C,0x211E,0x2120,0x2122,0x2124,0x2126,0x2128,0x212A,0x212C,0x212E,0x2130,0x2132,0x201A,0x2000,0x2000
.dw 0x2000,0x2000,0x2019,0x2101,0x2103,0x2105,0x2107,0x2109,0x210B,0x210D,0x210F,0x2111,0x2113,0x2115,0x2117,0x2119,0x211B,0x211D,0x211F,0x2121,0x2123,0x2125,0x2127,0x2129,0x212B,0x212D,0x212F,0x2131,0x2133,0x201A,0x2000,0x2000
.dw 0x2000,0x2000,0x2019,0x2134,0x2136,0x2138,0x213A,0x213C,0x213E,0x2140,0x2142,0x2144,0x2146,0x2148,0x214A,0x214C,0x214E,0x2150,0x2152,0x2154,0x2156,0x2158,0x215A,0x215C,0x215E,0x2160,0x2162,0x2164,0x2166,0x201A,0x2000,0x2000
.dw 0x2000,0x2000,0x2019,0x2135,0x2137,0x2139,0x213B,0x213D,0x213F,0x2141,0x2143,0x2145,0x2147,0x2149,0x214B,0x214D,0x214F,0x2151,0x2153,0x2155,0x2157,0x2159,0x215B,0x215D,0x215F,0x2161,0x2163,0x2165,0x2167,0x201A,0x2000,0x2000
.dw 0x2000,0x2000,0x2019,0x2168,0x216A,0x216C,0x216E,0x2170,0x2172,0x2174,0x2176,0x2178,0x217A,0x217C,0x217E,0x2180,0x2182,0x2184,0x2186,0x2188,0x218A,0x218C,0x218E,0x2190,0x2192,0x2194,0x2196,0x2198,0x219A,0x201A,0x2000,0x2000
.dw 0x2000,0x2000,0x2019,0x2169,0x216B,0x216D,0x216F,0x2171,0x2173,0x2175,0x2177,0x2179,0x217B,0x217D,0x217F,0x2181,0x2183,0x2185,0x2187,0x2189,0x218B,0x218D,0x218F,0x2191,0x2193,0x2195,0x2197,0x2199,0x219B,0x201A,0x2000,0x2000
.dw 0x2000,0x2000,0x2019,0x219C,0x219E,0x21A0,0x21A2,0x21A4,0x21A6,0x21A8,0x21AA,0x21AC,0x21AE,0x21B0,0x21B2,0x21B4,0x21B6,0x21B8,0x21BA,0x21BC,0x21BE,0x21C0,0x21C2,0x21C4,0x21C6,0x21C8,0x21CA,0x21CC,0x21CE,0x201A,0x2000,0x2000
.dw 0x2000,0x2000,0x2019,0x219D,0x219F,0x21A1,0x21A3,0x21A5,0x21A7,0x21A9,0x21AB,0x21AD,0x21AF,0x21B1,0x21B3,0x21B5,0x21B7,0x21B9,0x21BB,0x21BD,0x21BF,0x21C1,0x21C3,0x21C5,0x21C7,0x21C9,0x21CB,0x21CD,0x21CF,0x201A,0x2000,0x2000
endwinmap:

intromap:
.dw 0x2000,0x2000,0x2000,0x2100,0x2102,0x2104,0x2106,0x2108,0x210A,0x210C,0x210E,0x2110,0x2112,0x2114,0x2116,0x2118,0x211A,0x211C,0x211E,0x2120,0x2122,0x2124,0x2126,0x2128,0x212A,0x212C,0x212E,0x2130,0x2132,0x2000,0x2000,0x2000
.dw 0x2000,0x2000,0x2000,0x2101,0x2103,0x2105,0x2107,0x2109,0x210B,0x210D,0x210F,0x2111,0x2113,0x2115,0x2117,0x2119,0x211B,0x211D,0x211F,0x2121,0x2123,0x2125,0x2127,0x2129,0x212B,0x212D,0x212F,0x2131,0x2133,0x2000,0x2000,0x2000
.dw 0x2000,0x2000,0x2000,0x2134,0x2136,0x2138,0x213A,0x213C,0x213E,0x2140,0x2142,0x2144,0x2146,0x2148,0x214A,0x214C,0x214E,0x2150,0x2152,0x2154,0x2156,0x2158,0x215A,0x215C,0x215E,0x2160,0x2162,0x2164,0x2166,0x2000,0x2000,0x2000
.dw 0x2000,0x2000,0x2000,0x2135,0x2137,0x2139,0x213B,0x213D,0x213F,0x2141,0x2143,0x2145,0x2147,0x2149,0x214B,0x214D,0x214F,0x2151,0x2153,0x2155,0x2157,0x2159,0x215B,0x215D,0x215F,0x2161,0x2163,0x2165,0x2167,0x2000,0x2000,0x2000
.dw 0x2000,0x2000,0x2000,0x2168,0x216A,0x216C,0x216E,0x2170,0x2172,0x2174,0x2176,0x2178,0x217A,0x217C,0x217E,0x2180,0x2182,0x2184,0x2186,0x2188,0x218A,0x218C,0x218E,0x2190,0x2192,0x2194,0x2196,0x2198,0x219A,0x2000,0x2000,0x2000
.dw 0x2000,0x2000,0x2000,0x2169,0x216B,0x216D,0x216F,0x2171,0x2173,0x2175,0x2177,0x2179,0x217B,0x217D,0x217F,0x2181,0x2183,0x2185,0x2187,0x2189,0x218B,0x218D,0x218F,0x2191,0x2193,0x2195,0x2197,0x2199,0x219B,0x2000,0x2000,0x2000
.dw 0x2000,0x2000,0x2000,0x219C,0x219E,0x21A0,0x21A2,0x21A4,0x21A6,0x21A8,0x21AA,0x21AC,0x21AE,0x21B0,0x21B2,0x21B4,0x21B6,0x21B8,0x21BA,0x21BC,0x21BE,0x21C0,0x21C2,0x21C4,0x21C6,0x21C8,0x21CA,0x21CD,0x21CF,0x2000,0x2000,0x2000
.dw 0x2000,0x2000,0x2000,0x219D,0x219F,0x21A1,0x21A3,0x21A5,0x21A7,0x21A9,0x21AB,0x21AD,0x21AF,0x21B1,0x21B3,0x21B5,0x21B7,0x21B9,0x21BB,0x21BD,0x21BF,0x21C1,0x21C3,0x21C5,0x21C7,0x21C9,0x21CB,0x21CE,0x21D0,0x2000,0x2000,0x2000
endintromap:







