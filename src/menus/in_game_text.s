.scope in_game_menu {
menu:
	; window
	.dw 0x002E, 0x1107
	; position
	.dw 0x0070
	.text 'Objets'
	.db 0x01
	.dw 0x00F0
	.text 'Sorts'
	.db 0x01
	.dw 0x0170
	.text 'Equiper'
	.db 0x01
	.dw 0x01F0
	.text 'Statut'
	.db 0x01
	.dw 0x0270
	.text 'Placer'
	.db 0x01
	.dw 0x02F0
	.text 'Changer'
	.db 0x01
	.dw 0x0370
	.text 'Options'
	.db 0x01
	.dw 0x03F0
	.text 'Sauver'
	.db 0

gils:
	.text 'Gils'
	.db 0

time:
	.text 'TEMPS'
	.db 0
}

.scope items_menu {
	item:
		.db 2
		.db 0
		.db 7
		.db 3

		.dw 0x0044
		.text 'Objets'
		.db 0
	notuse:
		.dw 0x0052
		.text 'Impossible à utiliser.'
		.db 0

}

.scope spells {
	white:
		.dw 0x00EE
		.text 'Blanc'
		.db 0
	black:
		.dw 0x016E
		.text 'Noir'
		.db 0
	summon:
		.dw 0x01EE
		.text 'Chimere'
		.db 0
	ninja:
		.dw 0x016E
		.text 'Ninja'
		.db 0
	kokan:
		.dw 0x0054
		.text 'Echange'
		.db 0
	mp_needed:
		.text 'Coût PM'
		.db 0
}

.scope status {
status:
	.dw 0x01F0
	.text 'Statut'
	.db 0

exp_for_next_level:
	.dw 0x0260
	.text 'Niveau suivant'
	.db 0

char_stats:
	.dw 0x0114 - 0x80
	; use precomputed 8x8vwf.
	.db 0xF0
	.db 0xF1
	.db 0xF2
	.db 0xF3
	.db 1
	.dw 0x01A0
	.text 'Expérience'
	.db 1

	.dw 0x0206
	.text 'PV'
	.db 1

	.dw 0x0286
	.text 'PM'
	.db 1

	.dw 0x0344
	.text 'Talents'
	.db 1

	.dw 0x03C2
	.text 'Vigueur'
	.db 1

	.dw 0x0442
	.text 'Agilité'
	.db 1

	.dw 0x04C2
	.text 'Vitesse'
	.db 1

	.dw 0x0542
	.text 'Esprit'
	.db 1

	.dw 0x05C2
	.text 'Volonté'
	.db 1

;att/def/mag:

	.dw 0x035A
	.text 'Attaque'
	.db 1

	.dw 0x03DA
	.text 'Attaque%'
	.db 1

	.dw 0x045A
	.text 'Défense'
	.db 1

	.dw 0x04DA
	.text 'Défense%'
	.db 1

	.dw 0x055A
	.text 'Déf Mag'
	.db 1

	.dw 0x05DA
	.text 'Déf Mag%'
	.db 0
}

.scope options {
title:
	.dw 0x0096
	.text 'Options'
	.db 0

config:
	.dw 0x0102, 0x141C

	.dw 0x0144
	.text 'Mode Combat'
	.db 0x01

	.dw 0x015E
	.text 'Actif  Pause'
	.db 0x01

	.dw 0x01C4
	.text 'Vitesse Cbt'
	.db 0x01

	.dw 0x021E
	.text 'Vite   Lent'
	.db 0x01

	.dw 0x0244
	.text 'Vitesse Msg'
	.db 0x01

	.dw 0x02C4
	.text 'Audio'
	.db 0x01

	.dw 0x02DE
	.text 'Stéréo Mono'
	.db 0x01

	.dw 0x0344
	.text 'Contrôle'
	.db 0x01

	.dw 0x035E
	.text 'Normal Perso.'
	.db 0x01

	.dw 0x03DE
	.text 'Seul   Multiple'
	.db 0x01

	.dw 0x0444
	.text 'Curseur'
	.db 0x01

	.dw 0x045E
	.text 'Reset  Mémoire'
	.db 0x01

	.dw 0x04C4
	.text 'Couleur'
	.db 0


controls:
	.dw 0x0204
	.text 'Action'
	.db 0x01

	.dw 0x0284
	.text 'Annuler'
	.db 0x01

	.dw 0x0304
	.text 'Menu'
	.db 0x01

	.dw 0x0384
	.text 'Left Button'
	.db 0x01

	.dw 0x0404
	.text 'Start'
	.db 1

	.dw 0x0484
	.text 'Fin'
	.db 0
}