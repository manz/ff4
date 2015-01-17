.table 'text/ff4_menus.tbl'
*=0x1efccd
    ; D:2100
    lda #0x02
    sta 0x01
    lda #0x00
    sta 0x02
    sta 0x03
    sta 0x05
    sta 0x06

    ; BG 1 screen address
    lda #0x62
    sta 0x07
    ; BG 2 screen address
    lda #0x6a
    sta 0x08
    ; BG 3 screen address
    lda #0x72
    sta 0x09
    ; BG 4 screen address
    lda #0x7a
    sta 0x0a

    ; BG 1, 2 Name address
    ; old value 0x22
    lda #0x22
    sta 0x0b
    ; BG 2, 4 Name address
    lda #0x22
    sta 0x0c

    lda #0x00
    sta 0x420b
    sta 0x420c
    lda #0x80
    sta 0x15
    tdc
    sta 0x16
    sta 0x17
    lda #0x1f
    sta 0x2c
    tdc
    sta 0x2d
    sta 0x2e
    sta 0x2f
    sta 0x30
    sta 0x31
    sta 0x33
    lda #0xe0
    sta 0x32
    rtl

; RELATED TO ADD SOME TILES TO THE FONT TILESET 8x8 font stuff
; copy more to vram to erase tileset extension.
;*=0x14ffeb
; ldx #0x2000

; copies the vram to the wram to make room for 8x8 font when on the map (might be used for inside as well).
;*=0x14ff90
; ldx #0x1800

; Petite fenètre 'Impossible ...' : 0x01A7DE
*=0x01A80D
    NOP
    NOP
    NOP




; Move monsters names
;02ffcf lda 0x2e8000,x



; NIVEAU
*=0x0189C3
	LDA.B #0x9A
	STA.W 0x000A,X

	LDA.B #0x9B
	STA.W 0x000C,X

	LDA.B #0x9C
	STA.W 0x000E,X

	LDA.B #0x9D
	STA.W 0x0010,X

	LDA.B #0x70
	STA.W 0x0012,X

	LDA.B #0x51
	STA.W 0x0040,X
	STA.W 0x0080,X
	JSR.L deroutage

	NOP
	NOP

;deroutage du grisement de 'sauver'
*=0x018939
	JSR.L derout_save
	NOP

	NOP
	NOP
	NOP

	NOP
	NOP
	NOP

	NOP
	NOP
	NOP


;modification des fenètres:
*=0x01DB61
;	.dw 0x0000, 0x1A1C	;fenètre principale
;	.dw 0x04EE, 0x0507	;fenètre Gils
;	.dw 0x04EE, 0x0507	;fenètre temps
;	.dw 0x006E, 0x0F07	;fenètre menu principal


.dw 0x0000, 0x1A16 ; fenètre principale
.dw 0x05EC, 0x0308 ; fenètre Gils
.dw 0x04EE, 0x0207 ; fenetre temps
.dw 0x002E, 0x1107 ; fenètre menu principal
;.dw 0x0070, 0xCBCA
;.dw 0xEADC, 0xF001
;.dw 0xA800, 0x8CA7
;.dw 0x01FF, 0x0170

; original windowZe
;.dw 0x0000, 0x1A16 ; fenètre principale
;.dw 0x05EA, 0x0308 ; fenètre Gils
;.dw 0x04EC, 0x0207 ; fenetre temps
;.dw 0x002C, 0x1107 ; fenètre menu principal
;.dw 0x0070, 0xCBCA
;.dw 0xEADC, 0xF001
;.dw 0xA800, 0x8CA7
;.dw 0x01FF, 0x0170

;*=0x01DB6D


;*****************
;** Decalages ! **
;*****************

; décalage du niveau (ex: 10)
*=0x0189FA
	STA.W 0x0014,X
	XBA
	STA.W 0x0016,X


; deplacement du nom du perso
*=0x0183D5
	STA.W 0x0040,Y
	XBA
	STA.W 0x0080,Y


; decalage du nombre de Gils
*=0x018FAF
	ADC.W #0x0052



; décalage du Temps
*=0x018BC1
	LDA.B #0x80
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


;**************************
;** Classes des Persos ! **
;**************************
; Modification pour alonger les noms des classes.
; Deplacement du nom des classe vers la gauche
*=0x018C1A
	ADC.W #0x0000

; alongement des noms de classe à 16 caractères.
*=0x018FD3
    jsr.l load_classes_pointer

	;ASL
	;ASL
	;ASL
	;ASL
	NOP
	NOP
	STA.B 0x45
	STZ.B 0x46
	LDX.B 0x45
	LDA.B #0x0F


