"""
Small (8x8) VWF init routine: prepares the menu tile buffer, runs the renderer init and wires up the long-form
RTL entry points for cross-bank callers.
"""
.include "config.i"
.include "src/vwf.i"
.include "../bank20.i"
.include "src/libmz.i"

.import "assets"
.import "libmz"

; root-scope externs: `.alloc` bodies open their own scope, so an extern
; declared inside never resolves at the use site.
.if BATTLE_ENABLED {
    .extern battle_render
    .extern battle_render.clear_buffer
}

.alloc small_vwf_init_block in bank20_reloc {
    .include "src/small_vwf/render.s"
    .include "src/small_vwf/item_description.s"
}
