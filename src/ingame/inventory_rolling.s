"""
Field-menu inventory rolling-buffer engine (single column, 5 visible rows + 1 prefetch): adapts the battle
approach for the main menu items list with HDMA-based circular scrolling.
"""
; Rolling Buffer Implementation for Main Menu Inventory (Single Column)
;
; HDMA-based circular buffer scrolling for single-column menu inventory.
; Adapts the battle inventory rolling approach for the menu context.
;
; Layout: Single column, 5 visible items, 48 total items
; Uses same HDMA technique as battle inventory for smooth scrolling.
;

; CONSTANTS

; Layout (single column)
MENU_VISIBLE_ITEMS := 10  ; Visible items at once
MENU_BUFFER_SLOTS := 11  ; 11 slots (10 visible + 1 pre-render)
MENU_TOTAL_ITEMS := 48  ; Total inventory items
MENU_SCROLL_LIMIT := 38  ; 48 - 10 = max scroll position

; Pixels per item row
MENU_PIXELS_PER_ROW := 16  ; Pixels per item slot (2 tilemap rows × 8)

; Scroll constants
MENU_SCROLL_WRAP := 176  ; 11 slots × 16 pixels = 176
; MENU_BASE_SCROLL is read from $93 (BG1VOFS shadow) at runtime

; Screen layout - item list position
; The item list doesn't start at scanline 0; there's a window border above it
MENU_ITEM_LIST_Y_START := 48  ; Scanline where item list begins (after border)
MENU_ITEM_LIST_HEIGHT := 160  ; 10 items × 16 pixels = 160 scanlines

; RAM VARIABLES
; Using menu RAM area (unused bytes)

; Field rolling-buffer state RAM block (12 bytes from $1BA8). Each
; named symbol below is just a typed offset into the shared struct
; — keeps existing call sites working byte-for-byte while making the
; layout self-documenting (and trivially relocatable later).
menu_rolling := 0x1BA8
menu_rolling_top_row := menu_rolling + RollingBufferState.top_row
menu_rolling_buffer_pos := menu_rolling + RollingBufferState.buffer_pos
menu_rolling_edge_row := menu_rolling + RollingBufferState.edge_row
menu_rolling_slot_index := menu_rolling + RollingBufferState.slot_index
menu_rolling_base_scroll := menu_rolling + RollingBufferState.base_scroll
menu_hdma_enable := menu_rolling + RollingBufferState.hdma_enable
menu_scroll_state := menu_rolling + RollingBufferState.scroll_state
menu_scroll_remaining := menu_rolling + RollingBufferState.scroll_remaining
menu_scroll_direction := menu_rolling + RollingBufferState.scroll_direction
menu_transfer_pending := menu_rolling + RollingBufferState.transfer_pending
menu_scroll_anim_offset := menu_rolling + RollingBufferState.scroll_anim_offset
menu_hdma_copy_pending := menu_rolling + RollingBufferState.hdma_copy_pending

; Scroll State Constants
SCROLL_STATE_IDLE := 0
SCROLL_STATE_SCROLLING := 1
; Shared held-DOWN cadence (src/lib/rolling_buffer.s).
SCROLL_PIXELS_PER_FRAME := INVENTORY_SCROLL_PIXELS_PER_FRAME
SCROLL_TOTAL_PIXELS := INVENTORY_SCROLL_TOTAL_PIXELS

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

MENU_HDMA_TABLE_ADDR := 0x9800  ; WRAM offset for HDMA table (active - read by HDMA)
MENU_HDMA_TABLE := 0x7E9800  ; Full 24-bit address
MENU_HDMA_SHADOW_ADDR := 0x9840  ; WRAM offset for shadow table (written by game logic)
MENU_HDMA_SHADOW := 0x7E9840  ; Full 24-bit address
MENU_HDMA_TABLE_SIZE := 40  ; Max table size in bytes (13 entries × 3 bytes + padding)
MENU_HDMA_BANK := 0x7E  ; Using WRAM bank

; HDMA registers for channel 5
HDMA5_CTRL := 0x4350  ; DMA control
HDMA5_DEST := 0x4351  ; PPU register
HDMA5_SRC_LO := 0x4352  ; Source address low
HDMA5_SRC_HI := 0x4353  ; Source address high
HDMA5_SRC_BANK := 0x4354  ; Source bank
HDMA5_IND_BANK := 0x4357  ; Indirect bank
HDMAEN := 0x420C  ; HDMA enable register

