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
MENU_VISIBLE_ITEMS      := 11       ; Visible items at once
MENU_BUFFER_SLOTS       := 12       ; 12 slots (11 visible + 1 pre-render)
MENU_TOTAL_ITEMS        := 48       ; Total inventory items
MENU_SCROLL_LIMIT       := 37       ; 48 - 11 = max scroll position

; Pixels per item row
MENU_PIXELS_PER_ROW     := 16       ; Pixels per item slot (2 tilemap rows × 8)

; Scroll constants
MENU_SCROLL_WRAP        := 192      ; 12 slots × 16 pixels = 192
; MENU_BASE_SCROLL is read from $93 (BG1VOFS shadow) at runtime

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

; Scroll State Constants
SCROLL_STATE_IDLE       := 0
SCROLL_STATE_SCROLLING  := 1
SCROLL_PIXELS_PER_FRAME := 2
SCROLL_TOTAL_PIXELS     := 16

; ============================================================================
; HDMA Configuration
; ============================================================================
; Use HDMA channel 5 for BG1 vertical scroll during item menu
; HDMA table needs 480 bytes (240 scanlines × 2 bytes per entry)
; Using SRAM at bank $70 in gap between tile_ring ($703FF5) and BATTLE_FLAGS ($704F00)
; Layout: $704000-$70400F = indirect table (16 bytes)
;         $704010-$7041F0 = scroll data (480 bytes)

MENU_HDMA_INDIRECT      := 0x4000       ; Indirect table (16 bytes at $704000)
MENU_HDMA_DATA          := 0x4010       ; SRAM offset for scroll data (480 bytes, ends at $41F0)
MENU_HDMA_TABLE         := 0x704010     ; Full 24-bit address for scroll data
MENU_HDMA_BANK          := 0x70         ; Using bank $70 (SRAM)

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
; HDMA mode: $42 = write 2 bytes, indirect mode
; Register: $210E (BG1VOFS)
; Table format at MENU_HDMA_INDIRECT:
;   $F0, lo, hi  = 240 lines from pointer lo/hi
;   $00          = end
; Data at pointer: 2-byte scroll values (lo, hi) for each line

InitMenuInventoryHDMA:
    php
    sep     #0x20                   ; 8-bit A

    ; First, initialize the HDMA data table
    jsr.w   InitMenuHDMATable

    ; Set up HDMA indirect table at $704000
    ; Format: count, ptr_lo, ptr_hi, ... $00
    ; Count byte: bit 7=1 means repeat (same data for each line)
    ; For 240 unique values, we need bit 7=0, but max count is 127
    ; So we use two entries: 127 lines + 113 lines = 240 total
    sep     #0x20                   ; 8-bit A

    ; Entry 1: 127 lines from $704010
    lda     #0x7F                   ; 127 lines (bit 7 clear = non-repeat)
    sta.l   0x704000
    lda     #0x10                   ; Low byte of $4010
    sta.l   0x704001
    lda     #0x40                   ; High byte of $4010
    sta.l   0x704002

    ; Entry 2: 113 lines from $704010 + (127*2) = $7040FE
    lda     #0x71                   ; 113 lines (127+113=240)
    sta.l   0x704003
    lda     #0xFE                   ; Low byte of $40FE (127*2 = 254 = $FE)
    sta.l   0x704004
    lda     #0x40                   ; High byte of $40FE
    sta.l   0x704005

    ; End marker
    lda     #0x00
    sta.l   0x704006

    ; Configure HDMA channel 5
    ; Must use long addressing - DB may be $7E but registers are at $00:43xx
    lda     #0x42                   ; Mode: indirect, 2 bytes to PPU
    sta.l   HDMA5_CTRL              ; $004350

    lda     #0x0E                   ; BG1VOFS register ($210E)
    sta.l   HDMA5_DEST              ; $004351

    ; Source = indirect table at $704000
    rep     #0x20                   ; 16-bit A
    lda.w   #MENU_HDMA_INDIRECT     ; $4000
    sta.l   HDMA5_SRC_LO            ; $004352-$004353
    sep     #0x20                   ; 8-bit A
    lda     #MENU_HDMA_BANK         ; $70
    sta.l   HDMA5_SRC_BANK          ; $004354

    ; Indirect bank = $70 (where scroll data lives)
    sta.l   HDMA5_IND_BANK          ; $004357

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
; Initializes the HDMA data table with base scroll values
; Creates per-scanline Y scroll values for 11 visible item rows

