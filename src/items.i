

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


; Per-item record size in the French-translated assets_items_dat table:
; 1-byte symbol prefix + 11-byte name = 12 bytes total. Original FF4-J
; used 9 bytes (1 + 8). Use these constants everywhere a code site
; walks the item-name table so layouts stay in sync.
ITEM_NAME_RECORD_SIZE := 0x0C
ITEM_NAME_TEXT_SIZE := 0x0B

; Per-item record size in the unleashed (16-char) name table at
; `assets_items_unleashed_dat`: 1-byte symbol prefix + 16-byte name =
; 17 bytes total. Battle / field / drops / treasure inventory all
; render from this table once the BATTLE_ITEMS_VWF + field-menu
; switches are on. Keep stride math + loop counters consistent via
; these two symbols.
ITEM_UNLEASHED_RECORD_SIZE := 0x11
ITEM_UNLEASHED_TEXT_SIZE := 0x10

; Field-menu item VWF tile budget. K=10 to match battle inventory ;
; with 11 buffer slots (10 visible + 1 pre-render) the high slots
; wrap past $FF and stomp the start of the font CHR area. Accepted
; for now to keep glyph widths usable on full 16-char names ;
; long-term fix is either a 9-bit tile_id allocator or a per-frame
; allocation strategy that does not need disjoint per-slot ranges.
FIELD_ITEM_VWF_TILE_BASE := 0xC0
FIELD_ITEM_VWF_TILE_BUDGET := 0x0A


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
