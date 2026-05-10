"""SRAM / WRAM layout map for the patched ROM and per-mode VWF scopes."""

; Original ROM call sites referenced by rolling-buffer / treasure-menu patches.
; Captured here as `.label` declarations so symbol exports land in `ff4.sym`
; (xdds + tracer can pretty-print them) and so search/replace stays mechanical.

"""DrawItemName: glyph + attr render via ($1d) + ($29)."""
.label draw_item_name = 0x019060

"""_9017: shared body for DrawItemName / DrawEquipItemName."""
.label draw_item_name_inner = 0x019017

"""DrawItemSlot entry (adds +$40 then falls through)."""
.label draw_item_slot = 0x01A1DE

"""DrawItemSlot inner (skips the +$40 row offset)."""
.label draw_item_slot_inner = 0x01A1ED

"""DrawTreasureList: drops list draw (8 items at $FF28)."""
.label draw_treasure_list = 0x01A15C

"""DrawInventoryList: 48-item bottom list draw."""
.label draw_inventory_list = 0x01A172

"""SelectBG1: $29=$B600 / $35=$6000 (drops staging + VRAM)."""
.label select_bg1 = 0x0184A2

"""SelectClearBG1: ClearBG1Tiles + SelectBG1."""
.label select_clear_bg1 = 0x01849F

"""SelectBG2: $29=$A600 / $35=$6800."""
.label select_bg2 = 0x0184BA

"""SelectBG3: $29=$D600 / $35=$7000 (inventory staging + VRAM)."""
.label select_bg3 = 0x018470

"""SelectBG4: $29=$C600 / $35=$7800."""
.label select_bg4 = 0x018488

"""TfrBG1TilesVblank: $7E:B600 -> VRAM $6000."""
.label tfr_bg1_tiles_vblank = 0x01942D

"""TfrBG2TilesVblank: $7E:A600 -> VRAM $6800."""
.label tfr_bg2_tiles_vblank = 0x019420

"""TfrBG3TilesVblank: $7E:D600 -> VRAM $7000."""
.label tfr_bg3_tiles_vblank = 0x019447


.scope field_vwf {
    """
    S-RAM layout
    0x700000 - 0x701fff: Save data
    0x702000 - 0x702fff: Tile buffer for dialog text renderer
    0x703000 - 0x7032FF: Tile buffer used in battle text renderer and menu text renderer
    0x705000 - 0x706300: Vram saved before entering menus.
    0x707000 - 0x709cff: Battle magic buffers
    0x710000 - 0x710100: Vars buffer
    0x710100 - 0x710107: BRK trap capture (P, PC.lo, PC.hi, PB)
    """
    tile_buffer = 0x702000
}

.scope _battle_vwf {
    tile_buffer = 0x702000
    battle_tile_buffer = 0x703000
}

.scope _menu_vwf {
    tile_buffer = 0x703000
}
