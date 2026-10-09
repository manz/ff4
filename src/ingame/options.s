"""Options-menu patches: rename palette colours (RGB → RVB), reposition labels and adjust slider offsets."""
.import "preamble"
.import "menus/in_game_text"
.import "menus/system_menus_text"
.include "config.i"
.include "src/ingame/macros.i"
.include "src/menus/system_menus_macros.i"


;RGB -> RVB :o)

.alloc at 0x01D1BB {
    lda.b #0x57

; déplacement du curseur principal des options
}
.alloc at 0x01D247 {
    lda.b #0x00

; Cursor offset in controls menu (x)
}
.alloc at 0x01D4E6 {
    lda.b #0x03

; cursor y
}
.alloc at 0x01D4E2 {
    adc.b #0x4C
}
.alloc at 0x01D1B0 {
    load_system_menu_text_pointer(options.title)
}
.alloc at 0x01D1A4 {
    load_system_menu_text_pointer(options.config)

; move controls title window
}
.alloc at 0x01E204 {
; fits "Contrôles personnalisés" (101 px in the small VWF), centred
    menu_window(8, 0, 14, 2)
}
.alloc at 0x01D487 {
    ldy.w #0xE204

; controles
}
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
