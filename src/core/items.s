"""
Inventory item layout and the VWF region map shared by the field, treasure,
drops, key-item and equip menus.

`Item` (id, qty) is the row layout of the field inventory ($7E:1440, 48 slots,
also the treasure list), the drops list ($7E:FF28, 8 slots) and the key-item
filter buffer ($7E:0712). Battle uses the 4-byte `BattleItemSlot` at $7E:321A.
"""

.include "core/vwf_state.i"
.include "core/rolling_state.i"

; Battle's vanilla item-name cells: 1-byte symbol + 11 name cells = 12. Original FF4-J used 9 (1 + 8). The equip and
; inventory windows' vanilla fills keep this width; the names come from `items_unleashed` and the VWF redraws them.
ITEM_NAME_RECORD_SIZE := 0x0C
ITEM_NAME_TEXT_SIZE := 0x0B

; Record in the 16-char `items_unleashed` table: 1-byte symbol + 16-byte name.
ITEM_UNLEASHED_RECORD_SIZE := 0x11
ITEM_UNLEASHED_TEXT_SIZE := 0x10

; Menu BG3 CHR at VRAM byte $4000 (Mode 0, BG34NBA = $22). Static font uses tile ids $00..$FF.
FIELD_BG3_CHR_VRAM_BYTE := 0x4000
FIELD_BG3_CHR_VRAM_WORD := FIELD_BG3_CHR_VRAM_BYTE >> 1

; VWF window starts at tile_id $100 in CHR = $4000 + $100 * 16 = $5000.
FIELD_VWF_VRAM_DEST_BYTE := FIELD_BG3_CHR_VRAM_BYTE + 0x1000
FIELD_VWF_VRAM_DEST_WORD := FIELD_VWF_VRAM_DEST_BYTE >> 1

; Field-menu VWF regions, tile ids in the BG3 CHR at $4000:
;   $000..$0FF  vanilla menu font
;   $100..$16D  field / treasure item names (11 slots * K=10)
;   $16E..$1A9  drops item names (6 slots at DROPS_VWF_TILE_SLOT_OFFSET = 11), treasure popup only
; Treasure and drops render each frame through the same draw_field_item_name hook (tile base from
; DP $5D); drops adds 11 to $5D and flushes through the secondary descriptor.
FIELD_ITEM_VWF_TILE_BASE := 0x100
FIELD_ITEM_VWF_TILE_BUDGET := 0x0A
DROPS_VWF_TILE_SLOT_OFFSET := 0x0B

; Key-item picker: runs over a live map, where $2800 is the BG3 tilemap (BG3SC $29), so it borrows
; the dialogue VWF window vwfinit sets up (BG3 CHR $6000, ids $100+ from $6800). The usual tile ids
; ($100 + slot * K, flags $01) land there; only the flush differs.
;   src offset = $100 * 16 = $1000 bytes into VWF_CHR_BUFFER
;   vram dest  = $6000 + $100 * 8 = $6800 (2bpp)
;   size       = 7 slots * K=10 * 16 = $460 bytes
KEY_ITEM_VWF_CHR_SRC_OFFSET := 0x1000
KEY_ITEM_VWF_VRAM_DEST_WORD := 0x6800
KEY_ITEM_VWF_BYTE_COUNT := sizeof(key_item_chr_save)

; Caller-context values for vwf_engine.caller_ctx (see src/core/vwf_ram.s).
VWF_CTX_PRIMARY := 0x00
VWF_CTX_DROPS := 0x01
VWF_CTX_KEY_ITEM := 0x02
; Equip screen names ($01:9013): six slots borrow the drops region (idle outside the treasure
; popup). Names start at col 19, so a row holds only icon + glyph budget.
VWF_CTX_EQUIP := 0x03
EQUIP_NAME_CELLS := 1 + FIELD_ITEM_VWF_TILE_BUDGET

; Drops flush (secondary slot), at the fixed +11-slot offset:
;   src offset = $16E * 16 = $16E0 bytes into VWF_CHR_BUFFER
;   vram dest  = ($5000 + $6E0) / 2 = $2B70
;   size       = 6 slots * K=10 * 16 = $3C0 bytes
DROPS_VWF_CHR_SRC_OFFSET := 0x16E0
DROPS_VWF_VRAM_DEST_WORD := 0x2B70
DROPS_VWF_BYTE_COUNT := 0x03C0

; Primary flush size: sized for field items (11 slots * K=10 * 16 = $6E0, rounded to $700). Treasure
; overshoots into drops' CHR, which the secondary DMA then overwrites. Sizing for treasure alone
; ($400) leaves field items' last slots unflushed and BRKs on scroll.
FIELD_VWF_PRIMARY_BYTE_COUNT := 0x0700


