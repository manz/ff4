"""
Shop-screen patches: window layout, text pointers, small-VWF owner messages, list and cursor positions.
"""
.import "core/preamble"
.import "ingame/inventory_rolling_trampolines"
.import "menus/tools_shop_text"
.import "core/assets"
.import "menus/in_game_text"
.import "menus/system_menus_text"
.include "menus/system_menus_macros.i"

.include "ingame/macros.i"
.import "core/vanilla"

; Gil window
.alloc at 0x1dea6 {
    menu_window(23, 4, 7, 3)
}
; Party window, one tile lower
.alloc at 0x1deba {
    menu_window(23, 9, 7, 11)
}
; Message window
.alloc at 0x01deb2 {
    menu_window(8, 0, 20, 2)
}
; Shop title
.alloc at 0x01deae {
    menu_window(0, 0, 8, 2)
}
; Actions window
.alloc at 0x01deaa {
    menu_window(1, 4, 20, 3)
}
; List window
.alloc at 0x01deb6 {
    menu_window(0, 8, 22, 17)
}
; Gil amount (7 digits) 2 tiles right
.alloc at 0x1c3f5 {
    ldy.w #0x01a6 + 8
}
; ギル label
.alloc at 0x01C3EC {
    load_system_menu_text_pointer(shops.gils)
}
.alloc at 0x01C350 {
    load_system_menu_text_pointer(shops.welcome_and_actions)
}
; The owner greeting goes through the small-VWF description; welcome_and_actions holds only the action labels.
.alloc at 0x01C353 {
    jmp.w shop_welcome_text_hook
}
.alloc at 0x01C43F {
    load_system_menu_text_pointer(shops.quantity)
}
; The buy prompt goes through the small-VWF description; the hook still draws the quantity block via $8301.
.alloc at 0x01C442 {
    jsr.w shop_quantity_text_hook
}
.alloc at 0x01c7e4 {
    load_system_menu_text_pointer(shops.quantity)
}
.alloc at 0x01C7E7 {
    jsr.w shop_quantity_text_hook
}
.alloc at 0x01C568 {
    load_system_menu_text_pointer(shops.gils_suffix)
}
.alloc at 0x01c74e {
    load_system_menu_text_pointer(shops.thank_you_window)
}
; The thank-you goes through the small-VWF description; the hook still draws the window via $82FB.
.alloc at 0x01C751 {
    jsr.w shop_thanks_text_hook
}
.alloc at 0x01c962 {
    load_system_menu_text_pointer(shops.sell_window)
}
.alloc at 0x01c41e {
    load_system_menu_text_pointer(shops.inventory_full)
}
.alloc at 0x01c700 {
    load_system_menu_text_pointer(shops.not_enough_gils)
}
; Quantity cursor on "10" and on "1": buy menu, then sell menu
.alloc at 0x01cb12 {
    ldx #0x3058 + 48
}
.alloc at 0x01cb17 {
    ldx.w #0x3040 + 54
}
.alloc at 0x01c80b {
    ldx.w #0x3058 + 48
}
.alloc at 0x01c810 {
    ldx.w #0x3040 + 54
}
{
; The "10" is a drawn number (it steps by 10), the "1" is text.
    _quantity_10_position = 0x019a + 12

; Sell menu, then buy menu
    .alloc at 0x01c81e {
        ldy.w #_quantity_10_position
    }


    .alloc at 0x01c464 {
        ldy.w #_quantity_10_position
    }
}


; Buy-list cursor X: 16 -> 8 px, following the names one column left.
.alloc at 0x01C5C0 {
    lda #0x08
}

; Buy-list name positions, one column left of vanilla's (column 3) to leave room for the price.
.alloc at 0x01C58E {
    .dw 0x0244, 0x02C4, 0x0344, 0x03C4, 0x0444, 0x04C4, 0x0544, 0x05C4
}

; ConfirmSell's count: right-aligned with the price, on column 16 (vanilla column 12)
.alloc at 0x01C9D7 {
    ldy.w #15 * 2 + 14 * 64
}

; ConfirmSell's price: DrawNum7 fills the 7 columns after Y, so it ends on column 16 too (vanilla 17)
.alloc at 0x01C9F3 {
    ldy.w #9 * 2 + 16 * 64
}

; ConfirmSell's cursor: Oui / Non on row 20 (vanilla 22), the window two rows shorter; Oui at column 11, Non at 16
.alloc at 0x01CA1A {
    .db 20 * 8
}

.alloc at 0x01CA22 {
    .db 9 * 8
}

.alloc at 0x01CA26 {
    .db 14 * 8
}

; ConfirmSell's item name: `jsr DrawItemName` with the item id in $5D
.alloc at 0x01CA02 {
    jsr.w shop_sell_item_name
}

; Buy-list names: the hijacked DrawItemName needs a slot index in $5D, where the loop leaves the item id.
.alloc at 0x01C580 {
    jsr.w shop_draw_item_name
}

; Hand cursor offset

.alloc at 0x01C37C {
    lda.w menu_cursor_data + 0x79
    asl
    asl
    asl
    asl
    sta 0x45
    asl
    adc 0x45
    nop
    nop
    sta 0x45
}
.alloc at 0x01920a {
; Party sprite positions. Attack formation: 3 front, 2 back
    .db 0x00 + 8, 0x1c + 8
    .db 0x00 + 8, 0x00 + 8
    .db 0x00 + 8, 0x38 + 8
    .db 0x18 + 8, 0x0c + 8
    .db 0x18 + 8, 0x2c + 8

; Defense formation: 3 back, 2 front
    .db 0x18 + 8, 0x1c + 8
    .db 0x18 + 8, 0x00 + 8
    .db 0x18 + 8, 0x38 + 8
    .db 0x00 + 8, 0x0c + 8
    .db 0x00 + 8, 0x2c + 8
}
.alloc at 0x01debe {
shop_title_ptr:
    .dw shops.weapons_title - 0x8000
    .dw shops.armor_title - 0x8000
    .dw shops.items_title - 0x8000
}
.alloc at 0x01c336 {
    lda.b #0
    xba
    lda.w shop_type
    asl
    tax
    rep #0x20
    lda.l shop_title_ptr, x
    tay
    sep #0x20
    nop
    nop
    nop
    ldx.w #0x0042
}
