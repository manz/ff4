.include 'src/ingame/macros.i'


{
*=0x01DB61
.scope _main_menu {
characters_window:
    menu_window(0, 0, 22, 26)
gil_window:
    menu_window(22, 23, 8, 3)
time_window:
    menu_window(23, 19, 7, 2)
menu:
    menu_window(23, 0, 7, 17)
}

*=0x01dd51
    menu_window(1,8,29,17)

*=0x01892E
    load_system_menu_text_pointer(in_game_menu.menu)
    ; jsr.w draw_window_and_vwf_message

; Gils
*=0x0187CE
    load_system_menu_text_pointer(in_game_menu.gils)

; moves gils two chars on the right
*=0x0187DA
    ldy.w #0x062A + 4

; TIME
*=0x0187C5
    ldx.w #0x52E + 2
    load_system_menu_text_pointer(in_game_menu.time)

; disable Save text
*=0x018939
    jmp.l disable_save

; Moves the classes on the next line
*=0x018C1A
   adc.w #0x004e

; disable class name
*=0x018b30
    rts

;*=0x0188d0
;    ldx.w #0x02CE


*=0x018FD3
    jsr.l load_classes_pointer
    nop
    sta 0x45
    xba
    sta 0x46
    ldx 0x45
    lda #0x0F

*=0x018fe3
{
load_next_char:
    lda.l assets_classes_dat, x
    beq end
    ; dakuten
    jsr.w 0x8E32
    sta.w 0x0000, y
    xba
    sta.w 0x0040, y
    iny
    lda.b 0x34
    sta.w 0x0000, y
    sta.w 0x0040, y
    inx
    iny

    bra load_next_char
end:
    rts
}

*=0x0189b9
; Level offset
    adc.w #0x0044

*=0x018a03
draw_hp_mp = 0x018a2a
        lda.w     #0x0046 + 0x40
        ldy.w     #0x0007      ; current hp
        jsr.w     draw_hp_mp
        lda.w     #0x0050 + 0x40
        ldy.w     #0x0009      ; max hp
        jsr.w     draw_hp_mp
        lda.w     #0x0086 + 0x40
        ldy.w     #0x000b      ; current mp
        jsr.w     draw_hp_mp
        lda.w     #0x0090 + 0x40
        ldy.w     #0x000d      ; max mp
        jsr.w     draw_hp_mp

; LEVEL
*=0x0189C3
{
    level_offset = 7 * 2
    lda #0xFF
    sta.w 0+level_offset, x
    lda #0x4F ; N
    sta.w 2+level_offset, x
    lda #0x57 ; V
    sta.w 4+level_offset, x
    lda #0xFF
    sta.w 6+level_offset, x
    nop

    lda #0x57              ; H 49 V 57
    sta.w 0x40 + 2 + 0x40,X
    lda #0x51              ; P
    sta.w 0x42 - 2 + 0x40,X
    sta.w 0x82 -2 + 0x40 ,X
    lda #0x4E              ; M
    sta.w 0x80 + 2 + 0x40,X
    lda #0xC7              ; /
    sta.w 0x4E + 0x40,X
    sta.w 0x8E + 0x40,X
}

; Moves the level down in the digest
*=0x0189FA
    sta.w 0x0016, x
    xba
    sta.w 0x0018, x

;; Move character name.
*=0x0183D5
	sta.w 0x0000, y
	xba
	sta.w 0x0040, y

; translate can't fight text

*=0x018B2A
    load_system_menu_text_pointer(in_game_menu.cant_fight)

; grey out more tiles for the first line in char block
*=0x018C30
    lda #15



;*=0x018b6b
;  lda     #0x42



; Time offset
*=0x018BC1
    lda.b #0x80
    STA.W 0x0578,Y
    XBA
    STA.W 0x057A,Y
    REP #0x20
    LDA.B 0x73
    SEP #0x20
    JSR.W 0x81D6
    LDA.B 0x5B
    STA.W 0x0570,Y
    LDA.B 0x5D
    STA.W 0x0572,Y
    LDA.B 0x5E
    STA.W 0x0574,Y
    LDA.B #0xC8
    STA.W 0x0576,Y
}

; main menu spells

; length of spells names
*=0x01B345
    lda.b #0x08

; compute spell pointer
;01b319 rep #0x20
;01b31b asl a
;01b31c sta 0x45
;01b31e asl a
;01b31f adc 0x45
;01b321 adc #0x8900
;01b324 tay
;01b325 sep #0x20
;01b327 lda #0x0f

*=0x01b319
    rep #0x20
    pha
    asl
    asl
    asl
    adc 1, s
    nop
    nop
   ; nop
;    adc.w #assets_magic_dat
    tay
    pla
    sep #0x20
    lda.b #assets_magic_dat >> 16

; instead of adding asset_magic_dat to Y move it to the lda to save 3 bytes
*=0x1b32b
    lda.w assets_magic_dat, y

*=0x1b349
    lda.w assets_magic_dat, y

; Copy of save and restore vram routines from menu, save 0x1300 instead of 0x1000 and store it to the sram
{
*=0x14ff62
	sram_buffer = 0x705000
	save_size = 0x1300
	phb
	tdc
	pha
	plb
	lda #0x80
	sta 0x2100       ; screen off
	sta 0x88
	lda #0x80
	sta 0x2115
	ldx #0x2000      ; ppu 0x2000
	stx 0x2116
	ldx 0x2139       ; read "dummy" value
	lda #0x81        ; single address, auto-increment
	sta 0x4300
	lda #0x39        ; source: 0x2139 (vram data read)
	sta 0x4301
	ldx.w #sram_buffer & 0xffff      ; destination: 0x7ee600
	stx 0x4302
	lda.b #sram_buffer >> 16
	sta 0x4304
	ldx.w #save_size      ; size: 0x1000
	stx 0x4305
	lda #0x01
	sta 0x420b
	plb
	rtl

*=0x14ffd6
;RestoreDlgGfx_ext:
	lda #0x00
	pha
	plb
	ldx #0x2000
	stx 0x011d
	ldx.w #sram_buffer & 0xffff
	stx 0x011f
	lda.b #sram_buffer >> 16
	sta 0x0121
	ldx.w #save_size
	stx 0x0122
	rtl
}
*=0x018E32
jsr.l lookup_dakuten
rts

*=0x00b670
jsr.l lookup_dakuten
xba
rts

;*=0x00b66e
;jsr.l lookup_dakuten
;rts

;                     --------sub start--------
;018E32  DA             PHX
;018E33  C9 42          CMP #$42
;018E35  B0 15          BCS $018E4C
;018E37  38             SEC
;018E38  E9 0F          SBC #$0F
;018E3A  0A             ASL
;018E3B  EB             XBA
;018E3C  A9 00          LDA #$00
;018E3E  EB             XBA
;018E3F  AA             TAX
;018E40  BF 1F FE 1E    LDA $1EFE1F,X
;018E44  EB             XBA
;018E45  BF 1E FE 1E    LDA $1EFE1E,X
;018E49  EB             XBA
;018E4A  FA             PLX
;018E4B  60             RTS
;                     ----------------
;018E4C  EB             XBA
;018E4D  A9 FF          LDA #$FF
;018E4F  FA             PLX
;018E50  60             RTS
;                     ----------------

