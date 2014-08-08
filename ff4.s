; ----------------
; Final Fantasy IV the new hack.
; ----------------
#include "src/libmz.i"

dialog_bank_ptr_base = 0x218000



; déroutage pour ajouter le splash screen
*=0x008031
	jsr.l start_splash_screen

; déroutage pour utiliser la vwf dans les dialogues.
*=0x00B463
	jsr.l vwfstart
	rts


#include "src/vwf_patches.s"


; include code and assets
*=0x208000
#include "src/libmz.s"
#include "src/intro.s"
#include "src/vwf.s"
#include "src/dialog.s"

*=0x21805D

.table "text/ff4fr.tbl"

.dw pt_intro_test_de_la_mort & 0xFFFF
.db pt_intro_test_de_la_mort >> 16
pt_intro_test_de_la_mort:
.text "ABCDEFGHIJ"

.db 0x00

*=0x258000
.incbin "assets/font.dat"
.incbin "assets/font_length_table.dat"

*=0x278000
; Splash screen assets
.incbin "assets/intro.map"
.incbin "assets/intro.col"
.incbin "assets/intro.set"







