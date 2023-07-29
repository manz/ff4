; ギル : gils
*=0x01C3EC
	load_system_menu_text_pointer(shops.gils)

*=0x01C350
	load_system_menu_text_pointer(shops.welcome_and_actions)

*=0x01C43F
	load_system_menu_text_pointer(shops.quantity)

*=0x01C568
	 load_system_menu_text_pointer(shops.gils + 2)

; moves gils text char right
*=0x01C561
	sec
	sbc #0x30 - 2

; 'tools message window
;*=0x01DEB2
;.db 0x10
;.db   0
;.db 0x14
;.db   3



; Tools Buy Sell Exit menu window
*=0x01DEAA
	; position
	.db 0x02,0x01
	;
	.db 0x12,0x03

; Changes the offset of the hand pointer
*=0x01C37C
	lda 0x1B79
	asl
	asl
	asl
	asl
	sta 0x45
	asl
	adc 0x45
	nop
	nop
	sta 0x45