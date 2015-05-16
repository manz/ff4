;décalage du nom vers le haut
*=0x01A9B7
	ldy.w #0x0044

*=0x01A99E
	load_system_menu_text_pointer(status.status)

*=0x01AAE9
	load_system_menu_text_pointer(status.exp_for_next_level)

*=0x01ABBC
	load_system_menu_text_pointer(status.char_stats)

*=0x01A9CA
	ldy.w     #0x15C - 0x80