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
region_dirty_bits = battle_render_state.region_dirty_bits
REGION_DIRTY_MESSAGES = RegionDirtyBits.messages.mask
REGION_DIRTY_MONSTERS = RegionDirtyBits.monsters.mask
REGION_DIRTY_NAMES = RegionDirtyBits.names.mask
REGION_DIRTY_COMMANDS = RegionDirtyBits.commands.mask

; Transient marker: $FF if `init_*_with_gate` short-circuited because the
; region was clean; $00 if it ran the full init.
render_skipped = battle_render_state.render_skipped

; Per-region tilemap-DMA pending bitmask. Set by `init_*_gated` on the render
; path; consumed by `dma_transfer` in NMI to fire a per-region tilemap DMA.
tilemap_pending_mask = battle_render_state.tilemap_pending_mask
TILEMAP_PENDING_COMMANDS = TilemapPendingBits.commands.mask
TILEMAP_PENDING_MAIN = TilemapPendingBits.main.mask

; --- Active-char highlight walker scratch (redraw_gates.s) ---
; Lives in the project-owned render-state block, not the $7E:EF9x
; battle scratch: vanilla cursor code and the rolling-inventory
; engine both claim bytes in there.
highlight_active_slot = battle_render_state.highlight_active_slot
highlight_pal_byte = battle_render_state.highlight_pal_byte
highlight_row = battle_render_state.highlight_row
; Last ($1822, $D7) pair the walker stamped for; the per-frame refresh
; re-stamps when either moves.
highlight_cache_slot = battle_render_state.highlight_cache_slot
highlight_cache_menu = battle_render_state.highlight_cache_menu

; --- Battle items window frame (inventory_rolling.s, magic_reloc.s) ---
; The magic list draws a taller frame over the menu buffer the items
; window shares; non-zero tells the next items transfer to rebuild the
; items frame before it copies the slots back in.
items_frame_dirty = battle_render_state.items_frame_dirty

; --- Battle spell list VWF (magic_reloc.s, message.s, inventory_rolling.s) ---
; The spell names render into the items window's tiles ($C0..$FB), never
; the command window's: both of those slide past each other on screen.
; Only the rows on screen hold glyphs: a ring of SPELL_RING_ROWS slots,
; list row r in slot r % SPELL_RING_ROWS, SPELL_NAME_TILES per name. Five
; rows show, a sixth while a scroll slides it in.
; Exactly 1 while the ring holds spell glyphs: the items window must
; re-render its slots before showing, and the ring cache below is valid.
spell_tiles_live = battle_render_state.spell_tiles_live
; Per-name scratch for messages_vwf.draw_spell_name.
spell_name_left = battle_render_state.spell_name_left
spell_name_src = battle_render_state.spell_name_src
; List the ring was rendered from (WRAM pointer); another list empties it.
spell_list_ptr = battle_render_state.spell_list_ptr
; Row being rendered and its ring slot.
spell_row = battle_render_state.spell_row
spell_slot = battle_render_state.spell_slot
; Non-zero once a render touched the ring: queue its CHR flush.
spell_ring_dirty = battle_render_state.spell_ring_dirty
; List row each ring slot holds, $FF for none.
spell_ring_rows = battle_render_state.spell_ring_rows
; pending_transfer_mask bit: flush the ring's CHR in the NMI's
; per-region pass.
CHR_REGION_SPELLS = ChrTransferBits.spells.mask
SPELL_TILE_BASE = 0xC0
SPELL_RING_ROWS = 6
SPELL_NAME_TILES = 5
SPELL_ROW_TILES = SPELL_NAME_TILES * 2
SPELL_RING_TILES = SPELL_ROW_TILES * SPELL_RING_ROWS
SPELL_LIST_ROWS = 12
SPELL_VISIBLE_ROWS = 5
SPELL_NAME_LENGTH = 9
