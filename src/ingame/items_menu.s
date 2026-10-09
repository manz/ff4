"""
Field-menu item names: DrawEquipItemName / DrawItemName go to the small VWF, and the colon/quantity column moves
past the longer French names.
Field / drops / treasure rolling inventory all defer to vanilla
DrawItemSlot at $01:9000, so patching here switches them in one
go.
"""
.import "items"

.import "ingame/inventory_rolling_trampolines"
.import "assets"
.import "ingame/items_menu_vwf"
.import "bank20_helpers"


; ===== DRAWITEMNAME JSL HOOKS =====
; Both vanilla entry points relocate to the bank-$20 VWF item name; the vanilla body they shared ($01:9019-$905F,
; the 9-byte-record walk) is never reached.

; DrawEquipItemName ($01:9013): only the equip screen calls it, with Y
; on the character record and X on the tilemap, unlike the item lists.
; Its own wrapper maps that onto the VWF helper. The vanilla entry is 6
; bytes ($9013-$9018), so the JSL + RTS fits.
.alloc at 0x019013 {
    jsr.l items_menu_vwf.draw_equip_item_name
    rts

; DrawItemName ($01:9060): vanilla `phy ; phy ; bra _9017` -> caller already
; passed A = item_id. Use the bank-01 jsr.w trampoline (3 bytes) + rts
; (1 byte) so the FIVE-byte JSL.L + RTS no longer spills into the
; sprite-render sub-routine at $01:9064 (the save-screen sprite path
; jsr's $9064 directly).
}
.alloc at 0x019060 {
    jsr.w draw_field_item_name_trampoline
    rts

; ===== COLON/QUANTITY POSITION PATCHES =====
; Item names expanded from 9 to 16 bytes (+7 chars = +14 VRAM bytes)
; Change offset from $0052 to $0060

; --- DrawItemSlot: left column colon/qty position ---
; Original: 01/A1FC: 69 52 00  ADC #$0052
}
.alloc at 0x01A1FC {
    adc #0x0060

; --- DrawItemSlot: right column colon/qty position ---
; Original: 01/A236: 69 52 00  ADC #$0052
}
.alloc at 0x01A236 {
    adc #0x0060
}
