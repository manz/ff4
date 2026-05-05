

"""
Standard FF4 inventory item layout: 2-byte (id, qty) pairs.

Used by every menu surface that shows player items in single-column

rolling-buffer form:
  - Field menu Items submenu       at $7E:1440 (48 slots)
  - Treasure menu inventory list   at $7E:1440 (same 48-slot array)
  - Treasure menu drops list       at $7E:FF28 (8 drop slots)
  - Key-item picker filter buffer  at $7E:0712 (filtered subset of $1440)

Battle inventory at $321A is a separate 4-byte layout (flags + id +
qty + spell) and gets its own struct in a follow-up plan.
"""

.struct Item {
    byte id
    byte qty
}


; Rolling-buffer engine state. Each profile (field menu, treasure
; inventory, treasure drops, key-item picker) gets its own contiguous
; 12-byte block at a known WRAM base; routines reference fields via
; `<base> + RollingBufferState.<field>` instead of hardcoded offsets.
;
; Field menu base:    $7E:1BA8
; Treasure inventory: $7E:1BD0
; (Drops + key-item bases will be assigned during Phase 4-5.)
.struct RollingBufferState {
    byte top_row
    byte buffer_pos
    byte edge_row
    byte slot_index
    word base_scroll
    byte hdma_enable
    byte _pad
    byte scroll_state
    byte scroll_remaining
    byte scroll_direction
    byte transfer_pending
    word scroll_anim_offset
    byte hdma_copy_pending
}
