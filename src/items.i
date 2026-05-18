

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

; --- Field-menu BG3 CHR base ---
; Menu PPU runs Mode 0 with BG34NBA = $22 (`ff4decomp/menu/menu.asm:3878+`),
; mapping BG3 CHR to VRAM word $2000 / byte $4000.
FIELD_BG3_CHR_VRAM_BYTE := 0x4000
FIELD_BG3_CHR_VRAM_WORD := FIELD_BG3_CHR_VRAM_BYTE >> 1

; small_vwf's `tilemap_write_no_inc` unconditionally ORs $01 into
; the tilemap-entry high byte (palette/attr byte). In Mode 0 2bpp
; BG3 that bit is the cc-low of the 10-bit tile_id, so tile_id
; $C0 from the allocator reads back as $1C0 on the tilemap side.
; PPU then looks for CHR at $4000 + $1C0 * 16 = $5C00. The flush
; therefore aims at $5C00, with the SRAM source still at
; VWF_CHR_BUFFER + VWF_CHR_FLUSH_OFFSET ($703C00) ; the allocator
; stays at $C0 so the per-slot CHR slice math does not need to
; jump a buffer.
FIELD_VWF_VRAM_DEST_BYTE := FIELD_BG3_CHR_VRAM_BYTE + 0x1C00
FIELD_VWF_VRAM_DEST_WORD := FIELD_VWF_VRAM_DEST_BYTE >> 1

; --- Field-menu VWF regions ---
; Mirrors the battle-side `region_size * N` partition in
; `src/battle/message.s`. Each region owns a contiguous tile-id
; window inside the BG3 CHR slot at VRAM $4000 (menu BG34NBA = $22).
; Adding a new VWF surface (item description, treasure list,
; whatever lives on field) means declaring a new region with its
; tile-id base + budget + VRAM dest and the engine routes via
; VwfConfig without touching the existing regions.
;
;   Region 0  $00..$BF   vanilla menu font CHR (untouched)
;   Region 1  $C0..$FF   field item-name rolling buffer
;                        (FIELD_ITEM_VWF_TILE_BASE + K * slot)
;
; With 11 buffer slots * K=10 tile-ids the high slots overflow past
; $FF and wrap into the font region ; the visible-slot-only render
; (display slots 0..9) is contained, but slot 10's pre-render slot
; lands at tile-id $124. Acceptable for now ; future regions or a
; tighter K take this constraint.
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
