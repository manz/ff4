"""
Treasure inventory rolling-buffer engine (single column, 5 visible, 6 buffer slots, scroll limit 43)  ; cloned
from `inventory_rolling.s` and tuned for the chest UI.
"""
; Treasure inventory rolling buffer (single-column, 5 visible).
;

; Cloned from src/ingame/inventory_rolling.s with:
;   - VISIBLE_ITEMS = 5, BUFFER_SLOTS = 6, SCROLL_LIMIT = 43.
;   - State RAM relocated to $1BD0..$1BDE (original treasure UI owns
;     $1BB3..$1BB7).
;   - Scroll position read from $1BB7 instead of $1B1A.
; HDMA channel 5, BG1 tilemap buffer ($7EB600), and shadow tables
; ($7E9800/$7E9840) are shared with field-menu rolling because the two
; menus are mutually exclusive on screen.

; Layout (single column)
.include "config.i"
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
; original treasure UI bytes ($1BB3..$1BB7) nor field-menu rolling state at
; $1BA8..$1BB6. Both menus are mutually exclusive on screen so the HDMA
; channel + tilemap buffer + shadow table are shared (re-init on entry).

; Treasure rolling-buffer state RAM block (12 bytes from $1BD0). Same
; struct layout as the field-menu state block - fields resolved via
; `RollingBufferState` from src/items.i so any layout change applies
; uniformly across profiles.
; Treasure rolling state moved out of $1B00-$1BFF (which vanilla menu /
; sprite code writes to via indexed STA past $1BEB) to a clean $7E:9C00
; region. Engine path needs the full 35-byte struct (state + config +
; hook far-ptrs) ; the macro path only ever touched the first 12 bytes
; so the original $1BD0 base worked despite vanilla's later collisions.
treasure_rolling := (0x7E9C00 as RollingBufferState)

; Cooldown counter sitting one byte past the shared struct so the
; engine layout stays untouched. Decremented each frame in
; treasure_scroll_state_check ; non-zero means treasure_scroll_*_trigger
; aborts and undoes vanilla's $1BB7 increment, debouncing the
; "hold-DOWN auto-repeat fires every 2 frames" issue that scrolled the
; inventory two items per visible tap.
; RollingBufferState ends at offset 35 inclusive (menu_id byte added
; in the engine port). Bump cooldown past that ; was +35 = collided
; with menu_id and treasure_ensure_hdma_initialized's STZ wiped it,
; sending engine dispatch to the wrong menu's HDMA path.
treasure_scroll_cooldown := treasure_rolling + 36
TREASURE_SCROLL_COOLDOWN_FRAMES := 0x18  ; ~24 frames between scrolls (long enough to outlast a typical button hold)

; Scroll State Constants
TREASURE_SCROLL_STATE_IDLE := 0
TREASURE_SCROLL_STATE_SCROLLING := 1
; Held-DOWN cadence shared with field-menu rolling (see
; src/lib/rolling_buffer.s INVENTORY_SCROLL_*).
TREASURE_SCROLL_PIXELS_PER_FRAME := INVENTORY_SCROLL_PIXELS_PER_FRAME
TREASURE_SCROLL_TOTAL_PIXELS := INVENTORY_SCROLL_TOTAL_PIXELS

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
; $704700+) so they don't fight whatever original treasure may stash in
; the $7E:9800 region used by the field-menu rolling buffer.
; Share field-menu HDMA tables (mutually exclusive on screen).
; Active (read by HDMA channel 5): $7E:9800
; Shadow (written by game): $7E:9840
; NMI hook copies shadow → active during VBlank when `menu_rolling.hdma_copy_pending`
; ($1BB6) is set, gated on `menu_rolling.hdma_enable` ($1BAE) being non-zero.
TREASURE_HDMA_TABLE_ADDR := 0x9800
TREASURE_HDMA_TABLE := 0x7E9800
TREASURE_HDMA_SHADOW_ADDR := 0x9840
TREASURE_HDMA_SHADOW := 0x7E9840
TREASURE_HDMA_TABLE_SIZE := 40
TREASURE_HDMA_BANK := 0x7E
; Shared menu HDMA signals defined in src/items.i - referenced here as
; field_menu_rolling.hdma_enable / field_menu_rolling.hdma_copy_pending.

