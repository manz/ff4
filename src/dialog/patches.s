"""
Minimal dialog-VWF wiring: pointer-loading helpers + entry hooks called from the existing dialog routines so
the VWF layer kicks in without rewriting the message window.
"""

.import "core/preamble"
.include "core/libmz.i"
.include "dialog/vwf.i"
.include "strings.i"  ; src/lang/<lang>
.import "dialog/pointers"
.import "dialog/vwf"
.import "core/vanilla"

.label _text_cmd_07_b369 = 0x00B369
.label _text_cmd_08_b398 = 0x00B398

.alloc at 0x00B404 {
    jsr.l compute_dialog_text_offset
    jsr.l get_bank1_1_pointer
    sta 0xDD
    ldx.b dialog_vwf.text_ptr
    stx.w dialog_text_ptr
    rts
}
.alloc at 0x00B41D {
    jsr.l compute_dialog_text_offset
    jsr.l get_bank1_2_pointer
    sta 0xDD
    ldx.b dialog_vwf.text_ptr
    stx.w dialog_text_ptr
    rts
}
.alloc at 0x00B436 {
    jsr.l compute_dialog_text_offset
    jsr.l get_bank3_pointer
    sta 0xDD
    ldx.b dialog_vwf.text_ptr
    stx.w dialog_text_ptr
    rts
}
.alloc at 0x00B3BB {
    lda.w map_id
    sta.b dialog_vwf.text_ptr
    lda.w world_id
    sta.b dialog_vwf.text_ptr + 1
    jsr.l get_bank2_pointer
    rts
}
; Skip display_script's first call: the text must render before the window opens.
.alloc at 0x00B32C {
    jsr.w first_window
}
; Replace display_script with the VWF one.
.alloc at 0x00B463 {
    jsr.l vwfstart
    rts

first_window:
    lda 0x01
    sta 0xDE
    sta 0xED
    jsr.l vwfinit
    rts

animation_wait_route:
    _wait_for_nmi_end = 0x912F
    jsr.w _wait_for_nmi_end

_wait_for_open_animation:
    lda 0x7F
    cmp #0x02
    bne _wait_for_open_animation
    inc 0xDF
    lda 0xDF
    cmp #0x08
    bne animation_wait_route

; restore tileset position
    lda ppu.BG34NBA
    and #0xF0
    clc
    adc #0x02
    sta ppu.BG34NBA

    jmp.w end_of_animation
}
; do not scroll between text blocks
.alloc at 0x00B370 {
    lda #0x00
    sta 0x07
    jmp.w _text_cmd_08_b398
}
.alloc at 0x00B335 {
    jmp.w animation_wait_route

end_of_animation:
    jmp.w _text_cmd_07_b369  ; skip_wait_for_action_button
}
{
; Yes / No window


    .table "text/ff4_menus.tbl"
    .alloc at 0x14F656 {
    .dw 0x2016
    fill_value(0x2017, 5)
    .dw 0x2018
    .dw 0x0000
    }


    .alloc at 0x14F666 {
    .dw 0x2019
    fill_value(0x20ff, 5)
    .dw 0x201a
    .dw 0x0000
    }


    .alloc at 0x14f676 {
    .dw 0x2019
    .dw 0x2014
    yes_cells()
    .dw 0x20ff
    .dw 0x201a
    .dw 0x0000
    }


    .alloc at 0x14F686 {
    .dw 0x2019
    fill_value(0x20ff, 5)
    .dw 0x201a
    .dw 0x0000
    }


    .alloc at 0x14F696 {
    .dw 0x2019
    .dw 0x20ff
    no_cells()
    .dw 0x20ff
    .dw 0x201a
    .dw 0x0000
    }


    .alloc at 0x14F6A6 {
    .dw 0x201b
    fill_value(0x201c, 5)
    .dw 0x201d
    .dw 0x0000
    fill_value(0x0000, 8)
    }
}


; Yes / No cursor positions

.alloc at 0x00ae38 {
    ldx.w #0x28c4 - 1
}
.alloc at 0x00ae51 {
    ldx.w #0x2904 - 1
}
; Palette changes for allowing shadows
.alloc at 0x15c229 {
    lda.l window_palette, x
}
.alloc at 0x15c236 {
    jsr.l update_palette
    nop
    nop
}
; Update secondary palette window background
.alloc at 0x00823B {
    jsr.l update_palette
    nop
    nop
}
; update the text palette used in the intro
.alloc at 0x8ff04 {
    .dw 0x0463
}
.alloc at 0x00B363 {
    jsr.l wait_for_action_button
    nop
    nop

; Make gils window bigger
    gils_line_size = 0x18
}
.alloc at 0x00ad28 {
    lda.b #gils_window_tilemap_1 >> 16
}
.alloc at 0x00ad2d {
    ldx.w #gils_window_tilemap_1 & 0xffff
}
.alloc at 0x00ad4b {
    ldx.w #gils_window_tilemap_2 & 0xffff
}
.alloc at 0x00ad39 {
    ldx.w #gils_line_size
}
.alloc at 0x00ad63 {
    ldx.w #gils_window_tilemap_3
}
.alloc at 0x00ad69 {
    ldx.w #gils_line_size
}
.alloc at 0x00ad51 {
    ldx.w #gils_line_size
}
.alloc at 0x00ad7b {
    ldx.w #gils_window_tilemap_4 & 0xffff
}
.alloc at 0x00ad81 {
    ldx.w #( gils_window_tilemap_4_end - gils_window_tilemap_4 ) & 0xffff
}
; clear up longer gils window
.alloc at 0x00addd {
    ldx.w #0x100 + 0x80
}
; gils value vram position
.alloc at 0x00ad8a {
    ldx.w #0x28d3 + 2
}
