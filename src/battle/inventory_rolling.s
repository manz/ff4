; ============================================================================
; Rolling Buffer Implementation for Battle Inventory (Single Column)
; ============================================================================
;
; Single-column layout with circular buffer, matching FF6's approach.
; Only 5 visible rows are rendered, with edge rows pre-rendered on scroll.
;
; Key insight: Render BEFORE scroll animation starts (not after).
;
; See docs/ff6_rolling_inventory_analysis.md for design rationale.
;
; ============================================================================

; ============================================================================
; CONSTANTS
; ============================================================================

; Layout (single column)
VISIBLE_ROWS            := 5        ; Rows visible on screen
BUFFER_SLOTS            := 6        ; 6 slots for 5 visible (1 off-screen for pre-render)
TOTAL_ITEMS             := 48       ; Total inventory items
TOTAL_ROWS              := 48       ; One item per row now

; Buffer sizes
TEXT_BYTES_PER_ITEM     := 60       ; 30 tiles x 2 bytes (dakuten + main rows)
TILEMAP_BYTES_PER_ROW   := 128      ; 2 tilemap rows x 64 bytes ($80)

; Memory addresses
text_buffer_base        := 0x8EA6   ; Text buffer (formatted tiles)
tilemap_buffer_base     := 0xC4E6   ; Tilemap buffer
tilemap_content_offset  := 0x44     ; Offset to content area ($C52A - $C4E6)

; ============================================================================
; RAM VARIABLES (Using unused battle RAM)
; ============================================================================
; $EF97-$EF99 are explicitly marked "unused" in RAM map
; $EF82 is marked "-" (unused)

rolling_top_row         := 0xEF97   ; Top visible row index (0-43)
rolling_buffer_pos      := 0xEF98   ; Circular buffer position (0-4)
rolling_edge_row        := 0xEF99   ; Row index to render (0-47)
rolling_slot_index      := 0xEF82   ; Current slot index for rendering (0-5)
                                    ; NOTE: Using $EF82 instead of $1817 to avoid conflicts with NMI/battle commands

; ============================================================================
; VRAM CIRCULAR BUFFER SLOTS (FF6-style)
; ============================================================================
; 5 fixed slots for visible rows, each 128 bytes (2 tilemap rows)
; Total VRAM usage: 640 bytes (vs 3072+ for linear)
;
; The HDMA scroll offset rotates which slot appears at which screen row.
; When scrolling down: slot[circular_pos] becomes new bottom, circular_pos++
; When scrolling up: circular_pos--, slot[circular_pos] becomes new top

VRAM_SLOT_SIZE          := 0x80     ; 128 bytes per slot (2 tilemap rows)
VRAM_SLOT_BASE          := 0x7400   ; Base VRAM address for slots

; VRAM slot addresses - MUST match actual content positions after transfer!
; VRAM uses WORD addresses (2 bytes per word).
; Content goes to WRAM tilemap_buffer_base + tilemap_content_offset ($C4E6 + $44 = $C52A)
; Entry 3 transfers from $C4E6 to VRAM $7400, size $0400 bytes = $200 words
; WRAM byte offset $44 = VRAM word offset $22 (divide by 2)
; So $C52A maps to VRAM $7400 + $22 = $7422
; Each WRAM slot is $80 bytes = $40 VRAM words (64 words = 2 tilemap rows = 16 pixels)
vram_slot_table:
    .dw     0x7422              ; Slot 0 (content at $7400 + $22 words)
    .dw     0x7462              ; Slot 1 (+$40 words)
    .dw     0x74A2              ; Slot 2 (+$40 words)
    .dw     0x74E2              ; Slot 3 (+$40 words)
    .dw     0x7522              ; Slot 4 (+$40 words)
    .dw     0x7562              ; Slot 5 (off-screen pre-render slot)

; Tilemap buffer slots (mirror of VRAM slots in WRAM)
; Each slot is 128 bytes at tilemap_buffer_base + slot * 128
TILEMAP_SLOT_BASE       := tilemap_buffer_base + tilemap_content_offset

; ============================================================================
; InitInventoryTextBuf_Rolling
; ============================================================================
; Replacement for $029E9C - renders only 5 visible rows
; Called when inventory window opens
;
; Input: None (reads $EF71 for current scroll position)
; Output: Text buffer populated with 5 visible items
; Clobbers: A, X, Y, $00-$06, $26-$2A

InitInventoryTextBuf_Rolling:
    ; Set data bank to $7E for WRAM access
    phb
    lda     #0x7E
    pha
    plb

    ; Initialize rolling buffer state
    ; At init time, always start at row 0 (top of inventory)
    ; NOTE: EF65 and EF67 are initialized by ResetListScrollHDMA when inventory opens
    stz.w   0xEF71                  ; Game's row index = 0
    stz.w   rolling_top_row
    stz.w   rolling_buffer_pos
    ; Note: Game's $4A flag (bit 2) already indicates inventory is active

    ; Render 6 rows to circular slots (5 visible + 1 off-screen)
    ; At init, item index = slot index (both 0-5)
    lda     #0
    sta.b   0x06                    ; Slot index (0-5)

_init_row_loop:
    ; For init: item index = slot index
    lda.b   0x06
    sta.w   rolling_edge_row        ; Item index for data lookup
    sta.w   rolling_slot_index      ; Slot index for buffer position

    ; Save slot index
    lda.b   0x06
    pha

    ; Render item to circular slot
    jsr.w   _RenderItemToCircularSlot

    ; Restore slot index
    pla
    sta.b   0x06

    ; Next slot
    inc.b   0x06
    lda.b   0x06
    cmp     #BUFFER_SLOTS           ; 6 slots total
    bne     _init_row_loop

    ; Queue VRAM transfer for initial render
    lda     #0x03
    ldy.w   #0x0002
    jsr.l   LoadMenuTfrData_Trampoline
    lda     #0x01
    sta.w   0x1825
    sta.w   0x1824

    plb                             ; Restore data bank
    rtl

; ============================================================================
; _RenderInventoryItem
; ============================================================================
; Renders a single inventory item to text buffer
;
; Input: rolling_slot_index = item slot index (0-47)
; Output: Item rendered to text buffer
; Clobbers: A, X, Y, $00-$02, $26-$2A

_RenderInventoryItem:
    ; Set data bank to $7E for WRAM access
    phb
    lda     #0x7E
    pha
    plb

    ; Calculate text buffer destination
    ; text_addr = text_buffer_base + (slot x TEXT_BYTES_PER_ITEM)
    lda.w   rolling_slot_index
    sta.b   0x26
    lda     #TEXT_BYTES_PER_ITEM
    sta.b   0x28
    jsr.l   Mult8_Trampoline

    rep     #0x20
    lda.b   0x2A
    clc
    adc     #text_buffer_base
    sta.w   0xEF52                  ; DrawText output destination
    tdc
    sep     #0x20

    ; Set up format buffer pointer
    ldx.w   #0x74FD
    stx.w   0xEF50

    ; Set tile count for DrawText
    lda     #15                     ; 15 tiles per line
    sta.w   0xEF54

    ; Get item data from game inventory
    ; Inventory structure: 4 bytes per slot at $321A
    ;   $321A+0: flags (bit 7 = disabled)
    ;   $321A+1: item ID
    ;   $321A+2: quantity
    ;   $321A+3: ???
    tdc                             ; Clear B before TAX
    lda.w   rolling_slot_index
    asl
    asl                             ; x 4 bytes per item
    tax

    lda.l   0x7E321B,x              ; Item ID (WRAM)
    sta.b   0x02                    ; Save for later
    sta.b   0x26                    ; For name lookup
    lda.l   0x7E321C,x              ; Quantity (WRAM)
    pha                             ; Save quantity

    ; Determine palette (white=enabled, gray=disabled)
    lda     #0x00
    sta.b   0x00                    ; Palette for name
    sta.b   0x01                    ; Palette for symbol
    lda.l   0x7E321A,x              ; Flags (WRAM)
    and     #0x80
    beq     _not_disabled
    lda     #0x04                   ; Gray palette
    sta.b   0x00
    sta.b   0x01
