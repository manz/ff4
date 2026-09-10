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

; --- Char-name highlight ---
; Signature of what the highlight was last applied for: the active char
; index folded with which name rows are actually on screen. The per-frame
; refresh compares against it and re-walks only when it moves, so the
; palette flip costs a compare on an idle frame. $FF forces a re-apply.
scp_state_key = BATTLE_RENDER_STATE + 0x04
; Scratch: tilemap row being written, which counts drawn names only.
scp_out_row = BATTLE_RENDER_STATE + 0x05
; Scratch: battle-struct base of the row being written. A word in our own
; arena rather than a direct-page byte - the walk runs from NMI, where the
; caller's page is not ours to borrow.
scp_base = BATTLE_RENDER_STATE + 0x06
