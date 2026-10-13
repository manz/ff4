"""
Equip-menu patches: header text, character name one row up (clear of the dextrality text), equipped-name columns.
"""
.import "core/preamble"
.import "menus/in_game_text"
.import "menus/system_menus_text"
.include "menus/system_menus_macros.i"


.alloc at 0x01bd0f {
    load_system_menu_text_pointer(equip.menu)
}
; Character name one row up, clear of the dextrality text.
.alloc at 0x01bd54 {
    ldy.w #0x01c6 - 0x40 - 2

; Equipped names two cells right of vanilla (col 20), after the 6-cell slot labels at col 14; the widest name ends
; at col 30.
    item_delta = 4
}
.alloc at 0x01bd7b {
    ldx.w #0x0164 + item_delta
}
.alloc at 0x01bd82 {
    ldx.w #0x01e4 + item_delta
}
.alloc at 0x01bd89 {
    ldx.w #0x0264 + item_delta
}
.alloc at 0x01bd92 {
    ldx.w #0x0064 + item_delta
}
.alloc at 0x01bda8 {
    ldx.w #0x00e4 + item_delta
}
.alloc at 0x1bd5c {
    jsr.l load_dextrelity_pointer
    _destrelity_return = 0x1bd73
    ldx.w #0x244
    jmp.w _destrelity_return
}
.alloc at 0x01e2d9 {
    .dw ( dextrality.string_0 & 0xFFFF ) - 0x8000
    .dw ( dextrality.string_1 & 0xFFFF ) - 0x8000
    .dw ( dextrality.string_2 & 0xFFFF ) - 0x8000
    .dw ( dextrality.string_3 & 0xFFFF ) - 0x8000
}

.alloc at 0x01BF81 {
; the two-handed weapon notice
    load_system_menu_text_pointer(equip.two_hands)
}