_not_disabled:

    ; Calculate item name address: assets_items_dat + (id x 12)
    ; Must use 16-bit math since id x 12 can exceed 255
    rep     #0x20                   ; 16-bit A
    lda.b   0x02                    ; Load (will get $02-$03)
    and.w   #0x00FF                 ; Mask to item ID only
    sta.b   0x08                    ; Save original ID
    asl                             ; x2
    clc
    adc.b   0x08                    ; x3
    asl
    asl                             ; x12
    tax
    sep     #0x20                   ; Back to 8-bit

    ; Build format string in $74FD (protected by inventory-active skip checks)
    ldy.w   #0x0000

    ; Format code: change tile flags
    lda     #0x0E
    sta.w   0x74FD,y
    iny
    lda.b   0x01                    ; Symbol palette
    sta.w   0x74FD,y
    iny

    ; Format code: set tile (symbol)
    lda     #0x03
    sta.w   0x74FD,y
    iny
    lda.l   assets_items_dat,x      ; Item symbol
    sta.w   0x74FD,y
    iny

    ; Format code: change tile flags (for name)
    lda     #0x0E
    sta.w   0x74FD,y
    iny
    lda.b   0x00                    ; Name palette
    sta.w   0x74FD,y
    iny

    ; Copy 11 character item name
    lda     #11
    sta.b   0x00                    ; Loop counter
_name_copy_loop:
    inx
    lda.l   assets_items_dat,x
    sta.w   0x74FD,y
    iny
    dec.b   0x00
    bne     _name_copy_loop

    ; Handle quantity or empty slot
    lda.b   0x02                    ; Item ID
    bne     _has_item

    ; Empty slot - just finish with line break
    pla                             ; Discard quantity
    lda     #0x05                   ; Line break
    sta.w   0x74FD,y
    iny
    lda     #0x03
    bra     _finish_format

_has_item:
    ; Add colon and quantity
    lda     #0xC8                   ; Colon character ":"
    sta.w   0x74FD,y
    iny

    pla                             ; Get quantity
    tax
    jsr.l   HexToDec_Trampoline     ; Convert to decimal
    jsr.l   NormalizeNum_Trampoline ; Format digits

    ; Add tens digit
    lda     #0x03
    sta.w   0x74FD,y
    iny
    lda.w   0x180E                  ; Tens digit
    sta.w   0x74FD,y
    iny

    ; Add ones digit
    lda     #0x03
    sta.w   0x74FD,y
    iny
    lda.w   0x180F                  ; Ones digit

_finish_format:
    sta.w   0x74FD,y
    iny

    ; Terminator
    lda     #0x00
    sta.w   0x74FD,y

    ; Call DrawText to render formatted text to text buffer
    jsr.l   DrawText_Rolling_Trampoline

    plb                             ; Restore data bank
    rts

; ============================================================================
; _RenderInventoryItemCircular
; ============================================================================
; Renders item to circular buffer slot
;
; Input: rolling_edge_row = item index (0-47) for data lookup
;        rolling_slot_index = buffer slot (0-4) for destination
; Output: Item rendered to text buffer at slot position
; Clobbers: A, X, Y, $00-$02, $26-$2A

_RenderInventoryItemCircular:
    phb
    lda     #0x7E
    pha
    plb

    ; Calculate text buffer destination using SLOT (not item index)
    ; text_addr = text_buffer_base + (slot x TEXT_BYTES_PER_ITEM)
    lda.w   rolling_slot_index                  ; Buffer slot (0-4)
    sta.b   0x26
    lda     #TEXT_BYTES_PER_ITEM
    sta.b   0x28
    jsr.l   Mult8_Trampoline

    rep     #0x20
    lda.b   0x2A
    clc
    adc     #text_buffer_base
    sta.w   0xEF52                  ; DrawText output destination
    tdc
    sep     #0x20

    ; Set up format buffer pointer
    ldx.w   #0x74FD
    stx.w   0xEF50

    ; Set tile count for DrawText
    lda     #15                     ; 15 tiles per line
    sta.w   0xEF54

    ; Get item data using ITEM INDEX (rolling_edge_row), not slot
    tdc
    lda.w   rolling_edge_row        ; Item index (0-47)
    asl
    asl                             ; x 4 bytes per item
    tax

    lda.l   0x7E321B,x              ; Item ID
    sta.b   0x02
    sta.b   0x26
    lda.l   0x7E321C,x              ; Quantity
    pha

    ; Determine palette
    lda     #0x00
    sta.b   0x00
    sta.b   0x01
    lda.l   0x7E321A,x              ; Flags
    and     #0x80
    beq     _circ_not_disabled
    lda     #0x04
    sta.b   0x00
    sta.b   0x01
_circ_not_disabled:

    ; Calculate item name address: assets_items_dat + (id x 12)
    rep     #0x20
    lda.b   0x02
    and.w   #0x00FF
    sta.b   0x08
    asl
    clc
    adc.b   0x08
    asl
    asl
    tax
    sep     #0x20

    ; Build format string in $74FD (protected by inventory-active skip checks)
    ldy.w   #0x0000

    ; Tile flags for symbol
    lda     #0x0E
    sta.w   0x74FD,y
    iny
    lda.b   0x01
    sta.w   0x74FD,y
    iny

    ; Symbol tile
    lda     #0x03
    sta.w   0x74FD,y
    iny
    lda.l   assets_items_dat,x
    sta.w   0x74FD,y
    iny

    ; Tile flags for name
    lda     #0x0E
    sta.w   0x74FD,y
    iny
    lda.b   0x00
    sta.w   0x74FD,y
    iny

    ; 11-char name
    lda     #11
    sta.b   0x00
_circ_name_loop:
    inx
    lda.l   assets_items_dat,x
    sta.w   0x74FD,y
    iny
    dec.b   0x00
    bne     _circ_name_loop

    ; Quantity handling
    lda.b   0x02
    bne     _circ_has_item

    pla
    lda     #0x05
    sta.w   0x74FD,y
    iny
    lda     #0x03
    bra     _circ_finish

_circ_has_item:
    lda     #0xC8                   ; Colon
    sta.w   0x74FD,y
    iny

    pla
    tax
    jsr.l   HexToDec_Trampoline
    jsr.l   NormalizeNum_Trampoline

    lda     #0x03
    sta.w   0x74FD,y
    iny
    lda.w   0x180E
    sta.w   0x74FD,y
    iny

    lda     #0x03
    sta.w   0x74FD,y
    iny
    lda.w   0x180F

