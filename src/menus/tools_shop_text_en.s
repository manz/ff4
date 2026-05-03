.include "src/ingame/macros.i"

.scope shops {
gils:
    move_to(27, 6)
    .text "GP"
    .db 0
welcome_and_actions:
    .dw 0x0054 - 2
    .text "Welcome!"
;.text 'いらっしゃい! どんなごようけんで?'
    .db 1
    .dw 0x0148 - 4
    .text "Buy Sell Exit"
    .db 0
quantity:
    """.text 'かう   うる   でる'"""
    .dw 0x0052
    .text "What do you want?   "
    .db 1
    .dw 0x0144
    .text "Quantity"
    .db 1
    .dw 0x0146 + 14 * 2
    .text "1"
    .db 0
thank_you_window:
    menu_window(5, 10, 11, 2)
thank_you_text:
    move_to(6, 11)
    .text "Thank you!"
    .db 0
inventory_full:
    menu_window(1, 10, 20, 4)
    move_to(2, 11)
    .text "The inventory is"
    .db 1
    move_to(2, 13)
    .text "full."
    .db 0
not_enough_gils:
    menu_window(5, 10, 16, 4)
    move_to(6, 11)
    .text "You don\'t have"
    .db 1
    move_to(6, 13)
    .text "enough GP."
    .db 0
sell_window:
    menu_window(8, 10, 14, 13)
    move_to(13, 13)
    .text " Units"
    .db 1
    move_to(19, 15)
    .text "GP"
    .db 1
    move_to(10, 17)
    .text "Is this"
    .db 1
    move_to(11, 19)
    .text "all right?"
    .db 1
    move_to(12, 21)
    .text "Yes No"
    .db 0
weapons_title:
    .text "Weapons"
    .db 0
armor_title:
    .text "Armor"
    .db 0
items_title:
    .text "Items"
    .db 0
}
