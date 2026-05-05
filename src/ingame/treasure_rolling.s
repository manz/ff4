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

treasure_rolling_top_row := 0x1BD0
treasure_rolling_buffer_pos := 0x1BD1
treasure_rolling_edge_row := 0x1BD2
treasure_rolling_slot_index := 0x1BD3
treasure_rolling_base_scroll := 0x1BD4  ; 16-bit
treasure_hdma_enable := 0x1BD6

treasure_scroll_state := 0x1BD8
treasure_scroll_remaining := 0x1BD9
treasure_scroll_direction := 0x1BDA
treasure_transfer_pending := 0x1BDB
treasure_scroll_anim_offset := 0x1BDC  ; 16-bit
treasure_hdma_copy_pending := 0x1BDE

; Scroll State Constants
TREASURE_SCROLL_STATE_IDLE := 0
TREASURE_SCROLL_STATE_SCROLLING := 1
TREASURE_SCROLL_PIXELS_PER_FRAME := 8  ; 8 pixels/frame = 2 frames per scroll
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
"""
Rebuilds the HDMA table in the SHADOW buffer for current scroll state.
The NMI handler copies shadow -> active during vblank for flicker-free updates.


For each visible row, calculates:
vram_slot = (buffer_pos + row) mod TREASURE_BUFFER_SLOTS
scroll = BASE + (vram_slot * 16) - (row * 16) + anim_offset

Direct mode table format: count, lo, hi per entry
"""
    ; Save processor status and registers
    php
    rep #0x30  ; 16-bit A, X, Y
    pha
    phx
    phy

; Save DP bytes we'll use as scratch (16-bit mode writes 2 bytes each)
    lda.b 0x40
    pha  ; Save $40-$41 (scroll value / vram_offset)
    lda.b 0x42
    pha  ; Save $42-$43 (row counter)

; X = table write offset
    ldx.w #0x0000

; Entry 0: header band — 128 scanlines at BASE scroll. Vanilla treasure
; window border occupies tilemap row 0 (8 px); items start at tilemap
; row 8. With BASE = $9F = -120 (= +392 mod 512 plane), the window
; border at tilemap row 0 lands at screen scanline 120; items at tilemap
; row 8 land at scanline 128. So header covers scanlines 0..127 leaving
; item bands to start at scanline 128 (= top of slot 0).
    sep #0x20  ; 8-bit A for count byte
    lda #128
    sta.l TREASURE_HDMA_SHADOW, x
    inx
    rep #0x20  ; 16-bit A for value
    lda.w treasure_rolling_base_scroll
    sta.l TREASURE_HDMA_SHADOW, x
    inx
    inx

; Entries 1-10: Item rows with circular buffer scroll values
    stz.b 0x42  ; Row counter (0-9)

_t_update_hdma_row_loop:
    ; Calculate vram_slot = (buffer_pos + row) % TREASURE_BUFFER_SLOTS
    lda.w treasure_rolling_buffer_pos
    and.w #0x00FF
    clc
    adc.b 0x42  ; + row number

_t_update_hdma_mod:
    cmp.w #TREASURE_BUFFER_SLOTS  ; >= 11?
    bcc _t_update_hdma_mod_done
    sec
    sbc.w #TREASURE_BUFFER_SLOTS
    bra _t_update_hdma_mod

_t_update_hdma_mod_done:
    ; A = vram_slot (0-10)

; Calculate vram_slot * 16 (pixels per slot in VRAM)
    asl
    asl
    asl
    asl  ; A = vram_slot * 16
    sta.b 0x40  ; Save vram_offset

; Calculate row * 16 (screen pixels per item row)
    lda.b 0x42
    and.w #0x00FF
    asl
    asl
    asl
    asl  ; row * 16 = scanline_offset

