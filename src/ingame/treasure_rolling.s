; Treasure inventory rolling buffer (single-column, 5 visible).
;

; Cloned from src/ingame/inventory_rolling.s with:
;   - VISIBLE_ITEMS = 5, BUFFER_SLOTS = 6, SCROLL_LIMIT = 43.
;   - State RAM relocated to $1BD0..$1BDE (vanilla treasure UI owns
;     $1BB3..$1BB7).
;   - Scroll position read from $1BB7 instead of $1B1A.
; HDMA channel 5, BG1 tilemap buffer ($7EB600), and shadow tables
; ($7E9800/$7E9840) are shared with field-menu rolling because the two
; menus are mutually exclusive on screen.

; Layout (single column)
TREASURE_VISIBLE_ITEMS := 5  ; Visible items at once
TREASURE_BUFFER_SLOTS := 6  ; 6 slots (5 visible + 1 pre-render)
TREASURE_TOTAL_ITEMS := 48  ; Total inventory items
TREASURE_SCROLL_LIMIT := 43  ; 48 - 5 = max scroll position

; Pixels per item row
TREASURE_PIXELS_PER_ROW := 16  ; Pixels per item slot (2 tilemap rows × 8)

; Scroll constants
TREASURE_SCROLL_WRAP := 96  ; 6 slots × 16 pixels = 96

; Screen layout
TREASURE_ITEM_LIST_Y_START := 48
TREASURE_ITEM_LIST_HEIGHT := 80  ; 5 items × 16 pixels

; RAM VARIABLES
; Treasure rolling state lives at $1BD0..$1BDE so it does not collide with
; vanilla treasure UI bytes ($1BB3..$1BB7) nor field-menu rolling state at
; $1BA8..$1BB6. Both menus are mutually exclusive on screen so the HDMA
; channel + tilemap buffer + shadow table are shared (re-init on entry).

; Treasure rolling-buffer state RAM block (12 bytes from $1BD0). Same
; struct layout as the field-menu state block — fields resolved via
; `RollingBufferState` from src/items.i so any layout change applies
; uniformly across profiles.
treasure_rolling := 0x1BD0
treasure_rolling_top_row := treasure_rolling + RollingBufferState.top_row
treasure_rolling_buffer_pos := treasure_rolling + RollingBufferState.buffer_pos
treasure_rolling_edge_row := treasure_rolling + RollingBufferState.edge_row
treasure_rolling_slot_index := treasure_rolling + RollingBufferState.slot_index
treasure_rolling_base_scroll := treasure_rolling + RollingBufferState.base_scroll
treasure_hdma_enable := treasure_rolling + RollingBufferState.hdma_enable
treasure_scroll_state := treasure_rolling + RollingBufferState.scroll_state
treasure_scroll_remaining := treasure_rolling + RollingBufferState.scroll_remaining
treasure_scroll_direction := treasure_rolling + RollingBufferState.scroll_direction
treasure_transfer_pending := treasure_rolling + RollingBufferState.transfer_pending
treasure_scroll_anim_offset := treasure_rolling + RollingBufferState.scroll_anim_offset
treasure_hdma_copy_pending := treasure_rolling + RollingBufferState.hdma_copy_pending

; Scroll State Constants
TREASURE_SCROLL_STATE_IDLE := 0
TREASURE_SCROLL_STATE_SCROLLING := 1
TREASURE_SCROLL_PIXELS_PER_FRAME := 16  ; 16 px/frame = 1 frame per scroll
TREASURE_SCROLL_TOTAL_PIXELS := 16

; HDMA Configuration (Direct Mode like FF6)
; Use HDMA channel 5 for BG1 vertical scroll during item menu
; Direct mode: table contains count + 2 data bytes per entry
; Using WRAM at $7E9800 (free area in menu RAM)
;
; Table format: count_byte, lo_byte, hi_byte (3 bytes per entry)

; Layout:
;   Entry 0: 48 scanlines (border) at BASE scroll
;   Entries 1-10: 16 scanlines each (10 item rows) with calculated scroll
;   Entry 11: 32 scanlines (below items) at BASE scroll
;   Entry 12: $00 (end marker)
;
; Total table size: ~36 bytes + end marker

