.include "src/vwf.i"
.include "src/libmz.i"

.extern wait_for_vblank
.extern wait_for_vblank_long
.extern dma_transfer_to_vram
.extern assets_menu_font_dat
.extern font_table
.if BATTLE_ENABLED {
    .extern battle_render
    .extern battle_render.clear_buffer
}

.include "src/small_vwf/render.s"
.include "src/small_vwf/item_description.s"
