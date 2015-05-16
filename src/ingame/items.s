; during scroll
*=0x01A814
	load_system_menu_text_pointer(items_menu.item)

; when scroll done
*=0x019F56
	load_system_menu_text_pointer(items_menu.item)
