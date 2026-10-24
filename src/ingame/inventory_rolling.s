"""
Field-menu inventory as a rolling buffer: 10 visible rows + 1 prefetch over 48 items, BG1VOFS driven by HDMA ch5.
"""

.import "core/preamble"
.import "core/vwf_ram"
.import "core/items"
.include "lib/rolling_buffer.i"

.import "ingame/vanilla_trampolines"
.import "lib/rolling_inventory_engine"

MENU_VISIBLE_ITEMS := 10
MENU_BUFFER_SLOTS := 11  ; 10 visible + 1 prefetch
_MENU_TOTAL_ITEMS := 48
MENU_SCROLL_LIMIT := 38  ; 48 - 10

_MENU_PIXELS_PER_ROW := 16

_MENU_SCROLL_WRAP := 176  ; 11 slots * 16 px

_MENU_ITEM_LIST_Y_START := 48  ; first list scanline, below the border
_MENU_ITEM_LIST_HEIGHT := 160  ; 10 items * 16 px

; State is `field_menu_rolling` (items.s). Not $7E:1BA8: DrawItemCharSelect scratch ($1BC1 / $1BC3) overlaps it.

_SCROLL_STATE_IDLE := 0
_SCROLL_STATE_SCROLLING := 1
; Shared held-DOWN cadence (src/lib/rolling_buffer.s).
_SCROLL_PIXELS_PER_FRAME := INVENTORY_SCROLL_PIXELS_PER_FRAME
_SCROLL_TOTAL_PIXELS := INVENTORY_SCROLL_TOTAL_PIXELS

; HDMA ch5, direct mode -> BG1VOFS. Entries are (count, lo, hi):
;   48 lines of border at base, 10 x 16-line item rows, 16 lines at base + 16, $00 terminator.
_MENU_HDMA_TABLE_ADDR := 0x9800  ; active table, read by HDMA
_MENU_HDMA_TABLE := 0x7E9800
_MENU_HDMA_SHADOW_ADDR := 0x9840  ; shadow, built by game code and copied in NMI
_MENU_HDMA_SHADOW := 0x7E9840
_MENU_HDMA_TABLE_SIZE := 40
_MENU_HDMA_BANK := 0x7E

.include "core/bank20.i"
.import "core/vanilla"