InitMenuHDMATable:
    php
    rep     #0x30                   ; 16-bit A, X, Y

    ; DEBUG: Fill table with obviously wrong value to test if HDMA works
    ; If HDMA is working, we'd see items WAY shifted
    ; Set HDMA_DEBUG to 0 for normal operation
    HDMA_DEBUG := 0
    .if HDMA_DEBUG {
    ldx.w   #0x0000
    lda.w   #0x0080                 ; Very obviously wrong scroll (128 pixels)
_debug_fill:
    sta.l   MENU_HDMA_TABLE,x
    inx
    inx
    cpx.w   #0x01E0                 ; 480 bytes
    bcc     _debug_fill
    plp
    rts
    }

    ; Fill table with initial scroll values
    ; At init, buffer_pos = 0, so slot 0 shows row 0
    ; Each visible row gets 16 scanlines (2 tilemap rows × 8 pixels)
    ; But we only need 12 scanlines per item row for menu spacing

    ldx.w   #0x0000                 ; Table offset
    ldy.w   #0x0000                 ; Row counter

_init_hdma_row_loop:
    ; Calculate scroll for this row
    ; At init, all rows show sequential items, so scroll = BASE for all
    ; (No circular wrapping needed at init since items are linear)
    lda.w   menu_rolling_base_scroll  ; Use saved base scroll from $93
    sta.b   0x40                    ; Save scroll value (use $40, not $00)

    ; Store for 16 scanlines per row (item height)
    pha
    lda.w   #0x0010                 ; 16 scanlines
    sta.b   0x44                    ; Use $44, not $04
_init_hdma_scanline:
    lda.b   0x40
    sta.l   MENU_HDMA_TABLE,x       ; Long address to SRAM bank $70
    inx
    inx                             ; 2 bytes per entry
    dec.b   0x44
    bne     _init_hdma_scanline
    pla

    ; Next row
    iny
    cpy.w   #MENU_VISIBLE_ITEMS     ; 11 rows
    bcc     _init_hdma_row_loop

    ; Fill remaining scanlines with last value
    lda.b   0x40
_init_hdma_fill:
    cpx.w   #0x01E0                 ; 240 entries × 2 bytes = 480
    bcs     _init_hdma_done
    sta.l   MENU_HDMA_TABLE,x       ; Long address to SRAM bank $70
    inx
    inx
    bra     _init_hdma_fill

_init_hdma_done:
    plp
    rts

; ============================================================================
; UpdateMenuScrollHDMA
; ============================================================================
; Called during menu scroll animation to build HDMA table
; Creates the circular buffer effect by varying scroll values per scanline.
;
; For each visible row, calculates:
;   vram_slot = (buffer_pos + row) mod 6
;   scroll = BASE + (vram_slot * 16) - (row * 12)

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

    ldx.w   #0x0000                 ; HDMA table index (byte offset)
    stz.b   0x42                    ; Row counter

_menu_hdma_row_loop:
    ; Calculate vram_slot = (buffer_pos + row) % MENU_BUFFER_SLOTS
    lda.w   menu_rolling_buffer_pos
    and.w   #0x00FF
    clc
    adc.b   0x42                    ; + row number
_menu_hdma_mod12:
    cmp.w   #MENU_BUFFER_SLOTS      ; >= 12?
    bcc     _menu_hdma_mod12_done
    sec
    sbc.w   #MENU_BUFFER_SLOTS
    bra     _menu_hdma_mod12