_circ_finish:
    sta.w   0x74FD,y
    iny

    lda     #0x00
    sta.w   0x74FD,y

    jsr.l   DrawText_Rolling_Trampoline

    plb
    rts

; ============================================================================
; _CopyItemToTilemapCircular
; ============================================================================
; Copies item from text buffer slot to tilemap slot (circular buffer)
;
; Input: rolling_slot_index = buffer slot (0-4)
; Output: Item copied to tilemap buffer at slot position
; Clobbers: A, X, Y, $00-$06

_CopyItemToTilemapCircular:
    ; Save DBR - Mult8_Trampoline may change it
    phb
    lda     #0x7E
    pha
    plb                             ; Ensure DBR is $7E for WRAM access

    ; Calculate tilemap buffer address for this SLOT (not item index)
    ; tilemap_addr = tilemap_buffer_base + (slot x TILEMAP_BYTES_PER_ROW)
    ; NO content_offset - write to full 128-byte slot
    lda.w   rolling_slot_index                  ; Buffer slot (0-4)
    sta.b   0x26
    lda     #TILEMAP_BYTES_PER_ROW
    sta.b   0x28
    jsr.l   Mult8_Trampoline

    rep     #0x20
    lda.b   0x2A
    clc
    adc     #tilemap_buffer_base + tilemap_content_offset             ; NO +tilemap_content_offset!
    sta.b   0x00                    ; Tilemap destination
    sep     #0x20

    ; Calculate text buffer source using SLOT
    lda.w   rolling_slot_index
    sta.b   0x26
    lda     #TEXT_BYTES_PER_ITEM
    sta.b   0x28
    jsr.l   Mult8_Trampoline

    rep     #0x20
    lda.b   0x2A
    tax
    sep     #0x20

    ; Copy first tilemap row (30 bytes)
    ldy.w   #0x0000
_circ_copy_row1:
    lda.w   text_buffer_base,x
    sta     (0x00),y
    inx
    iny
    cpy.w   #30
    bne     _circ_copy_row1

    ; Clear remaining bytes of first row (30-63) to prevent stale border tiles
    ; Fill with $FF (blank tile) and $00 (palette 0)
_circ_clear_row1:
    lda     #0xFF                   ; Blank tile
    sta     (0x00),y
    iny
    lda     #0x00                   ; Palette 0
    sta     (0x00),y
    iny
    cpy.w   #0x0040
    bne     _circ_clear_row1

    ; Copy second tilemap row (+$40 offset)
    ldy.w   #0x0040
_circ_copy_row2:
    lda.w   text_buffer_base,x
    sta     (0x00),y
    inx
    iny
    cpy.w   #0x005E
    bne     _circ_copy_row2

    ; Clear remaining bytes of second row (0x5E-0x7F)
_circ_clear_row2:
    lda     #0xFF                   ; Blank tile
    sta     (0x00),y
    iny
    lda     #0x00                   ; Palette 0
    sta     (0x00),y
    iny
    cpy.w   #0x0080
    bne     _circ_clear_row2

    ; Restore DBR
    plb
    rts

; ============================================================================
; _CopyItemToTilemap
; ============================================================================
; Copies a single item from text buffer to the correct tilemap position
; (Used for initial rendering where slot = item index)
;
; Input: rolling_slot_index = item slot index (0-47)
; Output: Item copied to tilemap buffer
; Clobbers: A, X, Y, $00-$06

_CopyItemToTilemap:
    ; Calculate row index from slot (same as slot for single column)
    lda.w   rolling_slot_index
    sta.b   0x04                    ; Save row index

    ; Calculate tilemap buffer address for this row
    ; tilemap_addr = tilemap_buffer_base + (row x TILEMAP_BYTES_PER_ROW)
    sta.b   0x26
    lda     #TILEMAP_BYTES_PER_ROW
    sta.b   0x28
    jsr.l   Mult8_Trampoline

    ; Add content offset (left column position)
    rep     #0x20
    lda.b   0x2A
    clc
    adc     #tilemap_buffer_base + tilemap_content_offset
    sta.b   0x00                    ; Tilemap destination
    sep     #0x20

    ; Calculate text buffer source offset
    lda.w   rolling_slot_index
    sta.b   0x26
    lda     #TEXT_BYTES_PER_ITEM
    sta.b   0x28
    jsr.l   Mult8_Trampoline

    rep     #0x20
    lda.b   0x2A                    ; Get offset (slot x 60)
    tax                             ; X = offset into text buffer
    sep     #0x20

    ; Copy first tilemap row (30 bytes = 15 tiles)
    ldy.w   #0x0000
_copy_row1:
    lda.w   text_buffer_base,x      ; Read from $8EA6 + offset
    sta     (0x00),y                ; Write to tilemap buffer
    inx
    iny
    cpy.w   #30
    bne     _copy_row1

    ; Copy second tilemap row (30 bytes)
    ; Tilemap row 2 is at +$40 (64 bytes) from row 1
    ldy.w   #0x0040
_copy_row2:
    lda.w   text_buffer_base,x      ; Read from $8EA6 + offset
    sta     (0x00),y
    inx
    iny
    cpy.w   #0x005E                 ; $40 + 30 = $5E
    bne     _copy_row2

    rts

; ============================================================================
; RenderBottomEdgeRow
; ============================================================================
; Pre-renders the new bottom row BEFORE scroll down animation starts
; Uses circular buffer - writes to the slot that's scrolling OUT (top slot)
; After scroll, that slot will appear at the bottom
;
; Called via JSL from bank 02

RenderBottomEdgeRow:
    ; Disable interrupts to prevent NMI from corrupting rolling_slot_index
    sei

    ; Set data bank to $7E for WRAM access
    phb
    lda     #0x7E
    pha
    plb

    ; Calculate the new bottom item index
    ; new_bottom = current_top + BUFFER_SLOTS (the item that will be at bottom after scroll)
    ; With 6 slots and 5 visible, this is the item we need to pre-render
    lda.w   0xEF71
    clc
    adc     #BUFFER_SLOTS

    ; Check bounds (max item is 47)
    cmp     #TOTAL_ITEMS
    bcs     _render_bottom_done     ; Past end, nothing to render

    sta.w   rolling_edge_row        ; Save item index for data lookup

    ; CIRCULAR BUFFER: Write to OFF-SCREEN slot (below bottom)
    ; Off-screen slot = (rolling_buffer_pos + 5) % 6
    ; This slot is currently invisible and will scroll into view at bottom
    lda.w   rolling_buffer_pos
    clc
    adc     #VISIBLE_ROWS           ; +5 to get to off-screen slot
    cmp     #BUFFER_SLOTS
    bcc     _bottom_slot_ok
    sec
    sbc     #BUFFER_SLOTS           ; Wrap if >= 6
