.table 'text/ff4_menus.tbl'

main_menu_text    = 0x00
gils_text         = 0x01
time_text         = 0x02
cantuse_text      = 0x03
item_text         = 0x04
not_use_text      = 0x05
config_text       = 0x06
options_text      = 0x07
white_magic_text  = 0x08
black_magic_text  = 0x09
summon_magic_text = 0x0A
state_text        = 0x0B


{
;=============================================
;	Table de Pointeurs 24bits:
;=============================================
;menu principal 	00
.pointer menup
;Gils			01
.pointer gils
;temps			02
.pointer time
;Can't use		03
.pointer cantuse

;item			04
.pointer item

;Impossible a utiliser	05
.pointer notuse

;configuration		06
.pointer config

;options		07
.pointer options

;magie			08
.pointer blanc

;noir			09
.pointer noir

;Invokation		0A
.pointer invok

;Etat			0B
.pointer etat

;for level up		0C
.pointer forlevup

;Stats			0D
.pointer stats

;controles		0E
.pointer controles

;buttons:		0F
.pointer button

;Mpneeded:		10
.pointer mpneed

;Ninja:			11
.pointer ninja

;Multiple:		12
.pointer mult

;manette:		13
.pointer manette

;equiper:		14
.pointer equip


;=============================================
;	Menu Principal:
;=============================================
menup:
	.dw 0x0070
{
;    .table 'text/gen/menu.tbl'
	.text 'Objets'
	.db 0x01, 0xF0, 0x00
	.text 'Sorts'
	.db 0x01, 0x70, 0x01
	.text 'Equiper'
	.db 0x01, 0xF0, 0x01
	.text 'Statut'
	.db 0x01, 0x70, 0x02
	.text 'Placer'
	.db 0x01, 0xF0, 0x02
	.text 'Changer'
	.db 0x01, 0x70, 0x03
	.text 'Options'
	.db 0x01, 0xF0, 0x03
	.text 'Sauver'
	.db 0
	}
; old
	.dw 0x0070
	.text 'Objets'
	.db 0x01, 0xF0, 0x00
	
	.text 'Sorts'
	.db 0x01, 0x70, 0x01

	.text 'Equiper'
	.db 0x01, 0xF0, 0x01

	.text 'Statut'
	.db 0x01, 0x70, 0x02

	.text 'Placer'
	.db 0x01, 0xF0, 0x02

	.text 'Changer'
	.db 0x01, 0x70, 0x03

	.text 'Options'
	.db 0x01, 0xF0, 0x03

	.text 'Sauver'
	.db 0
gils:
	.dw 0x05B0 + 0x40 + 0x40 + 0x40 + 6
	.text 'Gils'
	.db 0
time:
	.dw 0x04F0
	.text 'Temps'
	.db 0
cantuse:
	.dw 0x0252
	.text ' Inutilisable'
	.db 0
item:
	.dw 0x0044
	.text 'Objets'
	.db 0
notuse:
	.dw 0x0052
	.text 'Impossible à utiliser.'
	.db 0

;=============================================
;	Options:
;=============================================
config:
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
options:
	.dw 0x0098
	.text 'Options'
	.db 0
controles:
	.dw 0x0096
	.text 'Contrôles'
	.db 1
	
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
button:
	.dw 0x0488
	.text 'Eteins Action Annuler Menu'
	.db 0
mult:
	.dw 0x0096
	.text 'Multiple'
	.db 0
manette:
	.dw 0x021E
	.text 'Manette'
	.db 1

	.dw 0x029E
	.text 'Manette'
	.db 1

	.dw 0x031E
	.text 'Manette'
	.db 1

	.dw 0x039E
	.text 'Manette'
	.db 1

	.dw 0x041E
	.text 'Manette'
	.db 0

;=============================================
;	Sorts:
;=============================================
blanc:
	.dw 0x00EE
	.text 'Blanc'
	.db 0
noir:
	.dw 0x016E
	.text 'Noir'
	.db 0
invok:
	.dw 0x01EE
	.text 'Chimere'
	.db 0
ninja:
	.dw 0x016E
	.text 'Ninja'
	.db 0
mpneed:
	.dw 0x020A
	.text 'Coût PM'
	.db 0

;=============================================
;	Statut:
;=============================================
etat:
	.dw 0x01F0
	.text 'Statut'
	.db 0
forlevup:
	.dw 0x0260
	.text 'Niveau suivant'
	.db 0
stats:
	.dw 0x01A0
	.text 'Expérience'
	.db 0x01
	
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


;=============================================
;	Equiper:
;=============================================
equip:
	.dw 0x005C
	.text 'MainD'
	.db 1

	.dw 0x00DC
	.text 'MainG'
	.db 1

	.dw 0x015C
	.text 'Tête'
	.db 1
	
	.dw 0x01DC
	.text 'Corps'
	.db 1
	
	.dw 0x025C
	.text 'Bras'
	.db 0
}