; Treasure HDMA tables live in expanded SRAM (bank $70 free area at
; $704700+) so they don't fight whatever vanilla treasure may stash in
; the $7E:9800 region used by the field-menu rolling buffer.
; Share field-menu HDMA tables (mutually exclusive on screen).
; Active (read by HDMA channel 5): $7E:9800
; Shadow (written by game): $7E:9840
; NMI hook copies shadow → active during VBlank when `menu_hdma_copy_pending`
; ($1BB6) is set, gated on `menu_hdma_enable` ($1BAE) being non-zero.
TREASURE_HDMA_TABLE_ADDR := 0x9800
TREASURE_HDMA_TABLE := 0x7E9800
TREASURE_HDMA_SHADOW_ADDR := 0x9840
TREASURE_HDMA_SHADOW := 0x7E9840
TREASURE_HDMA_TABLE_SIZE := 40
TREASURE_HDMA_BANK := 0x7E
treasure_hdma_copy_pending_shared := 0x1BB6  ; field-menu copy-pending flag

; HDMA channel 6 for the treasure rolling buffer. Vanilla treasure
; enables HDMAEN=$AD (ch7|ch5|ch3|ch2|ch0); ch2 in particular is an
; INDIRECT mode-3 channel that writes BG3HOFS+BG3VOFS for the drops-
; band parallax. Sharing ch5 fought ch2's per-scanline BG3VOFS writes
; until we masked ch2 entirely, which then dropped the drops parallax
; effect. Move our writes to ch6 (free in vanilla treasure) so ch2
; can keep driving its drops-band scroll untouched.
TREASURE_HDMA6_CTRL := 0x4360
TREASURE_HDMA6_DEST := 0x4361
TREASURE_HDMA6_SRC_LO := 0x4362
TREASURE_HDMA6_SRC_HI := 0x4363
TREASURE_HDMA6_SRC_BANK := 0x4364
TREASURE_HDMA6_IND_BANK := 0x4367
HDMAEN := 0x420C  ; HDMA enable register

init_treasure_inventory_hdma:
"""
Sets up HDMA channel 5 for per-scanline BG1 vertical scroll control
Called when entering the item menu

HDMA mode: $02 = write 2 bytes to same register, DIRECT mode (like FF6)
Register: $210E (BG1VOFS)
Table format: count_byte, lo_byte, hi_byte per entry, $00 to end
"""
    php
    sep #0x20  ; 8-bit A

; Build the HDMA data table in WRAM
; Use UpdateMenuScrollHDMA directly - InitMenuHDMATable is redundant
; since UpdateMenuScrollHDMA is called immediately after anyway
    jsr.w update_treasure_scroll_hdma

; Configure HDMA channel 6 for DIRECT mode
; Must use long addressing - DB may be $7E but registers are at $00:43xx
    lda #0x02  ; Mode: DIRECT, write 2 bytes to same PPU reg
    sta.l TREASURE_HDMA6_CTRL  ; $004360

    lda #0x12  ; BG3VOFS register ($2112) — treasure inventory is on BG3
    sta.l TREASURE_HDMA6_DEST  ; $004361

; Source = HDMA table in WRAM at $7E9800
    rep #0x20  ; 16-bit A
    lda.w #TREASURE_HDMA_TABLE_ADDR  ; $9800
    sta.l TREASURE_HDMA6_SRC_LO  ; $004362-$004363
    sep #0x20  ; 8-bit A
    lda #TREASURE_HDMA_BANK  ; $7E
    sta.l TREASURE_HDMA6_SRC_BANK  ; $004364

; HDMA channel 5 is now enabled via shadow variable (treasure_hdma_enable)
; The NMI hook at $8083 reads the shadow and writes to HDMAEN

    plp
    rts

disable_treasure_inventory_hdma:
"""
Disables HDMA channel 5 when leaving item menu
The shadow variable is cleared by menu_exit_hook
"""
    php
    sep #0x20  ; 8-bit A
    ; Shadow variable cleared by caller, NMI will write 0 to HDMAEN
    plp
    rts

init_treasure_hdma_table:
"""
Builds direct mode HDMA table in WRAM at $7E9800
Format: count, lo, hi per entry, $00 to end
Initial state: all rows at BASE scroll (no circular buffer offset)
"""
    rep #0x30  ; 16-bit A, X, Y
    php
    pha  ; Save A
    phx  ; Save X
    phy  ; Save Y

; Save DP bytes we'll use as scratch
    lda.b 0x40
    pha  ; Save $40-$41

; X = table write offset
    ldx.w #0x0000

; Entry 0: Border area - 48 scanlines at BASE scroll
    sep #0x20  ; 8-bit A for count byte
    lda #48  ; 48 scanlines
    sta.l TREASURE_HDMA_TABLE, x
    inx
    rep #0x20  ; 16-bit A for value
    lda.w treasure_rolling_base_scroll
    sta.l TREASURE_HDMA_TABLE, x
    inx
    inx

