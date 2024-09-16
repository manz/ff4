*=0x01bd0f
    load_system_menu_text_pointer(equip.menu)

; Moves Character name one line up to avoid colision with dextrality text.
*=0x01bd54
    ldy.w #0x01c6 - 0x40 - 2

_item_delta = 8

*=0x01bd7b
    ldx.w #0x0164 + _item_delta

*=0x01bd82
    ldx.w #0x01e4 + _item_delta

*=0x01bd89
    ldx.w #0x0264 + _item_delta

*=0x01bd92
    ldx.w #0x0064 + _item_delta

*=0x01bda8
    ldx.w #0x00e4 + _item_delta


*=0x1bd5c
    jsr.l load_dextrelity_pointer
    destrelity_return = 0x1bd73
    ldx.w #0x244
    jmp.w destrelity_return

*=0x01e2d9
    .dw (dextrality.string_0 & 0xFFFF) - 0x8000
    .dw (dextrality.string_1 & 0xFFFF) - 0x8000
    .dw (dextrality.string_2 & 0xFFFF) - 0x8000
    .dw (dextrality.string_3 & 0xFFFF) - 0x8000

