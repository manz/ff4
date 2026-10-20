

"""
Treasure-menu drops list (8 items at $7E:FF28) as a single-column rolling buffer: 5 visible, 6 slots.

Renders into the BG4 staging page ($7E:C600) inside TreasureItemsWindow; HDMA ch4 (free in the treasure menu)
drives BG4VOFS. Hooks: `jsr $A15C` at $01:D80E (init) and $01:D92D (refresh), in treasure_rolling_patches.s.
State: `drops_rolling` at $7E:9C30.
"""


.import "core/preamble"
.import "core/vwf_ram"
.import "core/items"

.import "ingame/vanilla_trampolines"
.import "lib/rolling_inventory_engine"
.import "core/vanilla"


DROPS_VISIBLE_ITEMS := 5
_DROPS_BUFFER_SLOTS := 6
DROPS_TOTAL_ITEMS := 8
_DROPS_SCROLL_LIMIT := 3
_DROPS_SCROLL_PIXELS_PER_FRAME := 8
_DROPS_SCROLL_TOTAL_PIXELS := 16

; Drops scroll position (no vanilla equivalent), in the last byte of the state slot. Keep the full 24-bit
; address: a 16-bit constant with `.l` access would hit bank $00 ROM.
drops_scroll_pos := 0x7E9C5F

; Own HDMA table / shadow, next to the treasure inventory's ($7E:9800 / $7E:9840).
_DROPS_HDMA_TABLE_ADDR := 0x9880
DROPS_HDMA_TABLE := 0x7E9880
_DROPS_HDMA_SHADOW_ADDR := 0x98C0
DROPS_HDMA_SHADOW := 0x7E98C0
_DROPS_HDMA_BANK := 0x7E

_DROPS_SCROLL_STATE_IDLE := 0
_DROPS_SCROLL_STATE_SCROLLING := 1

; --- Profile hooks -----------------------------------------------------------

.include "core/bank20.i"


