; White spells
*=0x01AFA2
	load_system_menu_text_pointer(spells.white)

; Black spells
*=0x01AFB6
	load_system_menu_text_pointer(spells.black)

; summons
*=0x01AFCA
	load_system_menu_text_pointer(spells.summon)

*=0x01AFDE
	load_system_menu_text_pointer(spells.ninja)

*=0x1d95e
	load_system_menu_text_pointer(spells.kokan)

*=0x01b0ec
	ldx.w #0x020A + 0x40
	load_system_menu_text_pointer(spells.mp_needed)

; Grisement des types sorts : 'Blancs' 'Noirs' etc ...
*=0x01B419
	ldy.w #0x0007
	sta.w 0xC5FF,x

; Spells type cursor offset
*=0x01B0CE
	lda.b #0x00

; Spells cost before char
*=0x01B0F7
	STA.W 0xC816 + 0x40 + 2

; Spells cost
*=0x01B0E6
	LDY.W #0x021A + 0x40 + 2
