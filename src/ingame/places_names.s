"""
Place-name window patches: increase the window length to fit French names and find the title in our table. The
rows themselves are filled by ingame/map_title_vwf.s, in the small VWF.
"""
.import "ingame/places_names_window"
.import "assets"
.import "vanilla"

{
    place_name_length = PLACE_NAME_LENGTH

    .alloc at 0x00B8F1 {
    lda.l place_names, x
    }

    .alloc at 0x00B963 {
    lda.l places_top_window, x
    }

    .alloc at 0x00B96B {
    lda.l places_top_window, x
    }

    .alloc at 0x00B973 {
    cpx.w #PLACE_WINDOW_WIDTH * 2

;.00:B98D                 LDA     $780,X
    }

    .alloc at 0x00B98D {
    lda.w dialog_text_buffer + place_name_length, x
    }

    .alloc at 0x00B999 {
    cpx.w #place_name_length
    }

    .alloc at 0x00B9D1 {
    cpx.w #place_name_length
    }

    .alloc at 0x00B9F6 {
    lda.l places_bottom_window, x
    }

    .alloc at 0x00B9FE {
    lda.l places_bottom_window, x
    }

    .alloc at 0x00BA06 {
    cpx.w #PLACE_WINDOW_WIDTH * 2

    vram_ptr = 0x2840 + ( 32 - PLACE_WINDOW_WIDTH ) / 2  ; centred on the screen
    }

    .alloc at 0x00B95A {
;.00:B95A                 LDX     #$2848 ; top window
    ldx.w #vram_ptr
    }

    .alloc at 0x00B978 {
;.00:B978                 LDX     #$2868 ; left window piece
    ldx.w #vram_ptr + 0x20
    }

    .alloc at 0x00B99E {
;.00:B99E                 LDX     #$2876 ; right window piece
    ldx.w #vram_ptr + 0x20 + place_name_length + 2
    }

    .alloc at 0x00B9B0 {
;.00:B9B0                 LDX     #$2888 ; left window piece
    ldx.w #vram_ptr + 0x40
    }

    .alloc at 0x00B9D6 {
;.00:B9D6                 LDX     #$2896 ; right window piece
    ldx.w #vram_ptr + 0x40 + place_name_length + 2
    }

    .alloc at 0x00B9ED {
;.00:B9ED                 LDX     #$28A8 ; bottom window
    ldx.w #vram_ptr + 0x60
    }
}
