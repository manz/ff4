"""English text data for the tools/weapon/armor shop UI."""
.include "ingame/macros.i"
.include "core/bank20.i"

.table "ff4_menus_small_vwf.tbl"  ; build.py: ff4_menus.tbl, accented capitals folded

.alloc tools_shop_text in bank20_reloc {
    .scope shops {
    """Shop UI strings."""
gils:
        move_to(29, 6)
        .text "Gil"
        .db 0
gils_suffix:
; after each price in the buy list ($01:C568): its own bytes, so its small-VWF tiles don't overlap the gil window's
        .text "Gil"
        .db 0
puis_je_vous_aider:
"""Owner greeting, drawn in the small-VWF description region."""
        .dw 0x0054 - 2
        .text "May I help you?"
        .db 0
welcome_and_actions:
        .dw 0x0148 - 4
; one cursor stop every 6 columns ($01:C37C), as vanilla's かう   うる   でる
        .text "Buy"
        col(6)
        .text "Sell"
        col(12)
        .text "Exit"
        .db 0
que_desirez_vous:
"""Owner prompt, drawn in the small-VWF description region."""
        .dw 0x0052
        .text "What would you like?"
        .db 0
quantity:
        .dw 0x0144
        .text "Quantity"
        .db 1
        .dw 0x0146 + 14 * 2
        .text "1"
        .db 0
thank_you_window:
        menu_window(5, 10, 11, 2)
; Empty text for vanilla's $82FB (window + text) via shop_thanks_text_hook; "Merci !" is drawn by the small VWF.
        .dw 0x0000
        .db 0
merci:
"""Owner thank-you, drawn in the small-VWF description region."""
        move_to(6, 11)
        .text "Thank you!"
        .db 0
inventory_full:
        menu_window(1, 10, 20, 4)
        move_to(2, 11)
        .text "Your inventory is"
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
        .text "enough Gil."
        .db 0
sell_window:
; name (DrawItemName $02D4) row 12; count (DrawNum2, $01:C9D7) and price (DrawNum7, $01:C9F3) right-aligned on column 16
; of rows 14 and 16, their units in one column after them. Text draws on the row under its position.
        menu_window(8, 10, 14, 11)
        move_to(17, 13)
        .text " Units"
        .db 1
        move_to(17, 15)
        .text " Gil"
        .db 1
        move_to(9, 17)
        .text "Is that all right?"
        .db 1
; the cursor ($01:CA19) stops two columns left of each answer, on row 20
        move_to(11, 19)
        .text "Yes"
        col(5)
        .text "No"
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
}