; HDMA channel 6 for the treasure rolling buffer. Original treasure
; enables HDMAEN=$AD (ch7|ch5|ch3|ch2|ch0); ch2 in particular is an
; INDIRECT mode-3 channel that writes BG3HOFS+BG3VOFS for the drops-
; band parallax. Sharing ch5 fought ch2's per-scanline BG3VOFS writes
; until we masked ch2 entirely, which then dropped the drops parallax
; effect. Move our writes to ch6 (free in original treasure) so ch2
; can keep driving its drops-band scroll untouched.
TREASURE_HDMA6_CTRL := 0x4360
TREASURE_HDMA6_DEST := 0x4361
TREASURE_HDMA6_SRC_LO := 0x4362
TREASURE_HDMA6_SRC_HI := 0x4363
TREASURE_HDMA6_SRC_BANK := 0x4364
TREASURE_HDMA6_IND_BANK := 0x4367
HDMAEN := 0x420C  ; HDMA enable register

.include "../bank20.i"

.alloc treasure_rolling_block in bank20_reloc {
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

    lda #0x12  ; BG3VOFS register ($2112) - treasure inventory is on BG3
    sta.l TREASURE_HDMA6_DEST  ; $004361

; Source = HDMA table in WRAM at $7E9800
    rep #0x20  ; 16-bit A
    lda.w #TREASURE_HDMA_TABLE_ADDR  ; $9800
    sta.l TREASURE_HDMA6_SRC_LO  ; $004362-$004363
    sep #0x20  ; 8-bit A
    lda #TREASURE_HDMA_BANK  ; $7E
    sta.l TREASURE_HDMA6_SRC_BANK  ; $004364

; HDMA channel 5 is now enabled via shadow variable (treasure_rolling.hdma_enable)
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
    lda.w treasure_rolling.base_scroll
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
    lda.w treasure_rolling.base_scroll
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
    lda.w treasure_rolling.base_scroll
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
; Build treasure HDMA scroll table. Inlined from the former
; `engine_update_scroll_hdma` macro since its per-row writes use
; compile-time state_base + hdma_shadow_addr ; routing through the
; bank-20 engine would need menu_id dispatch at every state read,
; which costs more than the modest 80-line duplication across the
; four menus.
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
    jsr.w _treasure_hdma_header
    stz.b 0x42

_row_loop:
    lda.w treasure_rolling + RollingBufferState.buffer_pos
    and.w #0x00FF
    clc
    adc.b 0x42

_mod_loop:
    cmp.w #TREASURE_BUFFER_SLOTS
    bcc _mod_done
    sec
    sbc.w #TREASURE_BUFFER_SLOTS
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
    adc.w treasure_rolling + RollingBufferState.base_scroll
    sta.b 0x40
    sep #0x20
    lda #16
    sta.l TREASURE_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.b 0x40
    sta.l TREASURE_HDMA_SHADOW, x
    inx
    inx
    rep #0x20
    inc.b 0x42
    lda.b 0x42
    cmp.w #TREASURE_VISIBLE_ITEMS
    bcs _row_loop_done
    jmp.w _row_loop

_row_loop_done:
    jsr.w _treasure_hdma_footer
    sep #0x20
    lda #0x00
    sta.l TREASURE_HDMA_SHADOW, x
    jsr.w _treasure_hdma_signal
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

_treasure_hdma_header:
"""Treasure profile header: drops band (120 lines at BASE-16) + inventory border (8 lines at BASE)."""

    sep #0x20
    lda #120
    sta.l TREASURE_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w treasure_rolling.base_scroll
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
    lda.w treasure_rolling.base_scroll
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
    lda.w treasure_rolling.base_scroll
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
    sta.l treasure_rolling.hdma_copy_pending
    sta.l field_menu_rolling.hdma_copy_pending
    rts

; Re-render all BUFFER_SLOTS (6) entries from $1440 using current
; $1BB7 (scroll_pos) and the existing buffer_pos rotation. Called from
; the redraw helper at $01:D933 after a swap completes - the swap
; mutates $1440 in place and original's DrawInventoryList would redraw
; the whole 48-item list, but we only need to refresh the 5 visible
; slots + 1 prefetch. Crucially does NOT touch buffer_pos or any of
; the state-machine bytes, so the cursor/scroll position the user
; was on before the swap survives.

treasure_refresh_slots_impl:
"""Treasure profile: re-render all 6 slots via the bank-20 engine (post-swap redraw at $01:D933)."""
    php
    sep #0x20
    rep #0x10
    lda.l 0x7E0000 + 0x1BB7  ; treasure scroll_pos (shared with vanilla cursor row)
    ldx.w #treasure_rolling
    jsr.l rolling_engine.rolling_engine_refresh_slots
    plp
    rtl

init_treasure_rolling_buffer_impl:
"""
    Init treasure rolling buffer (5 visible + prefetch slot 6) via the
    bank-20 rolling-inventory engine. State + hook far-ptrs live at
    $7E:9C00  ; the engine writes the config block then JSLs into
    `rolling_engine.rolling_engine_init` to zero the scratch, stamp
    `base_scroll = $FFFF`, fire draw_window + ensure_hdma hooks, and
    render `visible_rows` slots.
"""

    php
    rep #0x30
    sep #0x20
    lda.b #TREASURE_BUFFER_SLOTS
    sta.l treasure_rolling + RollingBufferState.visible_rows
    lda.b #0x02
    sta.l treasure_rolling + RollingBufferState.slot_height_tiles
    lda.b #0x40
    sta.l treasure_rolling + RollingBufferState.item_list_ptr
    lda.b #0x14
    sta.l treasure_rolling + RollingBufferState.item_list_ptr + 1
    lda.b #0x7E
    sta.l treasure_rolling + RollingBufferState.item_list_ptr + 2
    lda.b #TREASURE_TOTAL_ITEMS
    sta.l treasure_rolling + RollingBufferState.item_count
    lda.b #0x06
    sta.l treasure_rolling + RollingBufferState.hdma_channel
    lda.b #0x80
    sta.l treasure_rolling + RollingBufferState.vwf_cfg_ptr
    lda.b #0x70
    sta.l treasure_rolling + RollingBufferState.vwf_cfg_ptr + 1
    lda.b #0x70
    sta.l treasure_rolling + RollingBufferState.vwf_cfg_ptr + 2
    lda.b #treasure_fn_render_slot_trampoline & 0xFF
    sta.l treasure_rolling + RollingBufferState.fn_render_slot
    lda.b #( treasure_fn_render_slot_trampoline >> 8 ) & 0xFF
    sta.l treasure_rolling + RollingBufferState.fn_render_slot + 1
    lda.b #( treasure_fn_render_slot_trampoline >> 16 ) & 0xFF
    sta.l treasure_rolling + RollingBufferState.fn_render_slot + 2
    lda.b #treasure_fn_update_hdma_trampoline & 0xFF
    sta.l treasure_rolling + RollingBufferState.fn_update_hdma
    lda.b #( treasure_fn_update_hdma_trampoline >> 8 ) & 0xFF
    sta.l treasure_rolling + RollingBufferState.fn_update_hdma + 1
    lda.b #( treasure_fn_update_hdma_trampoline >> 16 ) & 0xFF
    sta.l treasure_rolling + RollingBufferState.fn_update_hdma + 2
    lda.b #treasure_fn_draw_window_trampoline & 0xFF
    sta.l treasure_rolling + RollingBufferState.fn_draw_window
    lda.b #( treasure_fn_draw_window_trampoline >> 8 ) & 0xFF
    sta.l treasure_rolling + RollingBufferState.fn_draw_window + 1
    lda.b #( treasure_fn_draw_window_trampoline >> 16 ) & 0xFF
    sta.l treasure_rolling + RollingBufferState.fn_draw_window + 2
    lda.b #ROLLING_MENU_ID_TREASURE
    sta.l treasure_rolling + RollingBufferState.menu_id
    plp
    php
    rep #0x10
    ldx.w #treasure_rolling
    jsr.l rolling_engine.rolling_engine_init
    plp
    rtl

treasure_fn_render_slot_trampoline:
"""Bank-20 RTL wrapper around `_treasure_render_item_to_slot`."""
    php
    jsr.w _treasure_render_item_to_slot
    plp
    rtl

treasure_fn_update_hdma_trampoline:
"""Bank-20 RTL wrapper around `treasure_ensure_hdma_initialized`."""
    php
    jsr.w treasure_ensure_hdma_initialized
    plp
    rtl

treasure_fn_draw_window_trampoline:
"""Bank-20 RTL wrapper around `_treasure_draw_inventory_window`."""
    php
    jsr.w _treasure_draw_inventory_window
    plp
    rtl

_treasure_draw_inventory_window:
"""Treasure menu draws a 5-row inventory window so the bottom border lands on the rolling-buffer footer scanlines."""
    rep #0x10
    ldy.w #treasure_inventory_window
    jsr.l draw_window_trampoline
    sep #0x10
    rts

; _treasure_render_item_to_slot
; Renders an item to a specific circular buffer slot in the tilemap.
;
; Input: treasure_rolling.edge_row = item index (0-47) for data lookup
;        treasure_rolling.slot_index = slot index (0-11) for destination
;
; Strategy: Set up $5d = slot_index (for Y position calculation),
;           $5a = pointer to item data, then call game's DrawItemSlot.

_treasure_render_item_to_slot:
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
    lda.w treasure_rolling.edge_row
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
    lda.w treasure_rolling.slot_index
    sta.b 0x5d

; Calculate Y = slot_index * 128 + $44
; Y is the tilemap offset for this slot
; +64 = 1 BG row (top window border at staging row 0)
; +4 for left margin (2 tiles)
    rep #0x20  ; 16-bit A (X/Y already 16-bit)
    lda.w treasure_rolling.slot_index
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
    jsr.w _clear_treasure_trash_area

; Call DrawItemSlot inner at $A1ED
; Expects: Y = tilemap offset, ($5A) = item pointer, ($29) = tilemap base
    jsr.l draw_item_slot_inner_trampoline  ; bank-$01 trampoline for original @ $A1ED

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

; Check if already initialized (base_scroll != 0xFFFF). Use long
; addressing - engine `_engine_call_hook` jumps in with DB unchanged
; from the vanilla caller (DB=$00), so abs reads would hit ROM and the
; gate would always read "not $FFFF" → bail. Hits every DB-relative
; access in this routine.
    rep #0x20  ; 16-bit A
    lda.l treasure_rolling.base_scroll
    cmp.w #0xFFFF
    bne _t_hdma_already_init

; Capture original BG3VOFS shadow ($9F). Original treasure menu uses
; $9F = -120 to position items at screen scanline 120; we mirror that.
    lda.l 0x7E019F
    sta.l treasure_rolling.base_scroll
; Clear the held-DOWN debounce counter ; engine_init_rolling_buffer
; zeros the 12-byte engine struct but cooldown lives one byte past,
; so explicitly nuke it here so the very first scroll trigger fires
; immediately after popup-open.
    sep #0x20
    lda #0x00
    sta.l treasure_scroll_cooldown
    rep #0x20

; Initialize HDMA channel configuration
    sep #0x20  ; Back to 8-bit for InitMenuInventoryHDMA
    jsr.w init_treasure_inventory_hdma

; Enable HDMA via the SHARED field-menu shadow at $1BAE. The existing
; field NMI hook (`field_menu_nmi_dma_transfer_check_impl`) reads this
; byte and copies the HDMA shadow→active table each frame.
; Treasure-only `treasure_rolling.hdma_enable` ($1BD6) is kept as a tracking
; flag but isn't read by the NMI path.
; OR-in ch6 enable bit ($40) so drops's ch4 bit ($10) - set by
; drops_ensure_hdma_initialized at menu open - survives. Plain
; `sta` would clobber the drops enable; same lazy-init order issue
; as treasure_force_hdma_setup which uses $F9 (= ch7|ch6|ch5|ch4|ch3|ch0).
    lda.l field_menu_rolling.hdma_enable
    ora #0x40  ; Channel 6 enable (treasure rolling buffer)
    sta.l field_menu_rolling.hdma_enable
    sta.l treasure_rolling.hdma_enable
; Push the enable straight to HDMAEN ($420C) so the very first frame
; after popup-open has ch6 active. Without this immediate write, the
; field NMI hook only copies $1BAE -> $420C on the NEXT vblank, which
; left the first rendered frame with HDMA off and BG3VOFS at whatever
; the previous menu left in $93 / $9F. Treasure inventory items then
; rendered at the WRONG vertical scanline and looked like garbled
; stride for a frame before settling.
    lda.l 0x00420C
    ora #0x40
    sta.l 0x00420C
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

; Tick cooldown counter so the next held-DOWN scroll is debounced.
    lda.w treasure_scroll_cooldown
    beq _t_scroll_cd_done
    dec.w treasure_scroll_cooldown

_t_scroll_cd_done:
; Check if we're scrolling
    lda.w treasure_rolling.scroll_state
    beq _t_scroll_state_idle

; We're scrolling - process one animation frame
    jsr.l treasure_update_scroll_frame_impl

; Check if scroll finished
    lda.w treasure_rolling.scroll_remaining
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
"""Treasure profile: kick scroll-down state machine via the engine."""
    php
    rep #0x10
    lda.l 0x7E1BB7  ; treasure scroll_pos (shared with vanilla cursor)
    ldx.w #treasure_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_down
    plp
    rtl

treasure_start_scroll_up_impl:
"""Treasure profile: kick scroll-up state machine via the engine."""
    php
    rep #0x10
    lda.l 0x7E1BB7
    ldx.w #treasure_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_up
    plp
    rtl

treasure_update_scroll_frame_impl:
"""Treasure profile: per-frame scroll animation tick."""
    php
    rep #0x10
    ldx.w #treasure_rolling
    jsr.l rolling_engine.rolling_engine_update_scroll_frame
    plp
    rtl

treasure_finish_scroll_impl:
"""Treasure profile: end-of-animation cleanup via the bank-20 engine."""
    php
    rep #0x10
    lda.l 0x7E1BB7
    ldx.w #treasure_rolling
    jsr.l rolling_engine.rolling_engine_finish_scroll
    plp
    rtl

; Inventory Rolling Buffer Patches - Relocated to Bank $20
; These routines are called via JSL from bank $01 hooks.

    .if INVENTORY_ROLLING_BUFFER {
treasure_menu_entry_hook_impl:
"""Treasure profile: menu-entry implementation (HDMA capture + flush)."""
    stz.w 0x1B1F
    lda #0x00
    sta.l field_menu_rolling.hdma_enable
; treasure_rolling.hdma_enable
    stz.w treasure_rolling.scroll_state
    stz.w treasure_rolling.scroll_remaining
    stz.w treasure_rolling.scroll_direction
    stz.w treasure_rolling.transfer_pending
    stz.w treasure_rolling.hdma_copy_pending
; Clear HDMA copy flag
    stz.w treasure_rolling.scroll_anim_offset
; Clear low byte
    stz.w treasure_rolling.scroll_anim_offset + 1
; Clear high byte
; Initialize cursor column to 0 for single-column mode
; This ensures $1b22 is always 0 even if it had a value from previous menu
    stz.w 0x1B22
; cursor_x = 0
; InitMenuRollingBuffer_Impl is called later via patched JSR at $9F7B
    rtl

treasure_menu_exit_hook_impl:
"""Treasure menu teardown: zero HDMA shadow, full 12-byte state, ch6 regs, original $1BC6 flag."""
    php
    sep #0x20
    lda #0x00
    sta.l field_menu_rolling.hdma_enable
; treasure_rolling.hdma_enable shadow off
    sta.l 0x7E1BC6
; restore original "in treasure menu" flag (was original `stz $1BC6` at $01:D7E6 before the hook patch)
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
    jsr.l reset_sprites_trampoline
    rtl
; treasure_swap_redraw_hook_impl_body
; Called after item swap to redraw visible items correctly.
; Must render to the correct circular buffer slots based on current buffer_pos.
; Does NOT reset buffer_pos - we stay at the current scroll position.

treasure_swap_redraw_hook_impl_body:
"""Treasure profile: post-swap re-render of all 6 slots via the engine."""
    php
    rep #0x10
    lda.l 0x7E1BB7
    ldx.w #treasure_rolling
    jsr.l rolling_engine.rolling_engine_swap_redraw
    plp
    rtl

; _clear_treasure_slot
; Clears a single inventory slot in the tilemap buffer.
; Input: treasure_rolling.slot_index = slot to clear (0-10)
; Used when item index is out of bounds (>= 48)

_clear_treasure_slot:
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
    lda.w treasure_rolling.slot_index
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
; _clear_treasure_trash_area
; Clears the 2x2 trash can area with blank tiles ($FF).
; Called before drawing normal items to remove any leftover trash icon.
; Input: Y = tilemap offset
;        ($29) = tilemap base
;

_clear_treasure_trash_area:
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
    treasure_rolling.slot_index = current slot
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
; treasure_check_and_clear_count_impl
; Called from DrawItemSlot to check item ID and handle count display.
; - If item ID is 0: writes $FF tiles to clear count, skips to RTS
; - If item ID is $FE: skips to RTS (no clearing needed)
; - Otherwise: returns normally to draw count
;
; Input: $5a = pointer to item data, Y = tilemap offset, $29 = tilemap ptr
; Modifies: A, return address on stack if skipping

treasure_check_and_clear_count_impl:
"""Treasure profile: drop the count column for empty/used slots (impl)."""
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
    lda.l treasure_rolling.hdma_enable
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
    adc.l treasure_rolling.buffer_pos
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
}

