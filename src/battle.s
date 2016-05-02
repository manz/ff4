command_length = 11

{
*=0x029CD6
	lda.b #command_length

*=0x029D15
	lda.b #command_length

*=0x029D42
	cpy.w #command_length + 2
;
*=0x029D5A
	cpy.w #command_length + 2
;
*=0x029D39
    lda.l assets_battle_commands_dat, x
; x offset of the battle commands window
;*=0x16fe66
;	.db 0
;; this byte controls the command window size
*=0x16fe68
   	.db command_length + 2

*=0x029CE0
	lda.b #command_length * 4

*=0x16FE54
.db command_length * 2
.db 5 * 2
.dw 0x8CB2	; read address
.dw 0xC1F4 ; - 6 * 2 	; write address
.db 0x01


{
; ram position of the prebuilt battle windows
*=0x16FEAD
battle_data_size = command_length * 4 * 5
.dw 0x8CB2
.dw 0x8CB2 + battle_data_size
.dw 0x8CB2 + battle_data_size * 2
.dw 0x8CB2 + battle_data_size * 3
.dw 0x8CB2 + battle_data_size * 4

*=0x02999F
 	ldx.w #battle_data_size
 	; move items ram location


*=0x029FBB
	battle_items_position = 0x2E00
	adc.w #battle_items_position

*=0x02991E
	jsr.l copy_battle_char
	nop

	nop
	nop
	nop

	nop
	nop


*=0x029932
	jsr.l copy_battle_char
	nop

	nop
	nop
	nop

	nop
	nop


; patch normal display_char to include 7FFFFF based switch
*=0x02A49B
	jsr.l battle_display_char
	rts

; patch normal display_dakuten_char to include 7FFFFF based switch
*=0x02A4AC
	jsr.l battle_display_dakuten_char
	rts

; enclose jsr build_tileset_function
; with 7FFFFF switch in the items related stuff.
*=0x02A06C
	jsr.w 0xFFC2


.macro set_battle_sram_copy_flag(value) {
    lda.b #value
    sta.l 0x7FFFFF
}

.macro enable_battle_sram_copy() {
    set_battle_sram_copy_flag(0x85)
}

.macro disable_battle_sram_copy() {
    set_battle_sram_copy_flag(0x00)
}

*=0x02FFC2
    enable_battle_sram_copy()
	jsr 0xA455
	disable_battle_sram_copy()
	rts


; 0x16FA40 battle dakuten


}

}