; scroll = BASE + vram_offset - scanline_offset + anim_offset
; Negate scanline_offset: EOR #$FFFF, INC
    eor.w #0xFFFF
    inc  ; A = -scanline_offset
    clc
    adc.b 0x40  ; + vram_offset
    clc
    adc.w treasure_rolling_base_scroll  ; + BASE
    ; DISABLED: Animation offset causes seam flicker at buffer wrap-around.
    ; When vram_slot=0 (seam row), scroll goes negative and lands in border
    ; zone [176-255], showing window border instead of item content.
    ; With 11 slots (176 pixels) in a 256-pixel tilemap, the math doesn't
    ; wrap cleanly like FF6's power-of-2 approach. Disabling gives instant
    ; scroll instead of smooth animation, but eliminates the visual glitch.
    ; TODO: Fix by clamping seam scroll or using content duplication.
.if 0 {
    clc
    adc.w treasure_scroll_anim_offset
; + animation offset
}
sta.b 0x40  ; scroll value for this row

_t_write_normal_entry:
    ; Write entry: count=16, value=scroll
    sep #0x20  ; 8-bit for count
    lda #16  ; 16 scanlines per item row
    sta.l TREASURE_HDMA_SHADOW, x
    inx
    rep #0x20  ; 16-bit for value
    lda.b 0x40
    sta.l TREASURE_HDMA_SHADOW, x
    inx
    inx

_t_row_done:
    ; Next row
    rep #0x20
    inc.b 0x42
    lda.b 0x42
    cmp.w #TREASURE_VISIBLE_ITEMS  ; 5 visible item rows
    bcs _t_row_loop_done
    jmp.w _t_update_hdma_row_loop

_t_row_loop_done:

; Footer band — 16 scanlines pointing past the slot rows so the
; prefetch slot stays hidden. With BASE=$FF88 (=-120), scanline 208
; reads tilemap row 11 with VOFS=BASE+16=$FF98 (=-104) → vy=104 =
; tilemap row 13 = blank (the rolling buffer only fills rows 1..12).
; Slot 5 at vy=96..103 stays just above the footer band.
    sep #0x20
    lda #16
    sta.l TREASURE_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w treasure_rolling_base_scroll
    clc
    adc.w #16  ; BASE+16 → footer scanlines hit blank rows past slot 5
    sta.l TREASURE_HDMA_SHADOW, x
    inx
    inx

; End marker
    sep #0x20
    lda #0x00
    sta.l TREASURE_HDMA_SHADOW, x

; Signal NMI to copy shadow -> active table. NMI reads $1BB6
; (field-shared copy-pending flag). Vanilla treasure col-toggle at $1BB6
; is held at 0 by our patches, so reusing it is safe.
    lda #0x01
    sta.w treasure_hdma_copy_pending
    sta.w treasure_hdma_copy_pending_shared

; Restore DP bytes (reverse order)
    rep #0x20
    pla
    sta.b 0x42  ; Restore $42-$43
    pla
    sta.b 0x40  ; Restore $40-$41

; Restore registers (in 16-bit mode to match push)
    ply
    plx
    pla
    plp  ; Restore original processor status
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
    php
    rep #0x10  ; 16-bit X/Y for treasure_render_item_to_slot
    sep #0x20  ; 8-bit A
    lda #0
    sta.b 0x46  ; loop counter K

_t_refresh_loop:
    ; item_index = scroll_pos + K
    lda.w 0x1BB7
    clc
    adc.b 0x46
    sta.w treasure_rolling_edge_row
    ; slot = (buffer_pos + K) mod BUFFER_SLOTS
    lda.w treasure_rolling_buffer_pos
    clc
    adc.b 0x46

_t_refresh_mod:
    cmp #TREASURE_BUFFER_SLOTS
    bcc _t_refresh_mod_done
    sec
    sbc #TREASURE_BUFFER_SLOTS
    bra _t_refresh_mod

_t_refresh_mod_done:
    sta.w treasure_rolling_slot_index
    jsr.w treasure_render_item_to_slot
    inc.b 0x46
    lda.b 0x46
    cmp #TREASURE_BUFFER_SLOTS
    bne _t_refresh_loop
    ; Push the freshly populated BG3 buffer to VRAM next vblank.
    lda #1
    sta.w treasure_transfer_pending
    plp
    rtl