; Entries 1-10: Item rows - 16 scanlines each at BASE scroll (initial)
; For init, all rows use BASE (no circular buffer offset yet)
    lda.w #0x0000
    sta.b 0x40  ; Row counter

_t_init_item_rows:
    sep #0x20  ; 8-bit A for count
    lda #16  ; 16 scanlines per item row
    sta.l TREASURE_HDMA_TABLE, x
    inx
    rep #0x20  ; 16-bit A for value
    lda.w treasure_rolling_base_scroll
    sta.l TREASURE_HDMA_TABLE, x
    inx
    inx

    inc.b 0x40
    lda.b 0x40

    cmp.w #1  ; 10 rows
    bcc _t_init_item_rows

; Entry 11: Below items - 16 scanlines at BASE + 16
; Lock to show the bottom window border area
    sep #0x20
    lda #16  ; 16 scanlines
    sta.l TREASURE_HDMA_TABLE, x
    inx
    rep #0x20
    lda.w treasure_rolling_base_scroll
    clc
    adc.w #16  ; Lock at base + 16
    sta.l TREASURE_HDMA_TABLE, x
    inx
    inx

; End marker
    sep #0x20
    lda #0x00
    sta.l TREASURE_HDMA_TABLE, x

; Restore DP bytes
    rep #0x20
    pla
    sta.b 0x40  ; Restore $40-$41

; Restore registers
    ply
    plx
    pla
    plp
    rts

update_treasure_scroll_hdma:
"""Build the treasure-menu HDMA scroll table via the shared engine."""
    engine_update_scroll_hdma(treasure_rolling, TREASURE_HDMA_SHADOW, TREASURE_BUFFER_SLOTS, TREASURE_VISIBLE_ITEMS, _treasure_hdma_header, _treasure_hdma_footer, _treasure_hdma_signal)

_treasure_hdma_header:
"""Treasure profile header: drops band (120 lines at BASE-16) + inventory border (8 lines at BASE)."""
    sep #0x20
    lda #120
    sta.l TREASURE_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w treasure_rolling_base_scroll
    sec
    sbc.w #16
    sta.l TREASURE_HDMA_SHADOW, x
    inx
    inx
    sep #0x20
    lda #8
    sta.l TREASURE_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w treasure_rolling_base_scroll
    sta.l TREASURE_HDMA_SHADOW, x
    inx
    inx
    rts

_treasure_hdma_footer:
"""Treasure profile footer: 16 scanlines at BASE+16 (hides prefetch slot)."""
    sep #0x20
    lda #16
    sta.l TREASURE_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w treasure_rolling_base_scroll
    clc
    adc.w #16
    sta.l TREASURE_HDMA_SHADOW, x
    inx
    inx
    rts

_treasure_hdma_signal:
"""Treasure profile signal: set both treasure flag and shared $1BB6 mirror."""
    sep #0x20
    lda #0x01
    sta.w treasure_hdma_copy_pending
    sta.w treasure_hdma_copy_pending_shared
    rts

; Re-render all BUFFER_SLOTS (6) entries from $1440 using current
; $1BB7 (scroll_pos) and the existing buffer_pos rotation. Called from
; the redraw helper at $01:D933 after a swap completes — the swap
; mutates $1440 in place and vanilla's DrawInventoryList would redraw
; the whole 48-item list, but we only need to refresh the 5 visible
; slots + 1 prefetch. Crucially does NOT touch buffer_pos or any of
; the state-machine bytes, so the cursor/scroll position the user
; was on before the swap survives.

treasure_refresh_slots_impl:
"""Treasure profile: re-render all 6 slots without resetting scroll state (vanilla redraw helper at $01:D933)."""
    engine_refresh_slots(treasure_rolling, 0x1BB7, TREASURE_BUFFER_SLOTS, treasure_render_item_to_slot)

init_treasure_rolling_buffer_impl:
"""Init treasure rolling buffer (5 visible + prefetch slot 6)."""
    engine_init_rolling_buffer(treasure_rolling, TREASURE_BUFFER_SLOTS, _treasure_draw_inventory_window, treasure_ensure_hdma_initialized, treasure_render_item_to_slot)

_treasure_draw_inventory_window:
"""Treasure menu draws the InventoryWindow ($DCCE) frame for the bottom inventory list on entry."""
    rep #0x10
    ldy.w #0xDCCE
    jsr.l DrawWindow_Trampoline
    sep #0x10
    rts