_bottom_slot_ok:
    sta.w   rolling_slot_index                  ; Slot index (0-5) for buffer positioning

    ; Render item data to this circular slot
    jsr.w   _RenderItemToCircularSlot

    ; Queue full tilemap transfer (game's VBlank will handle it)
    lda     #0x03
    ldy.w   #0x0002
    jsr.l   LoadMenuTfrData_Trampoline
    lda     #0x01
    sta.w   0x1825
    sta.w   0x1824

    ; Advance circular position (top slot advances as we scroll down)
    lda.w   rolling_buffer_pos
    inc
    cmp     #BUFFER_SLOTS
    bcc     _store_pos_down
    lda     #0
_store_pos_down:
    sta.w   rolling_buffer_pos

_render_bottom_done:
    plb                             ; Restore data bank
    .db 0x58                        ; cli - re-enable interrupts
    rts                             ; Called from within bank $20 now

; ============================================================================
; RenderTopEdgeRow
; ============================================================================
; Pre-renders the new top row BEFORE scroll up animation starts
; Uses circular buffer - writes to the slot that's scrolling OUT (bottom slot)
; After scroll, that slot will appear at the top
;
; Called via JSL from bank 02

RenderTopEdgeRow:
    ; Disable interrupts to prevent NMI from corrupting rolling_slot_index
    sei

    ; Set data bank to $7E for WRAM access
    phb
    lda     #0x7E
    pha
    plb

    ; Calculate the new top item index
    ; new_top = current_top - 1
    lda.w   0xEF71
    dec                             ; New top row after scroll

    ; Check bounds
    bmi     _render_top_done        ; Negative = invalid

    sta.w   rolling_edge_row        ; Save item index for data lookup

    ; CIRCULAR BUFFER: Write to slot BEFORE current circular_pos
    ; This slot will become the new TOP after scroll
    ; First decrement circular_pos, then write to that slot
    lda.w   rolling_buffer_pos
    dec
    bpl     _store_pos_up
    lda     #BUFFER_SLOTS - 1       ; Wrap 0→5
_store_pos_up:
    sta.w   rolling_buffer_pos      ; Update position FIRST for scroll up
    sta.w   rolling_slot_index                  ; Slot index (0-5) for buffer positioning

    ; Render item data to this circular slot
    jsr.w   _RenderItemToCircularSlot

    ; Queue full tilemap transfer (game's VBlank will handle it)
    lda     #0x03
    ldy.w   #0x0002
    jsr.l   LoadMenuTfrData_Trampoline
    lda     #0x01
    sta.w   0x1825
    sta.w   0x1824

_render_top_done:
    plb                             ; Restore data bank
    .db 0x58                        ; cli - re-enable interrupts
    rts                             ; Called from within bank $20 now

; ============================================================================
; _RenderItemToCircularSlot
; ============================================================================
; Renders item to a circular buffer slot
;
; Input: rolling_edge_row = item index (0-47) for data lookup
;        rolling_slot_index = slot index (0-4) for destination
; Output: Item rendered to text buffer slot, copied to tilemap slot

_RenderItemToCircularSlot:
    ; Save processor status and disable interrupts
    ; Using PHP/PLP instead of SEI/CLI to handle nested calls correctly
    php
    sei

    ; Save DBR - DrawText may change it and we need it for tilemap copy
    phb

    ; Save D and set to $0000 for direct page operations
    rep     #0x20
    tdc
    pha                             ; Save original D on stack
    lda.w   #0x0000
    tcd
    sep     #0x20

    ; CRITICAL: Save zero page variables on stack
    ; This prevents corruption if NMI fires during game's block copy
    ; Save $00-$0B (block copy uses $00-$06) and $26-$2B (Mult8 uses these)
    lda.b   0x00
    pha
    lda.b   0x01
    pha
    lda.b   0x02
    pha
    lda.b   0x03
    pha
    lda.b   0x04
    pha
    lda.b   0x05
    pha
    lda.b   0x06
    pha
    lda.b   0x07
    pha
    lda.b   0x08
    pha
    lda.b   0x09
    pha
    lda.b   0x0A
    pha
    lda.b   0x0B
    pha
    ; Also save $26-$2B used by Mult8_Trampoline
    lda.b   0x26
    pha
    lda.b   0x27
    pha
    lda.b   0x28
    pha
    lda.b   0x29
    pha
    lda.b   0x2A
    pha
    lda.b   0x2B
    pha

    ; Calculate text buffer destination for this SLOT
    ; text_addr = text_buffer_base + (slot × TEXT_BYTES_PER_ITEM)
    lda.w   rolling_slot_index                  ; Slot index (0-4)
    sta.b   0x26
    lda     #TEXT_BYTES_PER_ITEM    ; 60 bytes per slot
    sta.b   0x28
    jsr.l   Mult8_Trampoline

    rep     #0x20
    lda.b   0x2A
    clc
    adc     #text_buffer_base
    sta.w   0xEF52                  ; DrawText output destination
    tdc
    sep     #0x20

    ; Set up format buffer pointer
    ldx.w   #0x74FD
    stx.w   0xEF50
    lda     #15
    sta.w   0xEF54

    ; Get item data using rolling_edge_row (the actual item index)
    tdc
    lda.w   rolling_edge_row
    asl
    asl
    tax

    lda.l   0x7E321B,x              ; Item ID
    sta.b   0x02
    lda.l   0x7E321C,x              ; Quantity
    pha

    ; Palette selection
    lda     #0x00
    sta.b   0x00
    sta.b   0x01
    lda.l   0x7E321A,x
    and     #0x80
    beq     _slot_not_disabled
    lda     #0x04
    sta.b   0x00
    sta.b   0x01
_slot_not_disabled:

    ; Calculate item name offset
    rep     #0x20
    lda.b   0x02
    and.w   #0x00FF
    sta.b   0x08
    asl
    clc
    adc.b   0x08
    asl
    asl
    tax
    sep     #0x20

    ; Build format string
    ldy.w   #0x0000
    lda     #0x0E
    sta.w   0x74FD,y
    iny
    lda.b   0x01
    sta.w   0x74FD,y
    iny
    lda     #0x03
    sta.w   0x74FD,y
    iny
    lda.l   assets_items_dat,x
    sta.w   0x74FD,y
    iny
    lda     #0x0E
    sta.w   0x74FD,y
    iny
    lda.b   0x00
    sta.w   0x74FD,y
    iny

    lda     #11
    sta.b   0x00
_slot_name_loop:
    inx
    lda.l   assets_items_dat,x
    sta.w   0x74FD,y
    iny
    dec.b   0x00
    bne     _slot_name_loop

    lda.b   0x02
    bne     _slot_has_item
    pla
    lda     #0x05
    sta.w   0x74FD,y
    iny
    lda     #0x03
    bra     _slot_finish

_slot_has_item:
    lda     #0xC8
    sta.w   0x74FD,y
    iny
    pla
    tax
    jsr.l   HexToDec_Trampoline
    jsr.l   NormalizeNum_Trampoline
    lda     #0x03
    sta.w   0x74FD,y
    iny
    lda.w   0x180E
    sta.w   0x74FD,y
    iny
    lda     #0x03
    sta.w   0x74FD,y
    iny
    lda.w   0x180F

_slot_finish:
    sta.w   0x74FD,y
    iny
    lda     #0x00
    sta.w   0x74FD,y

    jsr.l   DrawText_Rolling_Trampoline

    ; DrawText fills text buffer - tilemap copy is done separately by:
    ; - _CopyAllSlotsToTilemap in TfrInventoryList_Rolling (for init)
    ; - _CopySlotToTilemap in scroll hooks (for scrolling)

    ; CRITICAL: Restore zero page variables from stack (reverse order)
    ; First restore $26-$2B (last pushed)
    pla
    sta.b   0x2B
    pla
    sta.b   0x2A
    pla
    sta.b   0x29
    pla
    sta.b   0x28
    pla
    sta.b   0x27
    pla
    sta.b   0x26
    ; Then restore $00-$0B
    pla
    sta.b   0x0B
    pla
    sta.b   0x0A
    pla
    sta.b   0x09
    pla
    sta.b   0x08
    pla
    sta.b   0x07
    pla
    sta.b   0x06
    pla
    sta.b   0x05
    pla
    sta.b   0x04
    pla
    sta.b   0x03
    pla
    sta.b   0x02
    pla
    sta.b   0x01
    pla
    sta.b   0x00

    ; Restore D before returning
    rep     #0x20
    pla
    tcd
    sep     #0x20

    ; Restore DBR (DrawText may have changed it)
    plb

    ; Restore processor status (including interrupt flag)
    plp
    rts

; ============================================================================
; _TransferCircularSlot
; ============================================================================
; Transfers a single circular slot to its fixed VRAM address
; Uses direct DMA instead of menu transfer system for precise control
;
; Input: rolling_slot_index = slot index (0-4)
; Output: 128 bytes transferred to VRAM

_TransferCircularSlot:
    ; Save processor status and disable interrupts
    php
    sei

    ; Save DBR - Mult8_Trampoline may change it
    phb
    lda     #0x7E
    pha
    plb                             ; Ensure DBR is $7E for WRAM access

    ; CRITICAL: Save zero page variables on stack
    ; This prevents corruption if NMI fires during game's block copy
    ; Save $00-$0B (block copy uses $00-$06) and $26-$2B (Mult8 uses these)
    lda.b   0x00
    pha
    lda.b   0x01
    pha
    lda.b   0x02
    pha
    lda.b   0x03
    pha
    lda.b   0x04
    pha
    lda.b   0x05
    pha
    lda.b   0x06
    pha
    lda.b   0x07
    pha
    lda.b   0x08
    pha
    lda.b   0x09
    pha
    lda.b   0x0A
    pha
    lda.b   0x0B
    pha
    ; Also save $26-$2B used by Mult8_Trampoline
    lda.b   0x26
    pha
    lda.b   0x27
    pha
    lda.b   0x28
    pha
    lda.b   0x29
    pha
    lda.b   0x2A
    pha
    lda.b   0x2B
    pha

    ; Look up VRAM destination from slot table
    lda.w   rolling_slot_index
    asl                             ; ×2 for word lookup
    tax
    rep     #0x20
    lda.l   vram_slot_table,x       ; Get VRAM address ($7400, $7480, etc.)
    sta.b   0x04                    ; Save VRAM dest
    sep     #0x20

    ; Calculate tilemap buffer source
    ; source = tilemap_buffer_base + (slot × 128) - NO content_offset!
    lda.w   rolling_slot_index
    sta.b   0x26
    lda     #TILEMAP_BYTES_PER_ROW
    sta.b   0x28
    jsr.l   Mult8_Trampoline

    rep     #0x20
    lda.b   0x2A
    clc
    adc     #tilemap_buffer_base + tilemap_content_offset              ; NO +tilemap_content_offset!
    sta.b   0x00                    ; Source address (low word)
    sep     #0x20

    ; Queue using menu transfer system (entry 3 covers our slots)
    ; The transfer will include this slot since it's at the right offset
    lda     #0x03
    ldy.w   #0x0002
    jsr.l   LoadMenuTfrData_Trampoline

    lda     #0x01
    sta.w   0x1825
    sta.w   0x1824

    ; CRITICAL: Restore zero page variables from stack (reverse order)
    ; First restore $26-$2B (last pushed)
    pla
    sta.b   0x2B
    pla
    sta.b   0x2A
    pla
    sta.b   0x29
    pla
    sta.b   0x28
    pla
    sta.b   0x27
    pla
    sta.b   0x26
    ; Then restore $00-$0B
    pla
    sta.b   0x0B
    pla
    sta.b   0x0A
    pla
    sta.b   0x09
    pla
    sta.b   0x08
    pla
    sta.b   0x07
    pla
    sta.b   0x06
    pla
    sta.b   0x05
    pla
    sta.b   0x04
    pla
    sta.b   0x03
    pla
    sta.b   0x02
    pla
    sta.b   0x01
    pla
    sta.b   0x00

    ; Restore DBR
    plb

    ; Restore processor status (including interrupt flag)
    plp
    rts

; ============================================================================
; _CopySlotToTilemap
; ============================================================================
; Copies a single slot from text buffer to tilemap buffer
; Input: rolling_slot_index = slot index (0-5)
; Uses $00-$01, $26, $28, $2A, X, Y

_CopySlotToTilemap:
    ; Save processor status and disable interrupts
    ; Using PHP/PLP instead of SEI/CLI to handle nested calls correctly
    php
    sei

    ; Save DBR - Mult8_Trampoline may change it
    phb

    ; Save and set D to 0 for direct page operations
    rep     #0x20
    tdc
    pha
    lda.w   #0x0000
    tcd
    sep     #0x20

    ; CRITICAL: Save zero page variables on stack
    ; This prevents corruption if NMI fires during game's block copy
    ; Save $00-$0B (block copy uses $00-$06) and $26-$2B (Mult8 uses these)
    lda.b   0x00
    pha
    lda.b   0x01
    pha
    lda.b   0x02
    pha
    lda.b   0x03
    pha
    lda.b   0x04
    pha
    lda.b   0x05
    pha
    lda.b   0x06
    pha
    lda.b   0x07
    pha
    lda.b   0x08
    pha
    lda.b   0x09
    pha
    lda.b   0x0A
    pha
    lda.b   0x0B
    pha
    ; Also save $26-$2B used by Mult8_Trampoline
    lda.b   0x26
    pha
    lda.b   0x27
    pha
    lda.b   0x28
    pha
    lda.b   0x29
    pha
    lda.b   0x2A
    pha
    lda.b   0x2B
    pha

    ; Calculate tilemap destination (NO content_offset - write to full slot)
    lda.w   rolling_slot_index
    sta.b   0x26
    lda     #TILEMAP_BYTES_PER_ROW
    sta.b   0x28
    jsr.l   Mult8_Trampoline

    rep     #0x20
    lda.b   0x2A
    clc
    adc     #tilemap_buffer_base + tilemap_content_offset             ; NO +tilemap_content_offset!
    sta.b   0x00
    sep     #0x20

    ; Calculate text buffer source
    lda.w   rolling_slot_index
    sta.b   0x26
    lda     #TEXT_BYTES_PER_ITEM
    sta.b   0x28
    jsr.l   Mult8_Trampoline

    rep     #0x20
    lda.b   0x2A
    tax
    sep     #0x20

    ; Copy row 1 (30 bytes)
    ldy.w   #0x0000
_copy_slot_row1:
    lda.w   text_buffer_base,x
    sta     (0x00),y
    inx
    iny
    cpy.w   #30
    bne     _copy_slot_row1

    ; Clear remaining bytes of row 1 (30-63) to prevent stale border tiles
_clear_slot_row1:
    lda     #0xFF                   ; Blank tile
    sta     (0x00),y
    iny
    lda     #0x00                   ; Palette 0
    sta     (0x00),y
    iny
    cpy.w   #0x0040
    bne     _clear_slot_row1

    ; Copy row 2 (+$40 offset)
    ldy.w   #0x0040
_copy_slot_row2:
    lda.w   text_buffer_base,x
    sta     (0x00),y
    inx
    iny
    cpy.w   #0x005E
    bne     _copy_slot_row2

    ; Clear remaining bytes of row 2 (0x5E-0x7F)
_clear_slot_row2:
    lda     #0xFF                   ; Blank tile
    sta     (0x00),y
    iny
    lda     #0x00                   ; Palette 0
    sta     (0x00),y
    iny
    cpy.w   #0x0080
    bne     _clear_slot_row2

    ; CRITICAL: Restore zero page variables $26-$2B from stack (reverse order - pushed last, pop first)
    pla
    sta.b   0x2B
    pla
    sta.b   0x2A
    pla
    sta.b   0x29
    pla
    sta.b   0x28
    pla
    sta.b   0x27
    pla
    sta.b   0x26

    ; CRITICAL: Restore zero page variables $00-$0B from stack (reverse order)
    pla
    sta.b   0x0B
    pla
    sta.b   0x0A
    pla
    sta.b   0x09
    pla
    sta.b   0x08
    pla
    sta.b   0x07
    pla
    sta.b   0x06
    pla
    sta.b   0x05
    pla
    sta.b   0x04
    pla
    sta.b   0x03
    pla
    sta.b   0x02
    pla
    sta.b   0x01
    pla
    sta.b   0x00

    ; Restore D register
    rep     #0x20
    pla
    tcd
    sep     #0x20

    ; Restore DBR (pushed after php/sei)
    plb

    ; Restore processor status (including interrupt flag)
    plp
    rts

; ============================================================================
; _CopyAllSlotsToTilemap
; ============================================================================
; Copies all 6 slots from text buffer to tilemap buffer
; Called from TfrInventoryList_Rolling AFTER game clears window buffers

_CopyAllSlotsToTilemap:
    ; Save DBR - Mult8_Trampoline may change it
    phb
    lda     #0x7E
    pha
    plb                             ; Ensure DBR is $7E for WRAM access

    lda     #0
    sta.b   0x06                    ; Slot counter (0-5)

_copy_slots_loop:
    ; Calculate tilemap destination: tilemap_buffer_base + (slot × 128)
    ; NO content_offset - write to full 128-byte slot
    lda.b   0x06
    sta.b   0x26
    lda     #TILEMAP_BYTES_PER_ROW  ; 128
    sta.b   0x28
    jsr.l   Mult8_Trampoline

    rep     #0x20
    lda.b   0x2A
    clc
    adc     #tilemap_buffer_base + tilemap_content_offset              ; NO +tilemap_content_offset!
    sta.b   0x00                    ; Tilemap dest pointer
    sep     #0x20

    ; Calculate text buffer source: text_buffer_base + (slot × 60)
    lda.b   0x06
    sta.b   0x26
    lda     #TEXT_BYTES_PER_ITEM    ; 60
    sta.b   0x28
    jsr.l   Mult8_Trampoline

    rep     #0x20
    lda.b   0x2A
    tax                             ; X = text buffer offset
    sep     #0x20

    ; Copy row 1 (30 bytes)
    ldy.w   #0x0000
_copy_all_row1:
    lda.w   text_buffer_base,x
    sta     (0x00),y
    inx
    iny
    cpy.w   #30
    bne     _copy_all_row1

    ; Clear remaining bytes of row 1 (30-63)
_clear_all_row1:
    lda     #0xFF                   ; Blank tile
    sta     (0x00),y
    iny
    lda     #0x00                   ; Palette 0
    sta     (0x00),y
    iny
    cpy.w   #0x0040
    bne     _clear_all_row1

    ; Copy row 2 (+$40 offset in tilemap)
    ldy.w   #0x0040
_copy_all_row2:
    lda.w   text_buffer_base,x
    sta     (0x00),y
    inx
    iny
    cpy.w   #0x005E
    bne     _copy_all_row2

    ; Clear remaining bytes of row 2 (0x5E-0x7F)
_clear_all_row2:
    lda     #0xFF                   ; Blank tile
    sta     (0x00),y
    iny
    lda     #0x00                   ; Palette 0
    sta     (0x00),y
    iny
    cpy.w   #0x0080
    bne     _clear_all_row2

    ; Next slot
    inc.b   0x06
    lda.b   0x06
    cmp     #BUFFER_SLOTS           ; 6 slots
    bne     _copy_slots_loop

    ; Restore DBR
    plb
    rts

; ============================================================================
; TfrInventoryList_Rolling
; ============================================================================
; Replacement for TfrInventoryList ($0298FA)
; Transfers the visible portion of tilemap buffer to VRAM
;
; Called via JSL from bank 02

TfrInventoryList_Rolling:
    ; Set data bank to $7E for WRAM access
    phb
    lda     #0x7E
    pha
    plb

    ; Copy all 6 slots from text buffer to tilemap buffer
    ; This runs AFTER the game's window clearing at $9AF4
    jsr.w   _CopyAllSlotsToTilemap

    ; Queue VRAM transfer (entry 3 covers $7400-$77FF)
    lda     #0x03
    ldy.w   #0x0002
    jsr.l   LoadMenuTfrData_Trampoline

    lda     #0x01
    sta.w   0x1825                  ; 1 transfer only
    sta.w   0x1824                  ; Enable transfer

    plb                             ; Restore data bank
    rtl

; ============================================================================
; RefreshVisibleItems - Re-render all visible items after scroll
; ============================================================================
; Simpler approach: instead of circular buffer tricks, just redraw the 5
; visible items to fixed slot positions (0-4) after each scroll.
; EF65 is reset to 0 by the caller.
;
; Called via JSL from WrapAndClear_Trampoline

RefreshVisibleItems:
    phb
    lda     #0x7E
    pha
    plb

    ; Render 5 visible items to slots 0-4
    ; Item index = EF71 + slot
    lda     #0
    sta.b   0x06                    ; Slot index (0-4)

_refresh_loop:
    ; Calculate item index = EF71 + slot
    lda.w   0xEF71
    clc
    adc.b   0x06
    sta.w   rolling_edge_row        ; Item index for data lookup

    ; Use slot index for buffer position
    lda.b   0x06
    sta.w   rolling_slot_index                  ; Slot index (0-4)

    ; Save slot index
    lda.b   0x06
    pha

    ; Render item to this slot
    jsr.w   _RenderItemToCircularSlot

    ; Restore slot index
    pla
    sta.b   0x06

    ; Next slot
    inc.b   0x06
    lda.b   0x06
    cmp     #VISIBLE_ROWS           ; 5 visible items
    bne     _refresh_loop

    ; Queue VRAM transfer
    lda     #0x03
    ldy.w   #0x0002
    jsr.l   LoadMenuTfrData_Trampoline
    lda     #0x01
    sta.w   0x1825
    sta.w   0x1824

    plb
    rtl

; ============================================================================
; PostRenderUp - Called after scroll UP animation completes
; ============================================================================
; Renders the next item (for potential next scroll UP) to the off-screen slot
; Off-screen slot after scroll UP = (pos - 1) mod 6 (above top)
;
; Called via JSL from WrapAndClear_Trampoline

PostRenderUp:
    phb
    lda     #0x7E
    pha
    plb

    ; Calculate item index = EF71 + VISIBLE_ROWS (the next item down the list)
    lda.w   0xEF71
    clc
    adc     #VISIBLE_ROWS
    cmp     #TOTAL_ITEMS
    bcs     _post_up_done           ; Past end, nothing to render
    sta.w   rolling_edge_row

    ; Off-screen slot = (pos - 1) mod 6
    lda.w   rolling_buffer_pos
    dec
    bpl     _post_up_slot_ok
    lda     #BUFFER_SLOTS - 1
_post_up_slot_ok:
    sta.w   rolling_slot_index

    jsr.w   _RenderItemToCircularSlot

    ; Queue VRAM transfer
    lda     #0x03
    ldy.w   #0x0002
    jsr.l   LoadMenuTfrData_Trampoline
    lda     #0x01
    sta.w   0x1825
    sta.w   0x1824

_post_up_done:
    plb
    rtl

; ============================================================================
; PostRenderDown - Called after scroll DOWN animation completes
; ============================================================================
; Renders the previous item (for potential scroll UP back) to the off-screen slot
; Off-screen slot after scroll DOWN = (pos + 5) mod 6 (below bottom)
;
; Called via JSL from WrapAndClear_Trampoline

PostRenderDown:
    phb
    lda     #0x7E
    pha
    plb

    ; Calculate item index = EF71 + VISIBLE_ROWS (the item just past visible bottom)
    ; This prepares for scroll UP (which would show this item at bottom)
    lda.w   0xEF71
    clc
    adc     #VISIBLE_ROWS
    cmp     #TOTAL_ITEMS
    bcs     _post_down_done         ; Past end, nothing to render
    sta.w   rolling_edge_row

    ; Off-screen slot = (pos + 5) mod 6
    lda.w   rolling_buffer_pos
    clc
    adc     #VISIBLE_ROWS
    cmp     #BUFFER_SLOTS
    bcc     _post_down_slot_ok
    sec
    sbc     #BUFFER_SLOTS
_post_down_slot_ok:
    sta.w   rolling_slot_index

    jsr.w   _RenderItemToCircularSlot

    ; Queue VRAM transfer
    lda     #0x03
    ldy.w   #0x0002
    jsr.l   LoadMenuTfrData_Trampoline
    lda     #0x01
    sta.w   0x1825
    sta.w   0x1824

_post_down_done:
    plb
    rtl

; ============================================================================
; PostScrollDown_Render
; ============================================================================
; Called via JSL from WrapAndClear_Trampoline after scroll animation completes.
;
; For scroll DOWN: Pre-render happened BEFORE animation (in ScrollListDown_Hook)
; so the newly visible slot already has correct content.
;
; We check if it was a scroll DOWN and optionally prepare the NEXT off-screen
; slot for future scroll UP operations.

PostScrollDown_Render:
    ; Check if this was a scroll DOWN animation (type 2)
    ; $1820 still contains the animation type at this point
    lda.w   0x1820
    cmp     #0x02
    bne     _psd_done

    ; For scroll DOWN, the pre-render already happened in ScrollListDown_Hook.
    ; The slot that scrolled into view (at bottom) has correct content.
    ;
    ; Optionally, we could prepare the slot that's now off-screen (at top)
    ; for a potential scroll UP. But since ScrollListUp_Hook does pre-render,
    ; this isn't strictly necessary.

_psd_done:
    rtl

; ============================================================================
; ScrollListDown_Hook
; ============================================================================
; Called via JMP.L from $02A8B8
; Starts scroll animation. Pre-rendering happens AFTER animation in PostScrollDown_Render.
; Returns via JMP.L to Return_To_Bank02 (which has RTS)
;
; Original code at $02A8B8:
;   ldx $ef71, dex, stx $ef71, lda #$0c, sta $ef64, lda #$02, sta $1820, rts

;MENU_FLAG_INVENTORY := 0x04         ; Bit 2 of $4A = inventory menu active

ScrollListDown_Hook:
    ; NOTE: Despite the name, this is called when pressing DOWN in single-column mode
    ; We need to INCREMENT EF71 to show later items (opposite of original 2-column logic)
    ;
    ; FF6-STYLE: Pre-render the new bottom item BEFORE starting the animation!
    ; This ensures the slot has correct content when it scrolls into view.

    ; Disable interrupts to prevent NMI from corrupting state
    sei

    ; Set data bank to $7E for RAM access
    phb
    lda     #0x7E
    pha
    plb

    ; Check if we can scroll further: EF71 + VISIBLE_ROWS must be < TOTAL_ITEMS
    lda.w   0xEF71
    cmp     #(TOTAL_ITEMS - VISIBLE_ROWS)
    bcs     _sd_abort               ; Already at max, can't scroll down

    ; === FF6-STYLE PRE-RENDER ===
    ; Before animation, render the item that will appear at the NEW bottom.
    ; The "off-screen" slot below the visible area will scroll into view.
    ; Off-screen slot = (rolling_buffer_pos + VISIBLE_ROWS) % BUFFER_SLOTS

    ; Calculate item index = EF71 + VISIBLE_ROWS + 1 (the item appearing at new bottom)
    ; After increment, EF71 will be current+1, so bottom item = (current+1) + 4 = current + 5
    lda.w   0xEF71
    clc
    adc     #VISIBLE_ROWS           ; item = EF71 + 5
    cmp     #TOTAL_ITEMS
    bcs     _sd_skip_prerender      ; Past end, nothing to render
    sta.w   rolling_edge_row        ; Save item index

    ; Calculate the off-screen slot that will become visible
    ; This is the slot 5 positions ahead of current top (wrapping)
    lda.w   rolling_buffer_pos
    clc
    adc     #VISIBLE_ROWS           ; pos + 5
    cmp     #BUFFER_SLOTS
    bcc     _sd_slot_ok
    sec
    sbc     #BUFFER_SLOTS           ; Wrap if >= 6
_sd_slot_ok:
    sta.w   rolling_slot_index

    ; Render item to the off-screen slot
    jsr.w   _RenderItemToCircularSlot
    ; Copy to tilemap buffer
    jsr.w   _CopySlotToTilemap
    ; Queue VRAM transfer
    jsr.w   _TransferCircularSlot

_sd_skip_prerender:
    ; INCREMENT EF71 to show later items (animation loop is NOPed out)
    lda.w   0xEF71
    inc
    sta.w   0xEF71

    ; Set up scroll animation
    lda     #0x0C
    sta.w   0xEF64
    lda     #0x02                   ; Animation 2 (scroll down)
    sta.w   0x1820

    ; Advance circular buffer position (top slot moves up, becomes off-screen)
    lda.w   rolling_buffer_pos
    inc
    cmp     #BUFFER_SLOTS
    bcc     _sd_pos_ok
    lda     #0
_sd_pos_ok:
    sta.w   rolling_buffer_pos

_sd_abort:
    plb                             ; Restore data bank
    .db     0x58                    ; cli - re-enable interrupts
    jmp.l   Return_To_Bank02

; ============================================================================
; ScrollListUp_Hook
; ============================================================================
; Called via JMP.L from $02A8CA
; Pre-renders new top row, then does original scroll setup
; Returns via JMP.L to Return_To_Bank02 (which has RTS)
;
; Original code at $02A8CA:
;   ldx $ef71, inx, stx $ef71, lda #$0c, sta $ef64, lda #$03, sta $1820, rts

ScrollListUp_Hook:
    ; NOTE: Despite the name, this is called when pressing UP in single-column mode
    ; We need to DECREMENT EF71 to show earlier items (opposite of original 2-column logic)
    ;
    ; For scroll UP, we DO need to pre-render BEFORE animation because:
    ; - The slot that will scroll INTO view might have stale data from a previous scroll down
    ; - We need to put the correct item there before it becomes visible

    ; Disable interrupts to prevent NMI from corrupting rolling_slot_index
    sei

    ; Set data bank to $7E for RAM access
    phb
    lda     #0x7E
    pha
    plb

    ; Check if we can scroll: EF71 must be > 0
    lda.w   0xEF71
    beq     _su_abort               ; Already at item 0, can't scroll up

    ; First decrement buffer position (new top slot)
    lda.w   rolling_buffer_pos
    dec
    bpl     _su_pos_ok
    lda     #BUFFER_SLOTS - 1       ; Wrap 0→5
_su_pos_ok:
    sta.w   rolling_buffer_pos
    sta.w   rolling_slot_index      ; This slot will be the new top (currently off-screen)

    ; Calculate previous item index = EF71 - 1 (the item that will appear at top)
    lda.w   0xEF71
    dec
    sta.w   rolling_edge_row

    ; Pre-render to new top slot (currently off-screen, about to scroll in)
    jsr.w   _RenderItemToCircularSlot
    ; Copy to tilemap buffer
    jsr.w   _CopySlotToTilemap
    ; Queue VRAM transfer for this slot
    jsr.w   _TransferCircularSlot

    ; DECREMENT EF71 to show earlier items (animation loop is NOPed out)
    lda.w   0xEF71
    dec
    sta.w   0xEF71

    ; Set up scroll animation
    lda     #0x0C
    sta.w   0xEF64
    lda     #0x03                   ; Animation 3 (scroll up)
    sta.w   0x1820

_su_abort:
    plb                             ; Restore data bank
    .db 0x58                        ; cli - re-enable interrupts
    jmp.l   Return_To_Bank02

; ============================================================================
; UpdateListScrollHDMA_Wrapped
; ============================================================================
; Replacement for $02A7F1 - builds HDMA table with scroll value WRAPPING
; This is the key to the circular buffer - scroll values wrap at 96 pixels
;
; Called via JMP.L from $02A7F1
; Input: X = current scroll offset (from $EF65)
;        Y = scanlines per row (12)
; Output: HDMA table at $7F74 filled with wrapped scroll values

HDMA_TABLE          := 0x7E7F74     ; Full 24-bit address: bank $7E, offset $7F74 (V scroll entries)
HDMA_TABLE_SIZE     := 0x0140       ; 320 bytes = 80 entries (5 visible slots × 16 scanlines)
SCROLL_WRAP         := 96           ; 6 slots × 16 pixels (tilemap buffer size)

UpdateListScrollHDMA_Wrapped:
    ; FF6-STYLE ROLLING BUFFER:
    ; Wrap scroll within 96-pixel range (6 slots) starting at 371
    ; Formula: wrapped = ((scroll - 371) % 96) + 371
    ; Range: 371 to 466
    sei                             ; Disable interrupts during HDMA table update
    rep     #0x30                   ; 16-bit A AND X/Y
    txa                             ; X = EF65 (scroll value passed in)

    ; Wrap scroll to 6-slot range
    sec
    sbc.w   #OUR_BASE_SCROLL        ; A = scroll - 371 (offset from base)

_wrap_loop:
    cmp.w   #SCROLL_WRAP            ; Compare with 96
    bcc     _wrap_done              ; If < 96, done
    sec
    sbc.w   #SCROLL_WRAP            ; A = A - 96
    bra     _wrap_loop

_wrap_done:
    clc
    adc.w   #OUR_BASE_SCROLL        ; A = (offset % 96) + 371

    ldx.w   #0x0000                 ; Table index
    ldy.w   #0x000C                 ; Scanlines per row group (12)

_hdma_loop:
    sta.l   HDMA_TABLE,x            ; Store scroll value

    dey
    bne     _hdma_skip_add

    ; Every 12 scanlines, add 4 pixels and wrap if needed
    clc
    adc.w   #0x0004
    ; Wrap if >= 371 + 96 = 467
    cmp.w   #OUR_BASE_SCROLL + SCROLL_WRAP
    bcc     _no_wrap_in_loop
    sec
    sbc.w   #SCROLL_WRAP            ; Wrap back by 96
_no_wrap_in_loop:
    ldy.w   #0x000C                 ; Reset scanline counter

_hdma_skip_add:
    inx
    inx
    inx
    inx                             ; X += 4 (next entry)
    cpx.w   #HDMA_TABLE_SIZE
    bne     _hdma_loop

    tdc                             ; Clear A
    sep     #0x20                   ; 8-bit A only (game expects 16-bit X/Y)
    .db     0x58                    ; CLI
    jmp.l   Return_To_Bank02

; ============================================================================
; Coordinate conversion constant
; ============================================================================
; Game scroll 371 should display our slot 0 at pixel 132
; Offset = 371 - 132 = 239
OUR_BASE_SCROLL     := 0x0173       ; 371 - same as original game

; HDMA table addresses - Y scroll portion only!
; Original ResetListScrollHDMA writes to $81F4 (Y scroll in swap table)
; Animation swaps this with $7F74 (Y scroll in active table)
; X scroll values at $81D2/$7F52 are left alone.
HDMA_SWAP_Y     := 0x7E81F4     ; Y scroll in swap table
HDMA_ACTIVE_Y   := 0x7E7F74     ; Y scroll in active table
HDMA_Y_SIZE     := 0x00F0       ; 240 bytes (same as original)

; ============================================================================
; ResetListScrollHDMA_Rolling
; ============================================================================
; Replacement for $02AAB8 - fills Y scroll in BOTH HDMA tables
; X scroll values stay as original game initialized them.
;
; Only difference from original: uses 132-based values instead of 371-based.

ResetListScrollHDMA_Rolling:
    ; Set game variables (game code expects these)
    ldx.w   #0x0173             ; 371 - game's expected base scroll
    stx.w   0xEF65
    ldy.w   #0x000C             ; 12 scanlines per group
    sty.w   0xEF67

    ; Fill Y scroll in both tables with our converted values
    rep     #0x30               ; 16-bit A and X/Y
    lda.w   #OUR_BASE_SCROLL    ; Start at 132 (not 371)
    ldx.w   #0x0000
    ldy.w   #0x000C

_reset_hdma_loop:
    ; Store to Y scroll portion of BOTH tables
    sta.l   HDMA_SWAP_Y,x       ; $81F4 + X
    sta.l   HDMA_ACTIVE_Y,x     ; $7F74 + X

    dey
    bne     _reset_hdma_skip

    ; Every 12 entries, add 4 pixels (same as original)
    clc
    adc.w   #0x0004
    ldy.w   #0x000C

_reset_hdma_skip:
    inx
    inx
    inx
    inx                         ; X += 4
    cpx.w   #HDMA_Y_SIZE        ; 240 bytes (same as original)
    bne     _reset_hdma_loop

    sep     #0x20               ; 8-bit A (game expects this)
    rtl
