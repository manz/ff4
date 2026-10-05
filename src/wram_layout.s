"""
WRAM the battle and the menus take in turns: $7E:97A6-$7E:99FF.

Layout only: pinned reservations at the addresses the code uses. Each
screen is a context of one pool: reservations inside a context never
overlap, contexts overlay by design (no two of these screens run at the
same time). The rolling-list states at $7E:9C00+ sit past this window.
"""


.import "preamble"

MENU_HDMA_SPAN := 0x40  ; one table, then its shadow right after

.pool menu_ram {
    bss
    contexts battle, field_menu, treasure, key_item, sell, equip
    range 0x7E97A6 0x7E99FF
    strategy order
}

; Battle item list text ring: 6 slots x 60 bytes, in the spell-list buffer
; the direct magic renderer freed.
.reserve battle_item_text_ring 360 at 0x7E97A6 in menu_ram.battle

.reserve field_hdma_table MENU_HDMA_SPAN at 0x7E9800 in menu_ram.field_menu
.reserve field_hdma_shadow MENU_HDMA_SPAN at 0x7E9840 in menu_ram.field_menu

; The treasure popup: its inventory reuses the field list's tables, the
; drops panel sits right after.
.reserve treasure_hdma_table MENU_HDMA_SPAN at 0x7E9800 in menu_ram.treasure
.reserve treasure_hdma_shadow MENU_HDMA_SPAN at 0x7E9840 in menu_ram.treasure
.reserve drops_hdma_table MENU_HDMA_SPAN at 0x7E9880 in menu_ram.treasure
.reserve drops_hdma_shadow MENU_HDMA_SPAN at 0x7E98C0 in menu_ram.treasure

.reserve key_item_hdma_table MENU_HDMA_SPAN at 0x7E9900 in menu_ram.key_item
.reserve key_item_hdma_shadow MENU_HDMA_SPAN at 0x7E9940 in menu_ram.key_item

.reserve sell_hdma_table MENU_HDMA_SPAN at 0x7E9900 in menu_ram.sell
.reserve sell_hdma_shadow MENU_HDMA_SPAN at 0x7E9940 in menu_ram.sell

.reserve equip_hdma_table MENU_HDMA_SPAN at 0x7E9980 in menu_ram.equip
.reserve equip_hdma_shadow MENU_HDMA_SPAN at 0x7E99C0 in menu_ram.equip
