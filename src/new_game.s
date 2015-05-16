.table 'text/ff4_menus.tbl'

{
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
	load_system_menu_text_pointer(newgame.save)

*=0x01962E
	load_system_menu_text_pointer(newgame.new_game)

*=0x019826
	load_system_menu_text_pointer(newgame.load_this_save)

*=0x01982C
	load_system_menu_text_pointer(newgame.yes_no)
;
*=0x01983E
	load_system_menu_text_pointer(newgame.time_load_save)

*=0x01984D
	load_system_menu_text_pointer(newgame.gils_load_game)
	ldx.w #0x674
*=0x019AC5
    load_system_menu_text_pointer(newgame.empty_save)

}