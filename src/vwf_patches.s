;=====================================================================
; Les Fonctions de chargement de pointeur de dialogue
;=====================================================================

*=0x00B404
	JSR.L CalculePositionTb
 	JSR.L PointeurBank1de1
 	STA.B $DD
 	LDX.B $3D
 	STX.W $0772
 	RTS
 
 *=0x00B41D
 	JSR.L CalculePositionTb
 	JSR.L PointeurBank1de2
 	STA.B $DD
 	LDX.B $3D
 	STX.W $0772
 	RTS
 
 *=0x00B436
 	JSR.L CalculePositionTb
 	JSR.L PointeurBank3
 	STA.B $DD
 	LDX.B $3D
 	STX.W $0772
 	RTS
 
 *=0x00B3BB
 	LDA.W $1702
 	STA.B $3D
 	LDA.W $1701
 	STA.B $3E
 	JSR.L PointeurBank2
 	RTS
 


; Patch pour eviter les problemes de scroll du texte
*=0x00B736
	LDA.B #$EC


; Patching Map Display
;*=0x00B718
;	NOP
;	NOP
;


;*=0x00B333
;	STZ.B $EB
;

*=0x00B81C
	LDA #$03


*=0x00B848
	LDX.W #$001A


*=0x00B86B
	LDX.W #$001A


*=0x00B88A
	ADC.B #$1A


*=0x00B897
	ADC.B #$1A


;patch pour pouvoir utiliser la vwf dans les intros
*=0x00D438
	LDY.W #$21D1


;patch de l'interieur de la fenètre pour decaler de $100 et utiliser le tileset vwfé :^)
*=0x14F75C
.db $D0,$21,$D0,$21,$D0,$21,$D0,$21,$D0,$21,$D0,$21,$D0,$21,$D0,$21,$D0,$21,$D0,$21,$D0,$21,$D0,$21,$D0,$21
.db $D0,$21,$D0,$21,$D0,$21,$D0,$21,$D0,$21,$D0,$21,$D0,$21,$D0,$21,$D0,$21,$D0,$21,$D0,$21,$D0,$21,$D0,$21


txref = $ED
*=0x14F66C
	.dw $2006+txref,$2008+txref			; ô OUI ;)


*=0x14F67C
	.dw $2007+txref,$2009+txref			; Bah oui


*=0x14F68C
	.dw $2000+txref,$2002+txref,$2004+txref		; ô NON


*=0x14F69C
	.dw $2001+txref,$2003+txref,$2005+txref		;bah Non



*=0x00B775
	RTS


*=0x00B791
NOP
NOP
NOP


*=0x00B7A9
NOP
NOP
NOP


*=0x00B7C4
NOP
NOP
NOP


;;; test
;*=0x00B834
;NOP
;NOP
;NOP
;

;*=0x00B84E
;NOP
;NOP
;NOP
;

;*=0x00B871
;NOP
;NOP
;NOP
;

;scroll 1
*=0x00B706
	STZ.W $2112


;scroll 2
*=0x00B733
	STZ.W $2111


*=0x00B738
	STZ.W $2112


*=0x00B755
	STZ.W $2112


;clear map call
*=0x00B7DF
	JSR.L wclear
	RTS


;décalage des mini fenètres ^^
;haut de la fenètre Gils
*=0x00AD33
	LDX.W #$2892+$100

;suite
*=0x00AD42
	LDX.W #$28B2+$100


;00AD5A LDX #$28D2
*=0x00AD5A
	LDX.W #$28D2+$100


;00AD72 LDX #$28F2
*=0x00AD72
	LDX.W #$28F2+$100


;00AD8A LDX #$28D3
*=0x00AD8A
	LDX.W #$28D3+$100


*=0x00AEE7
	LDA.B #$29


;décalage du curseur
*=0x00AE38
	LDX.W #$29C4


*=0x00AE51
	LDX.W #$2A04