init_treasure_rolling_buffer_impl:
"""
Called when inventory menu opens
Initializes the circular buffer state and sets up HDMA
"""
    php  ; Save processor state at entry
    pha  ; Save A

; Save DP byte we'll use as scratch
    lda.b 0x46
    pha  ; Save $46

; Draw the inventory window border (replaces the DrawWindow vanilla
; DrawInventoryList would have drawn before iterating items).
    rep #0x10  ; 16-bit X/Y for ldy.w
    ldy.w #0xDCCE  ; InventoryWindow (def_window 1, 0, 27, 48)
    jsr.l DrawWindow_Trampoline
    sep #0x10  ; Back to 8-bit X/Y

; Initialize buffer + state-machine bytes (stz works in any mode).
    stz.w treasure_rolling_top_row
    stz.w treasure_rolling_buffer_pos
    stz.w treasure_scroll_state
    stz.w treasure_scroll_remaining
    stz.w treasure_scroll_direction
    stz.w treasure_transfer_pending
    stz.w treasure_scroll_anim_offset
    stz.w treasure_scroll_anim_offset + 1
    stz.w treasure_hdma_copy_pending

; Mark base scroll as uninitialized (0xFFFF = sentinel)
; Will be captured from $93 on first scroll when it's valid
    rep #0x20  ; 16-bit A
    lda.w #0xFFFF  ; Sentinel: "not yet captured"
    sta.w treasure_rolling_base_scroll
    sep #0x20

; Capture $93 + enable HDMA shadow now. Treasure's redraw helper at
; $01:D929 fires after the window+sprites have been drawn, so the
; vanilla $93 shadow is valid at this point — no need to defer to
; first scroll like the field-menu init does.
    sep #0x20
    jsr.w treasure_ensure_hdma_initialized

; Render initial 12 slots (items 0-11) to buffer
    sep #0x20  ; 8-bit A - CRITICAL!
    lda #0x00
    sta.b 0x46  ; Loop counter

_t_menu_init_row_loop:
    lda.b 0x46
    sta.w treasure_rolling_edge_row
    sta.w treasure_rolling_slot_index

; Render item to circular buffer slot
    jsr.w treasure_render_item_to_slot

    inc.b 0x46
    lda.b 0x46
    cmp #TREASURE_BUFFER_SLOTS  ; Render 6 items explicitly (single-col, 5 visible + 1 pre-render)
    bne _t_menu_init_row_loop

; Restore DP byte
    pla
    sta.b 0x46  ; Restore $46

    pla  ; Restore A
    plp  ; Restore original processor state
    rtl


treasure_scroll_down_prepare:
"""
Called before scroll down animation
Pre-renders the bottom edge item
"""
    php
    sep #0x20  ; 8-bit A - CRITICAL!

; Lazy init: if base_scroll == 0xFFFF, capture $93 and init HDMA
    jsr.w treasure_ensure_hdma_initialized

; Check if we can scroll (scroll_pos < SCROLL_LIMIT)
    lda.w 0x1BB7  ; Current scroll position
    cmp #TREASURE_SCROLL_LIMIT
    bcs _t_menu_scroll_down_done  ; At bottom

; Calculate new bottom item = scroll_pos + VISIBLE_ITEMS
    clc
    adc #TREASURE_VISIBLE_ITEMS
    sta.w treasure_rolling_edge_row

; The slot scrolling OFF the top (buffer_pos) will be reused for the new bottom item
; Render to buffer_pos BEFORE incrementing
    lda.w treasure_rolling_buffer_pos
    sta.w treasure_rolling_slot_index

; Render item to the slot that's scrolling off
    jsr.w treasure_render_item_to_slot

