; S-RAM layout
; 0x700000 - 0x701fff: Save data
; 0x702000 - 0x702fff: Tile buffer for dialog text renderer
; 0x703000 - 0x7032FF: Tile buffer used in battle text renderer and menu text renderer
; 0x705000 - 0x706300: Vram saved before entering menus.
; 0x707000 - 0x709cff: Battle magic buffers
; 0x710000 - 0x710100: Vars buffer
.scope field_vwf {
    tile_buffer = 0x702000
}

.scope battle_vwf {
    tile_buffer = 0x702000
    battle_tile_buffer = 0x703000
}

.scope menu_vwf {
    tile_buffer = 0x703000
}
