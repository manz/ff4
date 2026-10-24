"""
Treasure inventory rolling buffer (single column, 5 visible, 6 slots), the chest-UI clone of
`inventory_rolling.s`. Scroll position is vanilla's $1BB7; HDMA ch6 drives BG3VOFS.
"""

.import "core/preamble"
.import "core/items"
.include "lib/rolling_buffer.i"

.import "ingame/vanilla_trampolines"
.import "lib/rolling_inventory_engine"


_TREASURE_VISIBLE_ITEMS := 5
TREASURE_BUFFER_SLOTS := 6  ; 5 visible + 1 prefetch
_TREASURE_TOTAL_ITEMS := 48
_TREASURE_SCROLL_LIMIT := 43  ; 48 - 5

_TREASURE_PIXELS_PER_ROW := 16

_TREASURE_SCROLL_WRAP := 96  ; 6 slots * 16 px

_TREASURE_ITEM_LIST_Y_START := 48
_TREASURE_ITEM_LIST_HEIGHT := 80

; State: `treasure_rolling` at $7E:9C00, outside $1B00-$1BFF (vanilla writes past $1BEB).

TREASURE_SCROLL_COOLDOWN_FRAMES := 0x0C  ; 12 frames between scrolls while DOWN/UP is held

_TREASURE_SCROLL_STATE_IDLE := 0
_TREASURE_SCROLL_STATE_SCROLLING := 1
; Held-DOWN cadence shared with the field menu (src/lib/rolling_buffer.s).
_TREASURE_SCROLL_PIXELS_PER_FRAME := INVENTORY_SCROLL_PIXELS_PER_FRAME
_TREASURE_SCROLL_TOTAL_PIXELS := INVENTORY_SCROLL_TOTAL_PIXELS


; HDMA tables shared with the field menu (never on screen together): active $7E:9800, shadow $7E:9840.
_TREASURE_HDMA_TABLE_ADDR := 0x9800
_TREASURE_HDMA_TABLE := 0x7E9800
_TREASURE_HDMA_SHADOW_ADDR := 0x9840
_TREASURE_HDMA_SHADOW := 0x7E9840
_TREASURE_HDMA_TABLE_SIZE := 40
_TREASURE_HDMA_BANK := 0x7E

; HDMA ch6: vanilla treasure arms ch7|ch5|ch3|ch2|ch0, and ch2 writes BG3VOFS for the drops band.

.include "core/bank20.i"
.import "core/vanilla"