init_menu_inventory_hdma:
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
    jsr.w update_menu_scroll_hdma

; Configure HDMA channel 5 for DIRECT mode
; Must use long addressing - DB may be $7E but registers are at $00:43xx
    lda #0x02  ; Mode: DIRECT, write 2 bytes to same PPU reg
    sta.l HDMA5_CTRL  ; $004350

    lda #0x0E  ; BG1VOFS register ($210E)
    sta.l HDMA5_DEST  ; $004351

; Source = HDMA table in WRAM at $7E9800
    rep #0x20  ; 16-bit A
    lda.w #MENU_HDMA_TABLE_ADDR  ; $9800
    sta.l HDMA5_SRC_LO  ; $004352-$004353
    sep #0x20  ; 8-bit A
    lda #MENU_HDMA_BANK  ; $7E
    sta.l HDMA5_SRC_BANK  ; $004354

; HDMA channel 5 is now enabled via shadow variable (menu_hdma_enable)
; The NMI hook at $8083 reads the shadow and writes to HDMAEN

    plp
    rts

disable_menu_inventory_hdma:
"""
Disables HDMA channel 5 when leaving item menu
The shadow variable is cleared by menu_exit_hook
"""
    php
    sep #0x20  ; 8-bit A
    ; Shadow variable cleared by caller, NMI will write 0 to HDMAEN
    plp
    rts

init_menu_hdma_table:
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
    sta.l MENU_HDMA_TABLE, x
    inx
    rep #0x20  ; 16-bit A for value
    lda.w menu_rolling_base_scroll
    sta.l MENU_HDMA_TABLE, x
    inx
    inx

; Entries 1-10: Item rows - 16 scanlines each at BASE scroll (initial)
; For init, all rows use BASE (no circular buffer offset yet)
    lda.w #0x0000
    sta.b 0x40  ; Row counter

_init_item_rows:
    sep #0x20  ; 8-bit A for count
    lda #16  ; 16 scanlines per item row
    sta.l MENU_HDMA_TABLE, x
    inx
    rep #0x20  ; 16-bit A for value
    lda.w menu_rolling_base_scroll
    sta.l MENU_HDMA_TABLE, x
    inx
    inx

    inc.b 0x40
    lda.b 0x40

    cmp.w #1  ; 10 rows
    bcc _init_item_rows

; Entry 11: Below items - 16 scanlines at BASE + 16
; Lock to show the bottom window border area
    sep #0x20
    lda #16  ; 16 scanlines
    sta.l MENU_HDMA_TABLE, x
    inx
    rep #0x20
    lda.w menu_rolling_base_scroll
    clc
    adc.w #16  ; Lock at base + 16
    sta.l MENU_HDMA_TABLE, x
    inx
    inx

; End marker
    sep #0x20
    lda #0x00
    sta.l MENU_HDMA_TABLE, x

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

update_menu_scroll_hdma:
"""Build the field-menu HDMA scroll table via the shared engine."""
    ; Build field-menu HDMA scroll table. Inlined from the former
    ; engine_update_scroll_hdma macro for the same reason as treasure.
{
    php
    rep #0x30
    pha
    phx
    phy
    lda.b 0x40
    pha
    lda.b 0x42
    pha
    ldx.w #0x0000
    jsr.w _menu_hdma_header
    stz.b 0x42

_row_loop:
    lda.w menu_rolling + RollingBufferState.buffer_pos
    and.w #0x00FF
    clc
    adc.b 0x42

_mod_loop:
    cmp.w #MENU_BUFFER_SLOTS
    bcc _mod_done
    sec
    sbc.w #MENU_BUFFER_SLOTS
    bra _mod_loop

_mod_done:
    asl
    asl
    asl
    asl
    sta.b 0x40
    lda.b 0x42
    and.w #0x00FF
    asl
    asl
    asl
    asl
    eor.w #0xFFFF
    inc
    clc
    adc.b 0x40
    clc
    adc.w menu_rolling + RollingBufferState.base_scroll
    sta.b 0x40
    sep #0x20
    lda #16
    sta.l MENU_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.b 0x40
    sta.l MENU_HDMA_SHADOW, x
    inx
    inx
    rep #0x20
    inc.b 0x42
    lda.b 0x42
    cmp.w #MENU_VISIBLE_ITEMS
    bcs _row_loop_done
    jmp.w _row_loop

_row_loop_done:
    jsr.w _menu_hdma_footer
    sep #0x20
    lda #0x00
    sta.l MENU_HDMA_SHADOW, x
    jsr.w _menu_hdma_signal
    rep #0x20
    pla
    sta.b 0x42
    pla
    sta.b 0x40
    ply
    plx
    pla
    plp
    rts
}