; NOW advance buffer position (the slot we just wrote to is now the "bottom")
    inc.w treasure_rolling_buffer_pos
    lda.w treasure_rolling_buffer_pos
    cmp #TREASURE_BUFFER_SLOTS
    bcc _t_menu_buf_pos_ok
    stz.w treasure_rolling_buffer_pos

_t_menu_buf_pos_ok:

; Update HDMA table for new buffer position
    jsr.w update_treasure_scroll_hdma

_t_menu_scroll_down_done:
    plp
    rts

; treasure_scroll_up_prepare
; Called before scroll up animation
; Pre-renders the top edge item

treasure_scroll_up_prepare:
    php
    sep #0x20  ; 8-bit A - CRITICAL!

; Lazy init: if base_scroll == 0xFFFF, capture $93 and init HDMA
    jsr.w treasure_ensure_hdma_initialized

; Note: The game already validated we can scroll before calling the hook.
; The hook already decremented 0x1BB7, so we always need to update buffer_pos.

; Decrement buffer position first
    lda.w treasure_rolling_buffer_pos
    beq _t_menu_wrap_up
    dec
    bra _t_menu_wrap_up_done

_t_menu_wrap_up:
    lda #TREASURE_BUFFER_SLOTS - 1

_t_menu_wrap_up_done:
    sta.w treasure_rolling_buffer_pos
    sta.w treasure_rolling_slot_index

; Calculate new top item = scroll_pos (already decremented by hook)
; This is the item that should appear at the top after scrolling
    lda.w 0x1BB7
    sta.w treasure_rolling_edge_row

; Render item to the new top slot
    jsr.w treasure_render_item_to_slot

; Update HDMA table for new buffer position
    jsr.w update_treasure_scroll_hdma

_t_menu_scroll_up_done:
    plp
    rts

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

; Calculate item data pointer: $1440 + (edge_row * 2)
    lda.w treasure_rolling_edge_row
    asl  ; * 2 (2 bytes per item)
    clc
    adc #0x40  ; Low byte of $1440
    sta.b 0x5a
    lda #0x14  ; High byte of $1440
    adc #0x00  ; Add carry
    sta.b 0x5b

; Load item ID and count from ($5A)
; Use long addressing to read directly from WRAM
    rep #0x20  ; 16-bit A (X/Y already 16-bit from entry)
    lda.b 0x5a  ; Get pointer value ($1440 + item*2)
    tax  ; X = address of item data (16-bit)
    sep #0x20  ; 8-bit A
    lda.l 0x7E0000, x  ; Load item ID from WRAM
    pha  ; Save item ID for CheckCanUseItem
    inx
    lda.l 0x7E0000, x  ; Load count from WRAM
    sta.b 0x5C  ; Store in $5C

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
"""
Initiates a non-blocking scroll down animation.
Called when user presses down and we need to scroll the list.
Sets up state machine and returns immediately (no blocking loop).
"""
    php
    sep #0x20  ; 8-bit A

; Lazy init HDMA if needed
    jsr.w treasure_ensure_hdma_initialized

; Advance buffer position FIRST
    inc.w treasure_rolling_buffer_pos
    lda.w treasure_rolling_buffer_pos
    cmp #TREASURE_BUFFER_SLOTS
    bcc _t_start_down_buf_ok
    stz.w treasure_rolling_buffer_pos
    lda #0x00  ; A = 0 after wrap

_t_start_down_buf_ok:

; Pre-render the item that's about to appear at bottom
; Bottom slot = (buffer_pos + VISIBLE_ITEMS - 1) % BUFFER_SLOTS
    clc
    adc #TREASURE_VISIBLE_ITEMS - 1  ; A has buffer_pos

_t_start_down_mod:
    cmp #TREASURE_BUFFER_SLOTS
    bcc _t_start_down_mod_done
    sec
    sbc #TREASURE_BUFFER_SLOTS
    bra _t_start_down_mod

_t_start_down_mod_done:
    sta.w treasure_rolling_slot_index

