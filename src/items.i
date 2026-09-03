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

; --- Drops VWF flush descriptor (secondary NMI flush slot) ---
; Hardcoded since drops only ever lives at the +11-slot offset in
; the field BG3 CHR window. NMI runs both primary (treasure) and
; secondary (drops) flushes per frame so each panel's CHR reaches
; VRAM intact regardless of which descriptor was written last.
;   src offset =  $16E   * 16 = $16E0  bytes into VWF_CHR_BUFFER
;   vram dest  = ($5000 + $6E0) / 2 = $2B70 (= drops's CHR base)
;   size       =  6 buffer slots * K=10 * 16 = $3C0 bytes
DROPS_VWF_CHR_SRC_OFFSET := 0x16E0
DROPS_VWF_VRAM_DEST_WORD := 0x2B70
DROPS_VWF_BYTE_COUNT := 0x03C0

; Primary flush size: covers the WORST-CASE primary consumer which
; is the field-items menu (11 buffer slots * K=10 * 16 bytes = $6E0,
; round up to $700). Treasure uses only 6 slots ($3C0) so the
; primary DMA overshoots its region by a few tiles, but the extra
; bytes flush into the start of drops's CHR window ($16E..$170)
; whose secondary DMA overwrites them with the correct drops CHR
; immediately afterwards. Was briefly $400 (treasure-only sized)
; after the two-descriptor split, which cut field-items' last 5
; buffer slots out of the flush window and tripped a BRK during
; field scroll once tilemap entries pointed at unflushed tile_ids.
FIELD_VWF_PRIMARY_BYTE_COUNT := 0x0700


.struct Item {
    byte id
    byte qty
}


; Rolling-buffer engine state. Each profile (field menu, treasure
; inventory, treasure drops, key-item picker) gets its own contiguous
; 12-byte block at a known WRAM base; routines reference fields via
; `<base> + RollingBufferState.<field>` instead of hardcoded offsets.
;

; Bases (all in clean $7E:9C00 arena, off vanilla scratch $1B**):
;   Treasure inv:      $7E:9C00
;   Drops:             $7E:9C30
;   Key-item picker:   $7E:9C60
;   Field menu:        $7E:9C90  (FIELD_MENU_ROLLING_BASE below)
;
; The whole arena lives inside the spell-list text buffers that the
; magic-direct-render rewrite freed (see battle/inventory_rolling.s
; comment: "freed by magic direct rendering: $97A6, $9E66, …"). Battle
; reuses the low end ($97A6 ring + $9DA7 command buffer), leaving the
; $990E..$9DA7 gap free - that's where our four rolling states sit.
; Menus are mutually exclusive with battle, and init re-seeds the
; struct on every menu open, so battle-side overwrites don't matter.
;
; Only the field base lives here for now - the other three are still
; defined inside their respective modules. Migrate them into shared
; constants when the singleton arena refactor lands.
FIELD_MENU_ROLLING_BASE := 0x7E9C90

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
    byte visible_rows
    byte slot_height_tiles
    long item_list_ptr
    byte item_count
    byte hdma_channel
    long vwf_cfg_ptr
    byte dirty_mask
    long fn_render_slot
    long fn_update_hdma
    long fn_draw_window
    byte menu_id
}

ROLLING_MENU_ID_FIELD := 0
ROLLING_MENU_ID_TREASURE := 1
ROLLING_MENU_ID_DROPS := 2
ROLLING_MENU_ID_KEY_ITEM := 3

; Typed view onto the field state - gives field_menu_rolling.hdma_enable,
; field_menu_rolling.fn_render_slot, etc. as flat symbols (a816 cast,
; eager-expanded in symbols.py::_try_expand_typed_cast).
;
; The field hdma_enable / hdma_copy_pending bytes also act as the
; SHARED menu HDMA signals - all four rolling menus poke them to ask
; the field-menu NMI hook (field_menu_nmi_dma_transfer_check_impl) to
; copy shadow→active during the next vblank. Reference directly as
; `field_menu_rolling.hdma_enable` / `.hdma_copy_pending` everywhere.
field_menu_rolling := (FIELD_MENU_ROLLING_BASE as RollingBufferState)

