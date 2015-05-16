
;*=0x029D39
;    lda.l battle_actions, x
;
;; copy 8 bytes for the action
;*=0x029D42
;    ;cpy #0x0008
;
;*=0x0FA7B9
;battle_actions:
;.table 'text/ff4_menus.tbl'
;.text 'Attaquer'

;*=0x028561
;	ldx #0x000A


;.02:8561                 LDX     #8


; 0x029A63
; may be main battle init
; all the windows are prebuilt
; call that results in loading funcs.
; $02/9A78 20 69 9D    JSR $9D69  [$02:9D69]   A:0005 X:7505 Y:000C P:envMxdIZC


; Ram address of the first tilemap
; 029A45 LDA $0000, x  ; 7E8CBC
;
;*=0x0289BB
;	ldy #0x6AC0
;*=0x029A75
;	nop
;	nop
;	nop
;.02:89BB                 LDY     #$6C00
command_length = 10

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
;
;; this byte controls the command window size
*=0x16fe68
   	.db command_length + 3


*=0x029CE0
	lda.b #command_length * 4

;*=0x029D9E
; 	lda.b #command_length * 4
;*=0x16FEAD
;	.dw 0x8CB2
;	.dw 0x8CB2 + 0x64
;	.dw 0x8CB2 + 0x64 * 2
;	.dw 0x8CB2 + 0x64 * 3
;	.dw 0x8CB2 + 0x64 * 4

; japanese window
;*=0x16FE54
;.db 0x0A
;.db 0x0A	; number of lines of text
;.dw 0x8CB2	; read address
;.dw 0xC1F4 	; write address
;.db 0x01

;*=0x029A55
;	 ADC.b     #0x80 ; '@'
;*=0x02A4C8
;.dw 0xA64E
;.dw 0xA637; monsters names
;.dw 0xA657 ; Char names
;.dw 0xA6A4 ; dunno
;.dw 0xA64F
;.dw 0xA6AC ; supposed to clear monsters
;.dw 0xA4E6
;.dw 0xA6BD ; dunno
;.dw 0xA6C3 ; dunno
;.dw 0xA6CA
;.dw 0xA6D1
;.dw 0xA6D8
;.dw 0xA7AD
;.dw 0xA782
;.dw 0xA77A
;*=0x02999A ; window borders for battle commands

;*=0x029B20 ; all windows
;   nop
;   nop
;   nop


;*=0x0299A2 ; nukes the content of the battle window
;	rts
;	nop
;	 nop

*=0x16FE54
.db command_length * 2
.db 5 * 2
.dw 0x8CB2	; read address
.dw 0xC1F4 	; write address
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
;	battle_items_position = 0x8CB2 + battle_data_size * 5
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

; write window data to sram new size 0x3e8
;*=0x029D63
;;  JSR     copy_data_to_the_tile_map
;	jsr.w 0xFFC2

; write magic data to sram 0x2d00
;*=0x02A128
;	jsr.w 0xFFC2

*=0x02FFC2
	lda #0x85
	sta.l 0x7FFFFF
	jsr 0xA455
	lda #0x00
	sta.l 0x7FFFFF
	rts

; battle display
;*=0x02991E
;	lda.w battle_items_position, x
;*=0x029923
;	lda.w battle_items_position + 0x30,x
;
;*=0x029932
;	lda.w battle_items_position, x
;*=0x029937
;	lda.w battle_items_position + 0x30,x
;
;; build equiped items ts
;*=0x029E5C
;	lda.b #0x42
;	nop
;	nop

}
;.16:FEAD                 .WORD $8CB2
;.16:FEAF                 .WORD $8D16
;.16:FEB1                 .WORD $8D7A
;.16:FEB3                 .WORD $8DDE
;.16:FEB5                 .WORD $8E42

}