; Item = scroll_pos + VISIBLE_ITEMS - 1 (scroll_pos already incremented)
    lda.w 0x1BB7
    clc
    adc #TREASURE_VISIBLE_ITEMS - 1
    sta.w treasure_rolling_edge_row
    jsr.w treasure_render_item_to_slot

; Set up scroll state machine
    lda #TREASURE_SCROLL_STATE_SCROLLING
    sta.w treasure_scroll_state
    lda #TREASURE_SCROLL_TOTAL_PIXELS
    sta.w treasure_scroll_remaining
    lda #TREASURE_SCROLL_PIXELS_PER_FRAME
    sta.w treasure_scroll_direction  ; +2 for down

; Initialize animation offset to -16 (compensate for buffer_pos already incremented)
; Animation goes from -16 towards 0 (adding +2 each frame)
    rep #0x20
    lda.w #0xFFF0  ; -16 in two's complement
    sta.w treasure_scroll_anim_offset
    sep #0x20

; Request DMA transfer for the new row
    lda #0x01
    sta.w treasure_transfer_pending

; Update HDMA table for new buffer position
    jsr.w update_treasure_scroll_hdma

    plp
    rtl


treasure_start_scroll_up_impl:
"""
Initiates a non-blocking scroll up animation.
Called when user presses up and we need to scroll the list.
"""
    php
    sep #0x20  ; 8-bit A

; Lazy init HDMA if needed
    jsr.w treasure_ensure_hdma_initialized

; Decrement buffer position FIRST
    lda.w treasure_rolling_buffer_pos
    beq _t_start_up_wrap
    dec
    bra _t_start_up_wrap_done

_t_start_up_wrap:
    lda #TREASURE_BUFFER_SLOTS - 1

_t_start_up_wrap_done:
    sta.w treasure_rolling_buffer_pos
    sta.w treasure_rolling_slot_index  ; Render to this slot

; Pre-render the item that's about to appear at top
; scroll_pos was already decremented by trigger, so it IS the top item
    lda.w 0x1BB7  ; scroll_pos (already decremented)
    sta.w treasure_rolling_edge_row
    jsr.w treasure_render_item_to_slot

; Set up scroll state machine
    lda #TREASURE_SCROLL_STATE_SCROLLING
    sta.w treasure_scroll_state
    lda #TREASURE_SCROLL_TOTAL_PIXELS
    sta.w treasure_scroll_remaining
    lda #0xFE  ; -2 (two's complement) for up
    sta.w treasure_scroll_direction

; Initialize animation offset to +16 (compensate for buffer_pos already decremented)
; Animation goes from +16 towards 0 (subtracting 2 each frame)
    rep #0x20
    lda.w #0x0010  ; +16
    sta.w treasure_scroll_anim_offset
    sep #0x20

; Request DMA transfer
    lda #0x01
    sta.w treasure_transfer_pending

; Update HDMA table
    jsr.w update_treasure_scroll_hdma

    plp
    rtl


treasure_update_scroll_frame_impl:
"""
Called each frame during scroll animation.
Updates animation offset, HDMA table, and cursor sprite position.
NOTE: Does NOT modify $93 - all scrolling is handled via HDMA.
"""
    php

; Update animation offset (NOT $93 - HDMA handles all scroll)
; Offset increases each frame based on direction
    rep #0x20  ; 16-bit A
    lda.w treasure_scroll_anim_offset
    sep #0x20
    lda.w treasure_scroll_direction
    bpl _t_scroll_frame_positive
    ; Negative direction (scrolling up) - decrease offset
    rep #0x20
    lda.w treasure_scroll_anim_offset
    sec
    sbc.w #TREASURE_SCROLL_PIXELS_PER_FRAME
    sta.w treasure_scroll_anim_offset
    bra _t_scroll_frame_update_cursor

_t_scroll_frame_positive:
    ; Positive direction (scrolling down) - increase offset
    rep #0x20
    lda.w treasure_scroll_anim_offset
    clc
    adc.w #TREASURE_SCROLL_PIXELS_PER_FRAME
    sta.w treasure_scroll_anim_offset

