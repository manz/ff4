"""
Inventory item layout + VWF region map shared across field, treasure,
drops, and key-item menus. Defines the `Item` struct (2-byte id + qty
pair) plus the BG3 CHR tile-id windows each menu surface owns.
"""

.include "src/vwf_state.i"

; Standard FF4 inventory item layout: 2-byte (id, qty) pairs.
;
; Used by every menu surface that shows player items in single-column

; rolling-buffer form:
;   - Field menu Items submenu       at $7E:1440 (48 slots)
;   - Treasure menu inventory list   at $7E:1440 (same 48-slot array)
;   - Treasure menu drops list       at $7E:FF28 (8 drop slots)
;   - Key-item picker filter buffer  at $7E:0712 (filtered subset of $1440)
;
; Battle inventory at $321A is a separate 4-byte layout (flags + id +
; qty + spell) and gets its own struct in a follow-up plan.


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
; mapping BG3 CHR to VRAM word $2000 / byte $4000. 256 static-font
; tile_ids live at $00..$FF ; the VWF region starts past that at
; tile_id $100 (9-bit tile_id territory) so glyph blits never
; trample the menu chrome / font CHR.
FIELD_BG3_CHR_VRAM_BYTE := 0x4000
FIELD_BG3_CHR_VRAM_WORD := FIELD_BG3_CHR_VRAM_BYTE >> 1

; VWF window starts at tile_id $100 in CHR = $4000 + $100 * 16 = $5000.
FIELD_VWF_VRAM_DEST_BYTE := FIELD_BG3_CHR_VRAM_BYTE + 0x1000
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
;   Region 0  $000..$0FF  vanilla menu font CHR (untouched)
;   Region 1  $100..$169  field / treasure inventory item-name buffer
;                         (FIELD_ITEM_VWF_TILE_BASE + K * slot,
;                          11 slots * K=10 tile_ids)
;   Region 1B $16E..$1A9  drops item-name buffer (treasure popup only),
;                         6 buffer slots offset by DROPS_VWF_TILE_SLOT_OFFSET
;                         (=11) from the treasure base so the two
;                         panels coexist without clobbering each other.
;
; Field menu vs treasure-popup vs drops are UI-exclusive at the panel
; level, but inside the treasure popup the treasure inventory AND the
; monster-drops band render every frame. They both route through the
; patched `DrawItemName` JSL hook in `items_menu_vwf.draw_field_item_name`
; which computes tile_id_base from DP $5D. Drops's render hook offsets
; $5D by +11 before calling the vanilla trampoline chain so its CHR
; lands at $16E.. instead of $100.. ; items_menu_vwf bumps chr_byte_count
; from $700 to $B00 so the NMI DMA flush covers both regions across
; all 6 buffer slots per panel.
;
; Pushing the VWF region into 9-bit tile_id territory ($100+) keeps
; it disjoint from the static font window ; the combined treasure +
; drops footprint fits at $100..$1A9 (margin to $1FF before the next
; BG3 CHR boundary).
FIELD_ITEM_VWF_TILE_BASE := 0x100
FIELD_ITEM_VWF_TILE_BUDGET := 0x0A
DROPS_VWF_TILE_SLOT_OFFSET := 0x0B


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
