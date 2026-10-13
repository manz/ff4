"""
Field-menu item names: DrawEquipItemName / DrawItemName go to the small VWF, and the colon/quantity column moves
past the longer French names. Every rolling list draws through vanilla DrawItemSlot, so this covers them all.
"""
.import "core/items"

.import "ingame/inventory_rolling_trampolines"
.import "core/assets"
.import "ingame/items_menu_vwf"
.import "core/bank20_helpers"


; Both entries go to the bank-$20 VWF; the shared vanilla body ($01:9019-$905F) is never reached.

; DrawEquipItemName ($01:9013): 6 bytes, room for JSL + RTS.
.alloc at 0x019013 {
    jsr.l items_menu_vwf.draw_equip_item_name
    rts
}
; DrawItemName ($01:9060): only 4 bytes. A JSL + RTS would spill into $01:9064, which the save screen calls.
.alloc at 0x019060 {
    jsr.w draw_field_item_name_trampoline
    rts
}
; DrawItemSlot colon/quantity offset, left then right column: $52 -> $60 for 16-byte names.
.alloc at 0x01A1FC {
    adc #0x0060
}
.alloc at 0x01A236 {
    adc #0x0060
}