;018ff4 sta 0x0000,y   [7ed8d5] A:0002 X:003c Y:d8d5 S:02e5 D:0100 DB:7e nvMxdIzc V: 92 H: 512
*=0x18ff4
    nop
    nop
    nop
; Move the class names where to freespace
; 018fe3 lda 0x0fa764,x
*=0x018fe3
    lda.l characters_classes, x
    beq 0x018ffe + 2
	;JSR.L _8x16
	;NOP
	;NOP
;	NOP
;	NOP
	jsr.l _8x16
	jsr.l _8x16dis2
	;jsr.l _8x8_vwf_display2
;	NOP
;	NOP
	NOP

;exemple d'appel
;
;	LDA.B #0xnumptr
;	JSR.L textload	;textload(numptr)

;deroutage pour charger le menu à l'aide d'un pointeur 24bit
*=0x018931
	JSR.W PT0000

; TIME
*=0x0187CE
	LDA.B #0x01
	JSR.L textload
	NOP
	NOP
	NOP

; Gils
*=0x0187C5
	LDA.B #0x02
	JSR.L textload
	NOP
	NOP
	NOP

; 'Ne peux utiliser'
*=0x01AED9
	JSR.W PT0001

; fenètre Ne peut utiliser
*=0x01DD40
	.dw 0x0210, 0x0310


;*************************************
;** Menu Objet                      **
;*************************************
;Objet:
;Layer 4
*=0x01A817
	JSR.W PT0002


;layer 2
*=0x019F59
	JSR.W PT0002


;fenètre Objet
*=0x01DCFC
	.dw 0x0000, 0x0307

;fenètre Description objet
*=0x01DCD6
	.dw 0x0010, 0x0316

*=0x01A36F
	LDA.B #0x05
	JSR.L textload

;Fenètre principale objet
*=0x01DCCE
	.dw 0x0000, 0x301E

;*************************************
;** Menu Configuration              **
;*************************************

; Configuration
*=0x01D1A7
	JSR.W PT0003

*=0x01E168
	.dw 0x0102, 0x141C

;RGB -> RVB :o)
*=0x01D1BB
	LDA.B #0x57

;fenètre du titre 'options'
*=0x01E15C
	.dw 0x0054, 0x0209

;'Options'
*=0x01D1B0
	LDA.B #0x07
	JSR.L textload

;déplacement du curseur principal des options
*=0x01D247
	LDA.B #0x00

;main dans le menu controle
;x
*=0x01D4E6
	LDA.B #0x03

;y
*=0x01D4E2
	ADC.B #0x4C

; 'buttons' :)
*=0x01D496
	LDA.B #0x0F
	JSR.L textload

;
*=0x01E200
	.dw 0x01C0, 0x0C1C

;multiple:
*=0x01D662
	JSR.W derout_mult

*=0x01D685
	LDA.B #0x13
	JSR.L textload

;*************************************
;** Menu Magie	                    **
;*************************************
*=0x01AFA2
	LDA.B #0x08
	JMP.W derout_magie

*=0x01AFB6
	LDA.B #0x09
	JMP.W derout_magie2

*=0x01AFCA
	LDA.B #0x0A
	JMP.W derout_magie3

;.patch (0x01AFA7)
;LDA.B #0x11
;	JMP.W derout_magie4

*=0x01AFDE
	LDA.B #0x11
	JSR.L textload

;MP needed
*=0x01B0EC
	LDA.B #0x10
	JSR.L textload
	NOP
	NOP
	NOP

;décalage du cout
*=0x01B0F7
	STA.W 0xC858

*=0x01B0E6
	LDY.W #0x025C


;décalage de la 'main'
*=0x01B0CE
	LDA.B #0x00

;Grisement des types sorts : 'Blancs' 'Noirs' etc ...
*=0x01B419
	LDY.W #0x0007
	STA.W 0xC5FF,X


;
; Spells menu
;


; length of spells names
*=0x01B345
	LDA.B #0x07

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

;*************************************
;** Menu Status	                    **
;*************************************

;décalage du nom vers le haut
*=0x01A9B7
	LDY.W #0x0044

*=0x01A99E
	LDA.B #0x0B
	JSR.L textload

*=0x01AAE9
	LDA.B #0x0C
	JSR.L textload

;experience et tout le bidule
*=0x01ABBC
	LDA.B #0x0D
	JSR.L textload

*=0x01D48D
	LDA.B #0x0E
	JSR.L textload

;*******************
;** Menu Equiper  **
;*******************

;dernière fenètre a apparaitre:
*=0x01DDA9
	.dw 0x0000, 0x0B1E

