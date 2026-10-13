"""
The battle renderer's own state, reserved in cart SRAM at $70:7100, outside the VWF CHR buffer (inventory slot CHR
overwrites it). Battle code uses it as `battle_render_state.<field>`; render_defs.i builds the bit constants.
"""


.import "core/preamble"

BATTLE_RENDER_STATE := 0x707100

; pending_transfer_mask: which VWF CHR slices the NMI flushes.
.struct ChrTransferBits {
    u1 pending
    u1 messages
    u1 monsters
    u1 names
    u1 commands
    u1 spells
    u1 status  ; the target window's status names (battle/status_names.s)
    u1 free
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

.struct BattleRenderState {
    ChrTransferBits pending_transfer_mask
    RegionDirtyBits region_dirty_bits
    byte render_skipped  ; $FF: init_*_gated skipped a clean region, $00: it ran the full init
    TilemapPendingBits tilemap_pending_mask
    byte inventory_footer_pinned  ; dma_transfer: the inventory footer pinning is on (message.s)
    byte highlight_active_slot  ; highlight walker scratch (redraw_gates.s); $7E:EF9x is taken by vanilla and inventory
    byte highlight_pal_byte
    byte highlight_row
    byte highlight_cache_slot  ; last ($1822, $D7) pair stamped; the per-frame refresh re-stamps when either moves
    byte highlight_cache_menu
    byte items_frame_dirty  ; the magic list drew over the items frame: the next items transfer rebuilds it
    byte spell_tiles_live  ; exactly 1 while the spell ring holds glyphs (the items slots must re-render)
    byte spell_name_left  ; per-name scratch for messages_vwf.draw_spell_name
    word free_0d
    byte render_region  ; the CHR region bit of the render in progress: its deinit flags it again (message.s)
    byte dma_dirty_slots  ; inventory slots whose CHR slice needs a flush
    word spell_list_ptr  ; list the ring was rendered from; another list empties it
    byte spell_row  ; row being rendered and its ring slot
    byte spell_slot
    byte spell_ring_dirty  ; a render touched the ring: queue its CHR flush
    byte[6] spell_ring_rows  ; list row each ring slot holds, $FF for none
}

; Bounded to the record: growing it past its span fails the build.
.pool battle_render_ram {
    bss
    range BATTLE_RENDER_STATE ( BATTLE_RENDER_STATE + sizeof(BattleRenderState) - 1 )
    strategy order
}
.reserve battle_render_state as BattleRenderState in battle_render_ram
