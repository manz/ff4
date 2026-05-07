"""
Shop-screen patches: move the gil window, adjust title positions, hook into the relocated shop text +
small-VWF item descriptions.
"""
.include "src/ingame/macros.i"

; move gils window

*=0x1dea6
    menu_window(23, 4, 7, 3)

; move character 1 tile below

*=0x1deba
    menu_window(23, 9, 7, 11)

; message window

*=0x01deb2
    menu_window(8, 0, 20, 2)

; shop title

*=0x01deae
    menu_window(0, 0, 8, 2)

; actions window

*=0x01deaa
    menu_window(1, 4, 20, 3)

; list window

*=0x01deb6
    menu_window(1, 8, 21, 17)


; Moves gils 7 digits 2 tiles to the right.

*=0x1c3f5
    ldy.w #0x01a6 + 8

; ギル : gils

*=0x01C3EC
    load_system_menu_text_pointer(shops.gils)

*=0x01C350
    load_system_menu_text_pointer(shops.welcome_and_actions)

*=0x01C43F
    load_system_menu_text_pointer(shops.quantity)

*=0x01c7e4
    load_system_menu_text_pointer(shops.quantity)

*=0x01C568
    load_system_menu_text_pointer(shops.gils + 2)

*=0x01c74e
    load_system_menu_text_pointer(shops.thank_you_window)

*=0x01c962
    load_system_menu_text_pointer(shops.sell_window)

*=0x01c41e
    load_system_menu_text_pointer(shops.inventory_full)

*=0x01c700
    load_system_menu_text_pointer(shops.not_enough_gils)


; Buy menu
; quantity hand pointer position "10"

*=0x01cb12
    ldx #0x3058 + 48

; quantity hand pointer position "1"

*=0x01cb17
    ldx.w #0x3040 + 54

; Sell menu

*=0x01c80b
    ldx.w #0x3058 + 48

*=0x01c810
    ldx.w #0x3040 + 54

{
; the 10 is drawn using a draw number function while the 1 is in the text.
; the 10 is dynamic if you place the cursor on 10 and press X it'll increase the number (10 increments)

    _quantity_10_position = 0x019a + 12

; Sell menu
    *=0x01c81e
    ldy.w #_quantity_10_position

; Buy menu
    *=0x01c464
    ldy.w #_quantity_10_position
}


; Changes the offset of the hand pointer

*=0x01C37C
    lda 0x1B79
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

*=0x01920a
    ; shop party sprite positions
    ; Attack formation 3 front, 2 back
    .db 0x00 + 8, 0x1c + 8
    .db 0x00 + 8, 0x00 + 8
    .db 0x00 + 8, 0x38 + 8
    .db 0x18 + 8, 0x0c + 8
    .db 0x18 + 8, 0x2c + 8

; Defense formation 3 back, 2 front
    .db 0x18 + 8, 0x1c + 8
    .db 0x18 + 8, 0x00 + 8
    .db 0x18 + 8, 0x38 + 8
    .db 0x00 + 8, 0x0c + 8
    .db 0x00 + 8, 0x2c + 8

*=0x01debe
_shop_title_ptr:
    .dw shops.weapons_title - 0x8000
    .dw shops.armor_title - 0x8000
    .dw shops.items_title - 0x8000

*=0x01c336
    lda.b #0
    xba
    lda 0x1a01
    asl
    tax
    rep #0x20
    lda.l _shop_title_ptr, x
    tay
    sep #0x20
    nop
    nop
    nop
    ldx.w #0x0042