; Treasure / drops rows: icon at tile column 2, name from column 3, 16-px hand cursor left of the
; icon. Drops' first item is on tilemap row 5; the hand top sits one pixel above the row.
TREASURE_ROW_ICON_COL := 2
TREASURE_CURSOR_X := TREASURE_ROW_ICON_COL * 8 - 16
; The equip inventory list uses the same rows.
EQUIP_LIST_CURSOR_X := TREASURE_CURSOR_X
; Visible rows and vanilla's scroll-down bound (first-visible row may not reach it).
EQUIP_LIST_VISIBLE_ROWS := 6
EQUIP_LIST_TOTAL_ITEMS := 48
EQUIP_LIST_SCROLL_LIMIT := EQUIP_LIST_TOTAL_ITEMS - EQUIP_LIST_VISIBLE_ROWS + 1
; Vanilla's list BG4VOFS ($01:BE95 seeds $99 with scroll * 16 + $FF98) puts window line 0 at screen
; line -$FF98. Rows start one tile below the border; the hand sits one pixel above a slot's bottom row.
EQUIP_LIST_BASE_SCROLL := 0xFF98
EQUIP_LIST_ORIGIN_LINES := 8
EQUIP_LIST_FIRST_ROW_Y := 0x10000 - EQUIP_LIST_BASE_SCROLL + EQUIP_LIST_ORIGIN_LINES
EQUIP_LIST_CURSOR_Y_BASE := EQUIP_LIST_FIRST_ROW_Y + 8 - 1
DROPS_FIRST_ITEM_ROW := 5
DROPS_CURSOR_Y_BASE := DROPS_FIRST_ITEM_ROW * 8 - 1


.struct Item {
    byte id
    byte qty
}
.assert sizeof(Item) == 2, "item indexing shifts the row left once (asl) per Item"

; The field inventory: 48 Items at $7E:1440, indexed `, x` by row * 2.
FIELD_INVENTORY := 0x1440
field_inventory := (FIELD_INVENTORY as Item)
; Item at the absolute WRAM pointer in X: `item_x.id, x`.
item_x := (0x7E0000 as Item)

; The battle inventory: 48 slots at $7E:321A, indexed `, x` by slot * 4.
.struct BattleItemSlot {
    byte flags
    byte id
    byte qty
    byte unused
}
battle_inventory := (0x7E321A as BattleItemSlot)


; Rolling-buffer state, one RollingBufferState per profile, bound below as `<profile>_rolling`.
; The $7E:9C00 arena sits in spell-list text buffers freed by magic direct rendering; battle only uses
; $97A6 and $9DA7, and menus re-seed the state on open.
TREASURE_ROLLING_BASE := 0x7E9C00
DROPS_ROLLING_BASE := 0x7E9C30
KEY_ITEM_ROLLING_BASE := 0x7E9C60
FIELD_MENU_ROLLING_BASE := 0x7E9C90
SELL_ROLLING_BASE := 0x7E9CC0
EQUIP_ROLLING_BASE := 0x7E9CF0

; Vanilla's frame tick (WaitVblank $01:818A: `inc $16a3`, wraps at 60). Menus run with NMI off and
; their loops iterate a variable number of times per frame, so watch this byte for a change.
menu_frame_time := 0x7E16A3

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
ROLLING_MENU_ID_SELL := 4
ROLLING_MENU_ID_EQUIP := 5

; Typed views onto each profile's state. field_menu_rolling.hdma_enable / .hdma_copy_pending are also
; the shared menu HDMA signals: every rolling menu sets them to ask the field-menu NMI hook to copy
; shadow to active next vblank.
field_menu_rolling := (FIELD_MENU_ROLLING_BASE as RollingBufferState)
treasure_rolling := (TREASURE_ROLLING_BASE as RollingBufferState)
drops_rolling := (DROPS_ROLLING_BASE as RollingBufferState)
key_item_rolling := (KEY_ITEM_ROLLING_BASE as RollingBufferState)
sell_rolling := (SELL_ROLLING_BASE as RollingBufferState)
equip_rolling := (EQUIP_ROLLING_BASE as RollingBufferState)

; The profile X points at (X = base low word): `rolling_x.<field>, x`.
rolling_x := (0x7E0000 as RollingBufferState)

; Treasure held-DOWN debounce, right after treasure_rolling. Non-zero: the scroll trigger aborts and
; undoes vanilla's $1BB7 increment, so holding DOWN repeats at a fixed cadence.
treasure_scroll_cooldown := TREASURE_ROLLING_BASE + sizeof(RollingBufferState)

; Last menu_frame_time seen by the treasure loop, so the cooldown ticks once per frame.
treasure_scroll_frame_seen := treasure_scroll_cooldown + 1
