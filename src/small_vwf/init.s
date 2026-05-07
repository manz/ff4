"""
Small (8x8) VWF init routine: prepares the menu tile buffer, runs the renderer init and wires up the long-form
RTL entry points for cross-bank callers.
"""
.include "src/vwf.i"
.include "src/libmz.i"

.import "assets"
.import "libmz"
.if BATTLE_ENABLED {
    .extern battle_render
    .extern battle_render.clear_buffer
}

.include "src/small_vwf/render.s"
.include "src/small_vwf/item_description.s"
