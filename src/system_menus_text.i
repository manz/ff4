.macro load_system_menu_text_pointer(pointer) {
	ldy.w #pointer - 0x8000
}

{
*=0x018301
	jmp.l display_text_in_menus

*=0x0182CD
	jmp.l load_text_with_destination_in_x

*=0x0180D9
	jmp.l display_window_with_text

*=0x018798
	jmp.l display_time
}