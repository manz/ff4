"""
Battle inventory rolling-buffer engine (single column, 5 visible rows + 1 prefetch slot): replaces original
`InitInventoryTextBuf` / `TfrInventoryList`, hooks scroll up/down, rebuilds the wrapped HDMA scroll table and
runs the field-menu NMI DMA check.
"""
.import "core/preamble"
.import "core/vwf_ram"
.import "battle/render_state"
.include "battle/render_save.i"
.import "core/items"
.import "core/bank20_helpers"
.import "core/assets"
.import "small_vwf/init"
.import "battle/magic_reloc"
.import "battle/sram"
.import "battle/vanilla_trampolines"
.import "core/vanilla"


.include "core/bank20.i"

.alloc _battle_inventory_rolling_block in bank20_reloc {
; Circular buffer (FF6-style): only the 5 visible rows are rendered; edge rows render BEFORE the scroll animation.

    VISIBLE_ROWS := 5
    BUFFER_SLOTS := 6  ; 5 visible + 1 off-screen prefetch
    _TOTAL_ITEMS := 48
    .include "battle/inventory_budget.i"
    .include "core/bank20.i"
    _TOTAL_ROWS := 48  ; one item per row

    _TEXT_BYTES_PER_ITEM := 60  ; 30 tiles x 2 bytes (dakuten + main rows)
    _TILE_PALETTE_MASK := 0x1C  ; tile attribute bits 2-4
    _ITEM_GREY_PALETTE := 0x04  ; palette 1: disabled item
    _TILEMAP_BYTES_PER_ROW := 128  ; 2 tilemap rows x 64 bytes ($80)

; Spell list buffers freed by magic direct rendering: $97A6, $9E66, $A526, $ABE6, $B2A6
    _text_buffer_base := 0x97A6  ; ring buffer, 6 slots x 60 = 360 bytes (freed spell buffer 1)
    inv_format_buffer := 0x9E66  ; draw_text format buffer (freed spell buffer 2)
    _tilemap_buffer_base := 0xC4E6
_ITEMS_FRAME_FIRST_ROW := 1  ; Buffer rows of the items window frame:
    _ITEMS_FRAME_BOTTOM_ROW := 14  ; sides on 1-13, bottom edge on 14,
    _ITEMS_FRAME_CLEAR_END_ROW := 26  ; rows 15-25 blank (magic frame area)
    _tilemap_content_offset := 0x46  ; $C52C: one tile right of vanilla's $44 ($C52A, col 2)

; Unused battle RAM. $EF82 rather than $1817, which conflicts with NMI/battle commands.
    _rolling_top_row := 0xEF97  ; top visible row index (0-43)
    _rolling_buffer_pos := 0xEF98  ; circular buffer position
    _rolling_edge_row := 0xEF99  ; row index to render (0-47)
    _rolling_slot_index := 0xEF82  ; slot being rendered (0-5)
    _inventory_needs_full_refresh := 0xEF9D  ; non-zero: re-render all visible slots this frame (init / item swap)

; One 128-byte slot (2 tilemap rows) per row; the HDMA scroll offset rotates which slot shows at which screen row.
    _VRAM_SLOT_SIZE := 0x80
    _VRAM_SLOT_BASE := 0x7400

; VRAM word addresses; must match where the transfer lands the content. Entry 3 copies $C4E6 to VRAM $7400,
; so WRAM byte offset $44 = word offset $22. Slots are $40 words apart.
_vram_slot_table:
    .dw 0x7422  ; Slot 0
    .dw 0x7462  ; Slot 1
    .dw 0x74A2  ; Slot 2
    .dw 0x74E2  ; Slot 3
    .dw 0x7522  ; Slot 4
    .dw 0x7562  ; Slot 5 (off-screen prefetch)

; WRAM mirror of the VRAM slots, 128 bytes each
    _TILEMAP_SLOT_BASE := _tilemap_buffer_base + _tilemap_content_offset

init_inventory_text_buf_rolling:
"""
    Replacement for original `$029E9C`: render the 5 visible inventory rows + 1 off-screen prefetch slot when the
    in-battle inventory window opens, resetting the rolling-buffer state. Clobbers A, X, Y, $00-$06, $26-$2A.
"""


    phb
    lda #0x7E
    pha
    plb

; Always start at row 0. EF65/EF67 are set by ResetListScrollHDMA.
    stz.w 0xEF71  ; Game's row index = 0
    stz.w 0xEF86  ; Scroll offset = 0 (top item visible)
    lda #1
    sta.w _inventory_needs_full_refresh  ; First frame after open: paint all visible.
    stz.b 0x60  ; Cursor row = 0 (top visible row)
    stz.w _rolling_top_row
    stz.w _rolling_buffer_pos
; Reset the magic-list flags so cart RAM from an earlier battle (or a savestate) can't force a repaint.
    lda.b #0x00
    sta.l battle_render_state.items_frame_dirty
    sta.l battle_render_state.spell_tiles_live

; Reset the VWF allocator to tile 0xC0 once; each slot render then owns a distinct tile range.
    jsr.l messages_vwf.init_inventory


; Render 6 rows (5 visible + 1 off-screen); at init item index = slot index
    lda #0
    sta.b 0x06  ; Slot index (0-5)

_init_row_loop:
    lda.b 0x06
    sta.w _rolling_edge_row  ; Item index for data lookup
    sta.w _rolling_slot_index  ; Slot index for buffer position

    lda.b 0x06
    pha

    jsr.w _render_item_to_circular_slot

    pla
    sta.b 0x06

    inc.b 0x06
    lda.b 0x06
    cmp #BUFFER_SLOTS  ; 6 slots total
    bne _init_row_loop

; Clear the VWF battle flag and flag DMA so the tile slice flushes on the next NMI
    jsr.l messages_vwf.deinit


; Queue VRAM transfer for initial render
    lda #0x03
    ldy.w #0x0002
    jsr.l load_menu_tfr_data_trampoline
    lda #0x01
    sta.w menu_tilemap_tfr_count
    sta.w menu_tilemap_tfr_enable

    plb
    rtl


    .macro _save_text_params() {
    """
    Push vanilla btlgfx's DrawText parameters ($EF50 text, $EF52 destination, $EF54/$EF55 lengths) and its working
    pointers ($30-$37, direct page 0). The renderer runs in the middle of other windows' draws, even inside one (from
    the NMI): left on the format buffer, they made the next message decode inventory rows and hang in DrawCharVar.
    """
    rep #0x20
    lda.w 0xEF54
    pha
    lda.w 0xEF52
    pha
    lda.w 0xEF50
    pha
    lda.b 0x30
    pha
    lda.b 0x32
    pha
    lda.b 0x34
    pha
    lda.b 0x36
    pha
    sep #0x20
    }

    .macro _restore_text_params() {
    """Pull what `_save_text_params` pushed; A left 0 (its high byte included: vanilla's `tax` would carry it)."""
    rep #0x20
    pla
    sta.b 0x36
    pla
    sta.b 0x34
    pla
    sta.b 0x32
    pla
    sta.b 0x30
    pla
    sta.w 0xEF50
    pla
    sta.w 0xEF52
    pla
    sta.w 0xEF54
    lda.w #0x0000
    sep #0x20
    }

; Pre-render the new bottom row into the off-screen slot before the scroll-down animation.
; Unused: scroll_list_down_hook renders its edge row itself.
_render_bottom_edge_row:
    sei  ; NMI would corrupt _rolling_slot_index

    phb
    lda #0x7E
    pha
    plb

; new bottom item = top + BUFFER_SLOTS
    lda.w 0xEF71
    clc
    adc #BUFFER_SLOTS

    cmp #_TOTAL_ITEMS
    bcs _render_bottom_done  ; Past end, nothing to render

    sta.w _rolling_edge_row

; off-screen slot = (_rolling_buffer_pos + 5) % 6
    lda.w _rolling_buffer_pos
    clc
    adc #VISIBLE_ROWS
    cmp #BUFFER_SLOTS
    bcc _bottom_slot_ok
    sec
    sbc #BUFFER_SLOTS

_bottom_slot_ok:
    sta.w _rolling_slot_index

    jsr.w _render_item_to_circular_slot

; Queue full tilemap transfer (game's VBlank handles it)
    lda #0x03
    ldy.w #0x0002
    jsr.l load_menu_tfr_data_trampoline
    lda #0x01
    sta.w menu_tilemap_tfr_count
    sta.w menu_tilemap_tfr_enable

; Advance circular position (top slot moves down)
    lda.w _rolling_buffer_pos
    inc
    cmp #BUFFER_SLOTS
    bcc _store_pos_down
    lda #0

_store_pos_down:
    sta.w _rolling_buffer_pos

_render_bottom_done:
    plb
    cli
    rts

; Pre-render the new top row into the slot before circular_pos before the scroll-up animation.
; Unused: scroll_list_up_hook renders its edge row itself.
_render_top_edge_row:
    sei  ; NMI would corrupt _rolling_slot_index

    phb
    lda #0x7E
    pha
    plb

    lda.w 0xEF71
    dec  ; New top row after scroll

    bmi _render_top_done

    sta.w _rolling_edge_row

; Decrement circular_pos first, then render into that slot (the new top)
    lda.w _rolling_buffer_pos
    dec
    bpl _store_pos_up
    lda #BUFFER_SLOTS - 1  ; Wrap 0 to 5

_store_pos_up:
    sta.w _rolling_buffer_pos
    sta.w _rolling_slot_index

    jsr.w _render_item_to_circular_slot

; Queue full tilemap transfer (game's VBlank handles it)
    lda #0x03
    ldy.w #0x0002
    jsr.l load_menu_tfr_data_trampoline
    lda #0x01
    sta.w menu_tilemap_tfr_count
    sta.w menu_tilemap_tfr_enable

_render_top_done:
    plb
    cli
    rts

; In: _rolling_edge_row = item index (0-47), _rolling_slot_index = destination slot.
; Out: item rendered to its text buffer slot and copied to its tilemap slot.
_render_item_to_circular_slot:
; php/plp rather than sei/cli so nested calls keep the caller's I flag
    php
    sei

; draw_text may change DBR
    phb

; D = $0000
    rep #0x20
    tdc
    pha  ; Save original D on stack
    lda.w #0x0000
    tcd
    sep #0x20

; Save $00-$0B (block copy) and $26-$2B (Mult8) in case NMI fires mid block copy
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
    lda.b btlgfx_dp.multiplier1
    pha
    lda.b btlgfx_dp.multiplier1 + 1
    pha
    lda.b btlgfx_dp.multiplier2
    pha
    lda.b btlgfx_dp.multiplier2 + 1
    pha
    lda.b btlgfx_dp.mult8_result
    pha
    lda.b btlgfx_dp.mult8_result + 1
    pha
    _save_text_params()
    save_render_state()

; text_addr = _text_buffer_base + slot * _TEXT_BYTES_PER_ITEM
    lda.w _rolling_slot_index  ; Slot index (0-4)
    sta.b btlgfx_dp.multiplier1
    lda #_TEXT_BYTES_PER_ITEM  ; 60 bytes per slot
    sta.b btlgfx_dp.multiplier2
    jsr.l mult8_trampoline

    rep #0x20
    lda.b btlgfx_dp.mult8_result
    clc
    adc #_text_buffer_base
    sta.w 0xEF52  ; draw_text output destination
    tdc
    sep #0x20

    ldx.w #inv_format_buffer
    stx.w 0xEF50
    lda #15
    sta.w 0xEF54

; item data at _rolling_edge_row * 4
    tdc
    lda.w _rolling_edge_row
    asl
    asl
    tax

    lda.l battle_inventory.id, x  ; Item ID
    sta.b 0x02
    bne _slot_id_nonzero
    jmp.w _empty_slot_fast  ; ID == 0 -> empty entry, skip VWF

_slot_id_nonzero:
    lda.l battle_inventory.qty, x  ; Quantity
    sta.b 0x03

; palette 1 when disabled (flags bit 7)
    lda #0x00
    sta.b 0x00
    sta.b 0x01
    lda.l battle_inventory.flags, x
    and #0x80
    beq _slot_not_disabled
    lda #0x04
    sta.b 0x00
    sta.b 0x01

_slot_not_disabled:
    jsr.w _build_item_format

    jsr.l draw_text_rolling_trampoline
    jmp.w _slot_render_done

_build_item_format:
"""
Build an item row's format string in `inv_format_buffer`: symbol, the name's baked tiles (0x0B id), the quantity
column. In: $00 name palette, $01 symbol palette, $02 item id, $03 quantity (A8, X/Y16, D=0, DB=$7E).
"""
; the item's string in items_unleashed: symbol byte, name, $00
    lda.b 0x02
    jsr.l item_name_offset
    tax

    ldy.w #0x0000
    lda #0x0E
    sta.w inv_format_buffer, y
    iny
    lda.b 0x01
    sta.w inv_format_buffer, y
    iny

    lda.l items_unleashed, x
    sta.w inv_format_buffer, y
    iny

    lda #0xFE
    sta.w inv_format_buffer, y
    iny


    lda #0x0E
    sta.w inv_format_buffer, y
    iny
    lda.b 0x00
    sta.w inv_format_buffer, y
    iny

; The name: its baked tiles (0x0B id), then back to fixed tiles and on to the quantity column.
    lda #0x0B
    sta.w inv_format_buffer, y
    iny
    lda.b 0x02
    sta.w inv_format_buffer, y
    iny
    lda #0xFE
    sta.w inv_format_buffer, y
    iny
    lda #0xFC
    sta.w inv_format_buffer, y
    iny
    lda #12
    sta.w inv_format_buffer, y
    iny


    lda.b 0x02
    bne _bif_has_item
    lda #0x05
    sta.w inv_format_buffer, y
    iny
    lda #0x03
    bra _bif_finish

_bif_has_item:
    lda #0xC8
    sta.w inv_format_buffer, y
    iny
    lda.b 0x03
; Zero-extend A before `tax`: A.hi holds a leaked byte from earlier 16-bit
; arithmetic, and with X=16 hex_to_dec would emit BCD for the wider value
; (qty 1 + leaked $06 -> X=$0601 -> "37").
    rep #0x20
    and.w #0x00ff
    tax
    sep #0x20
    jsr.l hex_to_dec_trampoline
    jsr.l normalize_num_trampoline
    lda.w hex_digits + 2
    sta.w inv_format_buffer, y
    iny
    lda.w hex_digits + 3

_bif_finish:
    sta.w inv_format_buffer, y
    iny
    lda #0x00
    sta.w inv_format_buffer, y
    rts

build_item_format_far:
"""`_build_item_format` for other banks' callers (the battle equip popup). Callable with JSL."""
    jsr.w _build_item_format
    rtl

_empty_slot_fast:
"""Empty entry (id 0): fill the slot with 30 blank tiles ($FF $00), skipping a ~80K-cycle draw_text."""


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
    restore_render_state()
    _restore_text_params()

; tilemap copy happens later: _copy_all_slots_to_tilemap (init), _copy_slot_to_tilemap (scroll)

; Restore zero page (reverse order)
    pla
    sta.b btlgfx_dp.mult8_result + 1
    pla
    sta.b btlgfx_dp.mult8_result
    pla
    sta.b btlgfx_dp.multiplier2 + 1
    pla
    sta.b btlgfx_dp.multiplier2
    pla
    sta.b btlgfx_dp.multiplier1 + 1
    pla
    sta.b btlgfx_dp.multiplier1
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

    rep #0x20
    pla
    tcd
    sep #0x20

    plb

    plp
    rts

; Queue a circular slot's tilemap transfer to VRAM. In: _rolling_slot_index.

_transfer_circular_slot:
    php
    sei

; mult8_trampoline may change DBR
    phb
    lda #0x7E
    pha
    plb  ; Ensure DBR is $7E for WRAM access

; Save $00-$0B (block copy) and $26-$2B (Mult8) in case NMI fires mid block copy
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
    lda.b btlgfx_dp.multiplier1
    pha
    lda.b btlgfx_dp.multiplier1 + 1
    pha
    lda.b btlgfx_dp.multiplier2
    pha
    lda.b btlgfx_dp.multiplier2 + 1
    pha
    lda.b btlgfx_dp.mult8_result
    pha
    lda.b btlgfx_dp.mult8_result + 1
    pha

; VRAM destination from the slot table
    lda.w _rolling_slot_index
    asl  ; ×2 for word lookup
    tax
    rep #0x20
    lda.l _vram_slot_table, x
    sta.b 0x04  ; Save VRAM dest
    sep #0x20

; source = _TILEMAP_SLOT_BASE + slot * 128
    lda.w _rolling_slot_index
    sta.b btlgfx_dp.multiplier1
    lda #_TILEMAP_BYTES_PER_ROW
    sta.b btlgfx_dp.multiplier2
    jsr.l mult8_trampoline

    rep #0x20
    lda.b btlgfx_dp.mult8_result
    clc
    adc #_tilemap_buffer_base + _tilemap_content_offset  ; _TILEMAP_SLOT_BASE
    sta.b 0x00  ; Source address (low word)
    sep #0x20

; Queue via the menu transfer system (entry 3 covers the slots)
    lda #0x03
    ldy.w #0x0002
    jsr.l load_menu_tfr_data_trampoline

    lda #0x01
    sta.w menu_tilemap_tfr_count
    sta.w menu_tilemap_tfr_enable

; Restore zero page (reverse order)
    pla
    sta.b btlgfx_dp.mult8_result + 1
    pla
    sta.b btlgfx_dp.mult8_result
    pla
    sta.b btlgfx_dp.multiplier2 + 1
    pla
    sta.b btlgfx_dp.multiplier2
    pla
    sta.b btlgfx_dp.multiplier1 + 1
    pla
    sta.b btlgfx_dp.multiplier1
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

    plb

    plp
    rts

; Copy one slot from the text buffer to the tilemap buffer.
; In: _rolling_slot_index (0-5). Uses $00-$01, $26, $28, $2A, X, Y.

_copy_slot_to_tilemap:
; php/plp rather than sei/cli so nested calls keep the caller's I flag
    php
    sei

; mult8_trampoline may change DBR
    phb

; D = $0000
    rep #0x20
    tdc
    pha
    lda.w #0x0000
    tcd
    sep #0x20

; Save $00-$0B (block copy) and $26-$2B (Mult8) in case NMI fires mid block copy
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
    lda.b btlgfx_dp.multiplier1
    pha
    lda.b btlgfx_dp.multiplier1 + 1
    pha
    lda.b btlgfx_dp.multiplier2
    pha
    lda.b btlgfx_dp.multiplier2 + 1
    pha
    lda.b btlgfx_dp.mult8_result
    pha
    lda.b btlgfx_dp.mult8_result + 1
    pha

; dest = _TILEMAP_SLOT_BASE + slot * 128
    lda.w _rolling_slot_index
    sta.b btlgfx_dp.multiplier1
    lda #_TILEMAP_BYTES_PER_ROW
    sta.b btlgfx_dp.multiplier2
    jsr.l mult8_trampoline

    rep #0x20
    lda.b btlgfx_dp.mult8_result
    clc
    adc #_tilemap_buffer_base + _tilemap_content_offset  ; _TILEMAP_SLOT_BASE
    sta.b 0x00
    sep #0x20

; source = slot * 60
    lda.w _rolling_slot_index
    sta.b btlgfx_dp.multiplier1
    lda #_TEXT_BYTES_PER_ITEM
    sta.b btlgfx_dp.multiplier2
    jsr.l mult8_trampoline

    rep #0x20
    lda.b btlgfx_dp.mult8_result
    tax
    sep #0x20

; Row 1: 30 content bytes, borders untouched
    ldy.w #0x0000

_copy_slot_row1:
    lda.w _text_buffer_base, x
    sta (0x00), y
    inx
    iny
    cpy.w #30
    bne _copy_slot_row1

; Row 2 (+$40)
    ldy.w #0x0040

_copy_slot_row2:
    lda.w _text_buffer_base, x
    sta (0x00), y
    inx
    iny
    cpy.w #0x005E
    bne _copy_slot_row2

; Restore zero page (reverse order)
    pla
    sta.b btlgfx_dp.mult8_result + 1
    pla
    sta.b btlgfx_dp.mult8_result
    pla
    sta.b btlgfx_dp.multiplier2 + 1
    pla
    sta.b btlgfx_dp.multiplier2
    pla
    sta.b btlgfx_dp.multiplier1 + 1
    pla
    sta.b btlgfx_dp.multiplier1

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

    rep #0x20
    pla
    tcd
    sep #0x20

    plb

    plp
    rts

_restore_items_frame:
"""
    Redraw the items window frame (sides on rows 1-13, bottom edge on 14, rows 15-25 cleared for the magic
    frame); the slot copy then puts the item rows back. DBR = $7E, X = 16.
"""


    rep #0x20
    ldx.w #_ITEMS_FRAME_FIRST_ROW * 0x40

_rif_side_row:
    lda.w #0x000B
    ldy.w #0x000C
    jsr.w _rif_fill_row
    cpx.w #_ITEMS_FRAME_BOTTOM_ROW * 0x40
    bne _rif_side_row
    lda.w #0x000D
    ldy.w #0x000F
    jsr.w _rif_fill_row
    lda.w #0x0000

_rif_clear:
    sta.w _tilemap_buffer_base, x
    inx
    inx
    cpx.w #_ITEMS_FRAME_CLEAR_END_ROW * 0x40
    bne _rif_clear
    sep #0x20
    rts

_rif_fill_row:
; One 32-cell row at X: A on the left edge, Y on the right edge, and the
; body tile between ($00FF blank on side rows, $000E on the bottom edge).
; M=16. Leaves X at the next row.
    sta.w _tilemap_buffer_base, x
    cmp.w #0x000D
    beq _rif_bottom_body
    lda.w #0x00FF
    bra _rif_body_set

_rif_bottom_body:
    lda.w #0x000E

_rif_body_set:
    inx
    inx
    phy
    ldy.w #30

_rif_body:
    sta.w _tilemap_buffer_base, x
    inx
    inx
    dey
    bne _rif_body
    pla
    sta.w _tilemap_buffer_base, x
    inx
    inx
    rts

; Copy all 6 slots from the text buffer to the tilemap buffer, after the game clears the window buffers.
_copy_all_slots_to_tilemap:
; mult8_trampoline may change DBR
    phb
    lda #0x7E
    pha
    plb  ; Ensure DBR is $7E for WRAM access

    lda #0
    sta.b 0x06  ; Slot counter (0-5)

_copy_slots_loop:
; dest = _TILEMAP_SLOT_BASE + slot * 128
    lda.b 0x06
    sta.b btlgfx_dp.multiplier1
    lda #_TILEMAP_BYTES_PER_ROW  ; 128
    sta.b btlgfx_dp.multiplier2
    jsr.l mult8_trampoline

    rep #0x20
    lda.b btlgfx_dp.mult8_result
    clc
    adc #_tilemap_buffer_base + _tilemap_content_offset  ; _TILEMAP_SLOT_BASE
    sta.b 0x00  ; Tilemap dest pointer
    sep #0x20

; source = _text_buffer_base + slot * 60
    lda.b 0x06
    sta.b btlgfx_dp.multiplier1
    lda #_TEXT_BYTES_PER_ITEM  ; 60
    sta.b btlgfx_dp.multiplier2
    jsr.l mult8_trampoline

    rep #0x20
    lda.b btlgfx_dp.mult8_result
    tax  ; X = text buffer offset
    sep #0x20

; Row 1: 30 content bytes, borders untouched
    ldy.w #0x0000

_copy_all_row1:
    lda.w _text_buffer_base, x
    sta (0x00), y
    inx
    iny
    cpy.w #30
    bne _copy_all_row1

; Row 2 (+$40)
    ldy.w #0x0040

_copy_all_row2:
    lda.w _text_buffer_base, x
    sta (0x00), y
    inx
    iny
    cpy.w #0x005E
    bne _copy_all_row2

    inc.b 0x06
    lda.b 0x06
    cmp #BUFFER_SLOTS  ; 6 slots
    bne _copy_slots_loop

    plb
    rts

tfr_inventory_list_rolling:
"""
    Replacement for original `TfrInventoryList` ($0298FA): re-render the visible inventory rows into our buffer and DMA
    the slice to VRAM. Reached via JSL from bank 02.
"""


    phb
    lda #0x7E
    pha
    plb

; Re-render the visible rows only when invalidated (open / item swap): scroll hooks pre-paint the hidden
; slot and a per-frame rebuild would clobber it. The magic list renders into this window's tiles, so once it
; has, repaint all. Compare to exactly 1: old savestates carry $FF in never-written cart RAM.
    lda.l battle_render_state.spell_tiles_live
    cmp.b #0x01
    bne _tfr_glyphs_ok
    lda.b #0x00
    sta.l battle_render_state.spell_tiles_live
    lda.b #0x01
    sta.w _inventory_needs_full_refresh

_tfr_glyphs_ok:
    lda.w _inventory_needs_full_refresh
    beq _tfr_skip_refresh
    jsr.w _refresh_visible_items_internal
    stz.w _inventory_needs_full_refresh

_tfr_skip_refresh:
; The magic list draws its own frame over this buffer: rebuild ours once.
    lda.l battle_render_state.items_frame_dirty
    beq _tfr_frame_ok
    jsr.w _restore_items_frame
    lda.b #0x00
    sta.l battle_render_state.items_frame_dirty

_tfr_frame_ok:

; Disabled bits change each turn (per-character usability, $03:A0F7): match the palettes.
    jsr.w _recolour_visible_slots

; Runs after the game's window clearing at $9AF4
    jsr.w _copy_all_slots_to_tilemap

; Queue VRAM transfer (entry 3 covers $7400-$77FF)
    lda #0x03
    ldy.w #0x0002
    jsr.l load_menu_tfr_data_trampoline

    lda #0x01
    sta.w menu_tilemap_tfr_count  ; 1 transfer only
    sta.w menu_tilemap_tfr_enable  ; Enable transfer

; Back to vanilla with A's high byte clear: the 16-bit work above leaves it set ($012C from the slot copy), and
; vanilla's later `and #7 / asl / tax` ($02:9702) carries it into a jump-table index (-> BRK at $02:0860).
    xba
    lda.b #0x00
    xba

    plb  ; Restore data bank
    rtl

_recolour_visible_slots:
"""
    Set each visible slot's palette from its item's disabled bit ($321A bit 7: grey, palette 1). Vanilla's
    UpdateEnabledItems recolours its own 48-row buffer, which the rolling list does not show. The hidden slot
    keeps its render-time palette.
"""


    lda #0
    sta.b 0x06  ; Ring slot

_recolour_slot:
; Visible row = (slot - _rolling_buffer_pos) mod BUFFER_SLOTS
    lda.b 0x06
    sec
    sbc.w _rolling_buffer_pos
    bcs _recolour_row_ok
    adc #BUFFER_SLOTS

_recolour_row_ok:
    cmp #VISIBLE_ROWS
    bcs _recolour_next
    clc
    adc.w _rolling_top_row
    rep #0x20
    and.w #0x00FF
    asl
    asl  ; x 4 bytes per item
    tax
    sep #0x20
    lda.l battle_inventory.flags, x
    asl  ; C = disabled
    lda #0x00
    bcc _recolour_palette
    lda #_ITEM_GREY_PALETTE

_recolour_palette:
    sta.b 0x07
; Text buffer offset = slot * 60 = slot * 64 - slot * 4
    rep #0x20
    lda.b 0x06
    and.w #0x00FF
    asl
    asl
    sta.b 0x08
    asl
    asl
    asl
    asl
    sec
    sbc.b 0x08
    tax
    sep #0x20
    ldy.w #_TEXT_BYTES_PER_ITEM >> 1  ; One attribute byte per tile

_recolour_cell:
    lda.w _text_buffer_base + 1, x
    and #0xFF - _TILE_PALETTE_MASK
    ora.b 0x07
    sta.w _text_buffer_base + 1, x
    inx
    inx
    dey
    bne _recolour_cell

_recolour_next:
    inc.b 0x06
    lda.b 0x06
    cmp #BUFFER_SLOTS
    bne _recolour_slot
    rts

; Re-render the 5 visible items from EF71 into their slots; no VRAM transfer (caller queues it).
_refresh_visible_items_internal:
; visible row r lives in slot (_rolling_buffer_pos + r) % BUFFER_SLOTS (rotated after a seam crossing)

    lda #0
    sta.b 0x06  ; Visible row index (0-4)

_refresh_int_loop:
; item = _rolling_top_row + visible_row
    lda.w _rolling_top_row
    clc
    adc.b 0x06
    sta.w _rolling_edge_row  ; Item index for data lookup

; slot = (_rolling_buffer_pos + visible_row) % BUFFER_SLOTS
    lda.w _rolling_buffer_pos
    clc
    adc.b 0x06  ; pos + visible_row
    cmp #BUFFER_SLOTS
    bcc _refresh_slot_ok
    sec
    sbc #BUFFER_SLOTS  ; Wrap if >= 6

_refresh_slot_ok:
    sta.w _rolling_slot_index  ; Actual circular buffer slot

    lda.b 0x06
    pha

    jsr.w _render_item_to_circular_slot

    pla
    sta.b 0x06

    inc.b 0x06
    lda.b 0x06
    cmp #VISIBLE_ROWS  ; 5 visible items
    bne _refresh_int_loop

    rts

; Unused: re-render the 5 visible items into fixed slots 0-4 (no rotation). Expects EF65 = 0.

_refresh_visible_items:
    phb
    lda #0x7E
    pha
    plb

    lda #0
    sta.b 0x06  ; Slot index (0-4)

_refresh_loop:
; item = EF71 + slot
    lda.w 0xEF71
    clc
    adc.b 0x06
    sta.w _rolling_edge_row  ; Item index for data lookup

    lda.b 0x06
    sta.w _rolling_slot_index  ; Slot index (0-4)

    lda.b 0x06
    pha

    jsr.w _render_item_to_circular_slot

    pla
    sta.b 0x06

    inc.b 0x06
    lda.b 0x06
    cmp #VISIBLE_ROWS  ; 5 visible items
    bne _refresh_loop

; Queue VRAM transfer
    lda #0x03
    ldy.w #0x0002
    jsr.l load_menu_tfr_data_trampoline
    lda #0x01
    sta.w menu_tilemap_tfr_count
    sta.w menu_tilemap_tfr_enable

    plb
    rtl

; Unused: after a scroll-up, render the next item into the off-screen slot (pos - 1) mod 6.

_post_render_up:
    phb
    lda #0x7E
    pha
    plb

; item = EF71 + VISIBLE_ROWS
    lda.w 0xEF71
    clc
    adc #VISIBLE_ROWS
    cmp #_TOTAL_ITEMS
    bcs _post_up_done  ; Past end, nothing to render
    sta.w _rolling_edge_row

; Off-screen slot = (pos - 1) mod 6
    lda.w _rolling_buffer_pos
    dec
    bpl _post_up_slot_ok
    lda #BUFFER_SLOTS - 1

_post_up_slot_ok:
    sta.w _rolling_slot_index

    jsr.w _render_item_to_circular_slot

; Queue VRAM transfer
    lda #0x03
    ldy.w #0x0002
    jsr.l load_menu_tfr_data_trampoline
    lda #0x01
    sta.w menu_tilemap_tfr_count
    sta.w menu_tilemap_tfr_enable

_post_up_done:
    plb
    rtl

; Unused: after a scroll-down, render the item past the bottom into the off-screen slot (pos + 5) mod 6.

_post_render_down:
    phb
    lda #0x7E
    pha
    plb

; item = EF71 + VISIBLE_ROWS
    lda.w 0xEF71
    clc
    adc #VISIBLE_ROWS
    cmp #_TOTAL_ITEMS
    bcs _post_down_done  ; Past end, nothing to render
    sta.w _rolling_edge_row

; Off-screen slot = (pos + 5) mod 6
    lda.w _rolling_buffer_pos
    clc
    adc #VISIBLE_ROWS
    cmp #BUFFER_SLOTS
    bcc _post_down_slot_ok
    sec
    sbc #BUFFER_SLOTS

_post_down_slot_ok:
    sta.w _rolling_slot_index

    jsr.w _render_item_to_circular_slot

; Queue VRAM transfer
    lda #0x03
    ldy.w #0x0002
    jsr.l load_menu_tfr_data_trampoline
    lda #0x01
    sta.w menu_tilemap_tfr_count
    sta.w menu_tilemap_tfr_enable

_post_down_done:
    plb
    rtl

post_scroll_down_render:
"""Tail of `wrap_and_clear_trampoline` (JSL) after a scroll animation; no-op, the scroll hooks pre-render."""
; $1820 still holds the animation type (2 = scroll down)
    lda.w menu_hdma_pending
    cmp #0x02
    bne _psd_done


_psd_done:
    rtl

scroll_list_down_hook:
"""
    Replacement for the scroll-down stub at `$02A8B8` (JMP.L, returns via return_to_bank02): pre-render the new
    bottom slot, then start the scroll-down animation.
"""


; Rolling buffer only for the inventory ($4A bit 2); the magic list keeps vanilla behaviour.
    lda.b btlgfx_dp.menu_windows_open
    and #0x04
    bne _sd_is_inventory

; Magic list: paint the spell row about to slide in at the bottom first.
    lda.l btl_list_scroll
    clc
    adc.b #battle_render.SPELL_VISIBLE_ROWS
    jsr.l spell_list_scroll_render
; vanilla $02A8B8 body
    ldx.w 0xEF71
    dex
    stx.w 0xEF71
    lda #0x0C
    sta.w 0xEF64
    lda #0x02
    sta.w menu_hdma_pending
    jmp.l return_to_bank02

_sd_is_inventory:
; Inventory (EF71 increments here): pre-render the new bottom item BEFORE the animation, IRQs off.
    sei

    phb
    lda #0x7E
    pha
    plb

; Stop at _rolling_top_row == _TOTAL_ITEMS - VISIBLE_ROWS (EF71 means something else in battle)
    lda.w _rolling_top_row
    cmp #( _TOTAL_ITEMS - VISIBLE_ROWS )
    bcs _sd_abort  ; Already at max, can't scroll down

; New bottom item = _rolling_top_row + 5, into the off-screen slot (pos + 5) % 6
    lda.w _rolling_top_row
    clc
    adc #VISIBLE_ROWS  ; item = _rolling_top_row + 5
    cmp #_TOTAL_ITEMS
    bcs _sd_skip_prerender  ; Past end, nothing to render
    sta.w _rolling_edge_row  ; Save item index

    lda.w _rolling_buffer_pos
    clc
    adc #VISIBLE_ROWS  ; pos + 5
    cmp #BUFFER_SLOTS
    bcc _sd_slot_ok
    sec
    sbc #BUFFER_SLOTS  ; Wrap if >= 6

_sd_slot_ok:
    sta.w _rolling_slot_index

    jsr.w _render_item_to_circular_slot
    jsr.w _copy_slot_to_tilemap
    jsr.w _transfer_circular_slot

_sd_skip_prerender:
; EF71++ (animation loop is NOPed out)
    lda.w 0xEF71
    inc
    sta.w 0xEF71

; _rolling_top_row tracks the top item; _refresh_visible_items_internal depends on it
    lda.w _rolling_top_row
    inc
    sta.w _rolling_top_row

    lda #0x0C
    sta.w 0xEF64
    lda #0x02  ; Animation 2 (scroll down)
    sta.w menu_hdma_pending

; Advance circular position (top slot goes off-screen)
    lda.w _rolling_buffer_pos
    inc
    cmp #BUFFER_SLOTS
    bcc _sd_pos_ok
    lda #0

_sd_pos_ok:
    sta.w _rolling_buffer_pos

_sd_abort:
; Keep cursor 1 visible during the animation
    stz.w 0xEF69  ; Clear hide cursor 1 flag
    stz.w 0xEF6E  ; Clear alternate hide cursor 1 flag

    plb  ; Restore data bank
    cli  ; re-enable interrupts
    jmp.l return_to_bank02

scroll_list_up_hook:
"""
    Replacement for the scroll-up stub at `$02A8CA` (JMP.L, returns via return_to_bank02): pre-render the new top
    row, then start the scroll-up animation.
"""


; Rolling buffer only for the inventory ($4A bit 2); the magic list keeps vanilla behaviour.
    lda.b btlgfx_dp.menu_windows_open
    and #0x04
    bne _su_is_inventory

; Magic list: paint the spell row about to slide in at the top ($FF past row 0 is out of range).
    lda.l btl_list_scroll
    dec
    jsr.l spell_list_scroll_render
; vanilla $02A8CA body
    ldx.w 0xEF71
    inx
    stx.w 0xEF71
    lda #0x0C
    sta.w 0xEF64
    lda #0x03
    sta.w menu_hdma_pending
    jmp.l return_to_bank02

_su_is_inventory:
; Inventory: pre-render the new top item BEFORE the animation; the slot scrolling in may hold stale data.
    sei

    phb
    lda #0x7E
    pha
    plb

; Stop at _rolling_top_row == 0 (EF71 means something else in battle)
    lda.w _rolling_top_row
    beq _su_abort  ; Already at item 0, can't scroll up

; Decrement buffer position first (new top slot)
    lda.w _rolling_buffer_pos
    dec
    bpl _su_pos_ok
    lda #BUFFER_SLOTS - 1  ; Wrap 0→5

_su_pos_ok:
    sta.w _rolling_buffer_pos
    sta.w _rolling_slot_index  ; This slot will be the new top (currently off-screen)

; new top item = _rolling_top_row - 1
    lda.w _rolling_top_row
    dec
    sta.w _rolling_edge_row

    jsr.w _render_item_to_circular_slot
    jsr.w _copy_slot_to_tilemap
    jsr.w _transfer_circular_slot

; _rolling_top_row is the authoritative top item
    lda.w _rolling_top_row
    dec
    sta.w _rolling_top_row

    lda #0x0C
    sta.w 0xEF64
    lda #0x03  ; Animation 3 (scroll up)
    sta.w menu_hdma_pending
    bra _su_exit

_su_abort:
; Pre-increment EF85, EF86, $63 so the caller's unconditional dec at $02:B4FA-B500 restores them;
; otherwise $63 (cursor item index) underflows to $FF past item 0.
    inc.w 0xEF85
    inc.w 0xEF86
    inc.b 0x63

_su_exit:
; Keep cursor 1 visible during the animation
    stz.w 0xEF69  ; Clear hide cursor 1 flag
    stz.w 0xEF6E  ; Clear alternate hide cursor 1 flag

    plb  ; Restore data bank
    cli  ; re-enable interrupts
    jmp.l return_to_bank02

    _HDMA_TABLE := 0x7E7F74  ; $7E:7F74, V-scroll entries
    _HDMA_TABLE_SIZE := 0x00F0  ; 240 bytes (same as _HDMA_Y_SIZE)
    SCROLL_WRAP := 0x0060  ; 96 = 6 slots × 16 pixels (tilemap buffer size)
    _SCROLL_WRAP_LIMIT := 0x01D3  ; 467 = 371 + 96 (wrap when >= this value)
    _OUR_BASE_SCROLL := 0x0173  ; 371 - same as original game

update_list_scroll_hdma_wrapped:
"""
    Replacement for the HDMA-build stub at `$02A7F1` (JMP.L): rebuild the per-scanline V-scroll table at $7F74.
    In: X = scroll offset ($EF65), Y = scanlines per row (12). Inventory values wrap at 96 px (6 slots x 16).
"""


; Non-inventory windows ($4A bit 2 clear) keep vanilla behaviour
    lda.b btlgfx_dp.menu_windows_open
    and #0x04
    bne _use_circular_buffer

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
; FF6 LoadItemBG1VScrollHDMATbl: at scanline S with scroll V the displayed VRAM row is V + S, so showing slot N
; at screen row R (scanline R*12) needs scroll = N*16 - R*12. Per row: slot = (_rolling_buffer_pos + row) % 6,
; scroll = BASE + slot * 16 - row * 12.
    sei  ; Disable interrupts during HDMA table update

; Save $00-$05 for the caller
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
; slot = (_rolling_buffer_pos + row) % 6
    lda.w _rolling_buffer_pos
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

    asl
    asl
    asl
    asl  ; A = vram_slot * 16
    sta.b 0x00  ; Save vram_offset

; row * 12 = row * 8 + row * 4
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

; scroll = BASE + vram_offset - scanline_offset; `eor.w #0xFFFF` as raw bytes (a816 lacks eor.w)
    .db 0x49
    .dw 0xffff

    inc
    clc
    adc.b 0x00  ; + vram_offset
    clc
    adc.w #_OUR_BASE_SCROLL  ; + BASE
    sta.b 0x00  ; $00 = scroll value for this row

; Same value for all 12 scanlines of this row
    ldy.w #0x000C  ; 12 scanlines

_scanline_loop:
    lda.b 0x00
    sta.l _HDMA_TABLE, x
    inx
    inx
    inx
    inx  ; X += 4 (next HDMA entry)
    dey
    bne _scanline_loop

    inc.b 0x02
    lda.b 0x02
    cmp.w #VISIBLE_ROWS  ; 5 rows total
    bne _row_loop

; Restore $00-$05
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

; Force the cursor only during a scroll animation ($1820 = 2 or 3)
    lda.l menu_hdma_pending  ; Animation type
    beq _cursor_skip_force  ; If 0, no animation - skip forcing

; Long addressing: DB may be $02 (ROM)
    pha  ; Save animation type
    lda #0x00
    sta.l btl_hide_cursor1  ; Clear hide cursor 1 flag
    sta.l btl_cursor1_y + 1  ; Clear alternate hide cursor 1 flag

    lda #0x0C
    sta.l btl_cursor1_x  ; Set cursor 1 X position

; Scroll down ($1820 = 2): bottom row, Y = $CC; scroll up: top row, Y = $9C
    pla  ; Restore animation type
    cmp #0x02  ; Scroll down?
    bne _cursor_scroll_up
    lda #0xCC  ; Bottom row Y position
    bra _cursor_set_y

_cursor_scroll_up:
    lda #0x9C  ; Top row Y position

_cursor_set_y:
    sta.l btl_cursor1_y  ; Set cursor 1 Y position

_cursor_skip_force:

    cli
    jmp.l return_to_bank02

; Y-scroll halves only: ResetListScrollHDMA fills $81F4 (swap table), the animation swaps it with $7F74.
; X scroll ($81D2/$7F52) is left alone.
    _HDMA_SWAP_Y := 0x7E81F4  ; Y scroll in swap table
    _HDMA_ACTIVE_Y := 0x7E7F74  ; Y scroll in active table
    _HDMA_Y_SIZE := 0x00F0  ; 240 bytes (same as original)

reset_list_scroll_hdma_rolling:
"""Replacement for `$02AAB8`: fill the Y-scroll bytes of both HDMA tables when the inventory window opens."""
; Non-inventory windows keep vanilla behaviour
    lda.b btlgfx_dp.menu_windows_open
    and #0x04
    bne _reset_use_circular

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
; Inventory: save $00-$03 for the caller
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

; Re-init the slots on every (re)open so VRAM holds the right items; also resets _rolling_buffer_pos
    jsr.l init_inventory_text_buf_rolling

; Fill Y scroll in both tables
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
    adc.w #_OUR_BASE_SCROLL  ; + BASE
    sta.b 0x00  ; Save scroll value

; Same value for all 12 scanlines of this row
    ldy.w #0x000C  ; 12 scanlines

_reset_scanline_loop:
    lda.b 0x00
    sta.l _HDMA_SWAP_Y, x  ; $81F4 + X
    sta.l _HDMA_ACTIVE_Y, x  ; $7F74 + X
    inx
    inx
    inx
    inx  ; X += 4
    dey
    bne _reset_scanline_loop

    inc.b 0x02
    lda.b 0x02
    cmp.w #VISIBLE_ROWS  ; 5 rows
    bne _reset_row_loop

    sep #0x20  ; 8-bit A (game expects this)
    pla
    sta.b 0x03
    pla
    sta.b 0x02
    pla
    sta.b 0x01
    pla
    sta.b 0x00
    rtl

    _swap_mode_flag := 0xEF94  ; Non-zero = swap mode active
    _first_selected_item := 0xEF95  ; First selected item index (bit 7 may be set)
    _hide_cursor_2 := 0xEF6A  ; Non-zero = hide cursor 2

check_cursor2_visibility_rolling:
"""
    In swap mode ($EF94 != 0), show cursor 2 ($EF6A = 0) only when the first-selected item ($EF95, bit 7
    masked) is in the visible window. JSL from wrap_and_clear_trampoline after a scroll animation.
"""


; Inventory only ($4A bit 2)
    lda.b btlgfx_dp.menu_windows_open
    and #0x04
    beq _cursor2_done

    lda.w _swap_mode_flag
    beq _cursor2_done  ; Not in swap mode, nothing to check

    lda.w _first_selected_item
    and #0x7F  ; Clear bit 7
    sta.b 0x00  ; Save selected item index

; visible if _rolling_top_row <= selected < _rolling_top_row + VISIBLE_ROWS

    lda.b 0x00  ; Selected item
    cmp.w _rolling_top_row
    bcc _cursor2_hide  ; selected < _rolling_top_row, hide cursor

    lda.w _rolling_top_row
    clc
    adc #VISIBLE_ROWS  ; _rolling_top_row + 5
    sta.b 0x01  ; Save upper bound

    lda.b 0x00  ; Selected item
    cmp.b 0x01  ; Compare to upper bound
    bcs _cursor2_hide  ; selected >= upper bound, hide cursor

    stz.w _hide_cursor_2  ; $EF6A = 0 (show)
    bra _cursor2_done

_cursor2_hide:
    lda #0x01
    sta.w _hide_cursor_2  ; $EF6A = 1 (hide)

_cursor2_done:
    rtl  ; Called via JSL from bank $02

; Field menu NMI handler (relocated from bank $01). Menu states are the `<profile>_rolling` binds from items.s.
    _FIELD_HDMA_TABLE := 0x7E9800
    _FIELD_HDMA_SHADOW := 0x7E9840
    _FIELD_HDMA_TABLE_SIZE := 40
    DROPS_HDMA_TABLE := 0x7E9880
    DROPS_HDMA_SHADOW := 0x7E98C0
    _DROPS_HDMA_TABLE_SIZE := 40
; Sell list.
    SELL_HDMA_TABLE := 0x7E9900
    SELL_HDMA_SHADOW := 0x7E9940
; header + 8 row bands + footer + terminator = 31 bytes.
    _SELL_HDMA_TABLE_SIZE := 32
; Equip screen inventory list.
    _EQUIP_HDMA_TABLE := 0x7E9980
    EQUIP_HDMA_SHADOW := 0x7E99C0
; header + 6 row bands + footer + terminator = 25 bytes.
    EQUIP_HDMA_TABLE_SIZE := 26

field_menu_nmi_dma_transfer_check_impl:
"""
    NMI hook (JSL from bank $01) relocated to bank $20: transfer the field rolling-buffer tilemap to VRAM and update
    the live HDMA scroll table.
"""


    php
    sep #0x20  ; 8-bit A

; Only when menu HDMA is enabled; field DMA would otherwise corrupt battle VRAM
    lda.l field_menu_rolling.hdma_enable
    bne _field_nmi_active
    jmp.w _field_nmi_done

_field_nmi_active:

; HDMA table: shadow ($9840) -> active ($9800), 40 bytes
    lda.l field_menu_rolling.hdma_copy_pending
    beq _field_nmi_hdma_copy_done
    lda #0x00
    sta.l field_menu_rolling.hdma_copy_pending

    rep #0x30  ; 16-bit A, X, Y
    ldx.w #0x0000

_field_nmi_hdma_copy_loop:
    lda.l _FIELD_HDMA_SHADOW, x
    sta.l _FIELD_HDMA_TABLE, x
    inx
    inx
    cpx.w #_FIELD_HDMA_TABLE_SIZE
    bcc _field_nmi_hdma_copy_loop
    sep #0x20  ; Back to 8-bit A

_field_nmi_hdma_copy_done:
; Drops HDMA table ($98C0 -> $9880): ch4 drives BG4VOFS from its own table; skipped when $1BAE bit 4 is clear.
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
    cpx.w #_DROPS_HDMA_TABLE_SIZE
    bcc _drops_nmi_hdma_copy_loop
    sep #0x20

_drops_nmi_hdma_copy_done:
; Sell-list HDMA table ($9940 -> $9900): BG3VOFS on ch5. A zero-filled active table reads as end-of-table.
    sep #0x20
    lda.l field_menu_rolling.hdma_enable
    and #0x20
    beq _sell_nmi_hdma_copy_done
    lda.l sell_rolling.hdma_copy_pending
    beq _sell_nmi_hdma_copy_done
    lda #0x00
    sta.l sell_rolling.hdma_copy_pending
    rep #0x30
    ldx.w #0x0000

_sell_nmi_hdma_copy_loop:
    lda.l SELL_HDMA_SHADOW, x
    sta.l SELL_HDMA_TABLE, x
    inx
    inx
    cpx.w #_SELL_HDMA_TABLE_SIZE
    bcc _sell_nmi_hdma_copy_loop
    sep #0x20

_sell_nmi_hdma_copy_done:
; Equip-list HDMA table ($99C0 -> $9980): BG4VOFS on ch5; never shown alongside the field list or a shop.
    sep #0x20
    lda.l field_menu_rolling.hdma_enable
    and #0x20
    beq _equip_nmi_hdma_copy_done
    lda.l equip_rolling.hdma_copy_pending
    beq _equip_nmi_hdma_copy_done
    lda #0x00
    sta.l equip_rolling.hdma_copy_pending
    rep #0x30
    ldx.w #0x0000

_equip_nmi_hdma_copy_loop:
    lda.l EQUIP_HDMA_SHADOW, x
    sta.l _EQUIP_HDMA_TABLE, x
    inx
    inx
    cpx.w #EQUIP_HDMA_TABLE_SIZE
    bcc _equip_nmi_hdma_copy_loop
    sep #0x20

_equip_nmi_hdma_copy_done:

; Field tilemap DMA (BG1). Skipped while the treasure menu owns the screen: $1BB3 is then the drops cursor
; row, and clearing it would snap the cursor back to row 0.
    lda.l menu_cursor_data + 0xc6
    bne _field_nmi_check_treasure
    lda.l field_menu_rolling.transfer_pending
    beq _field_nmi_check_treasure
    lda #0x00
    sta.l field_menu_rolling.transfer_pending

    sep #0x20
    lda #0x01
    sta.w dma_ch0.DMAP
    lda #PPU.VMDATAL
    sta.w dma_ch0.BBAD
    rep #0x20
    lda.w #0xB600
    sta.w dma_ch0.A1TL
    sep #0x20
    lda #0x7E
    sta.w dma_ch0.A1B
    rep #0x20
    lda.w #0x0800
    sta.w dma_ch0.DASL
    lda.w #0x6000
    sta.w ppu.VMADDL
    sep #0x20
    lda #0x01
    sta.w cpu_regs.MDMAEN

_field_nmi_check_treasure:
; Treasure tilemap DMA (BG3)
    lda.l treasure_rolling.transfer_pending
    beq _field_nmi_done
    lda #0x00
    sta.l treasure_rolling.transfer_pending

    sep #0x20
    lda #0x01
    sta.w dma_ch0.DMAP
    lda #PPU.VMDATAL
    sta.w dma_ch0.BBAD
    rep #0x20
    lda.w #0xD600  ; BG3 screen buffer source ($7ED600)
    sta.w dma_ch0.A1TL
    sep #0x20
    lda #0x7E
    sta.w dma_ch0.A1B
    rep #0x20
    lda.w #0x0800  ; 2 KB tilemap
    sta.w dma_ch0.DASL
    lda.w #0x7000  ; BG3 tilemap VRAM target
    sta.w ppu.VMADDL
    sep #0x20
    lda #0x01
    sta.w cpu_regs.MDMAEN

_field_nmi_done:
; VWF CHR flush on DMA ch6 (untouched by vanilla btlgfx/menu and our engines; ch7 is shared).
; Same bank as this impl, so a short JSR pairs with the routine's RTS.
    jsr.w render.flush_chr_to_vram
    plp
    rtl
}

; Each rolling slot owns ITEM_VWF_TILE_BUDGET tiles from ITEM_VWF_TILE_BASE;
; together they must stay inside the BG3 tile page.
.assert ITEM_VWF_TILE_BASE + BUFFER_SLOTS * ITEM_VWF_TILE_BUDGET <= 0x100, "battle inventory slots run past tile $FF"