_menu_hdma_header:
"""Field profile header: 48-scanline border at BASE scroll (one entry)."""
    sep #0x20
    lda #48
    sta.l MENU_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w menu_rolling_base_scroll
    sta.l MENU_HDMA_SHADOW, x
    inx
    inx
    rts

_menu_hdma_footer:
"""Field profile footer: 16 scanlines at BASE+16 (locks bottom-border row 24)."""
    sep #0x20
    lda #16
    sta.l MENU_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w menu_rolling_base_scroll
    clc
    adc.w #16
    sta.l MENU_HDMA_SHADOW, x
    inx
    inx
    rts

_menu_hdma_signal:
"""Field profile NMI signal: set copy-pending shadow flag."""
    sep #0x20
    lda #0x01
    sta.w menu_hdma_copy_pending
    rts

init_menu_rolling_buffer_impl:
"""
Init field rolling buffer (10 visible, lazy 11th slot).

Populates the phase-1 engine config + hook fields so the bank-20
`rolling_engine_*` entries can drive the same instance the macro
expansion below already manages. Engine consumers stay inert until
phase 2 swaps the macro for the JSL path  ; populating now lets the
integration tests assert real config values and gives us a stable
ABI surface to port against.
"""


    php
    rep #0x30  ; M=16, X=16
    sep #0x20  ; M=8 (X stays 16)
    ; visible_rows + slot_height_tiles
    lda.b #MENU_VISIBLE_ITEMS
    sta.l 0x7E0000 + menu_rolling + RollingBufferState.visible_rows
    lda.b #0x02  ; 2 BG rows per slot
    sta.l 0x7E0000 + menu_rolling + RollingBufferState.slot_height_tiles
    ; item_list_ptr = $7E:1440 (vanilla inventory array)
    lda.b #0x40
    sta.l 0x7E0000 + menu_rolling + RollingBufferState.item_list_ptr
    lda.b #0x14
    sta.l 0x7E0000 + menu_rolling + RollingBufferState.item_list_ptr + 1
    lda.b #0x7E
    sta.l 0x7E0000 + menu_rolling + RollingBufferState.item_list_ptr + 2
    ; item_count = 48 (vanilla field inventory)
    lda.b #0x30
    sta.l 0x7E0000 + menu_rolling + RollingBufferState.item_count
    ; hdma_channel = 5 (BG1VOFS HDMA used by field-items rolling buffer)
    lda.b #0x05
    sta.l 0x7E0000 + menu_rolling + RollingBufferState.hdma_channel
    ; vwf_cfg_ptr = $70:7080 (VWF_CONFIG_BASE)
    lda.b #0x80
    sta.l 0x7E0000 + menu_rolling + RollingBufferState.vwf_cfg_ptr
    lda.b #0x70
    sta.l 0x7E0000 + menu_rolling + RollingBufferState.vwf_cfg_ptr + 1
    lda.b #0x70
    sta.l 0x7E0000 + menu_rolling + RollingBufferState.vwf_cfg_ptr + 2
    ; fn_render_slot = menu_fn_render_slot_trampoline (bank-20 RTL wrapper)
    lda.b #menu_fn_render_slot_trampoline & 0xFF
    sta.l 0x7E0000 + menu_rolling + RollingBufferState.fn_render_slot
    lda.b #( menu_fn_render_slot_trampoline >> 8 ) & 0xFF
    sta.l 0x7E0000 + menu_rolling + RollingBufferState.fn_render_slot + 1
    lda.b #( menu_fn_render_slot_trampoline >> 16 ) & 0xFF
    sta.l 0x7E0000 + menu_rolling + RollingBufferState.fn_render_slot + 2
    ; fn_update_hdma = menu_fn_update_hdma_trampoline
    lda.b #menu_fn_update_hdma_trampoline & 0xFF
    sta.l 0x7E0000 + menu_rolling + RollingBufferState.fn_update_hdma
    lda.b #( menu_fn_update_hdma_trampoline >> 8 ) & 0xFF
    sta.l 0x7E0000 + menu_rolling + RollingBufferState.fn_update_hdma + 1
    lda.b #( menu_fn_update_hdma_trampoline >> 16 ) & 0xFF
    sta.l 0x7E0000 + menu_rolling + RollingBufferState.fn_update_hdma + 2
    ; fn_draw_window = menu_fn_draw_window_trampoline
    lda.b #menu_fn_draw_window_trampoline & 0xFF
    sta.l 0x7E0000 + menu_rolling + RollingBufferState.fn_draw_window
    lda.b #( menu_fn_draw_window_trampoline >> 8 ) & 0xFF
    sta.l 0x7E0000 + menu_rolling + RollingBufferState.fn_draw_window + 1
    lda.b #( menu_fn_draw_window_trampoline >> 16 ) & 0xFF
    sta.l 0x7E0000 + menu_rolling + RollingBufferState.fn_draw_window + 2
    lda.b #ROLLING_MENU_ID_FIELD
    sta.l 0x7E0000 + menu_rolling + RollingBufferState.menu_id
    plp
    php
    rep #0x10
    ldx.w #menu_rolling
    jsr.l rolling_engine.rolling_engine_init
    plp
    rtl

