; ----------------
; Final Fantasy IV the new hack.
; ----------------
.include 'src/libmz.i'

.include 'src/vwf_patches.s'
;.include 'src/battle.s'

dialog_bank_ptr_base = 0x218000


; patch snes cartrdige type
; original PCB: SHVC-1A3B
; target PCB: SHVC-1A5B

;FFD5 20H / 30H Map Mode
;*=0xFFD6
;    .db 0x02 ; Cartridge Type
;    .db 0x0B ; ~ 0BH ROM Size
;    .db 0x05 ; RAM Size


; déroutage pour ajouter le splash screen
*=0x008031
	jsr.l start_splash_screen

; déroutage pour utiliser la vwf dans les dialogues.
*=0x00B463
	jsr.l vwfstart
	rts

;*=0x0AF000
;   .incbin 'fonts/8x8.bin'


*=0x0f8000
    .incbin 'assets/items.dat'

*=0x208000
    .include 'src/libmz.s'
    .include 'src/intro.s'
    .include 'src/vwf.s'
    .include 'src/dialog.s'
    .include 'src/menus.s'
    .incbin 'assets/magic.dat'

*=0x218000
    .incbin 'assets/bank1_1.ptr'
    .incbin 'assets/bank1_2.ptr'
    .incbin 'assets/bank2.ptr'

*=0x228000
    .incbin 'assets/bank1_1.dat'

*=0x24A000
    .incbin 'assets/bank1_2.dat'

*=0x25A000
    .incbin 'assets/bank2.dat'
;    .incbin 'assets/places.dat'

*=0x27A000
    .incbin 'assets/font.dat'
    .incbin 'assets/font_length_table.dat'

; Splash screen assets
*=0x288000
    .incbin 'assets/intro.map'
    .incbin 'assets/intro.col'
    .incbin 'assets/intro.set'







