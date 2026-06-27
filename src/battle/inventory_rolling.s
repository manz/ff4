"""
Battle inventory rolling-buffer engine (single column, 5 visible rows + 1 prefetch slot): replaces original
`InitInventoryTextBuf` / `TfrInventoryList`, hooks scroll up/down, rebuilds the wrapped HDMA scroll table and
runs the field-menu NMI DMA check.
"""
.include "config.i"
.include "../items.i"
.extern assets_items_dat
.extern assets_items_unleashed_dat
.extern mult8_trampoline
.extern load_menu_tfr_data_trampoline
.extern hex_to_dec_trampoline
.extern normalize_num_trampoline
.extern draw_text_rolling_trampoline
.extern return_to_bank02
.extern render.flush_chr_to_vram

; externs live at root scope: a816 registers `.extern` only in the scope it is
; declared in, and an `.alloc` body opens its own scope, so an extern declared
; inside never resolves at the use site.
.if BATTLE_ITEMS_VWF {
    .extern messages_vwf.init_inventory
    .extern messages_vwf.deinit
}

.include "../bank20.i"

.alloc battle_inventory_rolling_block in bank20_reloc {

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
    VISIBLE_ROWS := 5  ; Rows visible on screen
    BUFFER_SLOTS := 6  ; 6 slots for 5 visible (1 off-screen for pre-render)
    TOTAL_ITEMS := 48  ; Total inventory items
    .include "src/battle/inventory_budget.i"
.include "../bank20.i"
    TOTAL_ROWS := 48  ; One item per row now

    ; Buffer sizes
    TEXT_BYTES_PER_ITEM := 60  ; 30 tiles x 2 bytes (dakuten + main rows)
    TILEMAP_BYTES_PER_ROW := 128  ; 2 tilemap rows x 64 bytes ($80)

    ; Memory addresses - using freed spell list buffers
    ; Spell list buffers freed by magic direct rendering: $97A6, $9E66, $A526, $ABE6, $B2A6
    text_buffer_base := 0x97A6  ; Ring buffer (6 slots × 60 = 360 bytes, uses freed spell buffer 1)
    inv_format_buffer := 0x9E66  ; Format buffer for draw_text (uses freed spell buffer 2)
    tilemap_buffer_base := 0xC4E6  ; Tilemap buffer
    tilemap_content_offset := 0x46  ; Was $44 ($C52A, col 2). +2 = 1 tiles right ($C52E, col 2).

    ; ============================================================================
    ; RAM VARIABLES (Using unused battle RAM)
    ; ============================================================================
    ; $EF97-$EF99 are explicitly marked "unused" in RAM map
    ; $EF82 is marked "-" (unused)

    rolling_top_row := 0xEF97  ; Top visible row index (0-43)
    rolling_buffer_pos := 0xEF98  ; Circular buffer position (0-4)
    rolling_edge_row := 0xEF99  ; Row index to render (0-47)
    rolling_slot_index := 0xEF82  ; Current slot index for rendering (0-5)
    inventory_needs_full_refresh := 0xEF9D  ; Non-zero = re-render all 5 visible slots this frame.
    ; Set on init / item swap. Scroll edges render the
    ; new hidden slot directly via _render_*_edge_row and
    ; do NOT need a full refresh.
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

    VRAM_SLOT_SIZE := 0x80  ; 128 bytes per slot (2 tilemap rows)
    VRAM_SLOT_BASE := 0x7400  ; Base VRAM address for slots

    ; VRAM slot addresses - MUST match actual content positions after transfer!
    ; VRAM uses WORD addresses (2 bytes per word).
    ; Content goes to WRAM tilemap_buffer_base + tilemap_content_offset ($C4E6 + $44 = $C52A)
    ; Entry 3 transfers from $C4E6 to VRAM $7400, size $0400 bytes = $200 words
    ; WRAM byte offset $44 = VRAM word offset $22 (divide by 2)
    ; So $C52A maps to VRAM $7400 + $22 = $7422
    ; Each WRAM slot is $80 bytes = $40 VRAM words (64 words = 2 tilemap rows = 16 pixels)

    _vram_slot_table:
        .dw 0x7422  ; Slot 0 (content at $7400 + $22 words)
        .dw 0x7462  ; Slot 1 (+$40 words)
        .dw 0x74A2  ; Slot 2 (+$40 words)
        .dw 0x74E2  ; Slot 3 (+$40 words)
        .dw 0x7522  ; Slot 4 (+$40 words)
        .dw 0x7562  ; Slot 5 (off-screen pre-render slot)

    ; Tilemap buffer slots (mirror of VRAM slots in WRAM)
    ; Each slot is 128 bytes at tilemap_buffer_base + slot * 128
    TILEMAP_SLOT_BASE := tilemap_buffer_base + tilemap_content_offset

    ; ============================================================================
    ; init_inventory_text_buf_rolling
    ; ============================================================================
    ; Replacement for $029E9C - renders only 5 visible rows
    ; Called when inventory window opens
    ;
    ; Input: None (reads $EF71 for current scroll position)
    ; Output: Text buffer populated with 5 visible items
    ; Clobbers: A, X, Y, $00-$06, $26-$2A

    init_inventory_text_buf_rolling:
    """
    Replacement for original `$029E9C`: render the 5 visible inventory rows + 1 off-screen prefetch slot when the
    in-battle inventory window opens, resetting the rolling-buffer state.
    """
    ; Set data bank to $7E for WRAM access
        phb
        lda #0x7E
        pha
        plb

    ; Initialize rolling buffer state
    ; At init time, always start at row 0 (top of inventory)
    ; NOTE: EF65 and EF67 are initialized by ResetListScrollHDMA when inventory opens
        stz.w 0xEF71  ; Game's row index = 0
        stz.w 0xEF86  ; Scroll offset = 0 (top item visible)
        lda #1
        sta.w inventory_needs_full_refresh  ; First frame after open: paint all visible.
        stz.b 0x60  ; Cursor row = 0 (top visible row)
        stz.w rolling_top_row
        stz.w rolling_buffer_pos
        ; Note: Game's $4A flag (bit 2) already indicates inventory is active

    .if BATTLE_ITEMS_VWF {
    ; Reset the VWF allocator to tile_id 0xC0 once for the whole pass.
    ; The 6-slot render loop below increments the allocator naturally so
    ; each item owns a distinct tile range (item N at 0xC0 + N * ~9 tiles).
        jsr.l messages_vwf.init_inventory
    }

    ; Render 6 rows to circular slots (5 visible + 1 off-screen)
    ; At init, item index = slot index (both 0-5)
    lda #0
    sta.b 0x06  ; Slot index (0-5)

    _init_row_loop:
        ; For init: item index = slot index
        lda.b 0x06
        sta.w rolling_edge_row  ; Item index for data lookup
        sta.w rolling_slot_index  ; Slot index for buffer position

    ; Save slot index
        lda.b 0x06
        pha

    ; Render item to circular slot
        jsr.w _render_item_to_circular_slot

    ; Restore slot index
        pla
        sta.b 0x06

    ; Next slot
        inc.b 0x06
        lda.b 0x06
        cmp #BUFFER_SLOTS  ; 6 slots total
        bne _init_row_loop

    .if BATTLE_ITEMS_VWF {
    ; End of inventory rolling pass: clear the VWF battle flag and signal
    ; DMA so the inventory tile slice flushes to VRAM on the next NMI.
        jsr.l messages_vwf.deinit
    }

    ; Queue VRAM transfer for initial render
    lda #0x03
    ldy.w #0x0002
    jsr.l load_menu_tfr_data_trampoline
    lda #0x01
    sta.w 0x1825
    sta.w 0x1824

    plb  ; Restore data bank
    rtl

    ; ============================================================================
    ; _render_inventory_item
    ; ============================================================================
    ; Renders a single inventory item to text buffer
    ;
    ; Input: rolling_slot_index = item slot index (0-47)
    ; Output: Item rendered to text buffer
    ; Clobbers: A, X, Y, $00-$02, $26-$2A

    _render_inventory_item:
        ; Set data bank to $7E for WRAM access
        phb
        lda #0x7E
        pha
        plb

    ; Calculate text buffer destination
    ; text_addr = text_buffer_base + (slot x TEXT_BYTES_PER_ITEM)
        lda.w rolling_slot_index
        sta.b 0x26
        lda #TEXT_BYTES_PER_ITEM
        sta.b 0x28
        jsr.l mult8_trampoline

        rep #0x20
        lda.b 0x2A
        clc
        adc #text_buffer_base
        sta.w 0xEF52  ; draw_text output destination
        tdc
        sep #0x20

    ; Set up format buffer pointer
        ldx.w #inv_format_buffer
        stx.w 0xEF50

    ; Set tile count for draw_text
        lda #15  ; 15 tiles per line
        sta.w 0xEF54

    ; Get item data from game inventory
    ; Inventory structure: 4 bytes per slot at $321A
    ;   $321A+0: flags (bit 7 = disabled)
    ;   $321A+1: item ID
    ;   $321A+2: quantity
    ;   $321A+3: ???
        tdc  ; Clear B before TAX
        lda.w rolling_slot_index
        asl
        asl  ; x 4 bytes per item
        tax

        lda.l 0x7E321B, x  ; Item ID (WRAM)
        sta.b 0x02  ; Save for later
        sta.b 0x26  ; For name lookup
        lda.l 0x7E321C, x  ; Quantity (WRAM)
        pha  ; Save quantity

    ; Determine palette (white=enabled, gray=disabled)
        lda #0x00
        sta.b 0x00  ; Palette for name
        sta.b 0x01  ; Palette for symbol
        lda.l 0x7E321A, x  ; Flags (WRAM)
        and #0x80
        beq _not_disabled
        lda #0x04  ; Gray palette
        sta.b 0x00
        sta.b 0x01

    _not_disabled:

    ; Calculate item name address: assets_items_dat + (id x 13)
    ; Must use 16-bit math since id x 13 can exceed 255
        rep #0x20  ; 16-bit A
        lda.b 0x02  ; Load (will get $02-$03)
        and.w #0x00FF  ; Mask to item ID only
        sta.b 0x08  ; Save original ID
        asl  ; x2
        clc
        adc.b 0x08  ; x3
        asl
        asl  ; x12
        tax
        sep #0x20  ; Back to 8-bit

    ; Build format string. Starts in fixed mode ; 0x0F toggles fixed <->
    ; VWF so only the name portion routes through the VWF blitter.
        ldy.w #0x0000

        lda #0x0E
        sta.w inv_format_buffer, y
        iny
        lda.b 0x01
        sta.w inv_format_buffer, y
        iny

        lda.l assets_items_dat, x
        sta.w inv_format_buffer, y
        iny

    .if BATTLE_ITEMS_VWF {
        lda #0xFE
        sta.w inv_format_buffer, y
        iny
    }

    lda #0x0E
    sta.w inv_format_buffer, y
    iny
    lda.b 0x00
    sta.w inv_format_buffer, y
    iny

    lda #11
    sta.b 0x00

    _name_copy_loop:
        inx
        lda.l assets_items_dat, x
        sta.w inv_format_buffer, y
        iny
        dec.b 0x00
        bne _name_copy_loop

    .if BATTLE_ITEMS_VWF {
        lda #0xFE
        sta.w inv_format_buffer, y
        iny
        lda #0xFC
        sta.w inv_format_buffer, y
        iny
        lda #12
        sta.w inv_format_buffer, y
        iny
    }

    lda.b 0x02
    bne _has_item

    pla
    lda #0x05
    sta.w inv_format_buffer, y
    iny
    lda #0x03
    bra _finish_format

    _has_item:
        lda #0xC8
        sta.w inv_format_buffer, y
        iny

        pla
        tax
        jsr.l hex_to_dec_trampoline
        jsr.l normalize_num_trampoline

        lda.w 0x180E
        sta.w inv_format_buffer, y
        iny

        lda.w 0x180F

    _finish_format:
        sta.w inv_format_buffer, y
        iny

        lda #0x00
        sta.w inv_format_buffer, y

    ; Call draw_text to render formatted text to text buffer
        jsr.l draw_text_rolling_trampoline

        plb  ; Restore data bank
        rts

    ; ============================================================================
    ; _render_inventory_item_circular
    ; ============================================================================
    ; Renders item to circular buffer slot
    ;
    ; Input: rolling_edge_row = item index (0-47) for data lookup
    ;        rolling_slot_index = buffer slot (0-4) for destination
    ; Output: Item rendered to text buffer at slot position
    ; Clobbers: A, X, Y, $00-$02, $26-$2A

    _render_inventory_item_circular:
        phb
        lda #0x7E
        pha
        plb

    ; Calculate text buffer destination using SLOT (not item index)
    ; text_addr = text_buffer_base + (slot x TEXT_BYTES_PER_ITEM)
        lda.w rolling_slot_index  ; Buffer slot (0-4)
        sta.b 0x26
        lda #TEXT_BYTES_PER_ITEM
        sta.b 0x28
        jsr.l mult8_trampoline

        rep #0x20
        lda.b 0x2A
        clc
        adc #text_buffer_base
        sta.w 0xEF52  ; draw_text output destination
        tdc
        sep #0x20

    ; Set up format buffer pointer
        ldx.w #inv_format_buffer
        stx.w 0xEF50

    ; Set tile count for draw_text
        lda #15  ; 15 tiles per line
        sta.w 0xEF54

    ; Get item data using ITEM INDEX (rolling_edge_row), not slot
        tdc
        lda.w rolling_edge_row  ; Item index (0-47)
        asl
        asl  ; x 4 bytes per item
        tax

        lda.l 0x7E321B, x  ; Item ID
        sta.b 0x02
        sta.b 0x26
        lda.l 0x7E321C, x  ; Quantity
        pha

    ; Determine palette
        lda #0x00
        sta.b 0x00
        sta.b 0x01
        lda.l 0x7E321A, x  ; Flags
        and #0x80
        beq _circ_not_disabled
        lda #0x04
        sta.b 0x00
        sta.b 0x01

    _circ_not_disabled:

    ; Calculate item name address: assets_items_dat + (id x 12)
        rep #0x20
        lda.b 0x02
        and.w #0x00FF
        sta.b 0x08
        asl
        clc
        adc.b 0x08
        asl
        asl
        tax
        sep #0x20

    ; Build format string. The custom inventory renderer starts in fixed
    ; mode and uses 0x0F as a fixed<->VWF toggle so only the name routes
    ; through the VWF blitter.
        ldy.w #0x0000

    ; Tile flags for symbol (fixed mode default)
        lda #0x0E
        sta.w inv_format_buffer, y
        iny
        lda.b 0x01
        sta.w inv_format_buffer, y
        iny

    ; Symbol tile (raw byte ; default mode is fixed)
        lda.l assets_items_dat, x
        sta.w inv_format_buffer, y
        iny

    ; Toggle to VWF for the name
    .if BATTLE_ITEMS_VWF {
        lda #0xFE
        sta.w inv_format_buffer, y
        iny
    }

    ; Tile flags for name
    lda #0x0E
    sta.w inv_format_buffer, y
    iny
    lda.b 0x00
    sta.w inv_format_buffer, y
    iny

    ; 11-char name (raw chars dispatched through VWF blitter)
    lda #11
    sta.b 0x00

    _circ_name_loop:
        inx
        lda.l assets_items_dat, x
        sta.w inv_format_buffer, y
        iny
        dec.b 0x00
        bne _circ_name_loop

    ; Toggle back to fixed for colon + digits
    .if BATTLE_ITEMS_VWF {
        lda #0xFE
        sta.w inv_format_buffer, y
        iny
        lda #0xFC
        sta.w inv_format_buffer, y
        iny
        lda #12
        sta.w inv_format_buffer, y
        iny
    }

    ; Quantity handling
    lda.b 0x02
    bne _circ_has_item

    pla
    lda #0x05
    sta.w inv_format_buffer, y
    iny
    lda #0x03
    bra _circ_finish

    _circ_has_item:
        lda #0xC8
        sta.w inv_format_buffer, y
        iny

        pla
        tax
        jsr.l hex_to_dec_trampoline
        jsr.l normalize_num_trampoline

        lda.w 0x180E
        sta.w inv_format_buffer, y
        iny

        lda.w 0x180F

    _circ_finish:
        sta.w inv_format_buffer, y
        iny

        lda #0x00
        sta.w inv_format_buffer, y

        jsr.l draw_text_rolling_trampoline

        plb
        rts

    ; ============================================================================
    ; _copy_item_to_tilemap_circular
    ; ============================================================================
    ; Copies item from text buffer slot to tilemap slot (circular buffer)
    ;
    ; Input: rolling_slot_index = buffer slot (0-4)
    ; Output: Item copied to tilemap buffer at slot position
    ; Clobbers: A, X, Y, $00-$06

    _copy_item_to_tilemap_circular:
        ; Save DBR - mult8_trampoline may change it
        phb
        lda #0x7E
        pha
        plb  ; Ensure DBR is $7E for WRAM access

    ; Calculate tilemap buffer address for this SLOT (not item index)
    ; tilemap_addr = tilemap_buffer_base + (slot x TILEMAP_BYTES_PER_ROW)
    ; NO content_offset - write to full 128-byte slot
        lda.w rolling_slot_index  ; Buffer slot (0-4)
        sta.b 0x26
        lda #TILEMAP_BYTES_PER_ROW
        sta.b 0x28
        jsr.l mult8_trampoline

        rep #0x20
        lda.b 0x2A
        clc
        adc #tilemap_buffer_base + tilemap_content_offset  ; NO +tilemap_content_offset!
        sta.b 0x00  ; Tilemap destination
        sep #0x20

    ; Calculate text buffer source using SLOT
        lda.w rolling_slot_index
        sta.b 0x26
        lda #TEXT_BYTES_PER_ITEM
        sta.b 0x28
        jsr.l mult8_trampoline

        rep #0x20
        lda.b 0x2A
        tax
        sep #0x20

    ; Copy first tilemap row (30 bytes)
        ldy.w #0x0000

    _circ_copy_row1:
        lda.w text_buffer_base, x
        sta (0x00), y
        inx
        iny
        cpy.w #30
        bne _circ_copy_row1

    ; Clear remaining bytes of first row (30-63) to prevent stale border tiles
    ; Fill with $FF (blank tile) and $00 (palette 0)

    _circ_clear_row1:
        lda #0xFF  ; Blank tile
        sta (0x00), y
        iny
        lda #0x00  ; Palette 0
        sta (0x00), y
        iny
        cpy.w #0x0040
        bne _circ_clear_row1

    ; Copy second tilemap row (+$40 offset)
        ldy.w #0x0040

    _circ_copy_row2:
        lda.w text_buffer_base, x
        sta (0x00), y
        inx
        iny
        cpy.w #0x005E
        bne _circ_copy_row2

    ; Clear remaining bytes of second row (0x5E-0x7F)

    _circ_clear_row2:
        lda #0xFF  ; Blank tile
        sta (0x00), y
        iny
        lda #0x00  ; Palette 0
        sta (0x00), y
        iny
        cpy.w #0x0080
        bne _circ_clear_row2

    ; Restore DBR
        plb
        rts

    ; ============================================================================
    ; _copy_item_to_tilemap
    ; ============================================================================
    ; Copies a single item from text buffer to the correct tilemap position
    ; (Used for initial rendering where slot = item index)
    ;
    ; Input: rolling_slot_index = item slot index (0-47)
    ; Output: Item copied to tilemap buffer
    ; Clobbers: A, X, Y, $00-$06

    _copy_item_to_tilemap:
        ; Calculate row index from slot (same as slot for single column)
        lda.w rolling_slot_index
        sta.b 0x04  ; Save row index

    ; Calculate tilemap buffer address for this row
    ; tilemap_addr = tilemap_buffer_base + (row x TILEMAP_BYTES_PER_ROW)
        sta.b 0x26
        lda #TILEMAP_BYTES_PER_ROW
        sta.b 0x28
        jsr.l mult8_trampoline

    ; Add content offset (left column position)
        rep #0x20
        lda.b 0x2A
        clc
        adc #tilemap_buffer_base + tilemap_content_offset
        sta.b 0x00  ; Tilemap destination
        sep #0x20

    ; Calculate text buffer source offset
        lda.w rolling_slot_index
        sta.b 0x26
        lda #TEXT_BYTES_PER_ITEM
        sta.b 0x28
        jsr.l mult8_trampoline

        rep #0x20
        lda.b 0x2A  ; Get offset (slot x 60)
        tax  ; X = offset into text buffer
        sep #0x20

    ; Copy first tilemap row (30 bytes = 15 tiles)
        ldy.w #0x0000

    _copy_row1:
        lda.w text_buffer_base, x  ; Read from $8EA6 + offset
        sta (0x00), y  ; Write to tilemap buffer
        inx
        iny
        cpy.w #30
        bne _copy_row1

    ; Copy second tilemap row (30 bytes)
    ; Tilemap row 2 is at +$40 (64 bytes) from row 1
        ldy.w #0x0040

    _copy_row2:
        lda.w text_buffer_base, x  ; Read from $8EA6 + offset
        sta (0x00), y
        inx
        iny
        cpy.w #0x005E  ; $40 + 30 = $5E
        bne _copy_row2

        rts

    ; ============================================================================
    ; _render_bottom_edge_row
    ; ============================================================================
    ; Pre-renders the new bottom row BEFORE scroll down animation starts
    ; Uses circular buffer - writes to the slot that's scrolling OUT (top slot)
    ; After scroll, that slot will appear at the bottom
    ;
    ; Called via JSL from bank 02

    _render_bottom_edge_row:
        ; Disable interrupts to prevent NMI from corrupting rolling_slot_index
        sei

    ; Set data bank to $7E for WRAM access
        phb
        lda #0x7E
        pha
        plb

    ; Calculate the new bottom item index
    ; new_bottom = current_top + BUFFER_SLOTS (the item that will be at bottom after scroll)
    ; With 6 slots and 5 visible, this is the item we need to pre-render
        lda.w 0xEF71
        clc
        adc #BUFFER_SLOTS

    ; Check bounds (max item is 47)
        cmp #TOTAL_ITEMS
        bcs _render_bottom_done  ; Past end, nothing to render

        sta.w rolling_edge_row  ; Save item index for data lookup

    ; CIRCULAR BUFFER: Write to OFF-SCREEN slot (below bottom)
    ; Off-screen slot = (rolling_buffer_pos + 5) % 6
    ; This slot is currently invisible and will scroll into view at bottom
        lda.w rolling_buffer_pos
        clc
        adc #VISIBLE_ROWS  ; +5 to get to off-screen slot
        cmp #BUFFER_SLOTS
        bcc _bottom_slot_ok
        sec
        sbc #BUFFER_SLOTS  ; Wrap if >= 6

    _bottom_slot_ok:
        sta.w rolling_slot_index  ; Slot index (0-5) for buffer positioning

    ; Render item data to this circular slot
        jsr.w _render_item_to_circular_slot

    ; Queue full tilemap transfer (game's VBlank will handle it)
        lda #0x03
        ldy.w #0x0002
        jsr.l load_menu_tfr_data_trampoline
        lda #0x01
        sta.w 0x1825
        sta.w 0x1824

    ; Advance circular position (top slot advances as we scroll down)
        lda.w rolling_buffer_pos
        inc
        cmp #BUFFER_SLOTS
        bcc _store_pos_down
        lda #0

    _store_pos_down:
        sta.w rolling_buffer_pos

    _render_bottom_done:
        plb  ; Restore data bank
        cli  ; re-enable interrupts
        rts  ; Called from within bank $20 now

    ; ============================================================================
    ; _render_top_edge_row
    ; ============================================================================
    ; Pre-renders the new top row BEFORE scroll up animation starts
    ; Uses circular buffer - writes to the slot that's scrolling OUT (bottom slot)
    ; After scroll, that slot will appear at the top
    ;
    ; Called via JSL from bank 02

    _render_top_edge_row:
        ; Disable interrupts to prevent NMI from corrupting rolling_slot_index
        sei

    ; Set data bank to $7E for WRAM access
        phb
        lda #0x7E
        pha
        plb

    ; Calculate the new top item index
    ; new_top = current_top - 1
        lda.w 0xEF71
        dec  ; New top row after scroll

    ; Check bounds
        bmi _render_top_done  ; Negative = invalid

        sta.w rolling_edge_row  ; Save item index for data lookup

    ; CIRCULAR BUFFER: Write to slot BEFORE current circular_pos
    ; This slot will become the new TOP after scroll
    ; First decrement circular_pos, then write to that slot
        lda.w rolling_buffer_pos
        dec
        bpl _store_pos_up
        lda #BUFFER_SLOTS - 1  ; Wrap 0→5

    _store_pos_up:
        sta.w rolling_buffer_pos  ; Update position FIRST for scroll up
        sta.w rolling_slot_index  ; Slot index (0-5) for buffer positioning

    ; Render item data to this circular slot
        jsr.w _render_item_to_circular_slot

    ; Queue full tilemap transfer (game's VBlank will handle it)
        lda #0x03
        ldy.w #0x0002
        jsr.l load_menu_tfr_data_trampoline
        lda #0x01
        sta.w 0x1825
        sta.w 0x1824

    _render_top_done:
        plb  ; Restore data bank
        cli  ; re-enable interrupts
        rts  ; Called from within bank $20 now

    ; ============================================================================
    ; _render_item_to_circular_slot
    ; ============================================================================
    ; Renders item to a circular buffer slot
    ;
    ; Input: rolling_edge_row = item index (0-47) for data lookup
    ;        rolling_slot_index = slot index (0-4) for destination
    ; Output: Item rendered to text buffer slot, copied to tilemap slot

    _render_item_to_circular_slot:
        ; Save processor status and disable interrupts
        ; Using PHP/PLP instead of SEI/CLI to handle nested calls correctly
        php
        sei

    ; Save DBR - draw_text may change it and we need it for tilemap copy
        phb

    ; Save D and set to $0000 for direct page operations
        rep #0x20
        tdc
        pha  ; Save original D on stack
        lda.w #0x0000
        tcd
        sep #0x20

    ; CRITICAL: Save zero page variables on stack
    ; This prevents corruption if NMI fires during game's block copy
    ; Save $00-$0B (block copy uses $00-$06) and $26-$2B (Mult8 uses these)
        lda.b 0x00
        pha
        lda.b 0x01
        pha
        lda.b 0x02
        pha
        lda.b 0x03
        pha
        lda.b 0x04
        pha
        lda.b 0x05
        pha
        lda.b 0x06
        pha
        lda.b 0x07
        pha
        lda.b 0x08
        pha
        lda.b 0x09
        pha
        lda.b 0x0A
        pha
        lda.b 0x0B
        pha
        ; Also save $26-$2B used by mult8_trampoline
        lda.b 0x26
        pha
        lda.b 0x27
        pha
        lda.b 0x28
        pha
        lda.b 0x29
        pha
        lda.b 0x2A
        pha
        lda.b 0x2B
        pha

    ; Calculate text buffer destination for this SLOT
    ; text_addr = text_buffer_base + (slot × TEXT_BYTES_PER_ITEM)
        lda.w rolling_slot_index  ; Slot index (0-4)
        sta.b 0x26
        lda #TEXT_BYTES_PER_ITEM  ; 60 bytes per slot
        sta.b 0x28
        jsr.l mult8_trampoline

        rep #0x20
        lda.b 0x2A
        clc
        adc #text_buffer_base
        sta.w 0xEF52  ; draw_text output destination
        tdc
        sep #0x20

    ; Set up format buffer pointer
        ldx.w #inv_format_buffer
        stx.w 0xEF50
        lda #15
        sta.w 0xEF54

    ; Get item data using rolling_edge_row (the actual item index)
        tdc
        lda.w rolling_edge_row
        asl
        asl
        tax

        lda.l 0x7E321B, x  ; Item ID
        sta.b 0x02
        bne _slot_id_nonzero
        jmp.w _empty_slot_fast  ; ID == 0 -> empty entry, skip VWF

    _slot_id_nonzero:
        lda.l 0x7E321C, x  ; Quantity
        pha

    ; Palette selection
        lda #0x00
        sta.b 0x00
        sta.b 0x01
        lda.l 0x7E321A, x
        and #0x80
        beq _slot_not_disabled
        lda #0x04
        sta.b 0x00
        sta.b 0x01

    _slot_not_disabled:

    ; Calculate item name offset into the 17-byte-per-record
    ; assets_items_unleashed_dat table: id * 17 = (id << 4) + id.
        rep #0x20
        lda.b 0x02
        and.w #0x00FF
        sta.b 0x08
        asl
        asl
        asl
        asl
        clc
        adc.b 0x08
        tax
        sep #0x20

    ; Build format string. Same fixed-default + 0x0F-toggle pattern the
    ; other two format builders in this file use.
        ldy.w #0x0000
        lda #0x0E
        sta.w inv_format_buffer, y
        iny
        lda.b 0x01
        sta.w inv_format_buffer, y
        iny

        lda.l assets_items_unleashed_dat, x
        sta.w inv_format_buffer, y
        iny

    .if BATTLE_ITEMS_VWF {
        lda #0xFE
        sta.w inv_format_buffer, y
        iny
    }

    lda #0x0E
    sta.w inv_format_buffer, y
    iny
    lda.b 0x00
    sta.w inv_format_buffer, y
    iny

    lda #16
    sta.b 0x00

    _slot_name_loop:
        inx
        lda.l assets_items_unleashed_dat, x
        sta.w inv_format_buffer, y
        iny
        dec.b 0x00
        bne _slot_name_loop

    .if BATTLE_ITEMS_VWF {
        lda #0xFE
        sta.w inv_format_buffer, y
        iny
        lda #0xFC
        sta.w inv_format_buffer, y
        iny
        lda #12
        sta.w inv_format_buffer, y
        iny
    }

    lda.b 0x02
    bne _slot_has_item
    pla
    lda #0x05
    sta.w inv_format_buffer, y
    iny
    lda #0x03
    bra _slot_finish

    _slot_has_item:
        lda #0xC8
        sta.w inv_format_buffer, y
        iny
        pla
        ; M=8 pla loads A.lo only; A.hi retains a leaked byte from the
        ; preceding 16-bit arithmetic. With X=16 the next `tax` would copy
        ; that garbage into X.hi and hex_to_dec would emit BCD for the
        ; wider value (qty 1 + leaked $06 -> X=$0601 -> "37"). Zero-extend
        ; A explicitly before transfer.
        rep #0x20
        and.w #0x00ff
        tax
        sep #0x20
        jsr.l hex_to_dec_trampoline
        jsr.l normalize_num_trampoline
        lda.w 0x180E
        sta.w inv_format_buffer, y
        iny
        lda.w 0x180F

    _slot_finish:
        sta.w inv_format_buffer, y
        iny
        lda #0x00
        sta.w inv_format_buffer, y

        jsr.l draw_text_rolling_trampoline
        jmp.w _slot_render_done

    _empty_slot_fast:
    """
    Empty inventory entry (item ID = 0). Skip the format-build + VWF
    blit and fill the slot's text buffer with 30 blank tile entries
    (2 bytes each = `$FF $00`). Saves the ~80K cycles draw_text would
    otherwise burn rendering an empty palette + name string.
    """
        rep #0x20
        lda.w 0xEF52
        sta.b 0x04  ; ptr-to-slot in DP scratch
        sep #0x20
        ldy.w #0

    _empty_fill_loop:
        lda.b #0xFF
        sta (0x04), y
        iny
        lda.b #0x00
        sta (0x04), y
        iny
        cpy.w #60
        bne _empty_fill_loop

    _slot_render_done:

    ; draw_text fills text buffer - tilemap copy is done separately by:
    ; - _copy_all_slots_to_tilemap in tfr_inventory_list_rolling (for init)
    ; - _copy_slot_to_tilemap in scroll hooks (for scrolling)

    ; CRITICAL: Restore zero page variables from stack (reverse order)
    ; First restore $26-$2B (last pushed)
        pla
        sta.b 0x2B
        pla
        sta.b 0x2A
        pla
        sta.b 0x29
        pla
        sta.b 0x28
        pla
        sta.b 0x27
        pla
        sta.b 0x26
        ; Then restore $00-$0B
        pla
        sta.b 0x0B
        pla
        sta.b 0x0A
        pla
        sta.b 0x09
        pla
        sta.b 0x08
        pla
        sta.b 0x07
        pla
        sta.b 0x06
        pla
        sta.b 0x05
        pla
        sta.b 0x04
        pla
        sta.b 0x03
        pla
        sta.b 0x02
        pla
        sta.b 0x01
        pla
        sta.b 0x00

    ; Restore D before returning
        rep #0x20
        pla
        tcd
        sep #0x20

    ; Restore DBR (draw_text may have changed it)
        plb

    ; Restore processor status (including interrupt flag)
        plp
        rts

    ; ============================================================================
    ; _transfer_circular_slot
    ; ============================================================================
    ; Transfers a single circular slot to its fixed VRAM address
    ; Uses direct DMA instead of menu transfer system for precise control
    ;
    ; Input: rolling_slot_index = slot index (0-4)
    ; Output: 128 bytes transferred to VRAM

    _transfer_circular_slot:
        ; Save processor status and disable interrupts
        php
        sei

    ; Save DBR - mult8_trampoline may change it
        phb
        lda #0x7E
        pha
        plb  ; Ensure DBR is $7E for WRAM access

    ; CRITICAL: Save zero page variables on stack
    ; This prevents corruption if NMI fires during game's block copy
    ; Save $00-$0B (block copy uses $00-$06) and $26-$2B (Mult8 uses these)
        lda.b 0x00
        pha
        lda.b 0x01
        pha
        lda.b 0x02
        pha
        lda.b 0x03
        pha
        lda.b 0x04
        pha
        lda.b 0x05
        pha
        lda.b 0x06
        pha
        lda.b 0x07
        pha
        lda.b 0x08
        pha
        lda.b 0x09
        pha
        lda.b 0x0A
        pha
        lda.b 0x0B
        pha
        ; Also save $26-$2B used by mult8_trampoline
        lda.b 0x26
        pha
        lda.b 0x27
        pha
        lda.b 0x28
        pha
        lda.b 0x29
        pha
        lda.b 0x2A
        pha
        lda.b 0x2B
        pha

    ; Look up VRAM destination from slot table
        lda.w rolling_slot_index
        asl  ; ×2 for word lookup
        tax
        rep #0x20
        lda.l _vram_slot_table, x  ; Get VRAM address ($7400, $7480, etc.)
        sta.b 0x04  ; Save VRAM dest
        sep #0x20

    ; Calculate tilemap buffer source
    ; source = tilemap_buffer_base + (slot × 128) - NO content_offset!
        lda.w rolling_slot_index
        sta.b 0x26
        lda #TILEMAP_BYTES_PER_ROW
        sta.b 0x28
        jsr.l mult8_trampoline

        rep #0x20
        lda.b 0x2A
        clc
        adc #tilemap_buffer_base + tilemap_content_offset  ; NO +tilemap_content_offset!
        sta.b 0x00  ; Source address (low word)
        sep #0x20

    ; Queue using menu transfer system (entry 3 covers our slots)
    ; The transfer will include this slot since it's at the right offset
        lda #0x03
        ldy.w #0x0002
        jsr.l load_menu_tfr_data_trampoline

        lda #0x01
        sta.w 0x1825
        sta.w 0x1824

    ; CRITICAL: Restore zero page variables from stack (reverse order)
    ; First restore $26-$2B (last pushed)
        pla
        sta.b 0x2B
        pla
        sta.b 0x2A
        pla
        sta.b 0x29
        pla
        sta.b 0x28
        pla
        sta.b 0x27
        pla
        sta.b 0x26
        ; Then restore $00-$0B
        pla
        sta.b 0x0B
        pla
        sta.b 0x0A
        pla
        sta.b 0x09
        pla
        sta.b 0x08
        pla
        sta.b 0x07
        pla
        sta.b 0x06
        pla
        sta.b 0x05
        pla
        sta.b 0x04
        pla
        sta.b 0x03
        pla
        sta.b 0x02
        pla
        sta.b 0x01
        pla
        sta.b 0x00

    ; Restore DBR
        plb

    ; Restore processor status (including interrupt flag)
        plp
        rts

    ; ============================================================================
    ; _copy_slot_to_tilemap
    ; ============================================================================
    ; Copies a single slot from text buffer to tilemap buffer
    ; Input: rolling_slot_index = slot index (0-5)
    ; Uses $00-$01, $26, $28, $2A, X, Y

    _copy_slot_to_tilemap:
        ; Save processor status and disable interrupts
        ; Using PHP/PLP instead of SEI/CLI to handle nested calls correctly
        php
        sei

    ; Save DBR - mult8_trampoline may change it
        phb

    ; Save and set D to 0 for direct page operations
        rep #0x20
        tdc
        pha
        lda.w #0x0000
        tcd
        sep #0x20

    ; CRITICAL: Save zero page variables on stack
    ; This prevents corruption if NMI fires during game's block copy
    ; Save $00-$0B (block copy uses $00-$06) and $26-$2B (Mult8 uses these)
        lda.b 0x00
        pha
        lda.b 0x01
        pha
        lda.b 0x02
        pha
        lda.b 0x03
        pha
        lda.b 0x04
        pha
        lda.b 0x05
        pha
        lda.b 0x06
        pha
        lda.b 0x07
        pha
        lda.b 0x08
        pha
        lda.b 0x09
        pha
        lda.b 0x0A
        pha
        lda.b 0x0B
        pha
        ; Also save $26-$2B used by mult8_trampoline
        lda.b 0x26
        pha
        lda.b 0x27
        pha
        lda.b 0x28
        pha
        lda.b 0x29
        pha
        lda.b 0x2A
        pha
        lda.b 0x2B
        pha

    ; Calculate tilemap destination (NO content_offset - write to full slot)
        lda.w rolling_slot_index
        sta.b 0x26
        lda #TILEMAP_BYTES_PER_ROW
        sta.b 0x28
        jsr.l mult8_trampoline

        rep #0x20
        lda.b 0x2A
        clc
        adc #tilemap_buffer_base + tilemap_content_offset  ; NO +tilemap_content_offset!
        sta.b 0x00
        sep #0x20

    ; Calculate text buffer source
        lda.w rolling_slot_index
        sta.b 0x26
        lda #TEXT_BYTES_PER_ITEM
        sta.b 0x28
        jsr.l mult8_trampoline

        rep #0x20
        lda.b 0x2A
        tax
        sep #0x20

    ; Copy row 1 (30 bytes) - content only, preserve borders
        ldy.w #0x0000

    _copy_slot_row1:
        lda.w text_buffer_base, x
        sta (0x00), y
        inx
        iny
        cpy.w #30
        bne _copy_slot_row1

    ; Copy row 2 (+$40 offset) - content only, preserve borders
        ldy.w #0x0040

    _copy_slot_row2:
        lda.w text_buffer_base, x
        sta (0x00), y
        inx
        iny
        cpy.w #0x005E
        bne _copy_slot_row2

    ; CRITICAL: Restore zero page variables $26-$2B from stack (reverse order - pushed last, pop first)
        pla
        sta.b 0x2B
        pla
        sta.b 0x2A
        pla
        sta.b 0x29
        pla
        sta.b 0x28
        pla
        sta.b 0x27
        pla
        sta.b 0x26

    ; CRITICAL: Restore zero page variables $00-$0B from stack (reverse order)
        pla
        sta.b 0x0B
        pla
        sta.b 0x0A
        pla
        sta.b 0x09
        pla
        sta.b 0x08
        pla
        sta.b 0x07
        pla
        sta.b 0x06
        pla
        sta.b 0x05
        pla
        sta.b 0x04
        pla
        sta.b 0x03
        pla
        sta.b 0x02
        pla
        sta.b 0x01
        pla
        sta.b 0x00

    ; Restore D register
        rep #0x20
        pla
        tcd
        sep #0x20

    ; Restore DBR (pushed after php/sei)
        plb

    ; Restore processor status (including interrupt flag)
        plp
        rts

    ; ============================================================================
    ; _copy_all_slots_to_tilemap
    ; ============================================================================
    ; Copies all 6 slots from text buffer to tilemap buffer
    ; Called from tfr_inventory_list_rolling AFTER game clears window buffers

    _copy_all_slots_to_tilemap:
        ; Save DBR - mult8_trampoline may change it
        phb
        lda #0x7E
        pha
        plb  ; Ensure DBR is $7E for WRAM access

        lda #0
        sta.b 0x06  ; Slot counter (0-5)

    _copy_slots_loop:
        ; Calculate tilemap destination: tilemap_buffer_base + (slot × 128)
        ; NO content_offset - write to full 128-byte slot
        lda.b 0x06
        sta.b 0x26
        lda #TILEMAP_BYTES_PER_ROW  ; 128
        sta.b 0x28
        jsr.l mult8_trampoline

        rep #0x20
        lda.b 0x2A
        clc
        adc #tilemap_buffer_base + tilemap_content_offset  ; NO +tilemap_content_offset!
        sta.b 0x00  ; Tilemap dest pointer
        sep #0x20

    ; Calculate text buffer source: text_buffer_base + (slot × 60)
        lda.b 0x06
        sta.b 0x26
        lda #TEXT_BYTES_PER_ITEM  ; 60
        sta.b 0x28
        jsr.l mult8_trampoline

        rep #0x20
        lda.b 0x2A
        tax  ; X = text buffer offset
        sep #0x20

    ; Copy row 1 (30 bytes) - content only, preserve borders
        ldy.w #0x0000

    _copy_all_row1:
        lda.w text_buffer_base, x
        sta (0x00), y
        inx
        iny
        cpy.w #30
        bne _copy_all_row1

    ; Copy row 2 (+$40 offset in tilemap) - content only, preserve borders
        ldy.w #0x0040

    _copy_all_row2:
        lda.w text_buffer_base, x
        sta (0x00), y
        inx
        iny
        cpy.w #0x005E
        bne _copy_all_row2

    ; Next slot
        inc.b 0x06
        lda.b 0x06
        cmp #BUFFER_SLOTS  ; 6 slots
        bne _copy_slots_loop

    ; Restore DBR
        plb
        rts

    ; ============================================================================
    ; tfr_inventory_list_rolling
    ; ============================================================================
    ; Replacement for TfrInventoryList ($0298FA)
    ; Transfers the visible portion of tilemap buffer to VRAM
    ;
    ; Called via JSL from bank 02

    tfr_inventory_list_rolling:
    """
    Replacement for original `TfrInventoryList` ($0298FA): re-render the visible inventory rows into our buffer and DMA
    the slice to VRAM. Reached via JSL from bank 02.
    """
    ; Set data bank to $7E for WRAM access
        phb
        lda #0x7E
        pha
        plb

    ; RE-RENDER all visible items only when something invalidated them
    ; (open / item swap). Scroll-edge hooks paint the new hidden slot
    ; before animation, so steady-state scroll requires zero re-render
    ; here. The flag was the per-frame full rebuild that was clobbering
    ; the pre-rendered hidden slot.
        lda.w inventory_needs_full_refresh
        beq _tfr_skip_refresh
        jsr.w _refresh_visible_items_internal
        stz.w inventory_needs_full_refresh

    _tfr_skip_refresh:

    ; Copy all 6 slots from text buffer to tilemap buffer
    ; This runs AFTER the game's window clearing at $9AF4
        jsr.w _copy_all_slots_to_tilemap

    ; Queue VRAM transfer (entry 3 covers $7400-$77FF)
        lda #0x03
        ldy.w #0x0002
        jsr.l load_menu_tfr_data_trampoline

        lda #0x01
        sta.w 0x1825  ; 1 transfer only
        sta.w 0x1824  ; Enable transfer

        plb  ; Restore data bank
        rtl

    ; ============================================================================
    ; _refresh_visible_items_internal
    ; ============================================================================
    ; Re-render all 5 visible items to our rolling buffer slots.
    ; Uses current EF71 as the top item index.
    ; Does NOT queue VRAM transfer (caller handles that).

    _refresh_visible_items_internal:
        ; Render 5 visible items to their CORRECT circular buffer slots
        ; The visible slots depend on rolling_buffer_pos due to circular rotation!
        ;

    ; After seam crossing, slots are rotated. For example if rolling_buffer_pos=3:
    ;   - Slot 3 shows item at rolling_top_row + 0
    ;   - Slot 4 shows item at rolling_top_row + 1
    ;   - Slot 5 shows item at rolling_top_row + 2
    ;   - Slot 0 shows item at rolling_top_row + 3 (wrapped)
    ;   - Slot 1 shows item at rolling_top_row + 4

        lda #0
        sta.b 0x06  ; Visible row index (0-4)

    _refresh_int_loop:
        ; Calculate item index = rolling_top_row + visible_row
        lda.w rolling_top_row
        clc
        adc.b 0x06
        sta.w rolling_edge_row  ; Item index for data lookup

    ; Calculate actual slot = (rolling_buffer_pos + visible_row) % BUFFER_SLOTS
        lda.w rolling_buffer_pos
        clc
        adc.b 0x06  ; pos + visible_row
        cmp #BUFFER_SLOTS
        bcc _refresh_slot_ok
        sec
        sbc #BUFFER_SLOTS  ; Wrap if >= 6

    _refresh_slot_ok:
        sta.w rolling_slot_index  ; Actual circular buffer slot

    ; Save visible row index
        lda.b 0x06
        pha

    ; Render item to this slot
        jsr.w _render_item_to_circular_slot

    ; Restore visible row index
        pla
        sta.b 0x06

    ; Next visible row
        inc.b 0x06
        lda.b 0x06
        cmp #VISIBLE_ROWS  ; 5 visible items
        bne _refresh_int_loop

        rts

    ; ============================================================================
    ; _refresh_visible_items - Re-render all visible items after scroll
    ; ============================================================================
    ; Simpler approach: instead of circular buffer tricks, just redraw the 5
    ; visible items to fixed slot positions (0-4) after each scroll.
    ; EF65 is reset to 0 by the caller.
    ;
    ; Called via JSL from wrap_and_clear_trampoline

    _refresh_visible_items:
        phb
        lda #0x7E
        pha
        plb

    ; Render 5 visible items to slots 0-4
    ; Item index = EF71 + slot
        lda #0
        sta.b 0x06  ; Slot index (0-4)

    _refresh_loop:
        ; Calculate item index = EF71 + slot
        lda.w 0xEF71
        clc
        adc.b 0x06
        sta.w rolling_edge_row  ; Item index for data lookup

    ; Use slot index for buffer position
        lda.b 0x06
        sta.w rolling_slot_index  ; Slot index (0-4)

    ; Save slot index
        lda.b 0x06
        pha

    ; Render item to this slot
        jsr.w _render_item_to_circular_slot

    ; Restore slot index
        pla
        sta.b 0x06

    ; Next slot
        inc.b 0x06
        lda.b 0x06
        cmp #VISIBLE_ROWS  ; 5 visible items
        bne _refresh_loop

    ; Queue VRAM transfer
        lda #0x03
        ldy.w #0x0002
        jsr.l load_menu_tfr_data_trampoline
        lda #0x01
        sta.w 0x1825
        sta.w 0x1824

        plb
        rtl

    ; ============================================================================
    ; _post_render_up - Called after scroll UP animation completes
    ; ============================================================================
    ; Renders the next item (for potential next scroll UP) to the off-screen slot
    ; Off-screen slot after scroll UP = (pos - 1) mod 6 (above top)
    ;
    ; Called via JSL from wrap_and_clear_trampoline

    _post_render_up:
        phb
        lda #0x7E
        pha
        plb

    ; Calculate item index = EF71 + VISIBLE_ROWS (the next item down the list)
        lda.w 0xEF71
        clc
        adc #VISIBLE_ROWS
        cmp #TOTAL_ITEMS
        bcs _post_up_done  ; Past end, nothing to render
        sta.w rolling_edge_row

    ; Off-screen slot = (pos - 1) mod 6
        lda.w rolling_buffer_pos
        dec
        bpl _post_up_slot_ok
        lda #BUFFER_SLOTS - 1

    _post_up_slot_ok:
        sta.w rolling_slot_index

        jsr.w _render_item_to_circular_slot

    ; Queue VRAM transfer
        lda #0x03
        ldy.w #0x0002
        jsr.l load_menu_tfr_data_trampoline
        lda #0x01
        sta.w 0x1825
        sta.w 0x1824

    _post_up_done:
        plb
        rtl

    ; ============================================================================
    ; _post_render_down - Called after scroll DOWN animation completes
    ; ============================================================================
    ; Renders the previous item (for potential scroll UP back) to the off-screen slot
    ; Off-screen slot after scroll DOWN = (pos + 5) mod 6 (below bottom)
    ;
    ; Called via JSL from wrap_and_clear_trampoline

    _post_render_down:
        phb
        lda #0x7E
        pha
        plb

    ; Calculate item index = EF71 + VISIBLE_ROWS (the item just past visible bottom)
    ; This prepares for scroll UP (which would show this item at bottom)
        lda.w 0xEF71
        clc
        adc #VISIBLE_ROWS
        cmp #TOTAL_ITEMS
        bcs _post_down_done  ; Past end, nothing to render
        sta.w rolling_edge_row

    ; Off-screen slot = (pos + 5) mod 6
        lda.w rolling_buffer_pos
        clc
        adc #VISIBLE_ROWS
        cmp #BUFFER_SLOTS
        bcc _post_down_slot_ok
        sec
        sbc #BUFFER_SLOTS

    _post_down_slot_ok:
        sta.w rolling_slot_index

        jsr.w _render_item_to_circular_slot

    ; Queue VRAM transfer
        lda #0x03
        ldy.w #0x0002
        jsr.l load_menu_tfr_data_trampoline
        lda #0x01
        sta.w 0x1825
        sta.w 0x1824

    _post_down_done:
        plb
        rtl

    ; ============================================================================
    ; post_scroll_down_render
    ; ============================================================================
    ; Called via JSL from wrap_and_clear_trampoline after scroll animation completes.
    ;
    ; For scroll DOWN: Pre-render happened BEFORE animation (in scroll_list_down_hook)
    ; so the newly visible slot already has correct content.
    ;
    ; We check if it was a scroll DOWN and optionally prepare the NEXT off-screen
    ; slot for future scroll UP operations.

    post_scroll_down_render:
    """Tail of `wrap_and_clear_trampoline` (JSL): post-animation hook for scroll-down."""
        ; Check if this was a scroll DOWN animation (type 2)
        ; $1820 still contains the animation type at this point
        lda.w 0x1820
        cmp #0x02
        bne _psd_done

    ; For scroll DOWN, the pre-render already happened in scroll_list_down_hook.
    ; The slot that scrolled into view (at bottom) has correct content.
    ;
    ; Optionally, we could prepare the slot that's now off-screen (at top)
    ; for a potential scroll UP. But since scroll_list_up_hook does pre-render,
    ; this isn't strictly necessary.

    _psd_done:
        rtl

    ; ============================================================================
    ; scroll_list_down_hook
    ; ============================================================================
    ; Called via JMP.L from $02A8B8
    ; Starts scroll animation. Pre-rendering happens AFTER animation in post_scroll_down_render.
    ; Returns via JMP.L to return_to_bank02 (which has RTS)
    ;

    ; Original code at $02A8B8:
    ;   ldx $ef71, dex, stx $ef71, lda #$0c, sta $ef64, lda #$02, sta $1820, rts

    ;MENU_FLAG_INVENTORY := 0x04         ; Bit 2 of $4A = inventory menu active

    scroll_list_down_hook:
    """
    Replacement for the scroll-down stub at `$02A8B8`: kicks off the down-scroll animation, pre-renders the new bottom
    slot for the rolling buffer.
    """
    ; === GUARD: Only use rolling buffer for inventory menu ===
    ; Check bit 2 of $4A (inventory flag). If not set, use original magic behavior.
        lda.b 0x4A
        and #0x04
        bne _sd_is_inventory

    ; --- ORIGINAL MAGIC MENU BEHAVIOR ---
    ; Original code: ldx $ef71, dex, stx $ef71, lda #$0c, sta $ef64, lda #$02, sta $1820, rts
        ldx.w 0xEF71
        dex
        stx.w 0xEF71
        lda #0x0C
        sta.w 0xEF64
        lda #0x02
        sta.w 0x1820
        jmp.l return_to_bank02

    _sd_is_inventory:
        ; NOTE: For inventory in single-column mode, we INCREMENT EF71 to show later items
        ;
        ; FF6-STYLE: Pre-render the new bottom item BEFORE starting the animation!
        ; This ensures the slot has correct content when it scrolls into view.

    ; Disable interrupts to prevent NMI from corrupting state
        sei

    ; Set data bank to $7E for RAM access
        phb
        lda #0x7E
        pha
        plb

    ; Check if we can scroll further: rolling_top_row + VISIBLE_ROWS must be < TOTAL_ITEMS
    ; Use rolling_top_row, NOT EF71 which has different meaning in battle!
        lda.w rolling_top_row
        cmp #( TOTAL_ITEMS - VISIBLE_ROWS )
        bcs _sd_abort  ; Already at max, can't scroll down

    ; === FF6-STYLE PRE-RENDER ===
    ; Before animation, render the item that will appear at the NEW bottom.
    ; The "off-screen" slot below the visible area will scroll into view.
    ; Off-screen slot = (rolling_buffer_pos + VISIBLE_ROWS) % BUFFER_SLOTS

    ; Calculate item index = rolling_top_row + VISIBLE_ROWS (the item appearing at new bottom)
    ; After increment, rolling_top_row will be current+1, so bottom item = (current+1) + 4 = current + 5
        lda.w rolling_top_row
        clc
        adc #VISIBLE_ROWS  ; item = rolling_top_row + 5
        cmp #TOTAL_ITEMS
        bcs _sd_skip_prerender  ; Past end, nothing to render
        sta.w rolling_edge_row  ; Save item index

    ; Calculate the off-screen slot that will become visible
    ; This is the slot 5 positions ahead of current top (wrapping)
        lda.w rolling_buffer_pos
        clc
        adc #VISIBLE_ROWS  ; pos + 5
        cmp #BUFFER_SLOTS
        bcc _sd_slot_ok
        sec
        sbc #BUFFER_SLOTS  ; Wrap if >= 6

    _sd_slot_ok:
        sta.w rolling_slot_index

    ; Render item to the off-screen slot
        jsr.w _render_item_to_circular_slot
        ; Copy to tilemap buffer
        jsr.w _copy_slot_to_tilemap
        ; Queue VRAM transfer
        jsr.w _transfer_circular_slot

    _sd_skip_prerender:
        ; INCREMENT EF71 to show later items (animation loop is NOPed out)
        lda.w 0xEF71
        inc
        sta.w 0xEF71

    ; INCREMENT rolling_top_row to track which item is at top of visible area
    ; This is critical for _refresh_visible_items_internal to work correctly!
        lda.w rolling_top_row
        inc
        sta.w rolling_top_row

    ; Set up scroll animation
        lda #0x0C
        sta.w 0xEF64
        lda #0x02  ; Animation 2 (scroll down)
        sta.w 0x1820

    ; Advance circular buffer position (top slot moves up, becomes off-screen)
        lda.w rolling_buffer_pos
        inc
        cmp #BUFFER_SLOTS
        bcc _sd_pos_ok
        lda #0

    _sd_pos_ok:
        sta.w rolling_buffer_pos

    _sd_abort:
        ; Ensure cursor 1 stays visible during scroll animation
        stz.w 0xEF69  ; Clear hide cursor 1 flag
        stz.w 0xEF6E  ; Clear alternate hide cursor 1 flag

        plb  ; Restore data bank
        cli  ; re-enable interrupts
        jmp.l return_to_bank02

    ; ============================================================================
    ; scroll_list_up_hook
    ; ============================================================================
    ; Called via JMP.L from $02A8CA
    ; Pre-renders new top row, then does original scroll setup
    ; Returns via JMP.L to return_to_bank02 (which has RTS)
    ;

    ; Original code at $02A8CA:
    ;   ldx $ef71, inx, stx $ef71, lda #$0c, sta $ef64, lda #$03, sta $1820, rts

    scroll_list_up_hook:
    """
    Replacement for the scroll-up stub at `$02A8CA`: pre-renders the new top row before kicking off the scroll-up
    animation.
    """
    ; === GUARD: Only use rolling buffer for inventory menu ===
    ; Check bit 2 of $4A (inventory flag). If not set, use original magic behavior.
        lda.b 0x4A
        and #0x04
        bne _su_is_inventory

    ; --- ORIGINAL MAGIC MENU BEHAVIOR ---
    ; Original code: ldx $ef71, inx, stx $ef71, lda #$0c, sta $ef64, lda #$03, sta $1820, rts
        ldx.w 0xEF71
        inx
        stx.w 0xEF71
        lda #0x0C
        sta.w 0xEF64
        lda #0x03
        sta.w 0x1820
        jmp.l return_to_bank02

    _su_is_inventory:
        ; NOTE: For inventory in single-column mode, we DECREMENT rolling_top_row to show earlier items
        ;

    ; For scroll UP, we DO need to pre-render BEFORE animation because:
    ; - The slot that will scroll INTO view might have stale data from a previous scroll down
    ; - We need to put the correct item there before it becomes visible

    ; Disable interrupts to prevent NMI from corrupting rolling_slot_index
        sei

    ; Set data bank to $7E for RAM access
        phb
        lda #0x7E
        pha
        plb

    ; Check if we can scroll: rolling_top_row must be > 0
    ; (Use our custom variable, NOT EF71 which has different meaning in battle!)
        lda.w rolling_top_row
        beq _su_abort  ; Already at item 0, can't scroll up

    ; First decrement buffer position (new top slot)
        lda.w rolling_buffer_pos
        dec
        bpl _su_pos_ok
        lda #BUFFER_SLOTS - 1  ; Wrap 0→5

    _su_pos_ok:
        sta.w rolling_buffer_pos
        sta.w rolling_slot_index  ; This slot will be the new top (currently off-screen)

    ; Calculate previous item index = rolling_top_row - 1 (the item that will appear at top)
    ; Use rolling_top_row, NOT EF71 which has different meaning in battle!
        lda.w rolling_top_row
        dec
        sta.w rolling_edge_row

    ; Pre-render to new top slot (currently off-screen, about to scroll in)
        jsr.w _render_item_to_circular_slot
        ; Copy to tilemap buffer
        jsr.w _copy_slot_to_tilemap
        ; Queue VRAM transfer for this slot
        jsr.w _transfer_circular_slot

    ; DECREMENT rolling_top_row to track which item is at top of visible area
    ; This is the authoritative source for which items are visible!
        lda.w rolling_top_row
        dec
        sta.w rolling_top_row

    ; Set up scroll animation
        lda #0x0C
        sta.w 0xEF64
        lda #0x03  ; Animation 3 (scroll up)
        sta.w 0x1820
        bra _su_exit

    _su_abort:
        ; Pre-increment EF85, EF86, $63 so the caller's unconditional
        ; `dec EF86 / dec EF85 / dec $63` at $02:B4FA-B500 lands back on
        ; the original values when our scroll-up aborts at the top of
        ; the list. Without this, $63 (cursor item index) underflows
        ; from 0 to 0xFF and the row 0 cursor item points at junk,
        ; reproducing the "one extra UP past item 0" visual.
        inc.w 0xEF85
        inc.w 0xEF86
        inc.b 0x63

    _su_exit:
        ; Ensure cursor 1 stays visible during scroll animation
        stz.w 0xEF69  ; Clear hide cursor 1 flag
        stz.w 0xEF6E  ; Clear alternate hide cursor 1 flag

        plb  ; Restore data bank
        cli  ; re-enable interrupts
        jmp.l return_to_bank02

    ; ============================================================================
    ; update_list_scroll_hdma_wrapped
    ; ============================================================================
    ; Replacement for $02A7F1 - builds HDMA table with scroll value WRAPPING
    ; This is the key to the circular buffer - scroll values wrap at 96 pixels
    ;
    ; Called via JMP.L from $02A7F1
    ; Input: X = current scroll offset (from $EF65)
    ;        Y = scanlines per row (12)
    ; Output: HDMA table at $7F74 filled with wrapped scroll values

    HDMA_TABLE := 0x7E7F74  ; Full 24-bit address: bank $7E, offset $7F74 (V scroll entries)
    HDMA_TABLE_SIZE := 0x00F0  ; 240 bytes (same as HDMA_Y_SIZE)
    SCROLL_WRAP := 0x0060  ; 96 = 6 slots × 16 pixels (tilemap buffer size)
    SCROLL_WRAP_LIMIT := 0x01D3  ; 467 = 371 + 96 (wrap when >= this value)
    OUR_BASE_SCROLL := 0x0173  ; 371 - same as original game

    update_list_scroll_hdma_wrapped:
    """
    Replacement for the HDMA-build stub at `$02A7F1`: rebuild the per-scanline V-scroll table for the inventory rolling
    buffer.
    """
    ; Check if we're in inventory mode (bit 2 of $4A)
    ; If not, use original behavior for other windows
        lda.b 0x4A
        and #0x04
        bne _use_circular_buffer

    ; Original behavior for non-inventory windows
    ; Input: X = scroll offset, Y = scanlines per row (12)
        rep #0x20  ; 16-bit A
        txa  ; A = scroll offset
        ldx.w #0x0000  ; Table index

    _orig_loop:
        sta.w 0x7F74, x  ; Store scroll value
        dey
        bne _orig_skip_add
        clc
        adc.w #0x0004  ; Add 4 every 12 scanlines
        ldy.w #0x000C  ; Reset scanline counter

    _orig_skip_add:
        inx
        inx
        inx
        inx
        cpx.w #0x00F0  ; 240 bytes
        bne _orig_loop
        .db 0x7B  ; TDC (clear A)
        sep #0x20  ; 8-bit A
        jmp.l return_to_bank02  ; Return via bank $02 trampoline

    _use_circular_buffer:
        ; FF6-STYLE CIRCULAR BUFFER HDMA
        ;

    ; Key insight from FF6's LoadItemBG1VScrollHDMATbl:
    ;   - At screen scanline S with scroll V, displayed VRAM row = V + S

    ;   - To show VRAM slot N at screen row R (scanline R*12):
    ;     scroll + R*12 = N*16, therefore scroll = N*16 - R*12
    ;

    ; Algorithm for each visible row (0-4):
    ;   vram_slot = (rolling_buffer_pos + row) % 6
    ;   scroll = BASE + (vram_slot * 16) - (row * 12)
    ;
    ; This ensures proper alignment AND seamless wraparound.
    ;
        sei  ; Disable interrupts during HDMA table update

    ; CRITICAL: Save direct page variables that the caller depends on
        lda.b 0x00
        pha
        lda.b 0x01
        pha
        lda.b 0x02
        pha
        lda.b 0x03
        pha
        lda.b 0x04
        pha
        lda.b 0x05
        pha

        rep #0x30  ; 16-bit A, X, Y

        ldx.w #0x0000  ; HDMA table index
        stz.b 0x02  ; Row counter (clears $02 and $03 in 16-bit mode)

    _row_loop:
        ; Calculate vram_slot = (rolling_buffer_pos + row) % 6
        lda.w rolling_buffer_pos
        and.w #0x00FF
        clc
        adc.b 0x02  ; + row number

    _mod6:
        cmp.w #BUFFER_SLOTS  ; >= 6?
        bcc _mod6_done
        sec
        sbc.w #BUFFER_SLOTS
        bra _mod6

    _mod6_done:
        ; A = vram_slot (0-5)

    ; Calculate vram_slot * 16
        asl
        asl
        asl
        asl  ; A = vram_slot * 16
        sta.b 0x00  ; Save vram_offset

    ; Calculate row * 12 = row * 8 + row * 4
    ; Use Y register for temp to avoid clobbering direct page
        lda.b 0x02  ; row (only low byte matters, high is 0)
        and.w #0x00FF  ; Ensure only low byte
        asl
        asl
        asl  ; row * 8
        tay  ; Y = row * 8
        lda.b 0x02
        and.w #0x00FF
        asl
        asl  ; row * 4
        sta.b 0x04  ; Use $04 for temp (not overlapping)
        tya  ; A = row * 8
        clc
        adc.b 0x04  ; row * 8 + row * 4 = row * 12
        ; A = scanline_offset (row * 12)

    ; scroll = BASE + vram_offset - scanline_offset
    ; eor.w   #0xFFFF                 ; Negate: -scanline_offset
    ; a816 does not support yet the w for eor.
        .db 0x49
        .dw 0xffff

        inc
        clc
        adc.b 0x00  ; + vram_offset
        clc
        adc.w #OUR_BASE_SCROLL  ; + BASE
        sta.b 0x00  ; $00 = scroll value for this row

    ; Store same scroll value for all 12 scanlines of this row
        ldy.w #0x000C  ; 12 scanlines

    _scanline_loop:
        lda.b 0x00
        sta.l HDMA_TABLE, x
        inx
        inx
        inx
        inx  ; X += 4 (next HDMA entry)
        dey
        bne _scanline_loop

    ; Next row
        inc.b 0x02
        lda.b 0x02
        cmp.w #VISIBLE_ROWS  ; 5 rows total
        bne _row_loop

    ; CRITICAL: Restore direct page variables before returning
        sep #0x20  ; 8-bit A for PLA
        pla
        sta.b 0x05
        pla
        sta.b 0x04
        pla
        sta.b 0x03
        pla
        sta.b 0x02
        pla
        sta.b 0x01
        pla
        sta.b 0x00

    ; Check if scroll animation is active before forcing cursor position
    ; Only force during animation ($1820 = 2 or 3), otherwise let normal code handle it
        lda.l 0x7E1820  ; Animation type
        beq _cursor_skip_force  ; If 0, no animation - skip forcing

    ; Animation is active - ensure cursor stays visible
    ; Must use long addressing since data bank may be $02 (ROM), not $7E (WRAM)
        pha  ; Save animation type
        lda #0x00
        sta.l 0x7EEF69  ; Clear hide cursor 1 flag
        sta.l 0x7EEF6E  ; Clear alternate hide cursor 1 flag

    ; X position is always $0C for single-column mode
        lda #0x0C
        sta.l 0x7EEF6B  ; Set cursor 1 X position

    ; Set Y based on animation direction
    ; Scroll down ($1820=2): cursor at bottom row, Y = $CC
    ; Scroll up ($1820=3): cursor at top row, Y = $9C
        pla  ; Restore animation type
        cmp #0x02  ; Scroll down?
        bne _cursor_scroll_up
        lda #0xCC  ; Bottom row Y position
        bra _cursor_set_y

    _cursor_scroll_up:
        lda #0x9C  ; Top row Y position

    _cursor_set_y:
        sta.l 0x7EEF6D  ; Set cursor 1 Y position

    _cursor_skip_force:

        cli
        jmp.l return_to_bank02

    ; HDMA table addresses - Y scroll portion only!
    ; Original ResetListScrollHDMA writes to $81F4 (Y scroll in swap table)
    ; Animation swaps this with $7F74 (Y scroll in active table)
    ; X scroll values at $81D2/$7F52 are left alone.
    HDMA_SWAP_Y := 0x7E81F4  ; Y scroll in swap table
    HDMA_ACTIVE_Y := 0x7E7F74  ; Y scroll in active table
    HDMA_Y_SIZE := 0x00F0  ; 240 bytes (same as original)

    ; ============================================================================
    ; reset_list_scroll_hdma_rolling
    ; ============================================================================
    ; Replacement for $02AAB8 - fills Y scroll in BOTH HDMA tables
    ; X scroll values stay as original game initialized them.
    ;
    ; Only difference from original: uses 132-based values instead of 371-based.

    reset_list_scroll_hdma_rolling:
    """Replacement for `$02AAB8`: fill the Y-scroll bytes of both HDMA tables when the inventory window opens."""
        ; Check if we're in inventory mode (bit 2 of $4A)
        lda.b 0x4A
        and #0x04
        bne _reset_use_circular

    ; Original behavior for non-inventory windows
        ldx.w #0x0173  ; 371 - base scroll
        stx.w 0xEF65
        ldy.w #0x000C  ; 12 scanlines
        sty.w 0xEF67
        rep #0x20  ; 16-bit A
        txa  ; A = 371
        ldx.w #0x0000

    _reset_orig_loop:
        sta.w 0x81F4, x  ; Swap table only (like original)
        dey
        bne _reset_orig_skip
        clc
        adc.w #0x0004  ; Add 4 every 12 scanlines
        ldy.w #0x000C

    _reset_orig_skip:
        inx
        inx
        inx
        inx
        cpx.w #0x00F0
        bne _reset_orig_loop
        .db 0x7B  ; TDC
        sep #0x20
        rtl

    _reset_use_circular:
        ; Circular buffer setup for inventory
        ; Save $00-$03 to prevent corrupting caller's state
        lda.b 0x00
        pha
        lda.b 0x01
        pha
        lda.b 0x02
        pha
        lda.b 0x03
        pha

        ldx.w #0x0173  ; 371 - game's expected base scroll
        stx.w 0xEF65
        ldy.w #0x000C  ; 12 scanlines per item row
        sty.w 0xEF67

    ; Re-initialize circular buffer contents when inventory (re)opens
    ; This ensures VRAM has correct items even after closing/reopening
        jsr.l init_inventory_text_buf_rolling

    ; rolling_buffer_pos is now set by init_inventory_text_buf_rolling

    ; Fill Y scroll in both tables using circular buffer formula
        stz.b 0x02  ; Row counter low byte (8-bit mode)
        stz.b 0x03  ; Row counter high byte
        rep #0x30  ; 16-bit A and X/Y
        ldx.w #0x0000  ; HDMA table index

    _reset_row_loop:
        ; At init: vram_slot = row, so scroll = BASE + row * 4
        lda.b 0x02  ; row
        and.w #0x00FF
        asl
        asl  ; row * 4
        clc
        adc.w #OUR_BASE_SCROLL  ; + BASE
        sta.b 0x00  ; Save scroll value

    ; Store same value for all 12 scanlines of this row
        ldy.w #0x000C  ; 12 scanlines

    _reset_scanline_loop:
        lda.b 0x00
        sta.l HDMA_SWAP_Y, x  ; $81F4 + X
        sta.l HDMA_ACTIVE_Y, x  ; $7F74 + X
        inx
        inx
        inx
        inx  ; X += 4
        dey
        bne _reset_scanline_loop

    ; Next row
        inc.b 0x02
        lda.b 0x02
        cmp.w #VISIBLE_ROWS  ; 5 rows
        bne _reset_row_loop

        sep #0x20  ; 8-bit A (game expects this)
        ; Restore $00-$03 before returning
        pla
        sta.b 0x03
        pla
        sta.b 0x02
        pla
        sta.b 0x01
        pla
        sta.b 0x00
        rtl

    ; ============================================================================
    ; check_cursor2_visibility_rolling
    ; ============================================================================
    ; Checks if cursor 2 (the first selected item in swap mode) should be visible.
    ; Called after scroll animation completes.
    ;

    ; Logic:
    ;   - If swap mode NOT active ($EF94 == 0), return immediately
    ;   - Get first selected item index from $EF95 (mask out bit 7)

    ;   - If rolling_top_row <= selected < rolling_top_row + VISIBLE_ROWS:
    ;       Show cursor 2 ($EF6A = 0)

    ;   - Else:
    ;       Hide cursor 2 ($EF6A = 1)
    ;
    ; Called via JSR from wrap_and_clear_trampoline (bank $02)

    swap_mode_flag := 0xEF94  ; Non-zero = swap mode active
    first_selected_item := 0xEF95  ; First selected item index (bit 7 may be set)
    hide_cursor_2 := 0xEF6A  ; Non-zero = hide cursor 2

    check_cursor2_visibility_rolling:
    """
    Toggle cursor-2 visibility while swap mode is active based on whether the first-selected item is in the visible
    window.
    """
    ; Check if we're in inventory mode (bit 2 of $4A)
    ; If not, don't touch cursor 2 state
        lda.b 0x4A
        and #0x04
        beq _cursor2_done

    ; Check if swap mode is active
        lda.w swap_mode_flag
        beq _cursor2_done  ; Not in swap mode, nothing to check

    ; Get first selected item index (mask out bit 7)
        lda.w first_selected_item
        and #0x7F  ; Clear bit 7
        sta.b 0x00  ; Save selected item index

    ; Check if selected item is in visible range:
    ; visible if: rolling_top_row <= selected < rolling_top_row + VISIBLE_ROWS

    ; First check: selected >= rolling_top_row
        lda.b 0x00  ; Selected item
        cmp.w rolling_top_row
        bcc _cursor2_hide  ; selected < rolling_top_row, hide cursor

    ; Second check: selected < rolling_top_row + VISIBLE_ROWS
        lda.w rolling_top_row
        clc
        adc #VISIBLE_ROWS  ; rolling_top_row + 5
        sta.b 0x01  ; Save upper bound

        lda.b 0x00  ; Selected item
        cmp.b 0x01  ; Compare to upper bound
        bcs _cursor2_hide  ; selected >= upper bound, hide cursor

    ; Item is visible - show cursor 2
        stz.w hide_cursor_2  ; $EF6A = 0 (show)
        bra _cursor2_done

    _cursor2_hide:
        ; Item is not visible - hide cursor 2
        lda #0x01
        sta.w hide_cursor_2  ; $EF6A = 1 (hide)

    _cursor2_done:
        rtl  ; Called via JSL from bank $02

    ; ============================================================================
    ; Field Menu NMI Handler (relocated from bank $01 to save space)
    ; ============================================================================
    ; Field + drops state aliases - use the cast'd struct views from
    ; items.i / src/ingame/drops_rolling.s. Field is `field_menu_rolling`
    ; (defined in items.i, visible at module scope). Drops state at
    ; $7E:9C30 isn't exported from its defining module, so re-cast it
    ; locally to get drops_rolling.hdma_copy_pending et al.
    drops_rolling := (0x7E9C30 as RollingBufferState)
    FIELD_HDMA_TABLE := 0x7E9800
    FIELD_HDMA_SHADOW := 0x7E9840
    FIELD_HDMA_TABLE_SIZE := 40
    DROPS_HDMA_TABLE := 0x7E9880
    DROPS_HDMA_SHADOW := 0x7E98C0
    DROPS_HDMA_TABLE_SIZE := 40

    ; Called via JSL from bank $01 nmi_dma_transfer_check

    field_menu_nmi_dma_transfer_check_impl:
    """
    NMI hook (JSL from bank $01) relocated to bank $20: transfer the field rolling-buffer tilemap to VRAM and update
    the live HDMA scroll table.
    """
        php
        sep #0x20  ; 8-bit A

    ; === GUARD: Only run if menu HDMA is enabled ===
    ; This prevents field menu DMA from corrupting battle VRAM
        lda.l field_menu_rolling.hdma_enable
        bne _field_nmi_active
        jmp.w _field_nmi_done

    _field_nmi_active:

    ; === HDMA table copy: shadow -> active ===
        lda.l field_menu_rolling.hdma_copy_pending
        beq _field_nmi_hdma_copy_done
        lda #0x00
        sta.l field_menu_rolling.hdma_copy_pending

    ; Copy 40 bytes from shadow ($9840) to active ($9800)
        rep #0x30  ; 16-bit A, X, Y
        ldx.w #0x0000

    _field_nmi_hdma_copy_loop:
        lda.l FIELD_HDMA_SHADOW, x
        sta.l FIELD_HDMA_TABLE, x
        inx
        inx
        cpx.w #FIELD_HDMA_TABLE_SIZE
        bcc _field_nmi_hdma_copy_loop
        sep #0x20  ; Back to 8-bit A

    _field_nmi_hdma_copy_done:
        ; === Drops HDMA table copy: $7E:98C0 shadow -> $7E:9880 active ===
        ; Drops uses ch4 driving BG4VOFS with its own 64-byte table, so the
        ; shadow→active copy needs a parallel block keyed off
        ; drops_rolling.hdma_copy_pending. Skip if drops HDMA is disabled in
        ; $1BAE bit 4.
        sep #0x20
        lda.l field_menu_rolling.hdma_enable
        and #0x10
        beq _drops_nmi_hdma_copy_done
        lda.l drops_rolling.hdma_copy_pending
        beq _drops_nmi_hdma_copy_done
        lda #0x00
        sta.l drops_rolling.hdma_copy_pending
        rep #0x30
        ldx.w #0x0000

    _drops_nmi_hdma_copy_loop:
        lda.l DROPS_HDMA_SHADOW, x
        sta.l DROPS_HDMA_TABLE, x
        inx
        inx
        cpx.w #DROPS_HDMA_TABLE_SIZE
        bcc _drops_nmi_hdma_copy_loop
        sep #0x20

    _drops_nmi_hdma_copy_done:

    ; === Tilemap DMA transfer (field menu = BG1) ===
    ; Skip when treasure menu owns the screen: $1BB3 is then the
    ; original drops cursor row, not field_menu_transfer_pending,
    ; and clearing it would snap the drops cursor back to row 0.
        lda.l 0x7E1BC6
        bne _field_nmi_check_treasure
        lda.l field_menu_rolling.transfer_pending
        beq _field_nmi_check_treasure
        lda #0x00
        sta.l field_menu_rolling.transfer_pending

        sep #0x20
        lda #0x01
        sta.w 0x4300
        lda #0x18
        sta.w 0x4301
        rep #0x20
        lda.w #0xB600
        sta.w 0x4302
        sep #0x20
        lda #0x7E
        sta.w 0x4304
        rep #0x20
        lda.w #0x0800
        sta.w 0x4305
        lda.w #0x6000
        sta.w 0x2116
        sep #0x20
        lda #0x01
        sta.w 0x420B

    _field_nmi_check_treasure:
    .if TREASURE_INVENTORY_ROLLING {
    ; === Tilemap DMA transfer (treasure menu = BG3) ===
        lda.l 0x7E0000 + 0x9C0B  ; treasure_rolling.transfer_pending
        beq _field_nmi_done
        lda #0x00
        sta.l 0x7E0000 + 0x9C0B

        sep #0x20
        lda #0x01
        sta.w 0x4300
        lda #0x18
        sta.w 0x4301
        rep #0x20
        lda.w #0xD600  ; BG3 screen buffer source ($7ED600)
        sta.w 0x4302
        sep #0x20
        lda #0x7E
        sta.w 0x4304
        rep #0x20
        lda.w #0x0800  ; 2 KB tilemap
        sta.w 0x4305
        lda.w #0x7000  ; BG3 tilemap VRAM target
        sta.w 0x2116
        sep #0x20
        lda #0x01
        sta.w 0x420B
    }

    _field_nmi_done:
        ; --- VWF CHR flush (DMA channel 6) ---
        ; Hands off to `render.flush_chr_to_vram`. Gates on `VWF_CHR_DIRTY`
        ; and reads VRAM dest + size from `VwfConfig`. Drives ch6, which
        ; the FF4 DMA audit shows untouched by vanilla btlgfx / menu and
        ; by every engine we ship (ch7 is the shared battle / libmz /
        ; field-NMI-tilemap channel, ch3 was the WRAM mirror experiment).
        ; `flush_chr_to_vram` lives in the same bank-20 reloc region as
        ; this impl ; use a short JSR so the return stays balanced with
        ; the RTS the engine routine ends with.
        jsr.w render.flush_chr_to_vram
        plp
        rtl
}
