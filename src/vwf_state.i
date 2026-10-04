"""
Shared VWF engine state addresses + future-config-struct slots.

Both the battle messages renderer (`battle_render` in
`src/battle/message.s`) and the menu small-VWF renderer
(`render` in `src/small_vwf/render.s`) build glyph CHR into the same
SRAM tile buffer at $70:3000. They cohabit by never running
concurrently: battle owns the buffer during battle scenes, small_vwf
owns it during field menus.

Define the shared address as a single symbol so future engines
(field-menu items, treasure-list VWF, drops-list VWF, ...) all
point at the same place automatically. Bumping the size only
needs to happen here  ; `_vram_copy.buffer` already sits at $70:5000
past the buffer so the VRAM-save staging is decoupled from the
CHR-buffer size.

Per-render parameters live in `vwf_cfg` (VwfConfig at $70:7080), the
engine's own state in `vwf_engine` (VwfEngine at $70:70C0): callers fill
the config, then call `render.render_with_config`.
"""


; --- VWF CHR buffer (shared across battle + menu renderers) -----------

VWF_CHR_BUFFER := 0x703000
; Sized to cover tile_ids $00..$1FF (512 * 16 bytes). Field menu
; rolling buffer has 11 slots * K=10 tiles starting at base $C0,
; so the high slots end up at tile_id $160+ ; the previous $1000
; sizing capped at $FF and the high-slot CHR landed in
; $704000-$704FFF which was outside any blit / DMA reach.
VWF_CHR_BUFFER_SIZE := 0x2000

; --- Battle-render gate state (OUTSIDE the CHR buffer) ------------------
; These bytes must not live inside VWF_CHR_BUFFER. The inventory rolling
; buffer anchors at tile_id $C0 and hands each of its 11 slots
; ITEM_VWF_TILE_BUDGET (10) tiles, so slot N's CHR slice runs from
; $70:3C00 + N*160 and the last slot ends at $70:4240. Slot 4 alone spans
; $70:3E80..$70:3F1F, which is exactly where the gate bytes used to sit --
; a rendered item name wrote glyph pixels over pending_transfer_mask, the

; region dirty bits, render_skipped and dma_dirty_slots (observed:
; pending_transfer_mask = $F3), so the battle names / monsters regions lost
; their dirty + CHR-pending bits and never flushed again: black name blocks
; and an empty monster window for the rest of the battle.
BATTLE_RENDER_STATE := 0x707100

; pending_transfer_mask: which VWF CHR slices the NMI flushes.
.struct ChrTransferBits {
    u1 pending
    u1 messages
    u1 monsters
    u1 names
    u1 commands
    u1 spells
    u2 free
}

; region_dirty_bits: regions whose text changed (1 = dirty).
.struct RegionDirtyBits {
    u1 messages
    u1 monsters
    u1 names
    u1 commands
    u4 free
}

; tilemap_pending_mask: per-region tilemap DMAs the NMI fires.
.struct TilemapPendingBits {
    u1 commands
    u1 main
    u6 free
}

; The battle renderer's own state; battle/render_defs.i documents each
; field under its `battle_render.` name.
.struct BattleRenderState {
    ChrTransferBits pending_transfer_mask
    RegionDirtyBits region_dirty_bits
    byte render_skipped
    TilemapPendingBits tilemap_pending_mask
    byte free_04
    byte highlight_active_slot
    byte highlight_pal_byte
    byte highlight_row
    byte highlight_cache_slot
    byte highlight_cache_menu
    byte items_frame_dirty
    byte spell_tiles_live
    byte spell_name_left
    word spell_name_src
    byte free_0f
    byte dma_dirty_slots
    word spell_list_ptr
    byte spell_row
    byte spell_slot
    byte spell_ring_dirty
    byte spell_ring_rows
}

battle_render_state := (BATTLE_RENDER_STATE as BattleRenderState)

; --- Null-terminated text-staging buffer ------------------------------
; Callers copy the source string (from items_unleashed, monster names,
; magic list, ...) into this buffer + write $00 terminator, then call
; `vwf_render_string` with just a pointer. Lets the engine drop the
; explicit char-count argument that battle / item-description / field
; helpers each carry today, and lets us swap the source layout
; (fixed-stride table vs null-terminated table vs RAM-resident string)
; without touching the renderer. Sized for the longest field-menu
; item slot in `assets_items_unleashed_dat` + 1 terminator + headroom.
VWF_TEXT_BUFFER := 0x707000
VWF_TEXT_BUFFER_SIZE := 0x40

; --- VWF config: per-render parameters, bound as `vwf_cfg` (below) ------
VWF_CONFIG_BASE := 0x707080

; --- Engine state in SRAM (no DP collisions), bound as `vwf_engine` ---
VWF_ENGINE_BASE := 0x7070C0

; Where one panel's CHR goes: the drops panel's flush (see caller_ctx).
.struct VwfFlushDesc {
    byte dirty
    word vram_word
    word byte_count
    word src_offset
}

.struct VwfEngine {
    word src_offset
    byte chr_dirty
    byte caller_ctx
    VwfFlushDesc flush_b
    word tilemap_offset
    byte prev_char
    byte current_char
}

.struct VwfConfig {
    word tile_id_base
    byte slot_budget
    word tilemap_base
    byte palette_byte
    byte flags
    word chr_vram_word
    word chr_byte_count
}

vwf_cfg := (VWF_CONFIG_BASE as VwfConfig)
vwf_engine := (VWF_ENGINE_BASE as VwfEngine)

; Engine-shared CHR-flush source offset. Every VWF caller writes
; glyph CHR at `VWF_CHR_BUFFER + tile_id_base * 16` ; both battle
; inventory and field menu items happen to anchor at tile_id base
; $C0, so the flush always starts $C00 bytes into the buffer.
; (If a future client uses a different base, this constant moves to
; the engine and we still avoid forking the DMA source per caller.)
VWF_CHR_FLUSH_OFFSET := 0x100 * 0x10

; --- VRAM save / restore range ---
; The dialog VWF saves the VRAM CHR window before dialog opens and
; restores it on close. With field-menu items + item-description
; each carving out their own slice of CHR ($5000..$5FFF), the save
; range must cover that whole 4KB block so menu close puts the
; menu CHR back the way the field renderer expects it.
;
;   Word $2800 .. $37FF  =  byte $5000 .. $6FFF  (8KB)
;
; Generous on the upper end so a future region 3 / region 4 (status,
; equipment, ...) lands inside the save window without bumping the
; SRAM scratch.
VRAM_SAVE_BASE_WORD := 0x2800
VRAM_SAVE_BYTE_COUNT := 0x2000
VRAM_SAVE_SRAM_BASE := 0x705000