_t_scroll_frame_update_cursor:
    sep #0x20  ; 8-bit A

; Update cursor sprite position if in "second item" mode ($1B19 != 0)
    lda.w 0x1B19
    beq _t_scroll_frame_no_cursor

; Move cursor sprite to match scroll
; $0311 is cursor Y position in OAM
    lda.w treasure_scroll_direction
    bpl _t_scroll_cursor_down
    ; Scrolling up - cursor moves down on screen
    inc.w 0x0311
    inc.w 0x0311
    bra _t_scroll_frame_no_cursor

_t_scroll_cursor_down:
    ; Scrolling down - cursor moves up on screen
    dec.w 0x0311
    dec.w 0x0311

_t_scroll_frame_no_cursor:
    ; Decrement remaining pixels
    lda.w treasure_scroll_remaining
    sec
    sbc #TREASURE_SCROLL_PIXELS_PER_FRAME
    sta.w treasure_scroll_remaining

; Update HDMA table (smooth scrolling)
    jsr.w update_treasure_scroll_hdma

; Request vblank operations
    jsr.l TfrSpritesVblank_Trampoline  ; bank-$01 trampoline for vanilla @ $824F
    jsr.l TfrBG2TilesVblank_Trampoline  ; bank-$01 trampoline for vanilla @ $9420

    plp
    rtl


treasure_finish_scroll_impl:
"""
Called when scroll animation completes.
Resets state machine and calls post-scroll cleanup routines.
"""
    php
    sep #0x20

; Check scroll direction to know which item to pre-render
    lda.w treasure_scroll_direction
    bmi _t_finish_scroll_was_up

; === Scrolled DOWN - pre-render for NEXT scroll down ===
; The slot that went off-screen (above) will appear at bottom on next scroll
; Slot = (buffer_pos - 1 + BUFFER_SLOTS) % BUFFER_SLOTS
    lda.w treasure_rolling_buffer_pos
    beq _t_finish_down_wrap
    dec
    bra _t_finish_down_slot_ok

_t_finish_down_wrap:
    lda #TREASURE_BUFFER_SLOTS - 1

_t_finish_down_slot_ok:
    sta.w treasure_rolling_slot_index

; Item = scroll_pos + VISIBLE_ITEMS
    lda.w 0x1BB7  ; Current scroll position
    clc
    adc #TREASURE_VISIBLE_ITEMS
    cmp #TREASURE_TOTAL_ITEMS  ; Don't render past end
    bcs _t_finish_skip_render
    sta.w treasure_rolling_edge_row
    jsr.w treasure_render_item_to_slot
    ; Request DMA transfer to VRAM
    lda #0x01
    sta.w treasure_transfer_pending
    bra _t_finish_skip_render

_t_finish_scroll_was_up:
    ; === Scrolled UP - pre-render for NEXT scroll up ===
    ; The slot that went off-screen (below) will appear at top on next scroll
    ; Slot = (buffer_pos + VISIBLE_ITEMS) % BUFFER_SLOTS
    lda.w treasure_rolling_buffer_pos
    clc
    adc #TREASURE_VISIBLE_ITEMS

_t_finish_up_mod:
    cmp #TREASURE_BUFFER_SLOTS
    bcc _t_finish_up_slot_ok
    sec
    sbc #TREASURE_BUFFER_SLOTS
    bra _t_finish_up_mod

_t_finish_up_slot_ok:
    sta.w treasure_rolling_slot_index

; Item = scroll_pos - 1 (only if scroll_pos > 0)
    lda.w 0x1BB7
    beq _t_finish_skip_render  ; At top, no need to pre-render
    dec
    sta.w treasure_rolling_edge_row
    jsr.w treasure_render_item_to_slot
    ; Request DMA transfer to VRAM
    lda #0x01
    sta.w treasure_transfer_pending

