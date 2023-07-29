.scope newgame {
new_game:
	.dw 0x0042 ; text position
	.text 'Nouvelle partie'
	.db 0

time_load_save:
	.dw 0x046E
	.text 'TEMPS'
	.db 0

gils_load_game:
	.text 'Gils'
	.db 0

save:
	.text 'Partie'
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

empty_save:
	.db 0x90 + 2, 0x00
	.text 'VIDE'
	.db 0
}