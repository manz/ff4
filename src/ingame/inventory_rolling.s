; ============================================================================
; Rolling Buffer Implementation for Main Menu Inventory (Single Column)
; ============================================================================
;
; HDMA-based circular buffer scrolling for single-column menu inventory.
; Adapts the battle inventory rolling approach for the menu context.
;
; Layout: Single column, 5 visible items, 48 total items
; Uses same HDMA technique as battle inventory for smooth scrolling.
;
; ============================================================================

; ============================================================================
; CONSTANTS
; ============================================================================

; Layout (single column)
MENU_VISIBLE_ITEMS      := 10       ; Visible items at once
MENU_BUFFER_SLOTS       := 11       ; 11 slots (10 visible + 1 pre-render)
MENU_TOTAL_ITEMS        := 48       ; Total inventory items
MENU_SCROLL_LIMIT       := 38       ; 48 - 10 = max scroll position

; Pixels per item row
MENU_PIXELS_PER_ROW     := 16       ; Pixels per item slot (2 tilemap rows × 8)

; Scroll constants
MENU_SCROLL_WRAP        := 176      ; 11 slots × 16 pixels = 176
; MENU_BASE_SCROLL is read from $93 (BG1VOFS shadow) at runtime

; Screen layout - item list position
; The item list doesn't start at scanline 0; there's a window border above it
MENU_ITEM_LIST_Y_START  := 48       ; Scanline where item list begins (after border)
MENU_ITEM_LIST_HEIGHT   := 160      ; 10 items × 16 pixels = 160 scanlines

; ============================================================================
; RAM VARIABLES
; ============================================================================
; Using menu RAM area (unused bytes)

menu_rolling_top_row    := 0x1BA8   ; Top visible item index (0-43)
menu_rolling_buffer_pos := 0x1BA9   ; Circular buffer position (0-5)
menu_rolling_edge_row   := 0x1BAA   ; Item index to render (0-47)
menu_rolling_slot_index := 0x1BAB   ; Current slot index (0-5)
menu_rolling_base_scroll := 0x1BAC  ; Base scroll value (16-bit, from $93 on entry)
menu_hdma_enable        := 0x1BAE   ; HDMA enable shadow (0 or $20 for channel 5)

; State Machine Variables (FF6-style non-blocking scroll)
menu_scroll_state       := 0x1BB0   ; 0=idle, 1=scrolling
menu_scroll_remaining   := 0x1BB1   ; Pixels remaining (16 down to 0)
menu_scroll_direction   := 0x1BB2   ; +2=down, -2=up (signed)
menu_transfer_pending   := 0x1BB3   ; Flag for NMI DMA transfer
menu_scroll_anim_offset := 0x1BB4   ; Current animation pixel offset (16-bit, signed)
menu_hdma_copy_pending  := 0x1BB6   ; Flag: shadow table needs copying to active (set by game, cleared by NMI)

; Scroll State Constants
SCROLL_STATE_IDLE       := 0
SCROLL_STATE_SCROLLING  := 1
SCROLL_PIXELS_PER_FRAME := 8        ; 8 pixels/frame = 2 frames per scroll
SCROLL_TOTAL_PIXELS     := 16

; ============================================================================
; HDMA Configuration (Direct Mode like FF6)
; ============================================================================
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

MENU_HDMA_TABLE_ADDR    := 0x9800       ; WRAM offset for HDMA table (active - read by HDMA)
MENU_HDMA_TABLE         := 0x7E9800     ; Full 24-bit address
MENU_HDMA_SHADOW_ADDR   := 0x9840       ; WRAM offset for shadow table (written by game logic)
MENU_HDMA_SHADOW        := 0x7E9840     ; Full 24-bit address
MENU_HDMA_TABLE_SIZE    := 40           ; Max table size in bytes (13 entries × 3 bytes + padding)
MENU_HDMA_BANK          := 0x7E         ; Using WRAM bank

; HDMA registers for channel 5
HDMA5_CTRL              := 0x4350       ; DMA control
HDMA5_DEST              := 0x4351       ; PPU register
HDMA5_SRC_LO            := 0x4352       ; Source address low
HDMA5_SRC_HI            := 0x4353       ; Source address high
HDMA5_SRC_BANK          := 0x4354       ; Source bank
HDMA5_IND_BANK          := 0x4357       ; Indirect bank
HDMAEN                  := 0x420C       ; HDMA enable register

; ============================================================================
; Code placement in bank $01 free space
; ============================================================================
*=0x01F800

; ============================================================================
; InitMenuInventoryHDMA
; ============================================================================
; Sets up HDMA channel 5 for per-scanline BG1 vertical scroll control
; Called when entering the item menu
;
; HDMA mode: $02 = write 2 bytes to same register, DIRECT mode (like FF6)
; Register: $210E (BG1VOFS)
; Table format: count_byte, lo_byte, hi_byte per entry, $00 to end

InitMenuInventoryHDMA:
    php
    sep     #0x20                   ; 8-bit A

    ; Build the HDMA data table in WRAM
    ; Use UpdateMenuScrollHDMA directly - InitMenuHDMATable is redundant
    ; since UpdateMenuScrollHDMA is called immediately after anyway
    jsr.w   UpdateMenuScrollHDMA

    ; Configure HDMA channel 5 for DIRECT mode
    ; Must use long addressing - DB may be $7E but registers are at $00:43xx
    lda     #0x02                   ; Mode: DIRECT, write 2 bytes to same PPU reg
    sta.l   HDMA5_CTRL              ; $004350

    lda     #0x0E                   ; BG1VOFS register ($210E)
    sta.l   HDMA5_DEST              ; $004351

    ; Source = HDMA table in WRAM at $7E9800
    rep     #0x20                   ; 16-bit A
    lda.w   #MENU_HDMA_TABLE_ADDR   ; $9800
    sta.l   HDMA5_SRC_LO            ; $004352-$004353
    sep     #0x20                   ; 8-bit A
    lda     #MENU_HDMA_BANK         ; $7E
    sta.l   HDMA5_SRC_BANK          ; $004354

    ; HDMA channel 5 is now enabled via shadow variable (menu_hdma_enable)
    ; The NMI hook at $8083 reads the shadow and writes to HDMAEN

    plp
    rts

; ============================================================================
; DisableMenuInventoryHDMA
; ============================================================================
; Disables HDMA channel 5 when leaving item menu
; The shadow variable is cleared by MenuExitHook