_menu_hdma_mod12_done:
    ; A = vram_slot (0-11)

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
    asl                             ; row * 16
    ; A = scanline_offset

    ; scroll = BASE + vram_offset - scanline_offset
    ;eor.w   #0xFFFF                 ; negate (two's complement step 1)
    .db 0x49
    .dw 0xffff
    inc                             ; negate (two's complement step 2)
    clc
    adc.b   0x40                    ; + vram_offset
    clc
    adc.w   menu_rolling_base_scroll ; + BASE (from saved $93)
    sta.b   0x40                    ; scroll value for this row

    ; Store for 16 scanlines (item height = 2 tilemap rows × 8 pixels)
    ldy.w   #0x0010                 ; 16 scanlines
_menu_hdma_scanline_loop:
    lda.b   0x40
    sta.l   MENU_HDMA_TABLE,x       ; Long address to SRAM bank $70
    inx
    inx                             ; X += 2 (2 bytes per scanline)
    dey
    bne     _menu_hdma_scanline_loop

    ; Next row
    inc.b   0x42
    lda.b   0x42
    cmp.w   #MENU_VISIBLE_ITEMS     ; 11 rows
    beq     _menu_hdma_row_done
    jmp     _menu_hdma_row_loop

_menu_hdma_row_done:
    ; Fill remaining scanlines with last scroll value
    lda.b   0x40
_menu_hdma_fill_end:
    cpx.w   #0x01E0                 ; 240 × 2 = 480 bytes
    bcs     _menu_hdma_fill_done
    sta.l   MENU_HDMA_TABLE,x       ; Long address to SRAM bank $70
    inx
    inx
    bra     _menu_hdma_fill_end
_menu_hdma_fill_done:
    ; HDMA is now enabled via shadow variable in NMI hook
    ; No need to write HDMAEN directly here

    ; Restore DP bytes (reverse order)
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
    sta.b   0x46                    ; Loop counter (use $46, avoid low DP)

_menu_init_row_loop:
    lda.b   0x46
    sta.w   menu_rolling_edge_row
    sta.w   menu_rolling_slot_index

    ; Render item to circular buffer slot
    jsr.w   MenuRenderItemToSlot

    inc.b   0x46
    lda.b   0x46
    cmp     #MENU_BUFFER_SLOTS
    bne     _menu_init_row_loop

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

    ; Set $5d = slot_index (for AND #$01 check, but we patched to AND #$00)
    lda.w   menu_rolling_slot_index
    sta.b   0x5d

    ; Calculate Y = slot_index * 128 + 66
    ; Y is the tilemap offset for this slot
    ; +64 for window border (1 tile row = 32 tiles × 2 bytes)
    ; +2 for left margin
    rep     #0x20                   ; 16-bit A
    lda.w   menu_rolling_slot_index
    and.w   #0x00FF                 ; Clear high byte
    xba                             ; Swap bytes: A = slot * 256
    lsr                             ; A = slot * 128
    clc
    adc.w   #0x0042                 ; + 66 (64 border + 2 margin)
    tay                             ; Y = tilemap offset
    sep     #0x20                   ; 8-bit A

    ; Call DrawItemSlot inner at $A1ED
    ; Expects: Y = tilemap offset, ($5A) = item pointer, ($29) = tilemap base
    jsr.w   0xA1ED

    ; Restore direct page variables and registers
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

    ; Pre-render the edge item (same as MenuScrollDownPrepare)
    ; Calculate new bottom item = scroll_pos + VISIBLE_ITEMS
    lda.w   0x1B1A                  ; Current scroll position (already incremented)
    clc
    adc     #MENU_VISIBLE_ITEMS - 1 ; -1 because 1B1A already incremented
    sta.w   menu_rolling_edge_row

    ; The slot scrolling OFF the top will be reused for new bottom item
    lda.w   menu_rolling_buffer_pos
    sta.w   menu_rolling_slot_index

    ; Render item to the slot that's scrolling off
    jsr.w   MenuRenderItemToSlot

    ; Advance buffer position
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

    ; Decrement buffer position first
    lda.w   menu_rolling_buffer_pos
    beq     _start_up_wrap
    dec
    bra     _start_up_wrap_done
_start_up_wrap:
    lda     #MENU_BUFFER_SLOTS - 1
_start_up_wrap_done:
    sta.w   menu_rolling_buffer_pos
    sta.w   menu_rolling_slot_index

    ; Calculate new top item = scroll_pos (already decremented by trigger)
    lda.w   0x1B1A
    sta.w   menu_rolling_edge_row

    ; Render item to the new top slot
    jsr.w   MenuRenderItemToSlot

    ; Set up scroll state machine
    lda     #SCROLL_STATE_SCROLLING
    sta.w   menu_scroll_state
    lda     #SCROLL_TOTAL_PIXELS
    sta.w   menu_scroll_remaining
    lda     #0xFE                   ; -2 (two's complement) for up
    sta.w   menu_scroll_direction

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
; Updates $93 (BG1VOFS shadow), HDMA table, and cursor sprite position.

UpdateScrollFrame:
    php

    ; Update $93 scroll value (16-bit operation)
    rep     #0x20                   ; 16-bit A
    lda.b   0x93                    ; BG1VOFS shadow (D=$0100, so $0193)
    clc
    ; Add direction (sign-extended from 8-bit)
    sep     #0x20
    lda.w   menu_scroll_direction
    bpl     _scroll_frame_positive
    ; Negative direction (scrolling up)
    rep     #0x20
    lda.b   0x93
    sec
    sbc.w   #SCROLL_PIXELS_PER_FRAME
    sta.b   0x93
    bra     _scroll_frame_update_cursor

_scroll_frame_positive:
    ; Positive direction (scrolling down)
    rep     #0x20
    lda.b   0x93
    clc
    adc.w   #SCROLL_PIXELS_PER_FRAME
    sta.b   0x93

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
    sep     #0x20                   ; 8-bit A

    ; Reset scroll state to idle
    stz.w   menu_scroll_state

    ; Call original post-scroll cleanup routines
    jsr.w   0xA105                  ; DrawItemCursors
    jsr.w   0x82A5                  ; UpdateCtrlAfterScroll (was incorrectly $A134)

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
