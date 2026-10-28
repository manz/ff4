"""
Place-name window patches: wider window for French names, titles from our table. ingame/map_title_vwf.s draws
the rows in the small VWF.
"""
.import "ingame/places_names_window"
.import "core/assets"
.import "core/vanilla"
.import "core/sram_layout"
.include "core/bank20.i"

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
; top edge (vanilla $2848)
        ldx.w #vram_ptr
    }

    .alloc at 0x00B978 {
; left edge, row 1
        ldx.w #vram_ptr + 0x20
    }

    .alloc at 0x00B99E {
; right edge, row 1
        ldx.w #vram_ptr + 0x20 + place_name_length + 2
    }

    .alloc at 0x00B9B0 {
; left edge, row 2
        ldx.w #vram_ptr + 0x40
    }

    .alloc at 0x00B9D6 {
; right edge, row 2
        ldx.w #vram_ptr + 0x40 + place_name_length + 2
    }

    .alloc at 0x00B9ED {
; bottom edge
        ldx.w #vram_ptr + 0x60
    }
}

; Vanilla closes the place-name window on the first step, so walking into a town with the pad held hides the name
; before it can be read. Keep it up for the first steps.
PLACE_NAME_STEPS := 4  ; a step takes 16 frames

.alloc at 0x00A9F7 {
; the walk's "lda $EA / bne / inc $EA" that requests the window close
    jsr.l place_name_step
    nop
    nop
}

.alloc _place_name_step_block in bank20_reloc {
place_name_step:
"""A step while walking: close the place-name window ($EA: 0 up, 1 closing, 2 closed) after PLACE_NAME_STEPS."""
    lda.b 0xEA
    bne closed
    lda.l place_name_steps
    inc
    sta.l place_name_steps
    cmp #PLACE_NAME_STEPS
    bcc up
    inc.b 0xEA
closed:
    lda #0x00
    sta.l place_name_steps
up:
    rtl
}
