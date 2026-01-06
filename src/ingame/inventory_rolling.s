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

; Scroll State Constants
SCROLL_STATE_IDLE       := 0
SCROLL_STATE_SCROLLING  := 1
SCROLL_PIXELS_PER_FRAME := 2
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

MENU_HDMA_TABLE_ADDR    := 0x9800       ; WRAM offset for HDMA table
MENU_HDMA_TABLE         := 0x7E9800     ; Full 24-bit address
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
    jsr.w   InitMenuHDMATable

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
    cmp.w   #MENU_VISIBLE_ITEMS     ; 10 rows
    bcc     _init_item_rows

    ; Entry 11: Below items - 32 scanlines at BASE + 184
    ; Lock to show area after the 11 item slots (11 * 16 + 8 = 184)
    sep     #0x20
    lda     #32                     ; 32 scanlines
    sta.l   MENU_HDMA_TABLE,x
    inx
    rep     #0x20
    lda.w   menu_rolling_base_scroll
    clc
    adc.w   #184                    ; Lock at base + 184
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
; Rebuilds the direct mode HDMA table for current scroll state.
; Creates the circular buffer effect by varying scroll values per row.
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
    pha                             ; Save $40-$41
    lda.b   0x42
    pha                             ; Save $42-$43

    ; X = table write offset
    ldx.w   #0x0000

    ; Entry 0: Border area - 48 scanlines at BASE scroll (unchanged)
    sep     #0x20                   ; 8-bit A for count byte
    lda     #48
    sta.l   MENU_HDMA_TABLE,x
    inx
    rep     #0x20                   ; 16-bit A for value
    lda.w   menu_rolling_base_scroll
    sta.l   MENU_HDMA_TABLE,x
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
    clc
    adc.w   menu_scroll_anim_offset ; + animation offset
    sta.b   0x40                    ; scroll value for this row

    ; Write entry: count=16, value=scroll
    sep     #0x20                   ; 8-bit for count
    lda     #16                     ; 16 scanlines per item row
    sta.l   MENU_HDMA_TABLE,x
    inx
    rep     #0x20                   ; 16-bit for value
    lda.b   0x40
    sta.l   MENU_HDMA_TABLE,x
    inx
    inx

    ; Next row
    inc.b   0x42
    lda.b   0x42
    cmp.w   #MENU_VISIBLE_ITEMS     ; 10 rows
    bcc     _update_hdma_row_loop

    ; Entry 11: Below items - 32 scanlines at BASE + 184
    sep     #0x20
    lda     #32
    sta.l   MENU_HDMA_TABLE,x
    inx
    rep     #0x20
    lda.w   menu_rolling_base_scroll
    clc
    adc.w   #184                    ; Lock at base + 184
    sta.l   MENU_HDMA_TABLE,x
    inx
    inx

    ; End marker
    sep     #0x20
    lda     #0x00
    sta.l   MENU_HDMA_TABLE,x

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

    ; Save registers and key direct page variables
    rep     #0x20                   ; 16-bit A for pushing
    pha
    lda.b   0x5a
    pha
    lda.b   0x29                    ; Save tilemap buffer pointer
    pha
    sep     #0x20                   ; 8-bit A
    lda.b   0x5d
    pha
    lda.b   0xDB                    ; Save tile attribute byte
    pha

    ; Set $29 = $B600 for BG1 tilemap buffer
    rep     #0x20
    lda.w   #0xB600
    sta.b   0x29
    sep     #0x20

    ; Calculate item data pointer: $1440 + (edge_row * 2)
    lda.w   menu_rolling_edge_row
    asl                             ; * 2 (2 bytes per item)
    clc
    adc     #0x40                   ; Low byte of $1440
    sta.b   0x5a
    lda     #0x14                   ; High byte of $1440
    adc     #0x00                   ; Add carry
    sta.b   0x5b

    ; Determine item palette (enabled=0x00, disabled=0x04) via game's check
    ; Load item ID from ($5A) and call palette determination at $A25D
    stz.b   0x34                    ; Clear $34 (no priority for BG1 items)
    lda.b   (0x5A)                  ; Load item ID
    jsr.w   0xA25D                  ; Sets $DB based on item usability

    ; Set $5d = slot_index (for AND #$01 check, but we patched to AND #$00)
    lda.w   menu_rolling_slot_index
    sta.b   0x5d

    ; Calculate Y = slot_index * 128 + 70
    ; Y is the tilemap offset for this slot
    ; +64 for window border (1 tile row = 32 tiles × 2 bytes)
    ; +6 for left margin (3 tiles)
    rep     #0x20                   ; 16-bit A
    lda.w   menu_rolling_slot_index
    and.w   #0x00FF                 ; Clear high byte
    xba                             ; Swap bytes: A = slot * 256
    lsr                             ; A = slot * 128
    clc
    adc.w   #0x0046                 ; + 70 (64 border + 6 margin)
    tay                             ; Y = tilemap offset
    sep     #0x20                   ; 8-bit A

    ; Call DrawItemSlot inner at $A1ED
    ; Expects: Y = tilemap offset, ($5A) = item pointer, ($29) = tilemap base
    jsr.w   0xA1ED

    ; Restore direct page variables and registers (reverse order)
    pla
    sta.b   0xDB                    ; Restore tile attribute byte
    pla
    sta.b   0x5d
    rep     #0x20
    pla
    sta.b   0x29                    ; Restore tilemap buffer pointer
    pla
    sta.b   0x5a
    pla
    sep     #0x20

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

    ; DON'T pre-render here - the slot coming into view is already pre-rendered
    ; from init or previous scroll. We'll pre-render the NEXT item in FinishScroll.

    ; Advance buffer position FIRST
    inc.w   menu_rolling_buffer_pos
    lda.w   menu_rolling_buffer_pos
    cmp     #MENU_BUFFER_SLOTS
    bcc     _start_down_buf_ok
    stz.w   menu_rolling_buffer_pos
_start_down_buf_ok:

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

    ; DON'T pre-render here - the slot coming into view is already pre-rendered
    ; from previous scroll. We'll pre-render the NEXT item in FinishScroll.

    ; Decrement buffer position FIRST
    lda.w   menu_rolling_buffer_pos
    beq     _start_up_wrap
    dec
    bra     _start_up_wrap_done
_start_up_wrap:
    lda     #MENU_BUFFER_SLOTS - 1
_start_up_wrap_done:
    sta.w   menu_rolling_buffer_pos

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
    stz.w   menu_scroll_anim_offset     ; Clear low byte
    stz.w   menu_scroll_anim_offset + 1 ; Clear high byte
    jsr.w   InitMenuRollingBuffer
    rtl

MenuExitHook_Impl:
    lda     #0x00
    sta.l   0x7E1BAE              ; menu_hdma_enable
    stz.w   menu_scroll_state
    jsr.w   DisableMenuInventoryHDMA
    jsr.w   0x8D6A
    rtl

NmiDmaTransferCheck_Impl:
    lda.w   menu_transfer_pending
    beq     _nmi_done
    stz.w   menu_transfer_pending
    php
    sep     #0x20
    lda     #0x01
    sta.w   0x4300
    lda     #0x18
    sta.w   0x4301
    rep     #0x20
    lda.w   #0xB600
    sta.w   0x4302
    sep     #0x20
    lda     #0x7E
    sta.w   0x4304
    rep     #0x20
    lda.w   #0x0800
    sta.w   0x4305
    lda.w   #0x6000
    sta.w   0x2116
    sep     #0x20
    lda     #0x01
    sta.w   0x420B
    plp
_nmi_done:
    rtl

}