;données pour translater ...
*=0x01DD95
	.dw 0x0000, 0x0B1E

*=0x01BD12
	JSR.W derout_equip

;*********************************
;** Décalage des objets equipés **
;*********************************

;Main D
*=0x01BD92
	LDX.W #0x0068

;Main G
*=0x01BDA8
	LDX.W #0x00E8

;Tête
*=0x01BD7B
	LDX.W #0x0168

;Corps
*=0x01BD82
	LDX.W #0x01E8

;Bras
*=0x01BD89
	LDX.W #0x0268

; this code belongs more to the items module.
;*=0x01903F
;	LDA.B #0x0A

;*=0x019028
;	JSR.W calc_itempos
;	retcalcpos:

;*=0x019047
;	JSR.W _8x16item

; Routines d'affichage de differents textes ^^
*=0x01FF36
retmag 	= 0x01AFAD
retmag2	= 0x01AFC1
retmag3	= 0x01AFD5

load_classes_pointer:
    phx
    rep #0x20

    and.w #0x00FF
    asl
    tax

    lda.l characters_classes_table, x
    sep #0x20

    plx
    rtl

;ça foire si je mets autre chose que des ASL
calc_itempos:
	ASL
	ASL
	ASL
	ASL
	RTS

_8x16item:
	JSR.L _8x16
	RTS

derout_magie:
	JSR.L textload
	JMP.W retmag

derout_magie2:
	JSR.L textload
	JMP.W retmag2

derout_magie3:
	JSR.L textload
	JMP.W retmag3

derout_mult:
	JSR.W 0x80D9
	LDA.B #0x12
	JSR.L textload
	RTS

derout_equip:
	LDA.B #0x14
	JSR.L textload
	RTS
PT0000:
	JSR.W 0x80D9

    ;dma_transfer_to_vram_nofunk(assets_menu_bin, 0x6000, assets_menu_bin__size, 0x1801)

	highway_to_hell:
;	wait_for_vblank_inline()
;	dma_transfer_to_vram_nofunk(0x0AF000 ,0x6000, 0x1000, 0x1801)
;	wait_for_vblank_inline()
 ;   dma_transfer_to_vram_nofunk(fuck, 0x2810, assets_menu_bin__size, 0x1801)

	LDA.B #0x00
	JSR.L textload
	RTS

PT0001:
	JSR.W 0x80D9
	LDA.B #0x03
	JSR.L textload
	RTS
PT0002:
	JSR.W 0x80D9
	LDA.B #0x04
	JSR.L textload
	RTS
PT0003:
	JSR.W 0x80D9
	LDA.B #0x06
	JSR.L textload
	RTS

; freespace
*=0x20B000

; routine de 8x16
_8x16:
	PHX
	REP #0x20
	AND.W #0x00FF
	ASL
	TAX
	LDA.L _8x16tbl,X
	SEP #0x20
	PLX
	RTL

; modification de la 8x16 pour le menu
_8x8_vwf_display1:
    sta.l 0x7E0040,X
    lda #0x01
    ora 0x7E0041, X
    sta.l 0x7E0041, X
    inx
    inx
    rtl

_8x8_vwf_display2:
   STA.W 0x0040,Y
   lda #0x01
   ora 0x34
   sta 0x34
   iny
   rtl

_8x16disp:
	CMP #0x00
	BEQ no_8x16
	STA.L 0x7E0000,X

	no_8x16:
		XBA
		STA.L 0x7E0040,X
	INX
	INX
	RTL

_8x16dis2:
	CMP #0x00
	BEQ no2_8x16
	STA.W 0x0000,Y

	no2_8x16:
		XBA
		STA.W 0x0040,Y
	INY
	RTL

;pointeur Items:
ptr_items:
	LDA.B 0x43
	ASL
	PHA
	ADC.B 0x43
	STA.B 0x43
	PLA
	ASL
	ASL
	ADC.B 0x43
	RTL

;deroutage pour le grisement de 'Sauver
derout_save:
	LDA.B #0x24
	STA 0xCA31	;S
	STA 0xCA33	;a
	STA 0xCA35	;u
	STA 0xCA37	;v
	STA 0xCA39	;e
	STA 0xCA3B	;r
	RTL

;deroutage pour l'affichage du NIVEAU
deroutage:
	LDA.B #0x4E	;M
	STA.W 0x0082,X

	LDA.B #0x57	;V
	STA.W 0x0042,X

;	LDA.B #0xC7	;/
;	STA.W 0x004E,X
;	STA.W 0x008E,X
	RTL