menu_fn_render_slot_trampoline:
"""
Bank-20 RTL wrapper around `_menu_render_item_to_slot`.

php/plp keeps M/X flag mutations inside the inner routine from
leaking back to the engine. The engine relies on X-flag = 16
throughout init  ; hooks that toggle X-flag truncate X to its low
byte, which sends subsequent `sta.l abs,X` writes to garbage
addresses.
"""


    php
    jsr.w _menu_render_item_to_slot
    plp
    rtl

menu_fn_update_hdma_trampoline:
"""
Bank-20 RTL wrapper around `ensure_hdma_initialized`.

Named fn_update_hdma in the struct but semantically the
"arm-HDMA-channel + first-frame setup" hook for init. Phase 3 may
split into ensure-once vs per-scroll-update if scroll-tick needs a
distinct entry, but the existing field-menu macro chain treats
ensure as idempotent so reusing it for both is fine.

php/plp guards the engine's X-flag = 16 from inner sep/rep.
"""


    php
    jsr.w ensure_hdma_initialized
    plp
    rtl

menu_fn_draw_window_trampoline:
"""
Bank-20 RTL wrapper around `_menu_draw_inventory_window`.

php/plp protects the engine's X-flag = 16  ; the inner draw does
`rep #$10  ; jsr ; sep #$10` for its own 8-bit-X dance and would
otherwise leave X-flag = 8 when we return, corrupting `,X` indexed
state writes downstream of the hook in the engine_init body.
"""


    php
    jsr.w _menu_draw_inventory_window
    plp
    rtl

_menu_draw_inventory_window:
"""Field menu draws the InventoryWindow ($DCCE) frame on entry."""
    rep #0x10
    ldy.w #0xDCCE
    jsr.l draw_window_trampoline
    sep #0x10
    rts

; _menu_render_item_to_slot
; Renders an item to a specific circular buffer slot in the tilemap.
;
; Input: menu_rolling_edge_row = item index (0-47) for data lookup
;        menu_rolling_slot_index = slot index (0-11) for destination
;
; Strategy: Set up $5d = slot_index (for Y position calculation),
;           $5a = pointer to item data, then call game's DrawItemSlot.

_menu_render_item_to_slot:
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
    lda.w #0xB600
    sta.b 0x29
    sep #0x20  ; 8-bit A

; Calculate item data pointer: $1440 + (edge_row * Item.__size)
    lda.w menu_rolling_edge_row
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
    jsr.l check_can_use_item_trampoline  ; bank-$01 trampoline for original @ $A25D (sets $DB)