treasure_scroll_down_prepare:
"""Treasure profile scroll-down pre-render."""
    engine_scroll_down_prepare(treasure_rolling, 0x1BB7, TREASURE_SCROLL_LIMIT, TREASURE_VISIBLE_ITEMS, TREASURE_BUFFER_SLOTS, treasure_ensure_hdma_initialized, treasure_render_item_to_slot, update_treasure_scroll_hdma)

treasure_scroll_up_prepare:
"""Treasure profile scroll-up pre-render."""
    engine_scroll_up_prepare(treasure_rolling, 0x1BB7, TREASURE_BUFFER_SLOTS, treasure_ensure_hdma_initialized, treasure_render_item_to_slot, update_treasure_scroll_hdma)

; treasure_render_item_to_slot
; Renders an item to a specific circular buffer slot in the tilemap.
;
; Input: treasure_rolling_edge_row = item index (0-47) for data lookup
;        treasure_rolling_slot_index = slot index (0-11) for destination
;
; Strategy: Set up $5d = slot_index (for Y position calculation),
;           $5a = pointer to item data, then call game's DrawItemSlot.

treasure_render_item_to_slot:
    php
    phb

; Set data bank to $7E for WRAM access
    lda #0x7E
    pha
    plb

; Set 16-bit A and X/Y for consistent register handling
    rep #0x30  ; 16-bit A and X/Y

; Save registers and key direct page variables
    pha
    phx  ; Save X (16-bit)
    phy  ; Save Y (16-bit)
    lda.b 0x5a
    pha
    lda.b 0x29  ; Save tilemap buffer pointer
    pha
    lda.b 0x45  ; Save $45-$46 (used by game routines)
    pha
    lda.b 0x33  ; Save $33-$34 (used for tile attributes)
    pha
    sep #0x20  ; 8-bit A
    lda.b 0x5d
    pha
    lda.b 0xDB  ; Save tile attribute byte
    pha

; Set $29 = $B600 for BG1 tilemap buffer
    rep #0x20  ; 16-bit A (X/Y still 16-bit)
    lda.w #0xD600  ; BG3 screen buffer (treasure inventory lives on BG3)
    sta.b 0x29
    sep #0x20  ; 8-bit A

; Calculate item data pointer: $1440 + (edge_row * Item.__size)
    lda.w treasure_rolling_edge_row
    asl  ; * Item.__size (2 bytes per Item)
    clc
    adc #0x40  ; Low byte of $1440
    sta.b 0x5a
    lda #0x14  ; High byte of $1440
    adc #0x00  ; Add carry
    sta.b 0x5b

; Load Item.id and Item.qty from ($5A) via long-addressing into WRAM.
    rep #0x20
    lda.b 0x5a  ; Pointer value = $1440 + edge_row * Item.__size
    tax
    sep #0x20
    lda.l 0x7E0000 + Item.id, x
    pha  ; Save Item.id for CheckCanUseItem
    lda.l 0x7E0000 + Item.qty, x
    sta.b 0x5C  ; Store qty in $5C

; Call CheckCanUseItem to set palette in $DB
; Input: A = item ID
; Output: $DB = $00 (usable) or $04 (not usable)
    stz.b 0x34  ; Clear $34 (no priority/flip bits)
    pla  ; Restore item ID
    jsr.l CheckCanUseItem_Trampoline  ; bank-$01 trampoline for vanilla @ $A25D (sets $DB)