;chargement du pointeur et chargement du texte
vwf_text_load:
    pha
    lda #0x01
    sta 0x03
    pla
    bra _textload

textload:
    stz 0x03
_textload:
	;chargement du pointeur
	PHX
	REP #0x20
	AND.W #0x00FF
	STA 0x00
	ASL
	ADC.B 0x00
	TAX

	LDA.L menu_text_pointer_table,X
	INX
	INX
	TAY
	SEP #0x20

	LDA.L menu_text_pointer_table,X
	STA 0x02
	STZ 0x01
	STZ 0x00
load_wram_pointer:
	REP #0x20
	LDA [0x00],Y
	INY
	INY
	CLC
	ADC 0x29
	TAX
	SEP #0x20
load_char_loop:
	LDA [0x00],Y
	BEQ end_of_string
	INY

	CMP #0x01
	BEQ load_wram_pointer
    pha
    lda 0x03
    bne vwf_display
    pla
	JSR.L _8x16
	JSR.L _8x16disp
	bra _text_load_continue

vwf_display:
    pla
	jsr.l _8x8_vwf_display1
_text_load_continue:
	BRA load_char_loop
end_of_string:
	PLX
	RTL


_8x16tbl:
;00= on affiche rien au dessus de la lettre :)
;ex: 0x4200 affiche un A majuscule sans rien au dessus
;	    0     1     2     3     4     5     6     7     8     9     A     B     C     D     E     F
	.dw 0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff	;0x0
	.dw 0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff	;0x1
	.dw 0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff	;0x2
	.dw 0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff	;0x3
	.dw 0xff00,0xff00,0x4200,0x4300,0x4400,0x4500,0x4600,0x4700,0x4800,0x4900,0x4A00,0x4B00,0x4C00,0x4D00,0x4E00,0x4F00	;0x4
	.dw 0x5000,0x5100,0x5200,0x5300,0x5400,0x5500,0x5600,0x5700,0x5800,0x5900,0x5A00,0x5B00,0x5C00,0x5D00,0x5E00,0x5F00	;0x5
	.dw 0x6000,0x6100,0x6200,0x6300,0x6400,0x6500,0x6600,0x6700,0x6800,0x6900,0x6A00,0x6B00,0x6C00,0x6D00,0x6E00,0x6F00	;0x6
	.dw 0x7000,0x7100,0x7200,0x7300,0x7400,0x7500,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff	;0x7
	.dw 0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff	;0x8
	.dw 0x608A,0x608B,0x608C,0x608D,0x5C8A,0x5C8B,0x6A8B,0x708A,0x708B,0xffff,0xffff,0xffff,0xffff,0xffff,0x9E00,0xffff	;0x9
	.dw 0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff	;0xA
	.dw 0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff	;0xB
	.dw 0xC000,0xC100,0xC200,0xC300,0xC400,0xC500,0xC600,0xC700,0xC800,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff	;0xC
	.dw 0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff	;0xD
	.dw 0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff	;0xE
	.dw 0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xffff,0xff00	;0xF


; addresse de la table des pointeurs pour le code :)
menu_text_pointer_table:
	; table de pointeurs 24 bits pour les textes du menu
.include 'src/txt_menu.s'

commandes:
    .text 'Attaquer           '




characters_classes:
;    .table 'text/gen/menu.tbl'
    black_knight:
    .text 'Chevalier noir'
    .db 0
    dragon_knight:
    .text 'Chevalier dragon'
    .db 0

    summoner:
    .text 'Invokeur'
    .db 0

    sage:
    .text 'Sage'
    .db 0

    ministrel:
    .text 'Menestrel'
    .db 0

    white_wizard:
    .text 'Sorcier Blanc'
    .db 0

    monk:
    .text 'Moine'
    .db 0

    black_wizard:
    .text 'Sorcier Noir'
    .db 0

    paladin:
    .text 'Paladin'
    .db 0

    engineer:
    .text 'Ingenieur'
    .db 0


    ninja:
    .text 'Ninja'
    .db 0

    lunarian:
    .text 'Selenite'
    .db 0



characters_classes_table:
  .dw black_knight - characters_classes
  .dw dragon_knight - characters_classes
  .dw summoner - characters_classes
  .dw sage - characters_classes
  .dw ministrel - characters_classes
  .dw white_wizard - characters_classes
  .dw monk - characters_classes
  .dw black_wizard - characters_classes
  .dw white_wizard - characters_classes
  .dw paladin - characters_classes
  .dw engineer - characters_classes
  .dw summoner - characters_classes
  .dw ninja - characters_classes
  .dw lunarian - characters_classes


;.incbin 'assets/menu.bin'