; Set $5d = slot_index (for AND #$01 check, but we patched to AND #$00)
    lda.w menu_rolling_slot_index
    sta.b 0x5d

; Calculate Y = slot_index * 128 + 70
; Y is the tilemap offset for this slot
; +64 for window border (1 tile row = 32 tiles × 2 bytes)
; +6 for left margin (3 tiles)
    rep #0x20  ; 16-bit A (X/Y already 16-bit)
    lda.w menu_rolling_slot_index
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
    bne _not_trash_item
    jsr.w draw_trash_single_column  ; Draw trash icon
    bra _skip_draw_item_slot

_not_trash_item:
    ; Clear the 2x2 trash can area first (in case we scrolled from trash position)
    jsr.w _clear_trash_area

; Call DrawItemSlot inner at $A1ED
; Expects: Y = tilemap offset, ($5A) = item pointer, ($29) = tilemap base
    jsr.l draw_item_slot_inner_trampoline  ; bank-$01 trampoline for original @ $A1ED

_skip_draw_item_slot:

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

ensure_hdma_initialized:
"""
Lazy initialization: captures $93 and sets up HDMA on first scroll.
Called from scroll prepare functions.
Checks if base_scroll == 0xFFFF (sentinel) and if so, initializes.
"""

; Check if already initialized (base_scroll != 0xFFFF)
    rep #0x20  ; 16-bit A
    lda.w menu_rolling_base_scroll
    cmp.w #0xFFFF
    bne _hdma_already_init

; Capture base scroll from $0193 (BG1VOFS shadow, menu uses DP=$0100)
; Use long addressing to ensure we read from WRAM
    .db 0xAF  ; LDA.L opcode
    .db 0x93, 0x01, 0x7E  ; $7E0193
    sta.w menu_rolling_base_scroll

; Initialize HDMA channel configuration
    sep #0x20  ; Back to 8-bit for InitMenuInventoryHDMA
    jsr.w init_menu_inventory_hdma

; NOW enable HDMA via shadow variable (channel is configured)
; Force long addressing: STA.L $7E1BAE
    lda #0x20  ; Channel 5
    .db 0x8F  ; STA.L opcode
    .dw menu_hdma_enable  ; $1BAE
    .db 0x7E  ; Bank $7E
    rts

_hdma_already_init:
    sep #0x20  ; Restore 8-bit mode
    rts

; STATE MACHINE ROUTINES (FF6-style non-blocking scroll)

scroll_state_check:
"""
Called at main loop entry ($019FF2) to handle scroll animation frames.
If scrolling is active, processes one frame and skips input handling.

Returns: Carry clear = process input normally
 Carry set = skip input (still scrolling)
"""


    php
    sep #0x20  ; 8-bit A

; Check if we're scrolling
    lda.w menu_scroll_state
    beq _scroll_state_idle

; We're scrolling - process one animation frame
    jsr.l update_scroll_frame_impl

; Check if scroll finished
    lda.w menu_scroll_remaining
    bne _scroll_still_active

; Scroll finished - clean up and return to idle
    jsr.l finish_scroll_impl

_scroll_state_idle:
    plp
    clc  ; Carry clear = process input
    rts

_scroll_still_active:
    plp
    sec  ; Carry set = skip input
    rts

start_scroll_down_impl:
"""Field profile: kick scroll-down state machine via the bank-20 engine."""
    php
    rep #0x10
    lda.l 0x7E1B1A  ; field scroll_pos
    ldx.w #menu_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_down
    plp
    rtl

start_scroll_up_impl:
"""Field profile: kick scroll-up state machine via the bank-20 engine."""
    php
    rep #0x10
    lda.l 0x7E1B1A
    ldx.w #menu_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_up
    plp
    rtl

update_scroll_frame_impl:
"""Field profile: per-frame scroll animation tick via the bank-20 engine."""
    php
    rep #0x10
    ldx.w #menu_rolling
    jsr.l rolling_engine.rolling_engine_update_scroll_frame
    plp
    rtl

finish_scroll_impl:
"""Field profile: end-of-animation cleanup via the bank-20 engine."""
    php
    rep #0x10
    lda.l 0x7E1B1A
    ldx.w #menu_rolling
    jsr.l rolling_engine.rolling_engine_finish_scroll
    plp
    rtl

; Inventory Rolling Buffer Patches - Relocated to Bank $20
; These routines are called via JSL from bank $01 hooks.

.if INVENTORY_ROLLING_BUFFER {
menu_entry_hook_impl:
"""Field-menu entry hook: lazy-init HDMA + force shadow flush before first frame."""
    stz.w 0x1B1F
    lda #0x00
    sta.l 0x7E1BAE
; menu_hdma_enable
    stz.w menu_scroll_state
    stz.w menu_scroll_remaining
    stz.w menu_scroll_direction
    stz.w menu_transfer_pending
    stz.w menu_hdma_copy_pending
; Clear HDMA copy flag
    stz.w menu_scroll_anim_offset
; Clear low byte
    stz.w menu_scroll_anim_offset + 1
; Clear high byte
; Initialize cursor column to 0 for single-column mode
; This ensures $1b22 is always 0 even if it had a value from previous menu
    stz.w 0x1B22
; cursor_x = 0
; InitMenuRollingBuffer_Impl is called later via patched JSR at $9F7B
    rtl

menu_exit_hook_impl:
"""Field menu teardown: zero HDMA shadow, full 12-byte rolling state, ch5 registers."""
    php
    sep #0x20
    lda #0x00
    sta.l 0x7E1BAE
; menu_hdma_enable shadow off so NMI writes 0 to HDMAEN this frame
    sta.l 0x004350
    sta.l 0x004351
    sta.l 0x004352
    sta.l 0x004353
    sta.l 0x004354
; HDMA5 ctrl/dest/src cleared so a stale config can't restart on next mode switch
    rep #0x20
    lda.w #0x0000
    sta.w menu_rolling
    sta.w menu_rolling + 2
    sta.w menu_rolling + 4
    sta.w menu_rolling + 6
    sta.w menu_rolling + 8
    sta.w menu_rolling + 10
    plp
    jsr.l reset_sprites_trampoline
    rtl
; swap_redraw_hook_impl_body
; Called after item swap to redraw visible items correctly.
; Must render to the correct circular buffer slots based on current buffer_pos.
; Does NOT reset buffer_pos - we stay at the current scroll position.

swap_redraw_hook_impl_body:
"""Field profile: post-swap re-render of all 11 slots via the engine."""
    php
    rep #0x10
    lda.l 0x7E1B1A
    ldx.w #menu_rolling
    jsr.l rolling_engine.rolling_engine_swap_redraw
    plp
    rtl


; _clear_inventory_slot
; Clears a single inventory slot in the tilemap buffer.
; Input: menu_rolling_slot_index = slot to clear (0-10)
; Used when item index is out of bounds (>= 48)

_clear_inventory_slot:
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
    lda.w #0xB600
    sta.b 0x29
; Calculate Y = slot_index * 128 + 70
    lda.w menu_rolling_slot_index
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

_clear_slot_loop:
    lda #0xFF
; Blank tile
    sta (0x29), y
    iny
    lda #0x04
; Palette 4 (matches normal items)
    sta (0x29), y
    iny
    dex
    bne _clear_slot_loop
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
; _clear_trash_area
; Clears the 2x2 trash can area with blank tiles ($FF).
; Called before drawing normal items to remove any leftover trash icon.
; Input: Y = tilemap offset
;        ($29) = tilemap base
;

_clear_trash_area:
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

draw_trash_single_column:


"""
Draws the trash can 2x2 tile graphic for single-column inventory.
Input: Y = tilemap offset (from slot calculation)
($29) = tilemap base ($B600)
menu_rolling_slot_index = current slot
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

_clear_row1:
    lda #0xFF
; Blank tile
    sta (0x29), y
    iny
    lda #0x00
; Attribute
    sta (0x29), y
    iny
    dex
    bne _clear_row1
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

_clear_row2:
    lda #0xFF
; Blank tile
    sta (0x29), y
    iny
    lda #0x00
; Attribute
    sta (0x29), y
    iny
    dex
    bne _clear_row2
    rts
; NmiDmaTransferCheck_Impl moved to bank $20 (battle/inventory_rolling.s)
; as field_menu_nmi_dma_transfer_check_impl to save space in bank $01
; check_and_clear_count_impl
; Called from DrawItemSlot to check item ID and handle count display.
; - If item ID is 0: writes $FF tiles to clear count, skips to RTS
; - If item ID is $FE: skips to RTS (no clearing needed)
; - Otherwise: returns normally to draw count
;
; Input: $5a = pointer to item data, Y = tilemap offset, $29 = tilemap ptr
; Modifies: A, return address on stack if skipping

check_and_clear_count_impl:
"""Drop the count column for empty/used slots."""
    lda (0x5a)
; Load item ID
    beq _clear_count
; If 0, clear and skip
    cmp #0xFE
; Check for special item $FE
    bne _normal_return
; If not $FE, return normally to draw count
; Item is $FE - skip count but don't clear
    bra _skip_to_rts

_clear_count:
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

_skip_to_rts:
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

_normal_return:
    rtl

circular_slot_calc:


"""
Calculate tilemap Y offset using circular buffer position.
Called from patched code at $A1BA via CircularSlotCalc_ext.

Input: $5D = game's slot counter (0, 2, 4, 6... incremented by 2 per row)
$5A = src pointer ($1440 = inventory, $FF28 = treasure drops)
Output: Y = tilemap offset for circular buffer slot
Preserves: 16-bit A mode on exit
"""


    sep #0x20
; 8-bit A
; Drops list at $FF28 reuses _a181 but doesn't have any rolling state.
; The original 2-col Y calc collides slots after we forced col=0 globally
; via the `and #$00` patch at DrawItemSlot, so two drops would render at
; the same scanline. Detect drops via $5B high byte and emit a unique
; per-slot Y (slot * 64 + 4) instead of any circular math.
    lda.b 0x5b
    cmp #0xFF
    bne _circ_slot_not_drops
    lda.b 0x5d
    rep #0x20
    and.w #0x00FF
    asl
    asl
    asl
    asl
    asl
    asl  ; * 64. $5D increments by 2 → step = 128 bytes = 2 tilemap rows,
; matching the 16-px-per-item layout original uses for col-0
; drops with BG1VOFS=-32 ($93) pushing them down to scanline 32.
    clc
    adc.w #0x0044  ; col 2 + 1 tilemap row down (+$40) so the first slot
; clears the window header before BG1VOFS shifts it.
    tay
    rts
_circ_slot_not_drops:
; Inventory in treasure context uses treasure_rolling_buffer_pos.
    lda.l 0x7E0000 + 0x9C06  ; treasure_hdma_enable (treasure_rolling + 0x06)
    beq _circ_check_field
    lda.b 0x5d
    lsr
    clc
    adc.l 0x7E0000 + 0x9C01  ; treasure_rolling_buffer_pos (treasure_rolling + 0x01)
_t_circ_mod:
    cmp #6  ; TREASURE_BUFFER_SLOTS
    bcc _t_circ_done
    sec
    sbc #6
    bra _t_circ_mod
_t_circ_done:
    rep #0x20
    and.w #0x00FF
    xba
    lsr
    clc
    adc.w #0x0004
    tay
    rts
_circ_check_field:
; Check if circular buffer mode is active (HDMA enabled)
    lda.l 0x7E0000 + menu_hdma_enable
    beq _circ_slot_original
; Not active, use original calculation
; Circular buffer Y calculation
; NOTE: Game increments $5D by 2 for each row (0, 2, 4, 6, 8, 10, 12, 14, 16, 18)
; We must divide by 2 first to get the visual slot (0-9)
    lda.b 0x5d
; Load slot counter (0, 2, 4...)
    lsr
; Divide by 2 to get visual slot (0-9)
    clc
    adc.l 0x7E0000 + menu_rolling_buffer_pos
; Add buffer_pos

_circ_slot_mod:
    cmp #MENU_BUFFER_SLOTS
; >= 11?
    bcc _circ_slot_done
    sec
    sbc #MENU_BUFFER_SLOTS
; Subtract 11 to wrap
    bra _circ_slot_mod

_circ_slot_done:
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

_circ_slot_original:
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

circular_slot_calc_ext:
"""Trampoline to call CircularSlotCalc from bank $01 patch at $A1BA"""
    jsr.w circular_slot_calc
    rtl
}
