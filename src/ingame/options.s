"""Options-menu patches: RGB -> RVB, label and cursor positions, controls window, and the ATB gauge row."""
.import "core/preamble"
.import "menus/in_game_text"
.import "menus/system_menus_text"
.include "ingame/macros.i"
.include "menus/system_menus_macros.i"
.include "core/bank20.i"
.include "ingame/bank01_slack.i"


; Controls menu cursor x, then y
.alloc at 0x01D4E6 {
    lda.b #0x03
}
.alloc at 0x01D4E2 {
    adc.b #0x4C
}
.alloc at 0x01D1B0 {
    load_system_menu_text_pointer(options.title)
}
.alloc at 0x01D1A4 {
    load_system_menu_text_pointer(options.config)
}
; Controls title window
.alloc at 0x01E204 {
; fits "Contrôles personnalisés" (101 px in the small VWF), centred
    menu_window(8, 0, 14, 2)
}
.alloc at 0x01D487 {
    ldy.w #0xE204
}
; Controls text
.alloc at 0x01D48D {
    load_system_menu_text_pointer(options.controls)
}

; The button lists of the controls window, vanilla's untranslated BtnList1Text / BtnList2Text.
.alloc at 0x01D496 {
    load_system_menu_text_pointer(options.button_actions)
}
.alloc at 0x01D49F {
    load_system_menu_text_pointer(options.button_actions)
}
.alloc at 0x01D4A5 {
    load_system_menu_text_pointer(options.pad_buttons)
}
.alloc at 0x01D4AE {
    load_system_menu_text_pointer(options.pad_buttons)
}
.alloc at 0x01D4B7 {
    load_system_menu_text_pointer(options.pad_buttons)
}

.alloc at 0x01D659 {
; multi-controller title window
    load_system_menu_text_pointer(options.pad_select_title_window)
}
.alloc at 0x01D65F {
; multi-controller window and title
    load_system_menu_text_pointer(options.pad_select)
}
.alloc at 0x01D685 {
; the label after each name
    load_system_menu_text_pointer(options.pad)
}

; Row 10: "Jauge ATB  Oui  Non" (read by battle/atb_gauge.s), under the colour sliders (rows 7-9).
; Setting: $16B3 bit 0, a saved byte vanilla leaves 0, so the gauge defaults to off.
ATB_GAUGE_SETTING := 0x7E16B3
ATB_GAUGE_ON := 0x01
_ROWS := 11
_GAUGE_ROW := 10
_SLIDER_FIRST := 7
_LIST_CURSOR_X := 0x00  ; the labels' cursor column (vanilla's $18, moved for the VWF labels)
_SLIDER_CURSOR_X := 0x68
_TOGGLE_LEFT_X := 0x68  ; vanilla's toggle cursor columns ($01:D61D): first and second choice
_TOGGLE_RIGHT_X := 0xA0
_GAUGE_ROW_Y := 0x30 + _GAUGE_ROW * 16
_GAUGE_CURSOR := 0x00032C  ; a sprite vanilla's options screen leaves free (after the sliders')
_TOGGLE_TILE := 0x300A  ; vanilla's toggle cursor: tile $0A, attributes $30
_GAUGE_CURSOR_HIGH := 0x000502  ; its OAM high-table byte (sprites 8-11, two bits each)
_GAUGE_CURSOR_X8 := 0x40  ; sprite 11: x bit 8
_GAUGE_CURSOR_LARGE := 0x80  ; sprite 11: 16x16

.alloc at 0x01D319 {
    .db _ROWS - 1  ; UP from the first row: the last
}
.alloc at 0x01D328 {
    .db _ROWS  ; DOWN past the last row: the first
}

.alloc at 0x01D23F size 10 {
; the row's cursor column: the sliders' or the labels'
    jsr.l options_atb.cursor_x
    bra _cursor_x_set
    .for pad := 0, 4 {
    nop
    }
}
.label _cursor_x_set = 0x01D249

.alloc at 0x01D376 size 7 {
; LEFT on rows 7-10: a slider, or the gauge's toggle
    jsr.l options_atb.slider_or_gauge
    bcs _left_done
    nop
}
.label _left_done = 0x01D396

.alloc at 0x01D3E1 size 7 {
; RIGHT on rows 7-10
    jsr.l options_atb.slider_or_gauge
    bcs _right_done
    nop
}
.label _right_done = 0x01D403

.alloc at 0x01D2C3 size 6 {
; the toggle cursors' attributes, and the gauge row's cursor
    jsr.l options_atb.toggle_cursors
    nop
    nop
}

.label _tfr_bg1_screen = 0x019430  ; vanilla: transfer the bg1 screen buffer to VRAM

.alloc _options_gauge_row in bank01_slack {
options_gauge_row:
"""The options screen's setup, its last step: the ATB gauge row's text (its own block), then vanilla's transfer."""
    load_system_menu_text_pointer(options_gauge.row)
    jsr.w draw_pos_text
    jmp.w _tfr_bg1_screen
}

.alloc at 0x01D1EC {
    jsr.w options_gauge_row
}

.alloc _options_atb in bank20_reloc {
    .scope options_atb {
cursor_x:
"""
A8 = the row ($1BA7): the cursor's x, the sliders' column on rows 7-9 (vanilla's test was row >= 7). Callable with
JSL.
"""
    cmp.b #_SLIDER_FIRST
    bcc _labels
    cmp.b #_GAUGE_ROW
    bcs _labels
    lda.b #_SLIDER_CURSOR_X
    rtl
_labels:
    lda.b #_LIST_CURSOR_X
    rtl

slider_or_gauge:
"""
In vanilla's LEFT/RIGHT on rows 7 and up, A8 = row - 6: carry set once the gauge row toggled its setting (the caller
goes on to the next button), else vanilla's slider index (X16 = (row - 7) * 2, A16) and carry clear. Callable with JSL.
"""
    dec
    cmp.b #_GAUGE_ROW - _SLIDER_FIRST
    beq _gauge
    asl
    rep #0x20
    and.w #0x00FF
    tax
    clc
    rtl
_gauge:
    lda.l ATB_GAUGE_SETTING
    eor.b #ATB_GAUGE_ON
    sta.l ATB_GAUGE_SETTING
    sec
    rtl

toggle_cursors:
"""
Vanilla's `ldx #$300A / stx $0306`, then the gauge row's toggle cursor: on "Oui" (left) or "Non". Keeps X. Callable
with JSL.
"""
    ldx.w #_TOGGLE_TILE
    stx.w 0x0306
    lda.l ATB_GAUGE_SETTING
    and.b #ATB_GAUGE_ON
    beq _off
    lda.b #_TOGGLE_LEFT_X
    bra _x
_off:
    lda.b #_TOGGLE_RIGHT_X
_x:
    sta.l _GAUGE_CURSOR
    lda.b #_GAUGE_ROW_Y
    sta.l _GAUGE_CURSOR + 1
    rep #0x20
    lda.w #_TOGGLE_TILE
    sta.l _GAUGE_CURSOR + 2
    sep #0x20
    lda.l _GAUGE_CURSOR_HIGH  ; the hand is 16x16: the sprite's size bit, its x bit 8 clear
    and.b #( ~_GAUGE_CURSOR_X8 ) & 0xFF
    ora.b #_GAUGE_CURSOR_LARGE
    sta.l _GAUGE_CURSOR_HIGH
    rtl
    }
}
