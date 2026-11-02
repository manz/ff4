"""
Equip-menu patches: header text, character name one row up (clear of the dextrality text), arrow count columns.
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

; The window's content one column left of vanilla: stats from col 7, the cursor hand, slot labels from col 13
; (src/lang/*/menus/in_game_text.s), names from col 17. Arrow counts at cols 28-29 (vanilla 27-28): a name's
; 11 cells end at col 27, and the widest arrow (76 px) fits before the count.
content_shift = 2  ; one column, in tilemap bytes
.alloc at 0x01BD27 {
    ldy.w #0x0090 - content_shift
}
.alloc at 0x01BD32 {
    ldy.w #0x0110 - content_shift
}
.alloc at 0x01BD3D {
    ldy.w #0x0190 - content_shift
}
.alloc at 0x01BD45 {
    sta.w 0xA690 - content_shift
}
.alloc at 0x01BD4A {
    sta.w 0xA710 - content_shift
}
.alloc at 0x01BD4F {
    sta.w 0xA790 - content_shift
}
.alloc at 0x01BE1F {
    .db 0x60 - 8  ; slot cursor X
}
.alloc at 0x01bd7b {
    ldx.w #0x0164 - content_shift
}
.alloc at 0x01bd82 {
    ldx.w #0x01e4 - content_shift
}
.alloc at 0x01bd89 {
    ldx.w #0x0264 - content_shift
}
.alloc at 0x01bd92 {
    ldx.w #0x0064 - content_shift
}
.alloc at 0x01bda8 {
    ldx.w #0x00e4 - content_shift
}
.alloc at 0x01BDA1 {
    .dw 0x00B8
}
.alloc at 0x01BDB6 {
    .dw 0x0138
}