.alloc _treasure_rolling_block in bank20_reloc {
_init_treasure_inventory_hdma:
"""
Builds the table and configures ch6: direct mode, 2 bytes -> BG3VOFS. Entries: count, lo, hi; $00 ends.
"""


    php
    sep #0x20

    jsr.w update_treasure_scroll_hdma

; Long addressing: DB may be $7E.
    lda #0x02
    sta.l dma_ch6.DMAP
    lda #PPU.BG3VOFS
    sta.l dma_ch6.BBAD
    rep #0x20
    lda.w #_TREASURE_HDMA_TABLE_ADDR
    sta.l dma_ch6.A1TL
    sep #0x20
    lda #_TREASURE_HDMA_BANK
    sta.l dma_ch6.A1B

    plp
    rts

_disable_treasure_inventory_hdma:
"""
No-op: the caller clears the enable shadow and the NMI writes HDMAEN.
"""


    php
    sep #0x20
    plp
    rts

_init_treasure_hdma_table:
"""
Builds the initial $7E:9800 table, every row at base scroll.
"""


    rep #0x30
    php
    pha
    phx
    phy

    lda.b 0x40
    pha

    ldx.w #0x0000

; Border: 48 lines at base.
    sep #0x20
    lda #48
    sta.l _TREASURE_HDMA_TABLE, x
    inx
    rep #0x20
    lda.w treasure_rolling.base_scroll
    sta.l _TREASURE_HDMA_TABLE, x
    inx
    inx

; Item rows: 16 lines each at base.
    lda.w #0x0000
    sta.b 0x40

_t_init_item_rows:
    sep #0x20
    lda #16
    sta.l _TREASURE_HDMA_TABLE, x
    inx
    rep #0x20
    lda.w treasure_rolling.base_scroll
    sta.l _TREASURE_HDMA_TABLE, x
    inx
    inx

    inc.b 0x40
    lda.b 0x40

    cmp.w #1
    bcc _t_init_item_rows

; Bottom border: 16 lines at base + 16.
    sep #0x20
    lda #16
    sta.l _TREASURE_HDMA_TABLE, x
    inx
    rep #0x20
    lda.w treasure_rolling.base_scroll
    clc
    adc.w #16
    sta.l _TREASURE_HDMA_TABLE, x
    inx
    inx

; End marker
    sep #0x20
    lda #0x00
    sta.l _TREASURE_HDMA_TABLE, x

    rep #0x20
    pla
    sta.b 0x40

    ply
    plx
    pla
    plp
    rts

update_treasure_scroll_hdma:
"""Build the treasure-menu HDMA scroll table."""
; Inlined per menu: the engine would need menu_id dispatch on every state read.
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
        lda.w treasure_rolling.buffer_pos
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
        adc.w treasure_rolling.base_scroll
        sta.b 0x40
        sep #0x20
        lda #16
        sta.l _TREASURE_HDMA_SHADOW, x
        inx
        rep #0x20
        lda.b 0x40
        sta.l _TREASURE_HDMA_SHADOW, x
        inx
        inx
        rep #0x20
        inc.b 0x42
        lda.b 0x42
        cmp.w #_TREASURE_VISIBLE_ITEMS
        bcs _row_loop_done
        jmp.w _row_loop

_row_loop_done:
        jsr.w _treasure_hdma_footer
        sep #0x20
        lda #0x00
        sta.l _TREASURE_HDMA_SHADOW, x
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
"""Header: drops band (120 lines at base - 16) + inventory border (8 lines at base)."""

    sep #0x20
    lda #120
    sta.l _TREASURE_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w treasure_rolling.base_scroll
    sec
    sbc.w #16
    sta.l _TREASURE_HDMA_SHADOW, x
    inx
    inx
    sep #0x20
    lda #8
    sta.l _TREASURE_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w treasure_rolling.base_scroll
    sta.l _TREASURE_HDMA_SHADOW, x
    inx
    inx
    rts

_treasure_hdma_footer:
"""Footer: 16 lines at base + 16, hiding the prefetch slot."""

    sep #0x20
    lda #16
    sta.l _TREASURE_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w treasure_rolling.base_scroll
    clc
    adc.w #16
    sta.l _TREASURE_HDMA_SHADOW, x
    inx
    inx
    rts

_treasure_hdma_signal:
"""Sets the treasure and shared hdma_copy_pending flags."""
    sep #0x20
    lda #0x01
    sta.l treasure_rolling.hdma_copy_pending
    sta.l field_menu_rolling.hdma_copy_pending
    rts


treasure_refresh_slots_impl:
"""Re-renders all 6 slots after a swap ($01:D933), keeping buffer_pos and the scroll state."""
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
Fills `treasure_rolling` ($7E:9C00) and inits the engine.
"""


    php
    rep #0x30
    sep #0x20
; Visible rows, not slots: the engine adds the prefetch slot (an extra slot wipes the bottom border).
    lda.b #_TREASURE_VISIBLE_ITEMS
    sta.l treasure_rolling.visible_rows
    lda.b #0x02
    sta.l treasure_rolling.slot_height_tiles
    lda.b #0x40
    sta.l treasure_rolling.item_list_ptr
    lda.b #0x14
    sta.l treasure_rolling.item_list_ptr + 1
    lda.b #0x7E
    sta.l treasure_rolling.item_list_ptr + 2
    lda.b #_TREASURE_TOTAL_ITEMS
    sta.l treasure_rolling.item_count
    lda.b #0x06
    sta.l treasure_rolling.hdma_channel
    lda.b #0x80
    sta.l treasure_rolling.vwf_cfg_ptr
    lda.b #0x70
    sta.l treasure_rolling.vwf_cfg_ptr + 1
    lda.b #0x70
    sta.l treasure_rolling.vwf_cfg_ptr + 2
    lda.b #_treasure_fn_render_slot_trampoline & 0xFF
    sta.l treasure_rolling.fn_render_slot
    lda.b #( _treasure_fn_render_slot_trampoline >> 8 ) & 0xFF
    sta.l treasure_rolling.fn_render_slot + 1
    lda.b #( _treasure_fn_render_slot_trampoline >> 16 ) & 0xFF
    sta.l treasure_rolling.fn_render_slot + 2
    lda.b #_treasure_fn_update_hdma_trampoline & 0xFF
    sta.l treasure_rolling.fn_update_hdma
    lda.b #( _treasure_fn_update_hdma_trampoline >> 8 ) & 0xFF
    sta.l treasure_rolling.fn_update_hdma + 1
    lda.b #( _treasure_fn_update_hdma_trampoline >> 16 ) & 0xFF
    sta.l treasure_rolling.fn_update_hdma + 2
    lda.b #_treasure_fn_draw_window_trampoline & 0xFF
    sta.l treasure_rolling.fn_draw_window
    lda.b #( _treasure_fn_draw_window_trampoline >> 8 ) & 0xFF
    sta.l treasure_rolling.fn_draw_window + 1
    lda.b #( _treasure_fn_draw_window_trampoline >> 16 ) & 0xFF
    sta.l treasure_rolling.fn_draw_window + 2
    lda.b #ROLLING_MENU_ID_TREASURE
    sta.l treasure_rolling.menu_id
    plp
    php
    rep #0x10
    ldx.w #treasure_rolling
    jsr.l rolling_engine.rolling_engine_init
    plp
    rtl

_treasure_fn_render_slot_trampoline:
"""Bank-20 RTL wrapper around `_treasure_render_item_to_slot`."""
    php
    jsr.w _treasure_render_item_to_slot
    plp
    rtl

_treasure_fn_update_hdma_trampoline:
"""Bank-20 RTL wrapper around `_treasure_ensure_hdma_initialized`."""
    php
    jsr.w _treasure_ensure_hdma_initialized
    plp
    rtl

_treasure_fn_draw_window_trampoline:
"""Bank-20 RTL wrapper around `_treasure_draw_inventory_window`."""
    php
    jsr.w _treasure_draw_inventory_window
    plp
    rtl

_treasure_draw_inventory_window:
"""Draws a 5-row inventory window so its bottom border lands on the footer band."""
    rep #0x10
    ldy.w #treasure_inventory_window
    jsr.l draw_window_trampoline
    sep #0x10
    rts

; Renders item edge_row ($1440) into ring slot slot_index through DrawItemSlot.

_treasure_render_item_to_slot:
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
    lda.w #0xD600  ; BG3 screen buffer (treasure inventory lives on BG3)
    sta.b menu_dp.tilemap_offset
    sep #0x20

; Item pointer = $1440 + edge_row * 2
    lda.w treasure_rolling.edge_row
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

; CheckCanUseItem: A = item id -> $DB = $00 usable / $04 not.
    stz.b menu_dp.window_attr
    pla
    jsr.l check_can_use_item_trampoline

    lda.w treasure_rolling.slot_index
    sta.b menu_dp.item_slot

; Y = slot * 128 + $44: one border row + 2-tile margin.
    rep #0x20
    lda.w treasure_rolling.slot_index
    and.w #0x00FF
    xba
    lsr
    clc
    adc.w #0x0044  ; + 68 (64 border + 4 margin)
    tay
    sep #0x20

; Trash ($FF) is a 2x2 icon.
    lda.b (menu_dp.item_ptr)
    cmp #0xFF
    bne _t_not_trash_item
    jsr.w _draw_trash_treasure
    bra _t_skip_draw_item_slot

_t_not_trash_item:
; Clear a trash icon left by the previous occupant.
    jsr.w _clear_treasure_trash_area

; DrawItemSlot inner ($01:A1ED): Y = tilemap offset, ($5A) = item, ($29) = tilemap base.
    jsr.l draw_item_slot_inner_trampoline

_t_skip_draw_item_slot:

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

_treasure_ensure_hdma_initialized:
"""
One-shot (base_scroll = $FFFF): captures base scroll and arms ch6.
"""


; Long addressing: entered with DB = $00.
    rep #0x20
    lda.l treasure_rolling.base_scroll
    cmp.w #0xFFFF
    bne _t_hdma_already_init

; base_scroll = vanilla's BG3VOFS shadow $9F (-120: list at scanline 120).
    lda 0x7E019F
    sta.l treasure_rolling.base_scroll
; Reset the held-DOWN cooldown (outside the struct the engine zeroes).
    sep #0x20
    lda #0x00
    sta.l treasure_scroll_cooldown
    rep #0x20

    sep #0x20
    jsr.w _init_treasure_inventory_hdma

; OR ch6 into the shared enable the NMI hook reads; a plain store would drop drops' ch4.
    lda.l field_menu_rolling.hdma_enable
    ora #0x40
    sta.l field_menu_rolling.hdma_enable
    sta.l treasure_rolling.hdma_enable
; Write HDMAEN now too: the NMI copy lands a frame late and the list shows misplaced for one frame.
    lda.l cpu_regs.HDMAEN
    ora #0x40
    sta.l cpu_regs.HDMAEN
    rts

_t_hdma_already_init:
    sep #0x20
    rts

; Non-blocking scroll state machine

_treasure_scroll_state_check:
"""
Main-loop entry ($01:9FF2): runs one scroll frame while scrolling.
Exit: carry set = still scrolling, skip input.
"""


    php
    sep #0x20

; The cooldown ticks in the NMI hook: this entry runs several times per frame.
    lda.w treasure_rolling.scroll_state
    beq _t_scroll_state_idle

    jsr.l treasure_update_scroll_frame_impl

    lda.w treasure_rolling.scroll_remaining
    bne _t_scroll_still_active

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
"""Starts the engine's scroll-down."""
    php
    rep #0x10
    lda.l menu_cursor_data + 0xb7  ; treasure scroll_pos (shared with vanilla cursor)
    ldx.w #treasure_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_down
    plp
    rtl

treasure_start_scroll_up_impl:
"""Starts the engine's scroll-up."""
    php
    rep #0x10
    lda.l menu_cursor_data + 0xb7
    ldx.w #treasure_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_up
    plp
    rtl

treasure_update_scroll_frame_impl:
"""Per-frame scroll tick."""
    php
    rep #0x10
    ldx.w #treasure_rolling
    jsr.l rolling_engine.rolling_engine_update_scroll_frame
    plp
    rtl

treasure_finish_scroll_impl:
"""Finishes the engine scroll."""
    php
    rep #0x10
    lda.l menu_cursor_data + 0xb7
    ldx.w #treasure_rolling
    jsr.l rolling_engine.rolling_engine_finish_scroll
    plp
    rtl

; Bodies of the bank-$01 hooks (JSL).

treasure_menu_entry_hook_impl:
"""Menu entry: clears HDMA enable and scroll state."""
    stz.w inventory_menu_mode
    lda #0x00
    sta.l field_menu_rolling.hdma_enable
    stz.w treasure_rolling.scroll_state
    stz.w treasure_rolling.scroll_remaining
    stz.w treasure_rolling.scroll_direction
    stz.w treasure_rolling.transfer_pending
    stz.w treasure_rolling.hdma_copy_pending
    stz.w treasure_rolling.scroll_anim_offset
    stz.w treasure_rolling.scroll_anim_offset + 1
    stz.w inventory_cursor1_x  ; single column: cursor x is always 0
; init_treasure_rolling_buffer_impl runs later, from the patched JSR at $01:D81D.
    rtl

treasure_menu_exit_hook_impl:
"""Menu exit: clears the HDMA enable, $1BC6, ch6 registers and the first 12 state bytes."""
    php
    sep #0x20
    lda #0x00
    sta.l field_menu_rolling.hdma_enable
    sta.l menu_cursor_data + 0xc6  ; vanilla's `stz $1BC6` ($01:D7E6), displaced by the hook
    sta.l dma_ch6.DMAP
    sta.l dma_ch6.BBAD
    sta.l dma_ch6.A1TL
    sta.l dma_ch6.A1TH
    sta.l dma_ch6.A1B
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

treasure_swap_redraw_hook_impl_body:
"""Post-swap re-render of all 6 slots at the current scroll position."""
    php
    rep #0x10
    lda.l menu_cursor_data + 0xb7
    ldx.w #treasure_rolling
    jsr.l rolling_engine.rolling_engine_swap_redraw
    plp
    rtl

; Blanks the name row of slot slot_index (index past the list).

_clear_treasure_slot:
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
    lda.w #0xD600  ; BG3 screen buffer (treasure inventory lives on BG3)
    sta.b menu_dp.tilemap_offset
    lda.w treasure_rolling.slot_index
    and.w #0x00FF
    xba
    lsr
    clc
    adc.w #0x0044
    tay
    sep #0x20
    ldx.w #12

_t_clear_slot_loop:
    lda #0xFF
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda #0x04
    sta.b (menu_dp.tilemap_offset), y
    iny
    dex
    bne _t_clear_slot_loop
    rep #0x20
    pla
    sta.b menu_dp.tilemap_offset
    ply
    plx
    pla
    plb
    plp
    rts
; Blanks the 2x2 trash icon area at Y in ($29).

_clear_treasure_trash_area:
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
; Second row
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

_draw_trash_treasure:

"""
Draws the 2x2 trash icon (tiles $04 $05 / $06 $07) and blanks the rest of both rows.
Entry: Y = tilemap offset, ($29) = tilemap base.
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
; Blank the other 13 cells (name + colon + 2 digits)
    ldx.w #13

_t_clear_row1:
    lda #0xFF
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda #0x00
    sta.b (menu_dp.tilemap_offset), y
    iny
    dex
    bne _t_clear_row1
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
; Blank the other 13 cells
    ldx.w #13

_t_clear_row2:
    lda #0xFF
    sta.b (menu_dp.tilemap_offset), y
    iny
    lda #0x00
    sta.b (menu_dp.tilemap_offset), y
    iny
    dex
    bne _t_clear_row2
    rts

treasure_check_and_clear_count_impl:
"""
DrawItemSlot count check: id 0 blanks the count and skips, $FE skips, anything else returns to draw it.
Entry: ($5A) = item, Y = tilemap offset, ($29) = tilemap base.
"""
    lda.b (menu_dp.item_ptr)
    beq _t_clear_count
    cmp #0xFE
    bne _t_normal_return
    bra _t_skip_to_rts

_t_clear_count:
; Blank colon + 2 digits
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

_t_skip_to_rts:
; Skip the rest of DrawItemSlot: drop the JSL (3 bytes) and JSR (2 bytes) returns, then RTL to the RTS at $01:A222.
    pla  ; PCL of JSL Impl return
    pla  ; PCH of JSL Impl return
    pla  ; PB  of JSL Impl return
    pla  ; PCL of JSR check_and_clear_count return
    pla  ; PCH of JSR check_and_clear_count return
; RTL to $01:A221 + 1.
    lda #0x01
    pha
    lda #0xA2
    pha
    lda #0x21
    pha

_t_normal_return:
    rtl

_treasure_circular_slot_calc:

"""
Ring-aware DrawItemSlot offset (patch at $01:A1BA). Entry: $5D = row * 2. Exit: Y = tilemap offset, 16-bit A.
"""


    sep #0x20
    lda.l treasure_rolling.hdma_enable
    beq _t_circ_slot_original
    lda.b menu_dp.item_slot
    lsr
    clc
    adc.l treasure_rolling.buffer_pos

_t_circ_slot_mod:
    cmp #TREASURE_BUFFER_SLOTS
    bcc _t_circ_slot_done
    sec
    sbc #TREASURE_BUFFER_SLOTS
    bra _t_circ_slot_mod

_t_circ_slot_done:
    rep #0x20
    and.w #0x00FF
    xba
    lsr
    clc
    adc.w #0x0004  ; margin only: $29 already includes the border
    tay
    rts

_t_circ_slot_original:
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

_treasure_circular_slot_calc_ext:
"""Long-call entry for the $01:A1BA patch."""
    jsr.w _treasure_circular_slot_calc
    rtl
}
