"""
Shared battle_render WRAM-layout + bit constants.

Compile-time definitions consumed by more than one module (message.s owns the
renderer; redraw_gates.s and the writer-site shims read the same dirty-bit and
tilemap-pending interface). Included inside `.scope battle_render { ... }` so
every consumer sees them as `battle_render.<name>`. Constants don't link, so
sharing them via `.include` (not `.extern`) is the correct, link-free idiom.
"""

; --- Per-region dirty bits (normal sense: 1 = dirty, 0 = clean) ---
; Sits next to the DMA queue byte; writers SET bits on state change.
region_dirty_bits = 0x703f01
REGION_DIRTY_MESSAGES = 0x01
REGION_DIRTY_MONSTERS = 0x02
REGION_DIRTY_NAMES = 0x04
REGION_DIRTY_COMMANDS = 0x08

; Transient marker: $FF if `init_*_with_gate` short-circuited because the
; region was clean; $00 if it ran the full init.
render_skipped = 0x703f02

; Per-region tilemap-DMA pending bitmask. Set by `init_*_gated` on the render
; path; consumed by `dma_transfer` in NMI to fire a per-region tilemap DMA.
tilemap_pending_mask = 0x703f03
TILEMAP_PENDING_COMMANDS = 0x01
TILEMAP_PENDING_MAIN = 0x02
