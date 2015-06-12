{
*=0x01DB61
	.dw 0x0000, 0x1A16 ; fenètre principale
	.dw 0x05EC, 0x0308 ; fenètre Gils
	.dw 0x04EE, 0x0207 ; fenetre temps
	.dw 0x002E, 0x1107 ; fenètre menu principal

*=0x01892E
	load_system_menu_text_pointer(in_game_menu.menu)

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

; Moves the classes on the left
*=0x018C1A
   adc.w #0x0000


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

; LEVEL
*=0x0189C3
{
	level_offset = 7 * 2
	lda #0xF0
	sta.w 0+level_offset, x
	lda #0xF1
	sta.w 2+level_offset, x
	lda #0xF2
	sta.w 4+level_offset, x
	lda #0xF3
	sta.w 6+level_offset, x
	nop

	lda #0x57  			; H 49 V 57
	sta.w 0x40 + 2,X
	lda #0x51  			; P
	sta.w 0x42 - 2,X
	sta.w 0x82 -2 ,X
	lda #0x4E  			; M
	sta.w 0x80 + 2,X
	lda #0xC7  			; /
	sta.w 0x4E,X
	sta.w 0x8E,X
}

; Moves the level down in the digest
*=0x0189FA
	sta.w 0x0016,X
	xba
	sta.w 0x0018,X

; deplacement du nom du perso
*=0x0183D5
	sta.w 0x0040,Y
	xba
	sta.w 0x0080,Y

; gils offset ; very bad idea it's used to display numbers everywhere
;*=0x018FAF
;	adc.w #0x0052

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
	lda.b #0x07

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
    asl
    asl
    asl
    nop
    nop
    nop
    adc.w #assets_magic_dat
    tay
    sep #0x20
    lda.b #assets_magic_dat >> 16