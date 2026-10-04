"""
The battle renderer's own state, reserved in cart SRAM at $70:7100.

Import this module wherever battle code reads or writes the render state:
`battle_render_state.<field>`. battle/render_defs.i documents the fields'
meaning and the bit constants built from the bit-field structs below.
"""


.import "preamble"

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
    byte[6] spell_ring_rows
}

; Bounded to the record, so growing it past its span fails the build
; instead of overrunning.
.pool battle_render_ram {
    range BATTLE_RENDER_STATE ( BATTLE_RENDER_STATE + BattleRenderState.__size - 1 )
    strategy order
}
.reserve battle_render_state as BattleRenderState in battle_render_ram
