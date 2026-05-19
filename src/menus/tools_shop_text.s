"""French translated text data for the tools/weapon/armor shop UI."""
.include "src/ingame/macros.i"

.table "text/ff4_menus.tbl"
.scope shops {
    """Shop UI strings."""
gils:
    move_to(27, 6)
    .text "Gils"
    .db 0
puis_je_vous_aider:
"""Owner welcome greeting  ; rendered through the small-VWF description region."""
    .dw 0x0054 - 2
    .text "Puis-je vous aider ?"
;.text 'いらっしゃい! どんなごようけんで?'
    .db 0
welcome_and_actions:
    .dw 0x0148 - 4
    .text "Achat Vente Sortir"
    .db 0
que_desirez_vous:
"""Owner welcome prompt  ; rendered through the small-VWF description region."""
    .dw 0x0052
    .text "Que désirez vous ?  "
    .db 0
quantity:
""".text 'かう   うる   でる'"""
    .dw 0x0144
    .text "Quantité"
    .db 1
    .dw 0x0146 + 14 * 2
    .text "1"
    .db 0
thank_you_window:
    menu_window(5, 10, 11, 2)
; Trailing empty-text block keeps the vanilla `$82FB` (draw window + text)
; happy when called via shop_thanks_text_hook ; the actual "Merci !" copy
; is rendered separately through the small-VWF description region.
    .dw 0x0000
    .db 0
merci:
"""Owner thank-you message  ; rendered through the small-VWF description region."""
    move_to(6, 11)
    .text "Merci !"
    .db 0
inventory_full:
    menu_window(1, 10, 20, 4)
    move_to(2, 11)
    .text "L\'inventaire est"
    .db 1
    move_to(2, 13)
    .text "plein."
    .db 0
not_enough_gils:
    menu_window(5, 10, 16, 4)
    move_to(6, 11)
    .text "Vous n\'avez pas"
    .db 1
    move_to(6, 13)
    .text "de Gils."
    .db 0
sell_window:
    menu_window(8, 10, 14, 13)
    move_to(13, 13)
    .text " Unités"
    .db 1
    move_to(19, 15)
    .text "Gils"
    .db 1
    move_to(10, 17)
    .text "Êtes-vous"
    .db 1
    move_to(11, 19)
    .text "d\'accord ?"
    .db 1
    move_to(12, 21)
    .text "Oui Non"
    .db 0
weapons_title:
    .text "Armes"
    .db 0
armor_title:
    .text "Armures"
    .db 0
items_title:
    .text "Objets"
    .db 0
}
