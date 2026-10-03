"""
Shared battle_render WRAM-layout + bit constants.

Compile-time definitions consumed by more than one module (message.s owns the
renderer  ; redraw_gates.s and the writer-site shims read the same dirty-bit and
tilemap-pending interface). Included inside `.scope battle_render { ... }` so
every consumer sees them as `battle_render.<name>`. Constants don't link, so
sharing them via `.include` (not `.extern`) is the correct, link-free idiom.
"""


; --- Per-region dirty bits (normal sense: 1 = dirty, 0 = clean) ---
; Sits next to the DMA queue byte; writers SET bits on state change.
; Lives at BATTLE_RENDER_STATE (see vwf_state.i) -- NOT in the CHR buffer,
; which the inventory slot slices overwrite.
region_dirty_bits = BATTLE_RENDER_STATE + 0x01
REGION_DIRTY_MESSAGES = 0x01
REGION_DIRTY_MONSTERS = 0x02
REGION_DIRTY_NAMES = 0x04
REGION_DIRTY_COMMANDS = 0x08

; Transient marker: $FF if `init_*_with_gate` short-circuited because the
; region was clean; $00 if it ran the full init.
render_skipped = BATTLE_RENDER_STATE + 0x02

; Per-region tilemap-DMA pending bitmask. Set by `init_*_gated` on the render
; path; consumed by `dma_transfer` in NMI to fire a per-region tilemap DMA.
tilemap_pending_mask = BATTLE_RENDER_STATE + 0x03
TILEMAP_PENDING_COMMANDS = 0x01
TILEMAP_PENDING_MAIN = 0x02

; --- Active-char highlight walker scratch (redraw_gates.s) ---
; Lives in the project-owned render-state block, not the $7E:EF9x
; battle scratch: vanilla cursor code and the rolling-inventory
; engine both claim bytes in there.
highlight_active_slot = BATTLE_RENDER_STATE + 0x05
highlight_pal_byte = BATTLE_RENDER_STATE + 0x06
highlight_row = BATTLE_RENDER_STATE + 0x07
; Last ($1822, $D7) pair the walker stamped for; the per-frame refresh
; re-stamps when either moves.
highlight_cache_slot = BATTLE_RENDER_STATE + 0x08
highlight_cache_menu = BATTLE_RENDER_STATE + 0x09

; --- Battle items window frame (inventory_rolling.s, magic_reloc.s) ---
; The magic list draws a taller frame over the menu buffer the items
; window shares; non-zero tells the next items transfer to rebuild the
; items frame before it copies the slots back in.
items_frame_dirty = BATTLE_RENDER_STATE + 0x0A
