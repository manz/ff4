{
place_name_length = 0x1A
*=0x00B90E
	lda.b #place_name_length

*=0x00B922
	cpx.b #place_name_length

*=0x00B8F1
	lda.l assets_places_names_dat, x

*=0x00B901
	lda.l assets_places_names_dat, x

*=0x00B92C
	lda.l assets_places_names_dat, x

*=0x00B938
	sta.w 0x774 + place_name_length, y

*=0x00B91E
	sta.w 0x774 + place_name_length, x


; window transfer related stuff
*=0x00B963
 	lda.l places_top_window, x

*=0x00B96B
 	lda.l places_top_window, x

*=0x00B973
	cpx.w  #0x003C ;place_name_length * 2 + 8

;.00:B98D                 LDA     $780,X
*=0x00B98D
	lda.w 0x774 + place_name_length, x

*=0x00B999
	cpx.w #place_name_length

*=0x00B9D1
	cpx.w #place_name_length


*=0x00B9F6
	lda.l places_bottom_window, x

*=0x00B9FE
	lda.l places_bottom_window, x

*=0x00BA06
	cpx.w #0x003C; place_name_length + 8


vram_ptr = 0x2840 + 1

*=0x00B95A
	;.00:B95A                 LDX     #$2848 ; top window
	ldx.w #vram_ptr
*=0x00B978
	;.00:B978                 LDX     #$2868 ; left window piece
	ldx.w #vram_ptr + 0x20
*=0x00B99E
	;.00:B99E                 LDX     #$2876 ; right window piece
	ldx.w #vram_ptr + 0x20 + place_name_length + 2
*=0x00B9B0
	;.00:B9B0                 LDX     #$2888 ; left window piece
	ldx.w #vram_ptr + 0x40
*=0x00B9D6
	;.00:B9D6                 LDX     #$2896 ; right window piece
	ldx.w #vram_ptr + 0x40 + place_name_length + 2
*=0x00B9ED
	;.00:B9ED                 LDX     #$28A8 ; bottom window
	ldx.w #vram_ptr + 0x60

}
