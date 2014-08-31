; ----------------
; Final Fantasy IV the new hack.
; ----------------
.include 'src/libmz.i'

dialog_bank_ptr_base = 0x218000


; déroutage pour ajouter le splash screen
*=0x008031
	jsr.l start_splash_screen

; déroutage pour utiliser la vwf dans les dialogues.
*=0x00B463
	jsr.l vwfstart
	rts


.include 'src/vwf_patches.s'


; include code and assets
*=0x208000
.include 'src/libmz.s'
.include 'src/intro.s'
.include 'src/vwf.s'
.include 'src/dialog.s'
.include 'src/menus.s'

;*=0x21805D

;.table 'text/ff4fr.tbl'
;*=0x2180FD
;.pointer pt_intro_test_de_la_mort
;pt_intro_test_de_la_mort:
;.db $04,$00
;.db $04,$01
;.db $04,$02
;.db $04,$03
;.db $04,$04

;.db $00

*=0x218000
.incbin 'assets/bank1.ptr'
;*=0x218600
;.incbin 'assets/bank2.ptr'
;.incbin 'assets/bank3.ptr'

*=0x228000
.incbin 'assets/bank1.dat'

;*=0x238000
;.incbin 'assets/bank2.dat'

;*=0x248000
;.incbin 'assets/bank3.dat'

*=0x258000
.incbin 'assets/font.dat'
.incbin 'assets/font_length_table.dat'


*=0x278000
; Splash screen assets
.incbin 'assets/intro.map'
.incbin 'assets/intro.col'
.incbin 'assets/intro.set'