.alloc _drops_rolling_block in bank20_reloc {
_drops_ensure_hdma_initialized:
"""One-shot: sets base_scroll, configures ch4 -> BG4VOFS and arms it. Long addressing: entered with DB = $00."""
    rep #0x20
    lda.l drops_rolling.base_scroll
    cmp.w #0xFFFF
    bne _drops_hdma_already_init

; -24: the window (BG line 0) shows at screen y=24, where vanilla's TreasureItemsWindow sits.
    lda.w #0xFFE8
    sta.l drops_rolling.base_scroll

; ch4: direct mode, 2 bytes -> BG4VOFS, from $7E:9880.
    sep #0x20
    lda #0x02
    sta.l dma_ch4.DMAP
    lda #PPU.BG4VOFS
    sta.l dma_ch4.BBAD
    rep #0x20
    lda.w #_DROPS_HDMA_TABLE_ADDR
    sta.l dma_ch4.A1TL
    sep #0x20
    lda #_DROPS_HDMA_BANK
    sta.l dma_ch4.A1B

; Arm ch4 only. A per-scanline TM ($212C) mask blanks the screen, so BG4 relies on zero-filled staging instead.
    lda.l field_menu_rolling.hdma_enable
    ora #0x10
    sta.l field_menu_rolling.hdma_enable
    sta.l drops_rolling.hdma_enable
; Initial table, so ch4 is valid on the first frame.
    jsr.w update_drops_scroll_hdma
    rts

_drops_hdma_already_init:
    sep #0x20
    rts

_drops_render_item_to_slot:
"""Renders drops item $7E:FF28 + edge_row * 2 into BG4 staging $7E:C600 + slot_index * 128 + $44."""
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
; $29 = $C600: the BG4 staging page holding TreasureItemsWindow.
    lda.w #0xC600
    sta.b menu_dp.tilemap_offset
    sep #0x20
    lda.w drops_rolling.edge_row
    asl
    clc
    adc #0x28
    sta.b menu_dp.item_ptr
    lda #0xFF
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
    stz.b menu_dp.window_attr
    pla
    jsr.l check_can_use_item_trampoline
; Slots offset by 11 (tile ids $16E..$1A9) so drops never share tile ids with the treasure inventory.
; caller_ctx = 1 (drops) routes the CHR flush through the secondary descriptor; reset to primary after.
    lda.w drops_rolling.slot_index
    clc
    adc #DROPS_VWF_TILE_SLOT_OFFSET
    sta.b menu_dp.item_slot
    lda #0x01
    sta.l vwf_engine.caller_ctx
    rep #0x20
    lda.w drops_rolling.slot_index
    and.w #0x00FF
    xba
    lsr
    clc
    adc.w #0x0044
    tay
    sep #0x20
    jsr.l draw_item_slot_inner_trampoline
    lda #0x00
    sta.l vwf_engine.caller_ctx
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

_clear_drops_slot:
"""No-op."""
    rts

update_drops_scroll_hdma:
"""Build the drops HDMA shadow table."""
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
        jsr.w _drops_hdma_header
        stz.b 0x42

_row_loop:
        lda.w drops_rolling.buffer_pos
        and.w #0x00FF
        clc
        adc.b 0x42

_mod_loop:
        cmp.w #_DROPS_BUFFER_SLOTS
        bcc _mod_done
        sec
        sbc.w #_DROPS_BUFFER_SLOTS
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
        adc.w drops_rolling.base_scroll
        sta.b 0x40
        sep #0x20
        lda #16
        sta.l DROPS_HDMA_SHADOW, x
        inx
        rep #0x20
        lda.b 0x40
        sta.l DROPS_HDMA_SHADOW, x
        inx
        inx
        rep #0x20
        inc.b 0x42
        lda.b 0x42
        cmp.w #DROPS_VISIBLE_ITEMS
        bcs _row_loop_done
        jmp.w _row_loop

_row_loop_done:
        jsr.w _drops_hdma_footer
        sep #0x20
        lda #0x00
        sta.l DROPS_HDMA_SHADOW, x
        jsr.w _drops_hdma_signal
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

_drops_hdma_header:
"""Header: 32 lines at base (-24): 24 off-screen + 8 of top border."""
    sep #0x20
    lda #32
    sta.l DROPS_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w drops_rolling.base_scroll
    sta.l DROPS_HDMA_SHADOW, x
    inx
    inx
    rts

_drops_hdma_footer:
"""
    Footer: 25 lines of bottom border at -8, then 87 lines at -24 on empty rows (32 + 80 + 112 = 224 lines).

    25, not 16: the trail must start past the border row (no repeated border tile), and at y=137 rather than
    136, where ch6 (treasure BG3VOFS) reloads; ch4 and ch6 must not reload on the same scanline.
"""


    sep #0x20
    lda #25
    sta.l DROPS_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w #0xFFF8
    sta.l DROPS_HDMA_SHADOW, x
    inx
    inx
    sep #0x20
    lda #87
    sta.l DROPS_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w #0xFFE8
    sta.l DROPS_HDMA_SHADOW, x
    inx
    inx
    rts

_drops_hdma_signal:
"""Sets hdma_copy_pending."""
    sep #0x20
    lda #0x01
    sta.l drops_rolling.hdma_copy_pending
    rts

; --- Engine instantiations -------------------------------------------------

drops_init_impl:
"""
    Fills `drops_rolling` ($7E:9C30) and inits the engine. The draw_window hook redraws TreasureItemsWindow
    first, so vanilla's DrawWindow ($01:D817) cannot clobber the rendered items.
"""


    php
    rep #0x30
    sep #0x20
    lda.b #DROPS_VISIBLE_ITEMS
    sta.l drops_rolling.visible_rows
    lda.b #0x02
    sta.l drops_rolling.slot_height_tiles
; item_list_ptr = $7E:FF28
    lda.b #0x28
    sta.l drops_rolling.item_list_ptr
    lda.b #0xFF
    sta.l drops_rolling.item_list_ptr + 1
    lda.b #0x7E
    sta.l drops_rolling.item_list_ptr + 2
    lda.b #DROPS_TOTAL_ITEMS
    sta.l drops_rolling.item_count
    lda.b #0x04
    sta.l drops_rolling.hdma_channel
    lda.b #0x80
    sta.l drops_rolling.vwf_cfg_ptr
    lda.b #0x70
    sta.l drops_rolling.vwf_cfg_ptr + 1
    lda.b #0x70
    sta.l drops_rolling.vwf_cfg_ptr + 2
    lda.b #_drops_fn_render_slot_trampoline & 0xFF
    sta.l drops_rolling.fn_render_slot
    lda.b #( _drops_fn_render_slot_trampoline >> 8 ) & 0xFF
    sta.l drops_rolling.fn_render_slot + 1
    lda.b #( _drops_fn_render_slot_trampoline >> 16 ) & 0xFF
    sta.l drops_rolling.fn_render_slot + 2
    lda.b #_drops_fn_update_hdma_trampoline & 0xFF
    sta.l drops_rolling.fn_update_hdma
    lda.b #( _drops_fn_update_hdma_trampoline >> 8 ) & 0xFF
    sta.l drops_rolling.fn_update_hdma + 1
    lda.b #( _drops_fn_update_hdma_trampoline >> 16 ) & 0xFF
    sta.l drops_rolling.fn_update_hdma + 2
    lda.b #_drops_fn_draw_window_trampoline & 0xFF
    sta.l drops_rolling.fn_draw_window
    lda.b #( _drops_fn_draw_window_trampoline >> 8 ) & 0xFF
    sta.l drops_rolling.fn_draw_window + 1
    lda.b #( _drops_fn_draw_window_trampoline >> 16 ) & 0xFF
    sta.l drops_rolling.fn_draw_window + 2
    lda.b #ROLLING_MENU_ID_DROPS
    sta.l drops_rolling.menu_id
    plp
    php
    rep #0x10
    ldx.w #drops_rolling
    jsr.l rolling_engine.rolling_engine_init
    plp
    rtl

_drops_fn_render_slot_trampoline:
"""Bank-20 RTL wrapper around `_drops_render_item_to_slot`."""
    php
    jsr.w _drops_render_item_to_slot
    plp
    rtl

_drops_fn_update_hdma_trampoline:
"""Bank-20 RTL wrapper around `_drops_ensure_hdma_initialized`."""
    php
    jsr.w _drops_ensure_hdma_initialized
    plp
    rtl

_drops_fn_draw_window_trampoline:
"""Bank-20 RTL wrapper around `_drops_draw_window`."""
    php
    jsr.w _drops_draw_window
    plp
    rtl

_drops_draw_window:
"""Pre-render hook: SelectBG4 + DrawWindow(treasure_drops_window) into $C600."""
    sep #0x20
    jsr.l drops_select_bg4_trampoline
    rep #0x10
    ldy.w #treasure_drops_window
    jsr.l draw_window_trampoline
    sep #0x10
    rts

drops_start_scroll_down_impl:
"""Starts the engine's scroll-down."""
    php
    rep #0x10
    lda.l drops_scroll_pos
    ldx.w #drops_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_down
    plp
    rtl

drops_start_scroll_up_impl:
"""Starts the engine's scroll-up."""
    php
    rep #0x10
    lda.l drops_scroll_pos
    ldx.w #drops_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_up
    plp
    rtl

drops_update_scroll_frame_impl:
"""Per-frame scroll tick."""
    php
    rep #0x10
    ldx.w #drops_rolling
    jsr.l rolling_engine.rolling_engine_update_scroll_frame
    plp
    rtl

drops_finish_scroll_impl:
"""Finishes the engine scroll."""
    php
    rep #0x10
    lda.l drops_scroll_pos
    ldx.w #drops_rolling
    jsr.l rolling_engine.rolling_engine_finish_scroll
    plp
    rtl

drops_refresh_slots_impl:
"""Re-renders all 6 slots."""
    php
    sep #0x20
    rep #0x10
    lda.l drops_scroll_pos
    ldx.w #drops_rolling
    jsr.l rolling_engine.rolling_engine_refresh_slots
    plp
    rtl

_drops_swap_redraw_impl:
"""Post-swap re-render."""
    php
    rep #0x10
    lda.l drops_scroll_pos
    ldx.w #drops_rolling
    jsr.l rolling_engine.rolling_engine_swap_redraw
    plp
    rtl
}
