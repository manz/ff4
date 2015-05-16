battle_magic_length = 8

; used for the copy for the dakuten offset
*=0x02A094
	; _ _ _ _ _ _
	; A B B B B B
	lda.b #battle_magic_length

;*=0x02A0DC
;	lda.b #battle_magic_length - 1

*=0x02A0E2
	lda.b #battle_magic_length

*=0x02a113
	lda.b #battle_magic_length - 1

*=0x02A0FF
	lda.l assets_magic_dat, x

*=0x02A117
	lda.l assets_magic_dat+1, x

*=0x02A09E
	lda.b #battle_magic_length * 4

*=0x02986C
	ldx  #0xC52A
	stx  0x00
	ldx.w #0xC52A + 2 + battle_magic_length * 2
	stx  0x02
	ldx  #0xC546
	stx  0x04

;original
magic_data_base = 0x909A

;magic_data_base = 0x703720
*=0x029893
	lda.w magic_data_base, x
	sta  (0x00), y
	lda.w magic_data_base + battle_magic_length * 4, x
	sta  (0x02), y
	nop
	nop
	nop
	;LDA     0x97D6,X
	nop
	nop
	;STA     (0x4),Y
	iny
	inx
	cpy.w #battle_magic_length * 2


*=0x0298AC
	lda.w magic_data_base, x
	sta (0x00), y
	lda.w magic_data_base + battle_magic_length * 4, x
	sta (0x02), y
	;LDA     $97D6,X
	nop
	nop
	nop
	;STA     (D,4),Y
	nop
	nop
	iny
	inx
	cpy.w #0x40 + battle_magic_length * 2

*=0x0298C6
	adc.w #battle_magic_length * 2 * 2

*=0x02988D
	lda.b #12


; 0x240 * 3 = 0x6C0
{
size = 0x120
;fsize = size * 4
;fsize = 0x6C0 ; original
fsize = 0x900
*=0x029825
	.dw 0x0000
	.dw fsize
	.dw fsize * 2
	.dw fsize * 3
	.dw fsize * 4

*=0x16FF2F
    .dw magic_data_base & 0xFFFF
    .dw (magic_data_base + fsize) & 0xFFFF
    .dw (magic_data_base + fsize * 2) & 0xFFFF
    .dw (magic_data_base + fsize * 3) & 0xFFFF
    .dw (magic_data_base + fsize * 4) & 0xFFFF

;*=0x16ff39
;	.dw 0x2C7A
;	.dw 0x2C7A + fsize
;	.dw 0x2C7A + fsize * 2
;	.dw 0x2C7A + fsize * 3
;	.dw 0x2C7A + fsize * 4


*=0x029834
	ldx.w #0x300 ; 0x240

*=0x02982F
	ldx.w #0x600 ; 0x480

; patches the transfer size
*=0x16fe1c
	.dw 0x600 ; 0x400
}
; number of lines to scroll ?
*=0x02B72B
	cmp #11

; items per line for cursor dpad right
*=0x02B781
	cmp #1


; dpad up
*=0x02B712
	nop
	nop

*=0x02B71C
	nop
	nop

; dpad down
*=0x02B751
;	INC     D,$63
	nop
	nop

*=0x02B742
	nop
	nop


*=0x16FC56
	.db 2
	.db 0x3C + 14
	.db 0x74

*=0x16FC5B
	.db 0x9C
	.db 0xA8
	.db 0xB4


*=0x02B764
	inc 0x5F
	;inc 0x5F
	nop
	nop
	inc 0x63
	;inc 0x63
	nop
	nop

*=0x02B785
	dec 0x5F
	;dec 0x5F
	nop
	nop
	dec 0x63
	;dec 0x63
	nop
	nop