; Set $5d = slot_index (for AND #$01 check, but we patched to AND #$00)
    lda.w treasure_rolling_slot_index
    sta.b 0x5d

; Calculate Y = slot_index * 128 + 70
; Y is the tilemap offset for this slot
; +64 for window border (1 tile row = 32 tiles × 2 bytes)
; +6 for left margin (3 tiles)
    rep #0x20  ; 16-bit A (X/Y already 16-bit)
    lda.w treasure_rolling_slot_index
    and.w #0x00FF  ; Clear high byte
    xba  ; Swap bytes: A = slot * 256
    lsr  ; A = slot * 128
    clc
    adc.w #0x0044  ; + 68 (64 border + 4 margin)
    tay  ; Y = tilemap offset (16-bit transfer)
    sep #0x20  ; 8-bit A

; Check for trash can item ($FF) - needs special 2x2 tile graphic
    lda (0x5a)  ; Load item ID
    cmp #0xFF
    bne _t_not_trash_item
    jsr.w draw_trash_treasure  ; Draw trash icon
    bra _t_skip_draw_item_slot

_t_not_trash_item:
    ; Clear the 2x2 trash can area first (in case we scrolled from trash position)
    jsr.w ClearTreasureTrashArea

; Call DrawItemSlot inner at $A1ED
; Expects: Y = tilemap offset, ($5A) = item pointer, ($29) = tilemap base
    jsr.l DrawItemSlotInner_Trampoline  ; bank-$01 trampoline for vanilla @ $A1ED

_t_skip_draw_item_slot:

; Restore direct page variables and registers (reverse order)
    pla
    sta.b 0xDB  ; Restore tile attribute byte
    pla
    sta.b 0x5d
    rep #0x20  ; 16-bit A
    pla
    sta.b 0x33  ; Restore $33-$34 (tile attributes)
    pla
    sta.b 0x45  ; Restore $45-$46 (used by game routines)
    pla
    sta.b 0x29  ; Restore tilemap buffer pointer
    pla
    sta.b 0x5a
    rep #0x10  ; 16-bit X/Y for pop (match push)
    ply  ; Restore Y (16-bit)
    plx  ; Restore X (16-bit)
    pla  ; Restore A (16-bit - still in 16-bit A from above)

    plb
    plp
    rts

treasure_ensure_hdma_initialized:
"""
Lazy initialization: captures $93 and sets up HDMA on first scroll.
Called from scroll prepare functions.
Checks if base_scroll == 0xFFFF (sentinel) and if so, initializes.
"""

; Check if already initialized (base_scroll != 0xFFFF)
    rep #0x20  ; 16-bit A
    lda.w treasure_rolling_base_scroll
    cmp.w #0xFFFF
    bne _t_hdma_already_init

; Capture vanilla BG3VOFS shadow ($9F). Vanilla treasure menu uses
; $9F = -120 to position items at screen scanline 120; we mirror that.
    lda.l 0x7E019F
    sta.w treasure_rolling_base_scroll

; Initialize HDMA channel configuration
    sep #0x20  ; Back to 8-bit for InitMenuInventoryHDMA
    jsr.w init_treasure_inventory_hdma

; Enable HDMA via the SHARED field-menu shadow at $1BAE. The existing
; field NMI hook (`field_menu_nmi_dma_transfer_check_impl`) reads this
; byte and copies the HDMA shadow→active table each frame.
; Treasure-only `treasure_hdma_enable` ($1BD6) is kept as a tracking
; flag but isn't read by the NMI path.
    lda #0x40  ; Channel 6 enable (treasure rolling buffer)
    sta.l 0x7E1BAE
    sta.w treasure_hdma_enable
    rts

_t_hdma_already_init:
    sep #0x20  ; Restore 8-bit mode
    rts

; STATE MACHINE ROUTINES (FF6-style non-blocking scroll)

treasure_scroll_state_check:
"""
Called at main loop entry ($019FF2) to handle scroll animation frames.
If scrolling is active, processes one frame and skips input handling.

Returns: Carry clear = process input normally
 Carry set = skip input (still scrolling)
"""
    php
    sep #0x20  ; 8-bit A

; Check if we're scrolling
    lda.w treasure_scroll_state
    beq _t_scroll_state_idle

; We're scrolling - process one animation frame
    jsr.l treasure_update_scroll_frame_impl

; Check if scroll finished
    lda.w treasure_scroll_remaining
    bne _t_scroll_still_active

; Scroll finished - clean up and return to idle
    jsr.l treasure_finish_scroll_impl

_t_scroll_state_idle:
    plp
    clc  ; Carry clear = process input
    rts

_t_scroll_still_active:
    plp
    sec  ; Carry set = skip input
    rts

treasure_start_scroll_down_impl:
"""Treasure profile: kick scroll-down state machine."""
    engine_start_scroll_down(treasure_rolling, 0x1BB7, TREASURE_VISIBLE_ITEMS, TREASURE_BUFFER_SLOTS, TREASURE_SCROLL_TOTAL_PIXELS, TREASURE_SCROLL_PIXELS_PER_FRAME, treasure_ensure_hdma_initialized, treasure_render_item_to_slot, update_treasure_scroll_hdma)

treasure_start_scroll_up_impl:
"""Treasure profile: kick scroll-up state machine."""
    engine_start_scroll_up(treasure_rolling, 0x1BB7, TREASURE_BUFFER_SLOTS, TREASURE_SCROLL_TOTAL_PIXELS, treasure_ensure_hdma_initialized, treasure_render_item_to_slot, update_treasure_scroll_hdma)

treasure_update_scroll_frame_impl:
"""Treasure profile: per-frame scroll animation tick."""
    engine_update_scroll_frame(treasure_rolling, TREASURE_SCROLL_PIXELS_PER_FRAME, update_treasure_scroll_hdma)

treasure_finish_scroll_impl:
"""Treasure profile: end-of-animation pre-render + cleanup."""
    engine_finish_scroll(treasure_rolling, 0x1BB7, TREASURE_VISIBLE_ITEMS, TREASURE_BUFFER_SLOTS, TREASURE_TOTAL_ITEMS, treasure_render_item_to_slot, update_treasure_scroll_hdma)

; Inventory Rolling Buffer Patches - Relocated to Bank $20
; These routines are called via JSL from bank $01 hooks.

.if INVENTORY_ROLLING_BUFFER {
TreasureMenuEntryHook_Impl:
    stz.w 0x1B1F
    lda #0x00
    sta.l 0x7E1BAE
; treasure_hdma_enable
    stz.w treasure_scroll_state
    stz.w treasure_scroll_remaining
    stz.w treasure_scroll_direction
    stz.w treasure_transfer_pending
    stz.w treasure_hdma_copy_pending
; Clear HDMA copy flag
    stz.w treasure_scroll_anim_offset
; Clear low byte
    stz.w treasure_scroll_anim_offset + 1
; Clear high byte
; Initialize cursor column to 0 for single-column mode
; This ensures $1b22 is always 0 even if it had a value from previous menu
    stz.w 0x1B22
; cursor_x = 0
; InitMenuRollingBuffer_Impl is called later via patched JSR at $9F7B
    rtl

TreasureMenuExitHook_Impl:
    """Treasure menu teardown: zero HDMA shadow, full 12-byte state, ch6 regs, vanilla $1BC6 flag."""
    php
    sep #0x20
    lda #0x00
    sta.l 0x7E1BAE
; treasure_hdma_enable shadow off
    sta.l 0x7E1BC6
; restore vanilla "in treasure menu" flag (was vanilla `stz $1BC6` at $01:D7E6 before the hook patch)
    sta.l 0x004360
    sta.l 0x004361
    sta.l 0x004362
    sta.l 0x004363
    sta.l 0x004364
; HDMA6 ctrl/dest/src cleared
    rep #0x20
    lda.w #0x0000
    sta.w treasure_rolling
    sta.w treasure_rolling + 2
    sta.w treasure_rolling + 4
    sta.w treasure_rolling + 6
    sta.w treasure_rolling + 8
    sta.w treasure_rolling + 10
    plp
    jsr.l ResetSprites_Trampoline
    rtl
; TreasureSwapRedrawHook_Impl_Body
; Called after item swap to redraw visible items correctly.
; Must render to the correct circular buffer slots based on current buffer_pos.
; Does NOT reset buffer_pos - we stay at the current scroll position.

TreasureSwapRedrawHook_Impl_Body:
    """Treasure profile: post-swap re-render of all 6 slots."""
    engine_swap_redraw(treasure_rolling, 0x1BB7, TREASURE_BUFFER_SLOTS, TREASURE_TOTAL_ITEMS, treasure_ensure_hdma_initialized, treasure_render_item_to_slot, ClearTreasureSlot, update_treasure_scroll_hdma)

; ClearTreasureSlot
; Clears a single inventory slot in the tilemap buffer.
; Input: treasure_rolling_slot_index = slot to clear (0-10)
; Used when item index is out of bounds (>= 48)

ClearTreasureSlot:
    php
    phb
; Set data bank to $7E for WRAM access
    lda #0x7E
    pha
    plb
; Save registers - use 16-bit mode for consistent push/pop
    rep #0x30
; 16-bit A and X/Y
    pha
    phx
    phy
    lda.b 0x29
    pha
; Set $29 = $B600 for BG1 tilemap buffer
    lda.w #0xD600  ; BG3 screen buffer (treasure inventory lives on BG3)
    sta.b 0x29
; Calculate Y = slot_index * 128 + 70
    lda.w treasure_rolling_slot_index
    and.w #0x00FF
    xba
; A = slot * 256
    lsr
; A = slot * 128
    clc
    adc.w #0x0044
; + 68 (64 border + 4 margin)
    tay
; Y = tilemap offset (16-bit)
    sep #0x20
; 8-bit A for tile writes (X/Y stay 16-bit)
; Clear the item name area (12 tiles = 24 bytes)
; Use $FF as blank tile
; Note: X is 16-bit but we only use low byte; loop works correctly
    ldx.w #12
; 12 tiles for item name + quantity (force 16-bit immediate)

_t_clear_slot_loop:
    lda #0xFF
; Blank tile
    sta (0x29), y
    iny
    lda #0x04
; Palette 4 (matches normal items)
    sta (0x29), y
    iny
    dex
    bne _t_clear_slot_loop
; Restore registers - must match push mode
    rep #0x20
; 16-bit A for pop (X/Y already 16-bit)
    pla
    sta.b 0x29
    ply
    plx
    pla
    plb
    plp
    rts
; ClearTreasureTrashArea
; Clears the 2x2 trash can area with blank tiles ($FF).
; Called before drawing normal items to remove any leftover trash icon.
; Input: Y = tilemap offset
;        ($29) = tilemap base
;

ClearTreasureTrashArea:
    phy
; Save Y
; First row: 2 tiles
    lda #0xFF
    sta (0x29), y
    iny
    lda #0x00
    sta (0x29), y
    iny
    lda #0xFF
    sta (0x29), y
    iny
    lda #0x00
    sta (0x29), y
; Second row: Y + 64 from start
    ply
; Restore original Y
    phy
; Save again
    rep #0x20
    tya
    clc
    adc.w #64
    tay
    sep #0x20
    lda #0xFF
    sta (0x29), y
    iny
    lda #0x00
    sta (0x29), y
    iny
    lda #0xFF
    sta (0x29), y
    iny
    lda #0x00
    sta (0x29), y
    ply
; Restore Y
    rts

draw_trash_treasure:


    """
    Draws the trash can 2x2 tile graphic for single-column inventory.
    Input: Y = tilemap offset (from slot calculation)
    ($29) = tilemap base ($B600)
    treasure_rolling_slot_index = current slot
    Tiles: $04 (top-left), $05 (top-right), $06 (bottom-left), $07 (bottom-right)

    Tilemap format: [tile_number, attributes] pairs
    Each row is 64 bytes (32 tiles × 2 bytes)
    """
; Y points to start of item slot area
; Draw 2x2 trash can icon, then clear remaining 10 tiles per row
; Save starting Y for second row calculation
    rep #0x20
; 16-bit for push
    phy
; Save starting Y
    sep #0x20
; 8-bit A
; First row: tiles $04, $05
    lda #0x04
; Tile $04 (top-left of trash can)
    sta (0x29), y
    iny
    lda #0x00
; Attribute: palette 0, no flip
    sta (0x29), y
    iny
    lda #0x05
; Tile $05 (top-right)
    sta (0x29), y
    iny
    lda #0x00
; Attribute
    sta (0x29), y
    iny
; Clear remaining 13 tiles on first row (10 name + colon + 2 digits)
    ldx.w #13

_t_clear_row1:
    lda #0xFF
; Blank tile
    sta (0x29), y
    iny
    lda #0x00
; Attribute
    sta (0x29), y
    iny
    dex
    bne _t_clear_row1
; Restore starting Y and add 64 for second row
    rep #0x20
; 16-bit A
    pla
; Get starting Y
    clc
    adc.w #64
; +64 bytes = next tilemap row
    tay
    sep #0x20
; 8-bit A
; Second row: tiles $06, $07
    lda #0x06
; Tile $06 (bottom-left)
    sta (0x29), y
    iny
    lda #0x00
; Attribute
    sta (0x29), y
    iny
    lda #0x07
; Tile $07 (bottom-right)
    sta (0x29), y
    iny
    lda #0x00
; Attribute
    sta (0x29), y
    iny
; Clear remaining 13 tiles on second row (10 name + colon + 2 digits)
    ldx.w #13

_t_clear_row2:
    lda #0xFF
; Blank tile
    sta (0x29), y
    iny
    lda #0x00
; Attribute
    sta (0x29), y
    iny
    dex
    bne _t_clear_row2
    rts
; NmiDmaTransferCheck_Impl moved to bank $20 (battle/inventory_rolling.s)
; as field_menu_nmi_dma_transfer_check_impl to save space in bank $01
; TreasureCheckAndClearCount_Impl
; Called from DrawItemSlot to check item ID and handle count display.
; - If item ID is 0: writes $FF tiles to clear count, skips to RTS
; - If item ID is $FE: skips to RTS (no clearing needed)
; - Otherwise: returns normally to draw count
;
; Input: $5a = pointer to item data, Y = tilemap offset, $29 = tilemap ptr
; Modifies: A, return address on stack if skipping

TreasureCheckAndClearCount_Impl:
    lda (0x5a)
; Load item ID
    beq _t_clear_count
; If 0, clear and skip
    cmp #0xFE
; Check for special item $FE
    bne _t_normal_return
; If not $FE, return normally to draw count
; Item is $FE - skip count but don't clear
    bra _t_skip_to_rts

_t_clear_count:
; Write $FF (blank tiles) to count area: colon + 2 digits = 3 tiles
    lda #0xFF
; Blank tile
    sta (0x29), y
; Colon position
    iny
    lda.b 0xdb
; Attribute byte
    sta (0x29), y
    iny
    lda #0xFF
    sta (0x29), y
; First digit position
    iny
    lda.b 0xdb
    sta (0x29), y
    iny
    lda #0xFF
    sta (0x29), y
; Second digit position
    iny
    lda.b 0xdb
    sta (0x29), y

_t_skip_to_rts:
; Replace the entire DrawItemSlot return chain so we land on the RTS at $01:A222
; instead of falling back to $A205 (NOPs + colon write).
;
; Stack on entry to Impl (pushed by trampoline + caller, top first):
;   [JSL Impl return: PCL, PCH, PB ($01)]
;   [JSR check_and_clear_count return: PCL, PCH ($A204)]
;   [DrawItemSlot caller's return ...]
;
; Pop both the JSL Impl return (3 bytes) AND the JSR trampoline return (2 bytes),
; then push a synthetic return to $01:A222 (RTS) for our RTL.
    pla  ; PCL of JSL Impl return
    pla  ; PCH of JSL Impl return
    pla  ; PB  of JSL Impl return
    pla  ; PCL of JSR check_and_clear_count return
    pla  ; PCH of JSR check_and_clear_count return
; Stack top now = DrawItemSlot's own caller return.
; Push return for RTL: $01:A221 (so RTL lands PC=$01:A222 = RTS).
    lda #0x01
    pha
    lda #0xA2
    pha
    lda #0x21
    pha

_t_normal_return:
    rtl

treasure_circular_slot_calc:


    """
    Calculate tilemap Y offset using circular buffer position.
    Called from patched code at $A1BA via CircularSlotCalc_ext.

    Input: $5D = game's slot counter (0, 2, 4, 6... incremented by 2 per row)
    Output: Y = tilemap offset for circular buffer slot
    Preserves: 16-bit A mode on exit
    """
    sep #0x20
; 8-bit A
; Check if circular buffer mode is active (HDMA enabled)
    lda.l 0x7E0000 + treasure_hdma_enable
    beq _t_circ_slot_original
; Not active, use original calculation
; Circular buffer Y calculation
; NOTE: Game increments $5D by 2 for each row (0, 2, 4, 6, 8, 10, 12, 14, 16, 18)
; We must divide by 2 first to get the visual slot (0-9)
    lda.b 0x5d
; Load slot counter (0, 2, 4...)
    lsr
; Divide by 2 to get visual slot (0-9)
    clc
    adc.l 0x7E0000 + treasure_rolling_buffer_pos
; Add buffer_pos

_t_circ_slot_mod:
    cmp #TREASURE_BUFFER_SLOTS
; >= 11?
    bcc _t_circ_slot_done
    sec
    sbc #TREASURE_BUFFER_SLOTS
; Subtract 11 to wrap
    bra _t_circ_slot_mod

_t_circ_slot_done:
; A = circular slot (0-10)
    rep #0x20
; 16-bit A
    and.w #0x00FF
; Clear high byte (force 16-bit immediate)
    xba
; A = slot * 256
    lsr
; A = slot * 128
    clc
    adc.w #0x0004
; + 4 (margin only, $29 already includes border)
    tay
; Y = tilemap offset
    rts

_t_circ_slot_original:
; Original game calculation: Y = ($5D / 2) * 128 + 4
    lda.b 0x5d
    lsr
; /2
    rep #0x20
; 16-bit A
    and.w #0x00FF
; Clear high byte (force 16-bit immediate)
    xba
; *256
    lsr
; *128
    clc
    adc.w #0x0004
; +4
    tay
    rts

treasure_circular_slot_calc_ext:
    """Trampoline to call CircularSlotCalc from bank $01 patch at $A1BA"""
    jsr.w treasure_circular_slot_calc
    rtl
}
