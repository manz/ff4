; ----------------
; Final Fantasy IV the new hack.
; ----------------
.include 'src/libmz.i'
.include 'src/system_menus_text.i'

.include 'src/minimal_vwf_patches.s'
.include 'src/battle.s'
.include 'src/battle_magic.s'

.include 'src/places_names.s'
.include 'src/new_game.s'
.include 'src/shop_menu.s'
.include 'src/ingame/menus.i'


dialog_bank_ptr_base = 0x218000


; patch snes cartrdige type
; original PCB: SHVC-1A3B
; target PCB: SHVC-1A5B

;FFD5 20H / 30H Map Mode
*=0xFFD6
    .db 0x02 ; Cartridge Type
    .db 0x0B ; ~ 0BH ROM Size
    .db 0x05 ; RAM Size


; déroutage pour ajouter le splash screen
*=0x008031
	jsr.l start_splash_screen

; déroutage pour utiliser la vwf dans les dialogues.
*=0x00B463
	jsr.l vwfstart
	rts

;*=0x0AF000
;   .incbin 'fonts/8x8.bin'

;*=0x0AFF00-0x10 * 10
*=0x0AF900
	.incbin 'assets/vwf_precomp.bin'

; Patch des noms des personages
*=0x0FA710
	.incbin 'assets/characters_names.dat'

*=0x0f8000
    .incbin 'assets/items.dat'

*=0x208000
    .include 'src/libmz.s'
    .include 'src/intro.s'
    .include 'src/vwf.s'
    .include 'src/dialog.s'
	.include 'src/places_names_window.s'
	; system menu text routines
	.include 'src/system_menus_text.s'

	; menu text scopes
	.include 'src/menus/start_screen_text.s'
	.include 'src/menus/tools_shop_text.s'
	.include 'src/menus/in_game_text.s'

	.include 'src/battle_sram.s'

    .incbin 'assets/magic.dat'
	.incbin 'assets/places_names.dat'
	.incbin 'assets/classes.ptr'
	.incbin 'assets/classes.dat'

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

*=0x27A000
    .incbin 'assets/font.dat'
    .incbin 'assets/font_length_table.dat'
	.incbin 'assets/wicked_font.dat'
    .incbin 'assets/wicked_font_length_table.dat'
	.incbin 'assets/book_font.dat'
    .incbin 'assets/book_font_length_table.dat'
    .incbin 'assets/bold_font.dat'
    .incbin 'assets/bold_font_length_table.dat'
    .incbin 'assets/battle_commands.dat'

font_table:
	.pointer assets_font_dat
	.pointer assets_wicked_font_dat
	.pointer assets_book_font_dat
	.pointer assets_bold_font_dat
length_table:
	.pointer assets_font_length_table_dat
	.pointer assets_wicked_font_length_table_dat
	.pointer assets_book_font_length_table_dat
	.pointer assets_bold_font_length_table_dat

; Splash screen assets
*=0x298000
    .incbin 'assets/intro.map'
    .incbin 'assets/intro.col'
    .incbin 'assets/intro.set'