DisableMenuInventoryHDMA:
    php
    sep     #0x20                   ; 8-bit A
    ; Shadow variable cleared by caller, NMI will write 0 to HDMAEN
    plp
    rts

; ============================================================================
; InitMenuHDMATable
; ============================================================================
; Builds direct mode HDMA table in WRAM at $7E9800
; Format: count, lo, hi per entry, $00 to end
; Initial state: all rows at BASE scroll (no circular buffer offset)

InitMenuHDMATable:
    php
    rep     #0x30                   ; 16-bit A, X, Y
    pha                             ; Save A
    phx                             ; Save X
    phy                             ; Save Y

    ; Save DP bytes we'll use as scratch
    lda.b   0x40
    pha                             ; Save $40-$41

    ; X = table write offset
    ldx.w   #0x0000

    ; Entry 0: Border area - 48 scanlines at BASE scroll
    sep     #0x20                   ; 8-bit A for count byte
    lda     #48                     ; 48 scanlines
    sta.l   MENU_HDMA_TABLE,x
    inx
    rep     #0x20                   ; 16-bit A for value
    lda.w   menu_rolling_base_scroll
    sta.l   MENU_HDMA_TABLE,x
    inx
    inx

    ; Entries 1-10: Item rows - 16 scanlines each at BASE scroll (initial)
    ; For init, all rows use BASE (no circular buffer offset yet)
    lda.w   #0x0000
    sta.b   0x40                    ; Row counter

_init_item_rows:
    sep     #0x20                   ; 8-bit A for count
    lda     #16                     ; 16 scanlines per item row
    sta.l   MENU_HDMA_TABLE,x
    inx
    rep     #0x20                   ; 16-bit A for value
    lda.w   menu_rolling_base_scroll
    sta.l   MENU_HDMA_TABLE,x
    inx
    inx

    inc.b   0x40
    lda.b   0x40

    cmp.w   #1     ; 10 rows
    bcc     _init_item_rows

    ; Entry 11: Below items - 16 scanlines at BASE + 16
    ; Lock to show the bottom window border area
    sep     #0x20
    lda     #16                     ; 16 scanlines
    sta.l   MENU_HDMA_TABLE,x
    inx
    rep     #0x20
    lda.w   menu_rolling_base_scroll
    clc
    adc.w   #16                     ; Lock at base + 16
    sta.l   MENU_HDMA_TABLE,x
    inx
    inx

    ; End marker
    sep     #0x20
    lda     #0x00
    sta.l   MENU_HDMA_TABLE,x

    ; Restore DP bytes
    rep     #0x20
    pla
    sta.b   0x40                    ; Restore $40-$41

    ; Restore registers
    ply
    plx
    pla
    plp
    rts

; ============================================================================
; UpdateMenuScrollHDMA
; ============================================================================
; Rebuilds the HDMA table in the SHADOW buffer for current scroll state.
; The NMI handler copies shadow -> active during vblank for flicker-free updates.
;
; For each visible row, calculates:
;   vram_slot = (buffer_pos + row) mod MENU_BUFFER_SLOTS
;   scroll = BASE + (vram_slot * 16) - (row * 16) + anim_offset
;
; Direct mode table format: count, lo, hi per entry

UpdateMenuScrollHDMA:
    ; Save processor status and registers
    php
    rep     #0x30                   ; 16-bit A, X, Y
    pha
    phx
    phy

    ; Save DP bytes we'll use as scratch (16-bit mode writes 2 bytes each)
    lda.b   0x40
    pha                             ; Save $40-$41 (scroll value / vram_offset)
    lda.b   0x42
    pha                             ; Save $42-$43 (row counter)

    ; X = table write offset
    ldx.w   #0x0000

    ; Entry 0: Border area - 48 scanlines at BASE scroll (unchanged)
    sep     #0x20                   ; 8-bit A for count byte
    lda     #48
    sta.l   MENU_HDMA_SHADOW,x
    inx
    rep     #0x20                   ; 16-bit A for value
    lda.w   menu_rolling_base_scroll
    sta.l   MENU_HDMA_SHADOW,x
    inx
    inx

    ; Entries 1-10: Item rows with circular buffer scroll values
    stz.b   0x42                    ; Row counter (0-9)

_update_hdma_row_loop:
    ; Calculate vram_slot = (buffer_pos + row) % MENU_BUFFER_SLOTS
    lda.w   menu_rolling_buffer_pos
    and.w   #0x00FF
    clc
    adc.b   0x42                    ; + row number
_update_hdma_mod:
    cmp.w   #MENU_BUFFER_SLOTS      ; >= 11?
    bcc     _update_hdma_mod_done
    sec
    sbc.w   #MENU_BUFFER_SLOTS
    bra     _update_hdma_mod
_update_hdma_mod_done:
    ; A = vram_slot (0-10)

    ; Calculate vram_slot * 16 (pixels per slot in VRAM)
    asl
    asl
    asl
    asl                             ; A = vram_slot * 16
    sta.b   0x40                    ; Save vram_offset

    ; Calculate row * 16 (screen pixels per item row)
    lda.b   0x42
    and.w   #0x00FF
    asl
    asl
    asl
    asl                             ; row * 16 = scanline_offset

    ; scroll = BASE + vram_offset - scanline_offset + anim_offset
    ; Negate scanline_offset: EOR #$FFFF, INC
    eor.w   #0xFFFF
    inc                             ; A = -scanline_offset
    clc
    adc.b   0x40                    ; + vram_offset
    clc
    adc.w   menu_rolling_base_scroll ; + BASE
    ; DISABLED: Animation offset causes seam flicker at buffer wrap-around.
    ; When vram_slot=0 (seam row), scroll goes negative and lands in border
    ; zone [176-255], showing window border instead of item content.
    ; With 11 slots (176 pixels) in a 256-pixel tilemap, the math doesn't
    ; wrap cleanly like FF6's power-of-2 approach. Disabling gives instant
    ; scroll instead of smooth animation, but eliminates the visual glitch.
    ; TODO: Fix by clamping seam scroll or using content duplication.
.if 0 {
    clc
    adc.w   menu_scroll_anim_offset ; + animation offset
}
    sta.b   0x40                    ; scroll value for this row

