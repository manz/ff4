.table 'text/ff4_menus.tbl'

{
*=0x01E00C
	.db 0x90 + 2, 0x00
	.text 'VIDE'
	.db 0

; new game window
*=0x01dfc7
	.db 0x12 ; width
	.db 0x02 ; height

; Cecil sprite position on the new game item
*=0x019904
	.db 0x85 ; x
	.db 0x04 ; y

; save number display
*=0x019A62
	sta.w 0xC8 - 0x40 + 8 ,y

*=0x019A55
	ldx.w #0x82 - 0x40


*=0x019A52
	ldy.w #save

*=0x01962E
	ldy.w #new_game

*=0x019826
	ldy.w #load_this_save

*=0x01982C
	ldy.w #yes_no

*=0x01983E
	ldy.w #time_load_save

*=0x01984D
 	ldy.w #gils_load_game
	ldx.w #0x674

*=0x019856
	ldy.w #0x62C-4
*=0x01DFE8
time_load_save:
	.dw 0x046E
	.text 'TEMPS'
	.db 0
gils_load_game:
	.text 'Gils'
	.db 0
*=0x01FFA0
save:
	.text 'Partie'
	.db 0

new_game:
	.dw 0x0042 ; text position
	.text 'Nouvelle partie'
	.db 0

load_this_save:
	.dw 0x006E
	.text 'Cette'
	.db 1
	 .dw 0x00EE
	.text 'partie?'
	.db 0

yes_no:
	.dw 0x0172
	.text 'Oui'
	.db 1
	.dw 0x01F2
	.text 'Non'
	.db 0

}