.alloc _inventory_rolling_block in bank20_reloc {
_init_menu_inventory_hdma:
"""
Builds the scroll table and configures HDMA ch5 (direct, 2 bytes -> BG1VOFS). Arming goes through the
`field_menu_rolling.hdma_enable` shadow the NMI hook writes to HDMAEN.
"""


    php
    sep #0x20
    jsr.w update_menu_scroll_hdma
; Long addressing: DB may be $7E.
    lda #0x02
    sta.l dma_ch5.DMAP
    lda #PPU.BG1VOFS
    sta.l dma_ch5.BBAD
    rep #0x20
    lda.w #_MENU_HDMA_TABLE_ADDR
    sta.l dma_ch5.A1TL
    sep #0x20
    lda #_MENU_HDMA_BANK
    sta.l dma_ch5.A1B
    plp
    rts

_disable_menu_inventory_hdma:
"""
No-op: menu_exit_hook clears the HDMA shadow and the NMI writes HDMAEN.
"""


    php
    sep #0x20
    plp
    rts

_init_menu_hdma_table:
"""
Builds the active HDMA table at $7E9800 with every row at base scroll.
"""


    rep #0x30
    php
    pha
    phx
    phy
    lda.b 0x40
    pha
    ldx.w #0x0000
; Border: 48 lines at base
    sep #0x20
    lda #48
    sta.l _MENU_HDMA_TABLE, x
    inx
    rep #0x20
    lda.w field_menu_rolling.base_scroll
    sta.l _MENU_HDMA_TABLE, x
    inx
    inx

; Item rows: 16 lines each at base
    lda.w #0x0000
    sta.b 0x40

_init_item_rows:
    sep #0x20
    lda #16
    sta.l _MENU_HDMA_TABLE, x
    inx
    rep #0x20
    lda.w field_menu_rolling.base_scroll
    sta.l _MENU_HDMA_TABLE, x
    inx
    inx

    inc.b 0x40
    lda.b 0x40

    cmp.w #1
    bcc _init_item_rows
; Bottom border: 16 lines at base + 16
    sep #0x20
    lda #16
    sta.l _MENU_HDMA_TABLE, x
    inx
    rep #0x20
    lda.w field_menu_rolling.base_scroll
    clc
    adc.w #16
    sta.l _MENU_HDMA_TABLE, x
    inx
    inx

    sep #0x20
    lda #0x00
    sta.l _MENU_HDMA_TABLE, x
    rep #0x20
    pla
    sta.b 0x40
    ply
    plx
    pla
    plp
    rts

update_menu_scroll_hdma:
"""Build the field-menu HDMA scroll table."""
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
        lda.w field_menu_rolling.buffer_pos
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
        adc.w field_menu_rolling.base_scroll
        sta.b 0x40
        sep #0x20
        lda #16
        sta.l _MENU_HDMA_SHADOW, x
        inx
        rep #0x20
        lda.b 0x40
        sta.l _MENU_HDMA_SHADOW, x
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
        sta.l _MENU_HDMA_SHADOW, x
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
"""HDMA header: 48-line border at base scroll."""
    sep #0x20
    lda #48
    sta.l _MENU_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w field_menu_rolling.base_scroll
    sta.l _MENU_HDMA_SHADOW, x
    inx
    inx
    rts

_menu_hdma_footer:
"""HDMA footer: 16 lines at base + 16 (bottom border row)."""
    sep #0x20
    lda #16
    sta.l _MENU_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w field_menu_rolling.base_scroll
    clc
    adc.w #16
    sta.l _MENU_HDMA_SHADOW, x
    inx
    inx
    rts

_menu_hdma_signal:
"""Sets hdma_copy_pending."""
    sep #0x20
    lda #0x01
    sta.w field_menu_rolling.hdma_copy_pending
    rts

init_menu_rolling_buffer_impl:
"""
Fills `field_menu_rolling` config and hooks, then runs the engine init.
"""


    php
    rep #0x30
    sep #0x20
    lda.b #MENU_VISIBLE_ITEMS
    sta.l field_menu_rolling.visible_rows
    lda.b #0x02  ; BG rows per slot
    sta.l field_menu_rolling.slot_height_tiles
; item_list_ptr = $7E:1440
    lda.b #0x40
    sta.l field_menu_rolling.item_list_ptr
    lda.b #0x14
    sta.l field_menu_rolling.item_list_ptr + 1
    lda.b #0x7E
    sta.l field_menu_rolling.item_list_ptr + 2
    lda.b #0x30
    sta.l field_menu_rolling.item_count
    lda.b #0x05
    sta.l field_menu_rolling.hdma_channel
    lda.b #vwf_cfg & 0xFF
    sta.l field_menu_rolling.vwf_cfg_ptr
    lda.b #( vwf_cfg >> 8 ) & 0xFF
    sta.l field_menu_rolling.vwf_cfg_ptr + 1
    lda.b #vwf_cfg >> 16
    sta.l field_menu_rolling.vwf_cfg_ptr + 2
    lda.b #_menu_fn_render_slot_trampoline & 0xFF
    sta.l field_menu_rolling.fn_render_slot
    lda.b #( _menu_fn_render_slot_trampoline >> 8 ) & 0xFF
    sta.l field_menu_rolling.fn_render_slot + 1
    lda.b #( _menu_fn_render_slot_trampoline >> 16 ) & 0xFF
    sta.l field_menu_rolling.fn_render_slot + 2
    lda.b #_menu_fn_update_hdma_trampoline & 0xFF
    sta.l field_menu_rolling.fn_update_hdma
    lda.b #( _menu_fn_update_hdma_trampoline >> 8 ) & 0xFF
    sta.l field_menu_rolling.fn_update_hdma + 1
    lda.b #( _menu_fn_update_hdma_trampoline >> 16 ) & 0xFF
    sta.l field_menu_rolling.fn_update_hdma + 2
    lda.b #_menu_fn_draw_window_trampoline & 0xFF
    sta.l field_menu_rolling.fn_draw_window
    lda.b #( _menu_fn_draw_window_trampoline >> 8 ) & 0xFF
    sta.l field_menu_rolling.fn_draw_window + 1
    lda.b #( _menu_fn_draw_window_trampoline >> 16 ) & 0xFF
    sta.l field_menu_rolling.fn_draw_window + 2
    lda.b #ROLLING_MENU_ID_FIELD
    sta.l field_menu_rolling.menu_id
    plp
    php
    rep #0x10
    ldx.w #field_menu_rolling
    jsr.l rolling_engine.rolling_engine_init
    plp
    rtl

_menu_fn_render_slot_trampoline:
"""
Bank-20 RTL wrapper around `_menu_render_item_to_slot`. php/plp keeps the engine's 16-bit X: an 8-bit X
truncates its `sta.l abs,X` state writes.
"""


    php
    jsr.w _menu_render_item_to_slot
    plp
    rtl

_menu_fn_update_hdma_trampoline:
"""
Bank-20 RTL wrapper around the idempotent `_ensure_hdma_initialized`. php/plp keeps the engine's 16-bit X.
"""


    php
    jsr.w _ensure_hdma_initialized
    plp
    rtl

_menu_fn_draw_window_trampoline:
"""
Bank-20 RTL wrapper around `_menu_draw_inventory_window`, which returns with 8-bit X; php/plp restores 16-bit.
"""


    php
    jsr.w _menu_draw_inventory_window
    plp
    rtl

_menu_draw_inventory_window:
"""Draws the InventoryWindow ($DCCE) frame."""
    rep #0x10
    ldy.w #0xDCCE
    jsr.l draw_window_trampoline
    sep #0x10
    rts

; Renders item `edge_row` into ring slot `slot_index` of the BG1 buffer at $7E:B600, via DrawItemSlot.
_menu_render_item_to_slot:
    php
    phb
    lda #0x7E
    pha
    plb
    rep #0x30
    pha
    phx
    phy
    lda.b menu_dp.item_ptr
    pha
    lda.b menu_dp.tilemap_offset
    pha
    lda.b 0x45
    pha
    lda.b menu_dp.window_top_only
    pha
    sep #0x20
    lda.b menu_dp.item_slot
    pha
    lda.b menu_dp.item_usable
    pha
    rep #0x20
    lda.w #0xB600
    sta.b menu_dp.tilemap_offset
    sep #0x20
; Item pointer = $1440 + edge_row * 2
    lda.w field_menu_rolling.edge_row
    asl
    clc
    adc #0x40
    sta.b menu_dp.item_ptr
    lda #0x14
    adc #0x00
    sta.b menu_dp.item_ptr + 1
    rep #0x20
    lda.b menu_dp.item_ptr
    tax
    sep #0x20
    lda.l item_x.id, x
    pha
    lda.l item_x.qty, x
    sta.b 0x5C
; CheckCanUseItem: A = item id -> $DB = $00 usable / $04 not
    stz.b menu_dp.window_attr
    pla
    jsr.l check_can_use_item_trampoline
    lda.w field_menu_rolling.slot_index
    sta.b menu_dp.item_slot
; Y = slot * 128 + $44 (one border row + 2 cells)
    rep #0x20
    lda.w field_menu_rolling.slot_index
    and.w #0x00FF
    xba
    lsr
    clc
    adc.w #0x0044
    tay
    sep #0x20
; Trash can ($FF) is a 2x2 icon.
    lda.b (menu_dp.item_ptr)
    cmp #0xFF
    bne _not_trash_item
    jsr.w _draw_trash_single_column
    bra _skip_draw_item_slot

_not_trash_item:
; Clear a trash icon left by a previous occupant.
    jsr.w _clear_trash_area
; DrawItemSlot inner ($01:A1ED): Y = tilemap offset, ($5A) = item, ($29) = tilemap base
    jsr.l draw_item_slot_inner_trampoline

_skip_draw_item_slot:
    pla
    sta.b menu_dp.item_usable
    pla
    sta.b menu_dp.item_slot
    rep #0x20
    pla
    sta.b menu_dp.window_top_only
    pla
    sta.b 0x45
    pla
    sta.b menu_dp.tilemap_offset
    pla
    sta.b menu_dp.item_ptr
    rep #0x10
    ply
    plx
    pla
    plb
    plp
    rts

_ensure_hdma_initialized:
"""
One-shot (base_scroll = $FFFF sentinel): captures base_scroll from $7E:0193 (BG1VOFS shadow, menu D = $0100),
configures ch5 and arms it.
"""


    rep #0x20
    lda.w field_menu_rolling.base_scroll
    cmp.w #0xFFFF
    bne _hdma_already_init
    .db 0xAF  ; lda.l $7E0193
    .db 0x93, 0x01, 0x7E
    sta.w field_menu_rolling.base_scroll
    sep #0x20
    jsr.w _init_menu_inventory_hdma
    lda #0x20  ; ch5
    .db 0x8F  ; sta.l field_menu_rolling.hdma_enable
    .dw field_menu_rolling.hdma_enable
    .db 0x7E
    rts

_hdma_already_init:
    sep #0x20
    rts

_scroll_state_check:
"""
Main-loop scroll tick ($01:9FF2): runs one animation frame while scrolling.
Exit: carry clear = process input, carry set = still scrolling, skip input.
"""


    php
    sep #0x20
    lda.w field_menu_rolling.scroll_state
    beq _scroll_state_idle
    jsr.l update_scroll_frame_impl
    lda.w field_menu_rolling.scroll_remaining
    bne _scroll_still_active
    jsr.l finish_scroll_impl

_scroll_state_idle:
    plp
    clc
    rts

_scroll_still_active:
    plp
    sec
    rts

start_scroll_down_impl:
"""Starts the engine's scroll-down."""
    php
    rep #0x10
    lda.l inventory_scroll_pos
    ldx.w #field_menu_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_down
    plp
    rtl

start_scroll_up_impl:
"""Starts the engine's scroll-up."""
    php
    rep #0x10
    lda.l inventory_scroll_pos
    ldx.w #field_menu_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_up
    plp
    rtl

update_scroll_frame_impl:
"""Per-frame scroll tick."""
    php
    rep #0x10
    ldx.w #field_menu_rolling
    jsr.l rolling_engine.rolling_engine_update_scroll_frame
    plp
    rtl

finish_scroll_impl:
"""Finishes the engine scroll."""
    php
    rep #0x10
    lda.l inventory_scroll_pos
    ldx.w #field_menu_rolling
    jsr.l rolling_engine.rolling_engine_finish_scroll
    plp
    rtl

menu_entry_hook_impl:
"""
Field-menu entry: resets scroll state, HDMA arming and the cursor column (single column).
The ring itself is initialised later, by the patched JSR at $01:9F7B.
"""
    stz.w inventory_menu_mode
    lda #0x00
    sta.l field_menu_rolling.hdma_enable
    stz.w field_menu_rolling.scroll_state
    stz.w field_menu_rolling.scroll_remaining
    stz.w field_menu_rolling.scroll_direction
    stz.w field_menu_rolling.transfer_pending
    stz.w field_menu_rolling.hdma_copy_pending
    stz.w field_menu_rolling.scroll_anim_offset
    stz.w field_menu_rolling.scroll_anim_offset + 1
    stz.w inventory_cursor1_x
    rtl

menu_exit_hook_impl:
"""Field-menu teardown: zeroes the HDMA shadow, ch5's registers and the first 12 state bytes."""
    php
    sep #0x20
    lda #0x00
    sta.l field_menu_rolling.hdma_enable
    sta.l dma_ch5.DMAP
    sta.l dma_ch5.BBAD
    sta.l dma_ch5.A1TL
    sta.l dma_ch5.A1TH
    sta.l dma_ch5.A1B
    rep #0x20
    lda.w #0x0000
    sta.w field_menu_rolling
    sta.w field_menu_rolling + 2
    sta.w field_menu_rolling + 4
    sta.w field_menu_rolling + 6
    sta.w field_menu_rolling + 8
    sta.w field_menu_rolling + 10
    plp
    jsr.l reset_sprites_trampoline
    rtl

swap_redraw_hook_impl_body:
"""Post-swap re-render of all 11 slots at the current buffer_pos."""
    php
    rep #0x10
    lda.l inventory_scroll_pos
    ldx.w #field_menu_rolling
    jsr.l rolling_engine.rolling_engine_swap_redraw
    plp
    rtl

; Blanks ring slot `slot_index` (12 cells, palette 4) for an item index past 48.
clear_inventory_slot:
    php
    phb
    lda #0x7E
    pha
    plb
    rep #0x30
    pha
    phx
    phy
    lda.b menu_dp.tilemap_offset
    pha
    lda.w #0xB600
    sta.b menu_dp.tilemap_offset
; Y = slot * 128 + $44
    lda.w field_menu_rolling.slot_index
    and.w #0x00FF
    xba
    lsr
    clc
    adc.w #0x0044
    tay
    sep #0x20
    ldx.w #12

_clear_slot_loop:
    lda #0xFF
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda #0x04
    sta.b (menu_dp.tilemap_offset), y
    iny
    dex
    bne _clear_slot_loop
    rep #0x20
    pla
    sta.b menu_dp.tilemap_offset
    ply
    plx
    pla
    plb
    plp
    rts

; Blanks the 2x2 trash icon cells at ($29),Y. Preserves Y.
_clear_trash_area:
    phy
    lda #0xFF
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda #0x00
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda #0xFF
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda #0x00
    sta.b (menu_dp.tilemap_offset), y
; Second row: Y + 64
    ply
    phy
    rep #0x20
    tya
    clc
    adc.w #64
    tay
    sep #0x20
    lda #0xFF
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda #0x00
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda #0xFF
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda #0x00
    sta.b (menu_dp.tilemap_offset), y
    ply
    rts

_draw_trash_single_column:
"""
Draws the 2x2 trash icon (tiles $04 $05 / $06 $07) at ($29),Y and blanks the 13 cells after it on each row.
"""


    rep #0x20
    phy
    sep #0x20
    lda #0x04
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda #0x00
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda #0x05
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda #0x00
    sta.b (menu_dp.tilemap_offset), y
    iny
    ldx.w #13  ; 10 name + colon + 2 digits

_clear_row1:
    lda #0xFF
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda #0x00
    sta.b (menu_dp.tilemap_offset), y
    iny
    dex
    bne _clear_row1
; Second row: start + 64
    rep #0x20
    pla
    clc
    adc.w #64
    tay
    sep #0x20
    lda #0x06
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda #0x00
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda #0x07
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda #0x00
    sta.b (menu_dp.tilemap_offset), y
    iny
    ldx.w #13

_clear_row2:
    lda #0xFF
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda #0x00
    sta.b (menu_dp.tilemap_offset), y
    iny
    dex
    bne _clear_row2
    rts

check_and_clear_count_impl:
"""
Called from DrawItemSlot. Item 0: blanks the colon + 2 digits and skips the count. Item $FE: skips the count.
Otherwise returns to draw it. Entry: ($5A) = item, Y = tilemap offset, ($29) = tilemap.
"""
    lda.b (menu_dp.item_ptr)
    beq _clear_count
    cmp #0xFE
    bne _normal_return
    bra _skip_to_rts

_clear_count:
    lda #0xFF
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda.b menu_dp.item_usable
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda #0xFF
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda.b menu_dp.item_usable
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda #0xFF
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda.b menu_dp.item_usable
    sta.b (menu_dp.tilemap_offset), y

_skip_to_rts:
; Return to DrawItemSlot's RTS ($01:A222) instead of $A205 (colon write).
; Stack, top first: JSL return (3 bytes), JSR return to $A204 (2 bytes), DrawItemSlot's caller.
; Drop both, then push $01:A221 so the RTL lands on $01:A222.
    pla
    pla
    pla
    pla
    pla
    lda #0x01
    pha
    lda #0xA2
    pha
    lda #0x21
    pha

_normal_return:
    rtl

_circular_slot_calc:
"""
DrawItemSlot's tilemap offset ($01:A1BA) for the ring slot.

Entry: $5D = vanilla slot counter (steps by 2), $5A = item pointer ($1440 inventory, $FF28 drops).
Exit: Y = tilemap offset, 16-bit A.
"""


    sep #0x20
; Drops ($FFxx) have no ring: one row pair per slot, else the single-column patch stacks two on one line.
    lda.b menu_dp.item_ptr + 1
    cmp #0xFF
    bne _circ_slot_not_drops
    lda.b menu_dp.item_slot
    rep #0x20
    and.w #0x00FF
    asl
    asl
    asl
    asl
    asl
    asl  ; $5D * 64: 128 bytes per item
    clc
    adc.w #0x0044  ; one row below the window header, column 2
    tay
    rts
_circ_slot_not_drops:
; Treasure inventory ring
    lda.l treasure_rolling.hdma_enable
    beq _circ_check_field
    lda.b menu_dp.item_slot
    lsr
    clc
    adc.l treasure_rolling.buffer_pos
_t_circ_mod:
    cmp #6  ; treasure buffer slots
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
; Field ring when its HDMA is armed: Y = (($5D / 2 + buffer_pos) mod 11) * 128 + 4
    lda.l field_menu_rolling.hdma_enable
    beq _circ_slot_original
    lda.b menu_dp.item_slot
    lsr
    clc
    adc.l field_menu_rolling.buffer_pos

_circ_slot_mod:
    cmp #MENU_BUFFER_SLOTS
    bcc _circ_slot_done
    sec
    sbc #MENU_BUFFER_SLOTS
    bra _circ_slot_mod

_circ_slot_done:
    rep #0x20
    and.w #0x00FF
    xba
    lsr
    clc
    adc.w #0x0004
    tay
    rts

_circ_slot_original:
; Vanilla: Y = ($5D / 2) * 128 + 4
    lda.b menu_dp.item_slot
    lsr
    rep #0x20
    and.w #0x00FF
    xba
    lsr
    clc
    adc.w #0x0004
    tay
    rts

circular_slot_calc_ext:
"""Long entry to `_circular_slot_calc` for the $01:A1BA patch."""
    jsr.w _circular_slot_calc
    rtl
}

.assert sizeof(Item) == 2, "the item pointer math uses one asl per Item"