_write_normal_entry:
    ; Write entry: count=16, value=scroll
    sep     #0x20                   ; 8-bit for count
    lda     #16                     ; 16 scanlines per item row
    sta.l   MENU_HDMA_SHADOW,x
    inx
    rep     #0x20                   ; 16-bit for value
    lda.b   0x40
    sta.l   MENU_HDMA_SHADOW,x
    inx
    inx

_row_done:
    ; Next row
    rep     #0x20                   ; Ensure 16-bit for comparison
    inc.b   0x42
    lda.b   0x42
    cmp.w   #MENU_VISIBLE_ITEMS     ; 10 rows
    bcs     _row_loop_done          ; >= 10, exit loop
    jmp.w   _update_hdma_row_loop
_row_loop_done:

    ; Entry 11: Below items - 16 scanlines at BASE + 16
    ; Lock to show the bottom window border area
    sep     #0x20
    lda     #16
    sta.l   MENU_HDMA_SHADOW,x
    inx
    rep     #0x20
    lda.w   menu_rolling_base_scroll
    clc
    adc.w   #16                    ; Lock at base + 16
    sta.l   MENU_HDMA_SHADOW,x
    inx
    inx

    ; End marker
    sep     #0x20
    lda     #0x00
    sta.l   MENU_HDMA_SHADOW,x

    ; Signal NMI to copy shadow -> active table
    lda     #0x01
    sta.w   menu_hdma_copy_pending

    ; Restore DP bytes (reverse order)
    rep     #0x20
    pla
    sta.b   0x42                    ; Restore $42-$43
    pla
    sta.b   0x40                    ; Restore $40-$41

    ; Restore registers (in 16-bit mode to match push)
    ply
    plx
    pla
    plp                             ; Restore original processor status
    rts

; ============================================================================
; InitMenuRollingBuffer
; ============================================================================
; Called when inventory menu opens
; Initializes the circular buffer state and sets up HDMA

InitMenuRollingBuffer:
    php                             ; Save processor state at entry
    pha                             ; Save A

    ; Draw the inventory window frame (what original DrawInventoryList does first)
    ldy     #0xDCCE                 ; InventoryWindow data pointer
    jsr.w   0x80D9                  ; DrawWindow

    ; Save DP byte we'll use as scratch
    lda.b   0x46
    pha                             ; Save $46

    ; Initialize buffer state (stz works in any mode)
    stz.w   menu_rolling_top_row
    stz.w   menu_rolling_buffer_pos

    ; Mark base scroll as uninitialized (0xFFFF = sentinel)
    ; Will be captured from $93 on first scroll when it's valid
    rep     #0x20                   ; 16-bit A
    lda.w   #0xFFFF                 ; Sentinel: "not yet captured"
    sta.w   menu_rolling_base_scroll
    sep     #0x20

    ; DON'T set up HDMA here - $93 isn't set yet!
    ; HDMA will be initialized on first scroll

    ; Render initial 12 slots (items 0-11) to buffer
    sep     #0x20                   ; 8-bit A - CRITICAL!
    lda     #0x00
    sta.b   0x46                    ; Loop counter

_menu_init_row_loop:
    lda.b   0x46
    sta.w   menu_rolling_edge_row
    sta.w   menu_rolling_slot_index

    ; Render item to circular buffer slot
    jsr.w   MenuRenderItemToSlot

    inc.b   0x46
    lda.b   0x46
    cmp     #11                     ; Render 11 items (0-10) explicitly
    bne     _menu_init_row_loop

    ; Restore DP byte
    pla
    sta.b   0x46                    ; Restore $46

    pla                             ; Restore A
    plp                             ; Restore original processor state
    rts

; ============================================================================
; MenuScrollDownPrepare
; ============================================================================
; Called before scroll down animation
; Pre-renders the bottom edge item

MenuScrollDownPrepare:
    php
    sep     #0x20                   ; 8-bit A - CRITICAL!

    ; Lazy init: if base_scroll == 0xFFFF, capture $93 and init HDMA
    jsr.w   EnsureHDMAInitialized

    ; Check if we can scroll (scroll_pos < SCROLL_LIMIT)
    lda.w   0x1B1A                  ; Current scroll position
    cmp     #MENU_SCROLL_LIMIT
    bcs     _menu_scroll_down_done  ; At bottom

    ; Calculate new bottom item = scroll_pos + VISIBLE_ITEMS
    clc
    adc     #MENU_VISIBLE_ITEMS
    sta.w   menu_rolling_edge_row

    ; The slot scrolling OFF the top (buffer_pos) will be reused for the new bottom item
    ; Render to buffer_pos BEFORE incrementing
    lda.w   menu_rolling_buffer_pos
    sta.w   menu_rolling_slot_index

    ; Render item to the slot that's scrolling off
    jsr.w   MenuRenderItemToSlot

    ; NOW advance buffer position (the slot we just wrote to is now the "bottom")
    inc.w   menu_rolling_buffer_pos
    lda.w   menu_rolling_buffer_pos
    cmp     #MENU_BUFFER_SLOTS
    bcc     _menu_buf_pos_ok
    stz.w   menu_rolling_buffer_pos
_menu_buf_pos_ok:

    ; Update HDMA table for new buffer position
    jsr.w   UpdateMenuScrollHDMA

_menu_scroll_down_done:
    plp
    rts

; ============================================================================
; MenuScrollUpPrepare
; ============================================================================
; Called before scroll up animation
; Pre-renders the top edge item

MenuScrollUpPrepare:
    php
    sep     #0x20                   ; 8-bit A - CRITICAL!

    ; Lazy init: if base_scroll == 0xFFFF, capture $93 and init HDMA
    jsr.w   EnsureHDMAInitialized

    ; Note: The game already validated we can scroll before calling the hook.
    ; The hook already decremented 0x1B1A, so we always need to update buffer_pos.

    ; Decrement buffer position first
    lda.w   menu_rolling_buffer_pos
    beq     _menu_wrap_up
    dec
    bra     _menu_wrap_up_done
_menu_wrap_up:
    lda     #MENU_BUFFER_SLOTS - 1
_menu_wrap_up_done:
    sta.w   menu_rolling_buffer_pos
    sta.w   menu_rolling_slot_index

    ; Calculate new top item = scroll_pos (already decremented by hook)
    ; This is the item that should appear at the top after scrolling
    lda.w   0x1B1A
    sta.w   menu_rolling_edge_row

    ; Render item to the new top slot
    jsr.w   MenuRenderItemToSlot

    ; Update HDMA table for new buffer position
    jsr.w   UpdateMenuScrollHDMA