_t_finish_skip_render:
    ; Reset scroll state to idle
    stz.w treasure_scroll_state

; Reset animation offset
    rep #0x20
    stz.w treasure_scroll_anim_offset
    sep #0x20

; Update HDMA table with final positions (offset = 0)
    jsr.w update_treasure_scroll_hdma

; Call original post-scroll cleanup routines
    jsr.l DrawItemCursors_Trampoline  ; bank-$01 trampoline for vanilla @ $A105
    jsr.l UpdateCtrlAfterScroll_Trampoline  ; bank-$01 trampoline for vanilla @ $82A5

    plp
    rtl

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
    lda #0x00
    sta.l 0x7E1BAE
; treasure_hdma_enable
    stz.w treasure_scroll_state
    jsr.w disable_treasure_inventory_hdma
    jsr.l ResetSprites_Trampoline
; bank-$01 trampoline for vanilla @ $8D6A
    rtl
; TreasureSwapRedrawHook_Impl_Body
; Called after item swap to redraw visible items correctly.
; Must render to the correct circular buffer slots based on current buffer_pos.
; Does NOT reset buffer_pos - we stay at the current scroll position.

TreasureSwapRedrawHook_Impl_Body:
    php
    sep #0x20
; 8-bit A
; CRITICAL: Ensure HDMA is initialized before using scroll values
; If swap happens before any scrolling, base_scroll would be 0xFFFF
    jsr.w treasure_ensure_hdma_initialized
; CRITICAL: Reset scroll state to prevent re-rendering after swap
; If scroll was in progress, FinishScroll_Impl would re-render items
    stz.w treasure_scroll_state
    stz.w treasure_scroll_remaining
; Ensure animation offset is zero (prevent visual shift)
    stz.w treasure_scroll_anim_offset
    stz.w treasure_scroll_anim_offset + 1
; Save DP byte for loop counter
    lda.b 0x46
    pha
; Re-render all visible items to correct circular buffer slots
; Item index = scroll_pos + row, Slot = (buffer_pos + row) % BUFFER_SLOTS
    lda #0x00
    sta.b 0x46
; Row counter (0-10)

_t_swap_redraw_loop:
; Calculate slot = (buffer_pos + row) % BUFFER_SLOTS first
; We need slot_index for both rendering and clearing
    lda.w treasure_rolling_buffer_pos
    clc
    adc.b 0x46
; + row

_t_swap_redraw_mod:
    cmp #TREASURE_BUFFER_SLOTS
    bcc _t_swap_redraw_mod_done
    sec
    sbc #TREASURE_BUFFER_SLOTS
    bra _t_swap_redraw_mod

_t_swap_redraw_mod_done:
    sta.w treasure_rolling_slot_index
; Calculate item index = scroll_pos + row
    lda.w 0x1BB7
; Scroll position
    clc
    adc.b 0x46
; + row
    cmp #TREASURE_TOTAL_ITEMS
; Check bounds (< 48)
    bcs _t_swap_redraw_clear
; Clear slot if out of range
    sta.w treasure_rolling_edge_row
; Render item to the correct slot
    jsr.w treasure_render_item_to_slot
    bra _t_swap_redraw_next

_t_swap_redraw_clear:
; Item index is out of bounds - clear this slot
; Set edge_row to point to an empty item (use item 0 which should be empty at end)
; Actually, render a blank slot by setting item pointer to empty data
    jsr.w ClearTreasureSlot

_t_swap_redraw_next:
; Next row
    inc.b 0x46
    lda.b 0x46
    cmp #TREASURE_BUFFER_SLOTS
; Render all 11 slots
    bne _t_swap_redraw_loop
; Restore DP byte
    pla
    sta.b 0x46
; Request DMA transfer
    lda #0x01
    sta.w treasure_transfer_pending
; Rebuild HDMA table to ensure consistency
; (Even though buffer_pos didn't change, this ensures the table is correct)
    jsr.w update_treasure_scroll_hdma
    plp
    rtl
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