_menu_scroll_up_done:
    plp
    rts

; ============================================================================
; MenuRenderItemToSlot
; ============================================================================
; Renders an item to a specific circular buffer slot in the tilemap.
;
; Input: menu_rolling_edge_row = item index (0-47) for data lookup
;        menu_rolling_slot_index = slot index (0-11) for destination
;
; Strategy: Set up $5d = slot_index (for Y position calculation),
;           $5a = pointer to item data, then call game's DrawItemSlot.

MenuRenderItemToSlot:
    php
    phb

    ; Set data bank to $7E for WRAM access
    lda     #0x7E
    pha
    plb

    ; Set 16-bit A and X/Y for consistent register handling
    rep     #0x30                   ; 16-bit A and X/Y

    ; Save registers and key direct page variables
    pha
    phx                             ; Save X (16-bit)
    phy                             ; Save Y (16-bit)
    lda.b   0x5a
    pha
    lda.b   0x29                    ; Save tilemap buffer pointer
    pha
    lda.b   0x45                    ; Save $45-$46 (used by game routines)
    pha
    lda.b   0x33                    ; Save $33-$34 (used for tile attributes)
    pha
    sep     #0x20                   ; 8-bit A
    lda.b   0x5d
    pha
    lda.b   0xDB                    ; Save tile attribute byte
    pha

    ; Set $29 = $B600 for BG1 tilemap buffer
    rep     #0x20                   ; 16-bit A (X/Y still 16-bit)
    lda.w   #0xB600
    sta.b   0x29
    sep     #0x20                   ; 8-bit A

    ; Calculate item data pointer: $1440 + (edge_row * 2)
    lda.w   menu_rolling_edge_row
    asl                             ; * 2 (2 bytes per item)
    clc
    adc     #0x40                   ; Low byte of $1440
    sta.b   0x5a
    lda     #0x14                   ; High byte of $1440
    adc     #0x00                   ; Add carry
    sta.b   0x5b

    ; Load item ID and count from ($5A)
    ; Use long addressing to read directly from WRAM
    rep     #0x20                   ; 16-bit A (X/Y already 16-bit from entry)
    lda.b   0x5a                    ; Get pointer value ($1440 + item*2)
    tax                             ; X = address of item data (16-bit)
    sep     #0x20                   ; 8-bit A
    lda.l   0x7E0000,x              ; Load item ID from WRAM
    pha                             ; Save item ID for CheckCanUseItem
    inx
    lda.l   0x7E0000,x              ; Load count from WRAM
    sta.b   0x5C                    ; Store in $5C

    ; Call CheckCanUseItem to set palette in $DB
    ; Input: A = item ID
    ; Output: $DB = $00 (usable) or $04 (not usable)
    stz.b   0x34                    ; Clear $34 (no priority/flip bits)
    pla                             ; Restore item ID
    jsr.w   0xA25D                  ; CheckCanUseItem - sets $DB

    ; Set $5d = slot_index (for AND #$01 check, but we patched to AND #$00)
    lda.w   menu_rolling_slot_index
    sta.b   0x5d

    ; Calculate Y = slot_index * 128 + 70
    ; Y is the tilemap offset for this slot
    ; +64 for window border (1 tile row = 32 tiles × 2 bytes)
    ; +6 for left margin (3 tiles)
    rep     #0x20                   ; 16-bit A (X/Y already 16-bit)
    lda.w   menu_rolling_slot_index
    and.w   #0x00FF                 ; Clear high byte
    xba                             ; Swap bytes: A = slot * 256
    lsr                             ; A = slot * 128
    clc
    adc.w   #0x0046                 ; + 70 (64 border + 6 margin)
    tay                             ; Y = tilemap offset (16-bit transfer)
    sep     #0x20                   ; 8-bit A

    ; Check for trash can item ($FF) - needs special 2x2 tile graphic
    lda     (0x5a)                  ; Load item ID
    cmp     #0xFF
    bne     _not_trash_item
    jsr.w   DrawTrashSingleColumn   ; Draw trash icon
    bra     _skip_draw_item_slot

_not_trash_item:
    ; Clear the 2x2 trash can area first (in case we scrolled from trash position)
    jsr.w   ClearTrashArea

    ; Call DrawItemSlot inner at $A1ED
    ; Expects: Y = tilemap offset, ($5A) = item pointer, ($29) = tilemap base
    jsr.w   0xA1ED

_skip_draw_item_slot:

    ; Restore direct page variables and registers (reverse order)
    pla
    sta.b   0xDB                    ; Restore tile attribute byte
    pla
    sta.b   0x5d
    rep     #0x20                   ; 16-bit A
    pla
    sta.b   0x33                    ; Restore $33-$34 (tile attributes)
    pla
    sta.b   0x45                    ; Restore $45-$46 (used by game routines)
    pla
    sta.b   0x29                    ; Restore tilemap buffer pointer
    pla
    sta.b   0x5a
    rep     #0x10                   ; 16-bit X/Y for pop (match push)
    ply                             ; Restore Y (16-bit)
    plx                             ; Restore X (16-bit)
    pla                             ; Restore A (16-bit - still in 16-bit A from above)

    plb
    plp
    rts

; ============================================================================
; EnsureHDMAInitialized
; ============================================================================
; Lazy initialization: captures $93 and sets up HDMA on first scroll.
; Called from scroll prepare functions.
; Checks if base_scroll == 0xFFFF (sentinel) and if so, initializes.

EnsureHDMAInitialized:
    ; Check if already initialized (base_scroll != 0xFFFF)
    rep     #0x20                   ; 16-bit A
    lda.w   menu_rolling_base_scroll
    cmp.w   #0xFFFF
    bne     _hdma_already_init

    ; Capture base scroll from $0193 (BG1VOFS shadow, menu uses DP=$0100)
    ; Use long addressing to ensure we read from WRAM
    .db 0xAF                        ; LDA.L opcode
    .db 0x93, 0x01, 0x7E            ; $7E0193
    sta.w   menu_rolling_base_scroll

    ; Initialize HDMA channel configuration
    sep     #0x20                   ; Back to 8-bit for InitMenuInventoryHDMA
    jsr.w   InitMenuInventoryHDMA

    ; NOW enable HDMA via shadow variable (channel is configured)
    ; Force long addressing: STA.L $7E1BAE
    lda     #0x20                   ; Channel 5
    .db 0x8F                        ; STA.L opcode
    .dw menu_hdma_enable            ; $1BAE
    .db 0x7E                        ; Bank $7E
    rts

_hdma_already_init:
    sep     #0x20                   ; Restore 8-bit mode
    rts

; ============================================================================
; STATE MACHINE ROUTINES (FF6-style non-blocking scroll)
; ============================================================================

; ============================================================================
; ScrollStateCheck
; ============================================================================
; Called at main loop entry ($019FF2) to handle scroll animation frames.
; If scrolling is active, processes one frame and skips input handling.
;
; Returns: Carry clear = process input normally
;          Carry set = skip input (still scrolling)

ScrollStateCheck:
    php
    sep     #0x20                   ; 8-bit A

    ; Check if we're scrolling
    lda.w   menu_scroll_state
    beq     _scroll_state_idle

    ; We're scrolling - process one animation frame
    jsr.w   UpdateScrollFrame

    ; Check if scroll finished
    lda.w   menu_scroll_remaining
    bne     _scroll_still_active

    ; Scroll finished - clean up and return to idle
    jsr.w   FinishScroll

_scroll_state_idle:
    plp
    clc                             ; Carry clear = process input
    rts

_scroll_still_active:
    plp
    sec                             ; Carry set = skip input
    rts

; ============================================================================
; StartScrollDown
; ============================================================================
; Initiates a non-blocking scroll down animation.
; Called when user presses down and we need to scroll the list.
; Sets up state machine and returns immediately (no blocking loop).

StartScrollDown:
    php
    sep     #0x20                   ; 8-bit A

    ; Lazy init HDMA if needed
    jsr.w   EnsureHDMAInitialized

    ; Advance buffer position FIRST
    inc.w   menu_rolling_buffer_pos
    lda.w   menu_rolling_buffer_pos
    cmp     #MENU_BUFFER_SLOTS
    bcc     _start_down_buf_ok
    stz.w   menu_rolling_buffer_pos
    lda     #0x00                   ; A = 0 after wrap
_start_down_buf_ok:

    ; Pre-render the item that's about to appear at bottom
    ; Bottom slot = (buffer_pos + VISIBLE_ITEMS - 1) % BUFFER_SLOTS
    clc
    adc     #MENU_VISIBLE_ITEMS - 1 ; A has buffer_pos
_start_down_mod:
    cmp     #MENU_BUFFER_SLOTS
    bcc     _start_down_mod_done
    sec
    sbc     #MENU_BUFFER_SLOTS
    bra     _start_down_mod
_start_down_mod_done:
    sta.w   menu_rolling_slot_index

    ; Item = scroll_pos + VISIBLE_ITEMS - 1 (scroll_pos already incremented)
    lda.w   0x1B1A
    clc
    adc     #MENU_VISIBLE_ITEMS - 1
    sta.w   menu_rolling_edge_row
    jsr.w   MenuRenderItemToSlot

    ; Set up scroll state machine
    lda     #SCROLL_STATE_SCROLLING
    sta.w   menu_scroll_state
    lda     #SCROLL_TOTAL_PIXELS
    sta.w   menu_scroll_remaining
    lda     #SCROLL_PIXELS_PER_FRAME
    sta.w   menu_scroll_direction   ; +2 for down

    ; Initialize animation offset to -16 (compensate for buffer_pos already incremented)
    ; Animation goes from -16 towards 0 (adding +2 each frame)
    rep     #0x20
    lda.w   #0xFFF0                 ; -16 in two's complement
    sta.w   menu_scroll_anim_offset
    sep     #0x20

    ; Request DMA transfer for the new row
    lda     #0x01
    sta.w   menu_transfer_pending

    ; Update HDMA table for new buffer position
    jsr.w   UpdateMenuScrollHDMA

    plp
    rts

; ============================================================================
; StartScrollUp
; ============================================================================
; Initiates a non-blocking scroll up animation.
; Called when user presses up and we need to scroll the list.

StartScrollUp:
    php
    sep     #0x20                   ; 8-bit A

    ; Lazy init HDMA if needed
    jsr.w   EnsureHDMAInitialized

    ; Decrement buffer position FIRST
    lda.w   menu_rolling_buffer_pos
    beq     _start_up_wrap
    dec
    bra     _start_up_wrap_done
_start_up_wrap:
    lda     #MENU_BUFFER_SLOTS - 1
_start_up_wrap_done:
    sta.w   menu_rolling_buffer_pos
    sta.w   menu_rolling_slot_index ; Render to this slot

    ; Pre-render the item that's about to appear at top
    ; scroll_pos was already decremented by trigger, so it IS the top item
    lda.w   0x1B1A                  ; scroll_pos (already decremented)
    sta.w   menu_rolling_edge_row
    jsr.w   MenuRenderItemToSlot

    ; Set up scroll state machine
    lda     #SCROLL_STATE_SCROLLING
    sta.w   menu_scroll_state
    lda     #SCROLL_TOTAL_PIXELS
    sta.w   menu_scroll_remaining
    lda     #0xFE                   ; -2 (two's complement) for up
    sta.w   menu_scroll_direction

    ; Initialize animation offset to +16 (compensate for buffer_pos already decremented)
    ; Animation goes from +16 towards 0 (subtracting 2 each frame)
    rep     #0x20
    lda.w   #0x0010                 ; +16
    sta.w   menu_scroll_anim_offset
    sep     #0x20

    ; Request DMA transfer
    lda     #0x01
    sta.w   menu_transfer_pending

    ; Update HDMA table
    jsr.w   UpdateMenuScrollHDMA

    plp
    rts

; ============================================================================
; UpdateScrollFrame
; ============================================================================
; Called each frame during scroll animation.
; Updates animation offset, HDMA table, and cursor sprite position.
; NOTE: Does NOT modify $93 - all scrolling is handled via HDMA.

UpdateScrollFrame:
    php

    ; Update animation offset (NOT $93 - HDMA handles all scroll)
    ; Offset increases each frame based on direction
    rep     #0x20                   ; 16-bit A
    lda.w   menu_scroll_anim_offset
    sep     #0x20
    lda.w   menu_scroll_direction
    bpl     _scroll_frame_positive
    ; Negative direction (scrolling up) - decrease offset
    rep     #0x20
    lda.w   menu_scroll_anim_offset
    sec
    sbc.w   #SCROLL_PIXELS_PER_FRAME
    sta.w   menu_scroll_anim_offset
    bra     _scroll_frame_update_cursor

_scroll_frame_positive:
    ; Positive direction (scrolling down) - increase offset
    rep     #0x20
    lda.w   menu_scroll_anim_offset
    clc
    adc.w   #SCROLL_PIXELS_PER_FRAME
    sta.w   menu_scroll_anim_offset

_scroll_frame_update_cursor:
    sep     #0x20                   ; 8-bit A

    ; Update cursor sprite position if in "second item" mode ($1B19 != 0)
    lda.w   0x1B19
    beq     _scroll_frame_no_cursor

    ; Move cursor sprite to match scroll
    ; $0311 is cursor Y position in OAM
    lda.w   menu_scroll_direction
    bpl     _scroll_cursor_down
    ; Scrolling up - cursor moves down on screen
    inc.w   0x0311
    inc.w   0x0311
    bra     _scroll_frame_no_cursor
_scroll_cursor_down:
    ; Scrolling down - cursor moves up on screen
    dec.w   0x0311
    dec.w   0x0311

_scroll_frame_no_cursor:
    ; Decrement remaining pixels
    lda.w   menu_scroll_remaining
    sec
    sbc     #SCROLL_PIXELS_PER_FRAME
    sta.w   menu_scroll_remaining

    ; Update HDMA table (smooth scrolling)
    jsr.w   UpdateMenuScrollHDMA

    ; Request vblank operations
    jsr.w   0x824F                  ; TfrSpritesVblank - transfer sprites
    jsr.w   0x9420                  ; TfrBG2TilesVblank - transfer description

    plp
    rts

; ============================================================================
; FinishScroll
; ============================================================================
; Called when scroll animation completes.
; Resets state machine and calls post-scroll cleanup routines.

FinishScroll:
    php
    sep     #0x20

    ; Check scroll direction to know which item to pre-render
    lda.w   menu_scroll_direction
    bmi     _finish_scroll_was_up

    ; === Scrolled DOWN - pre-render for NEXT scroll down ===
    ; The slot that went off-screen (above) will appear at bottom on next scroll
    ; Slot = (buffer_pos - 1 + BUFFER_SLOTS) % BUFFER_SLOTS
    lda.w   menu_rolling_buffer_pos
    beq     _finish_down_wrap
    dec
    bra     _finish_down_slot_ok
_finish_down_wrap:
    lda     #MENU_BUFFER_SLOTS - 1
_finish_down_slot_ok:
    sta.w   menu_rolling_slot_index

    ; Item = scroll_pos + VISIBLE_ITEMS
    lda.w   0x1B1A                  ; Current scroll position
    clc
    adc     #MENU_VISIBLE_ITEMS
    cmp     #MENU_TOTAL_ITEMS       ; Don't render past end
    bcs     _finish_skip_render
    sta.w   menu_rolling_edge_row
    jsr.w   MenuRenderItemToSlot
    ; Request DMA transfer to VRAM
    lda     #0x01
    sta.w   menu_transfer_pending
    bra     _finish_skip_render

_finish_scroll_was_up:
    ; === Scrolled UP - pre-render for NEXT scroll up ===
    ; The slot that went off-screen (below) will appear at top on next scroll
    ; Slot = (buffer_pos + VISIBLE_ITEMS) % BUFFER_SLOTS
    lda.w   menu_rolling_buffer_pos
    clc
    adc     #MENU_VISIBLE_ITEMS
_finish_up_mod:
    cmp     #MENU_BUFFER_SLOTS
    bcc     _finish_up_slot_ok
    sec
    sbc     #MENU_BUFFER_SLOTS
    bra     _finish_up_mod
_finish_up_slot_ok:
    sta.w   menu_rolling_slot_index

    ; Item = scroll_pos - 1 (only if scroll_pos > 0)
    lda.w   0x1B1A
    beq     _finish_skip_render     ; At top, no need to pre-render
    dec
    sta.w   menu_rolling_edge_row
    jsr.w   MenuRenderItemToSlot
    ; Request DMA transfer to VRAM
    lda     #0x01
    sta.w   menu_transfer_pending

_finish_skip_render:
    ; Reset scroll state to idle
    stz.w   menu_scroll_state

    ; Reset animation offset
    rep     #0x20
    stz.w   menu_scroll_anim_offset
    sep     #0x20

    ; Update HDMA table with final positions (offset = 0)
    jsr.w   UpdateMenuScrollHDMA

    ; Call original post-scroll cleanup routines
    jsr.w   0xA105                  ; DrawItemCursors
    jsr.w   0x82A5                  ; UpdateCtrlAfterScroll

    plp
    rts

; ============================================================================
; Inventory Rolling Buffer Patches - Relocated to Bank $20
; ============================================================================
; These routines are called via JSL from bank $01 hooks.
; ============================================================================

.if INVENTORY_ROLLING_BUFFER {

MenuEntryHook_Impl:
    stz.w   0x1B1F
    lda     #0x00
    sta.l   0x7E1BAE              ; menu_hdma_enable
    stz.w   menu_scroll_state
    stz.w   menu_scroll_remaining
    stz.w   menu_scroll_direction
    stz.w   menu_transfer_pending
    stz.w   menu_hdma_copy_pending      ; Clear HDMA copy flag
    stz.w   menu_scroll_anim_offset     ; Clear low byte
    stz.w   menu_scroll_anim_offset + 1 ; Clear high byte
    ; Initialize cursor column to 0 for single-column mode
    ; This ensures $1b22 is always 0 even if it had a value from previous menu
    stz.w   0x1B22                      ; cursor_x = 0
    ; InitMenuRollingBuffer is called later via patched JSR at $9F7B
    rtl

MenuExitHook_Impl:
    lda     #0x00
    sta.l   0x7E1BAE              ; menu_hdma_enable
    stz.w   menu_scroll_state
    jsr.w   DisableMenuInventoryHDMA
    jsr.w   0x8D6A
    rtl

; ============================================================================
; SwapRedrawHook_Impl
; ============================================================================
; Called after item swap to redraw visible items correctly.
; Must render to the correct circular buffer slots based on current buffer_pos.
; Does NOT reset buffer_pos - we stay at the current scroll position.
SwapRedrawHook_Impl:
    php
    sep     #0x20                   ; 8-bit A

    ; CRITICAL: Ensure HDMA is initialized before using scroll values
    ; If swap happens before any scrolling, base_scroll would be 0xFFFF
    jsr.w   EnsureHDMAInitialized

    ; CRITICAL: Reset scroll state to prevent re-rendering after swap
    ; If scroll was in progress, FinishScroll would re-render items
    stz.w   menu_scroll_state
    stz.w   menu_scroll_remaining

    ; Ensure animation offset is zero (prevent visual shift)
    stz.w   menu_scroll_anim_offset
    stz.w   menu_scroll_anim_offset + 1

    ; Save DP byte for loop counter
    lda.b   0x46
    pha

    ; Re-render all visible items to correct circular buffer slots
    ; Item index = scroll_pos + row, Slot = (buffer_pos + row) % BUFFER_SLOTS
    lda     #0x00
    sta.b   0x46                    ; Row counter (0-10)

_swap_redraw_loop:
    ; Calculate slot = (buffer_pos + row) % BUFFER_SLOTS first
    ; We need slot_index for both rendering and clearing
    lda.w   menu_rolling_buffer_pos
    clc
    adc.b   0x46                    ; + row
_swap_redraw_mod:
    cmp     #MENU_BUFFER_SLOTS
    bcc     _swap_redraw_mod_done
    sec
    sbc     #MENU_BUFFER_SLOTS
    bra     _swap_redraw_mod
_swap_redraw_mod_done:
    sta.w   menu_rolling_slot_index

    ; Calculate item index = scroll_pos + row
    lda.w   0x1B1A                  ; Scroll position
    clc
    adc.b   0x46                    ; + row
    cmp     #MENU_TOTAL_ITEMS       ; Check bounds (< 48)
    bcs     _swap_redraw_clear      ; Clear slot if out of range
    sta.w   menu_rolling_edge_row

    ; Render item to the correct slot
    jsr.w   MenuRenderItemToSlot
    bra     _swap_redraw_next

_swap_redraw_clear:
    ; Item index is out of bounds - clear this slot
    ; Set edge_row to point to an empty item (use item 0 which should be empty at end)
    ; Actually, render a blank slot by setting item pointer to empty data
    jsr.w   ClearInventorySlot

_swap_redraw_next:
    ; Next row
    inc.b   0x46
    lda.b   0x46
    cmp     #MENU_BUFFER_SLOTS      ; Render all 11 slots
    bne     _swap_redraw_loop

    ; Restore DP byte
    pla
    sta.b   0x46

    ; Request DMA transfer
    lda     #0x01
    sta.w   menu_transfer_pending

    ; Rebuild HDMA table to ensure consistency
    ; (Even though buffer_pos didn't change, this ensures the table is correct)
    jsr.w   UpdateMenuScrollHDMA

    plp
    rtl

; ============================================================================
; ClearInventorySlot
; ============================================================================
; Clears a single inventory slot in the tilemap buffer.
; Input: menu_rolling_slot_index = slot to clear (0-10)
; Used when item index is out of bounds (>= 48)
ClearInventorySlot:
    php
    phb

    ; Set data bank to $7E for WRAM access
    lda     #0x7E
    pha
    plb

    ; Save registers - use 16-bit mode for consistent push/pop
    rep     #0x30                   ; 16-bit A and X/Y
    pha
    phx
    phy
    lda.b   0x29
    pha

    ; Set $29 = $B600 for BG1 tilemap buffer
    lda.w   #0xB600
    sta.b   0x29

    ; Calculate Y = slot_index * 128 + 70
    lda.w   menu_rolling_slot_index
    and.w   #0x00FF
    xba                             ; A = slot * 256
    lsr                             ; A = slot * 128
    clc
    adc.w   #0x0046                 ; + 70 (64 border + 6 margin)
    tay                             ; Y = tilemap offset (16-bit)
    sep     #0x20                   ; 8-bit A for tile writes (X/Y stay 16-bit)

    ; Clear the item name area (12 tiles = 24 bytes)
    ; Use $FF as blank tile
    ; Note: X is 16-bit but we only use low byte; loop works correctly
    ldx.w   #12                     ; 12 tiles for item name + quantity (force 16-bit immediate)
_clear_slot_loop:
    lda     #0xFF                   ; Blank tile
    sta     (0x29),y
    iny
    lda     #0x04                   ; Palette 4 (matches normal items)
    sta     (0x29),y
    iny
    dex
    bne     _clear_slot_loop

    ; Restore registers - must match push mode
    rep     #0x20                   ; 16-bit A for pop (X/Y already 16-bit)
    pla
    sta.b   0x29
    ply
    plx
    pla

    plb
    plp
    rts

; ============================================================================
; ClearTrashArea
; ============================================================================
; Clears the 2x2 trash can area with blank tiles ($FF).
; Called before drawing normal items to remove any leftover trash icon.
; Input: Y = tilemap offset
;        ($29) = tilemap base
;
ClearTrashArea:
    phy                             ; Save Y
    ; First row: 2 tiles
    lda     #0xFF
    sta     (0x29),y
    iny
    lda     #0x00
    sta     (0x29),y
    iny
    lda     #0xFF
    sta     (0x29),y
    iny
    lda     #0x00
    sta     (0x29),y

    ; Second row: Y + 64 from start
    ply                             ; Restore original Y
    phy                             ; Save again
    rep     #0x20
    tya
    clc
    adc.w   #64
    tay
    sep     #0x20

    lda     #0xFF
    sta     (0x29),y
    iny
    lda     #0x00
    sta     (0x29),y
    iny
    lda     #0xFF
    sta     (0x29),y
    iny
    lda     #0x00
    sta     (0x29),y

    ply                             ; Restore Y
    rts

; ============================================================================
; DrawTrashSingleColumn
; ============================================================================
; Draws the trash can 2x2 tile graphic for single-column inventory.
; Input: Y = tilemap offset (from slot calculation)
;        ($29) = tilemap base ($B600)
;        menu_rolling_slot_index = current slot
; Tiles: $04 (top-left), $05 (top-right), $06 (bottom-left), $07 (bottom-right)
;
; Tilemap format: [tile_number, attributes] pairs
; Each row is 64 bytes (32 tiles × 2 bytes)
;
DrawTrashSingleColumn:
    ; Y points to start of item slot area
    ; Draw 2x2 trash can icon, then clear remaining 10 tiles per row

    ; Save starting Y for second row calculation
    rep     #0x20                   ; 16-bit for push
    phy                             ; Save starting Y
    sep     #0x20                   ; 8-bit A

    ; First row: tiles $04, $05
    lda     #0x04                   ; Tile $04 (top-left of trash can)
    sta     (0x29),y
    iny
    lda     #0x00                   ; Attribute: palette 0, no flip
    sta     (0x29),y
    iny
    lda     #0x05                   ; Tile $05 (top-right)
    sta     (0x29),y
    iny
    lda     #0x00                   ; Attribute
    sta     (0x29),y
    iny

    ; Clear remaining 13 tiles on first row (10 name + colon + 2 digits)
    ldx.w   #13
_clear_row1:
    lda     #0xFF                   ; Blank tile
    sta     (0x29),y
    iny
    lda     #0x00                   ; Attribute
    sta     (0x29),y
    iny
    dex
    bne     _clear_row1

    ; Restore starting Y and add 64 for second row
    rep     #0x20                   ; 16-bit A
    pla                             ; Get starting Y
    clc
    adc.w   #64                     ; +64 bytes = next tilemap row
    tay
    sep     #0x20                   ; 8-bit A

    ; Second row: tiles $06, $07
    lda     #0x06                   ; Tile $06 (bottom-left)
    sta     (0x29),y
    iny
    lda     #0x00                   ; Attribute
    sta     (0x29),y
    iny
    lda     #0x07                   ; Tile $07 (bottom-right)
    sta     (0x29),y
    iny
    lda     #0x00                   ; Attribute
    sta     (0x29),y
    iny

    ; Clear remaining 13 tiles on second row (10 name + colon + 2 digits)
    ldx.w   #13
_clear_row2:
    lda     #0xFF                   ; Blank tile
    sta     (0x29),y
    iny
    lda     #0x00                   ; Attribute
    sta     (0x29),y
    iny
    dex
    bne     _clear_row2

    rts

; NmiDmaTransferCheck_Impl moved to bank $20 (battle/inventory_rolling.s)
; as FieldMenu_NmiDmaTransferCheck_Impl to save space in bank $01

; ============================================================================
; CheckAndClearCount
; ============================================================================
; Called from DrawItemSlot to check item ID and handle count display.
; - If item ID is 0: writes $FF tiles to clear count, skips to RTS
; - If item ID is $FE: skips to RTS (no clearing needed)
; - Otherwise: returns normally to draw count
;
; Input: $5a = pointer to item data, Y = tilemap offset, $29 = tilemap ptr
; Modifies: A, return address on stack if skipping
CheckAndClearCount:
    lda     (0x5a)              ; Load item ID
    beq     _clear_count        ; If 0, clear and skip
    cmp     #0xFE               ; Check for special item $FE
    bne     _normal_return      ; If not $FE, return normally to draw count
    ; Item is $FE - skip count but don't clear
    bra     _skip_to_rts

_clear_count:
    ; Write $FF (blank tiles) to count area: colon + 2 digits = 3 tiles
    lda     #0xFF               ; Blank tile
    sta     (0x29),y            ; Colon position
    iny
    lda.b   0xdb                ; Attribute byte
    sta     (0x29),y
    iny
    lda     #0xFF
    sta     (0x29),y            ; First digit position
    iny
    lda.b   0xdb
    sta     (0x29),y
    iny
    lda     #0xFF
    sta     (0x29),y            ; Second digit position
    iny
    lda.b   0xdb
    sta     (0x29),y

_skip_to_rts:
    ; Modify return address to skip to DrawItemSlot's RTS at $A222
    pla                         ; Pop low byte of return address
    pla                         ; Pop high byte of return address
    lda     #0xA2               ; Push high byte first
    pha                         ; (RTS expects high byte deeper in stack)
    lda     #0x21               ; Push low byte: $A222 - 1 = $A221
    pha
_normal_return:
    rts

; ============================================================================
; CircularSlotCalc
; ============================================================================
; Calculate tilemap Y offset using circular buffer position.
; Called from patched code at $A1BA via CircularSlotCalc_ext.
;
; Input: $5D = game's slot counter (0, 2, 4, 6... incremented by 2 per row)
; Output: Y = tilemap offset for circular buffer slot
; Preserves: 16-bit A mode on exit
;
CircularSlotCalc:
    sep     #0x20                   ; 8-bit A
    ; Check if circular buffer mode is active (HDMA enabled)
    lda.l   0x7E0000 + menu_hdma_enable
    beq     _circ_slot_original     ; Not active, use original calculation

    ; Circular buffer Y calculation
    ; NOTE: Game increments $5D by 2 for each row (0, 2, 4, 6, 8, 10, 12, 14, 16, 18)
    ; We must divide by 2 first to get the visual slot (0-9)
    lda.b   0x5d                    ; Load slot counter (0, 2, 4...)
    lsr                             ; Divide by 2 to get visual slot (0-9)
    clc
    adc.l   0x7E0000 + menu_rolling_buffer_pos ; Add buffer_pos
_circ_slot_mod:
    cmp     #MENU_BUFFER_SLOTS      ; >= 11?
    bcc     _circ_slot_done
    sec
    sbc     #MENU_BUFFER_SLOTS      ; Subtract 11 to wrap
    bra     _circ_slot_mod
_circ_slot_done:
    ; A = circular slot (0-10)
    rep     #0x20                   ; 16-bit A
    and.w   #0x00FF                 ; Clear high byte (force 16-bit immediate)
    xba                             ; A = slot * 256
    lsr                             ; A = slot * 128
    clc
    adc.w   #0x0006                 ; + 6 (margin only, $29 already includes border)
    tay                             ; Y = tilemap offset
    rts

_circ_slot_original:
    ; Original game calculation: Y = ($5D / 2) * 128 + 4
    lda.b   0x5d
    lsr                             ; /2
    rep     #0x20                   ; 16-bit A
    and.w   #0x00FF                 ; Clear high byte (force 16-bit immediate)
    xba                             ; *256
    lsr                             ; *128
    clc
    adc.w   #0x0004                 ; +4
    tay
    rts

; --- CircularSlotCalc_ext ---
; Trampoline to call CircularSlotCalc from bank $01 patch at $A1BA
CircularSlotCalc_ext:
    jsr.w   CircularSlotCalc
    rtl

}
