"""
Shop sell-list rolling buffer: 9-slot ring (8 visible + 1 prefetch) in the BG3 buffer at $7E:D600, BG3VOFS
driven per scanline by HDMA ch5.

Replaces vanilla `DrawInventoryList` ($01:A172), which draws all 48 items once: 48 single-column VWF rows
(128 bytes each) do not fit the 2 KB buffer. The shop uses no HDMA itself, so ch5 is armed through the shared
`field_menu_rolling.hdma_enable`.
"""


.import "core/preamble"
.include "core/bank20.i"
.import "core/items"

.import "ingame/vanilla_trampolines"
.import "core/libmz"
.import "lib/rolling_inventory_engine"
.import "core/vanilla"

_SELL_VISIBLE_ITEMS := 8
_SELL_BUFFER_SLOTS := 9
_SELL_TOTAL_ITEMS := 48

; Vanilla's sell scroll position (first visible row), read directly so its bounds checks stay authoritative.
_SELL_SCROLL_POS := 0x7E1B96

; HDMA ch5 driving BG3VOFS.
_SELL_HDMA_ENABLE_BIT := 0x20

; HDMA tables ($9800 treasure, $9880 drops).
_SELL_HDMA_TABLE_ADDR := 0x9900
_SELL_HDMA_SHADOW_ADDR := 0x9940
_SELL_HDMA_BANK := 0x7E
SELL_HDMA_SHADOW := 0x7E9940
SELL_HDMA_TABLE := 0x7E9900

; Window in the BG3 buffer: top border on slot 0, ring on slots 1..9 (128 bytes each), bottom border on 12.
_SELL_BG3_BUFFER := 0xD600
_SELL_SLOT_ORIGIN := 1

; Blank window cell.
_SELL_BLANK_TILE := 0xFF
_SELL_TILEMAP_ATTR := 0x00
; Side borders in the first and last columns.
_SELL_BORDER_LEFT_TILE := 0xFA
_SELL_BORDER_RIGHT_TILE := 0xFB
_SELL_BORDER_RIGHT_COL := 31

; Vanilla's BG3VOFS for the window ($9F seeded at $01:C7C1).
_SELL_BASE_SCROLL := 0xFFB8

; Vanilla's scroll cadence: 8 frames of 2px for one 16px item.
_SELL_SCROLL_FRAMES := 8

.alloc _sell_rolling_block in bank20_reloc {
_sell_ensure_hdma_initialized:
"""
One-shot: sets base_scroll, configures ch5 -> BG3VOFS and arms it. Long addressing: entered with the caller's DB.
"""


    rep #0x20
    lda.l sell_rolling.base_scroll
    cmp.w #0xFFFF
    bne _sell_hdma_already_init
    lda.w #_SELL_BASE_SCROLL
    sta.l sell_rolling.base_scroll

    sep #0x20
    lda #0x02  ; direct mode, 2 bytes per write
    sta.l dma_ch5.DMAP
    lda #PPU.BG3VOFS
    sta.l dma_ch5.BBAD
    rep #0x20
    lda.w #_SELL_HDMA_TABLE_ADDR
    sta.l dma_ch5.A1TL
    sep #0x20
    lda #_SELL_HDMA_BANK
    sta.l dma_ch5.A1B

; Arm ch5 via the shared signal the NMI hook ORs into $420C.
    lda.l field_menu_rolling.hdma_enable
    ora #_SELL_HDMA_ENABLE_BIT
    sta.l field_menu_rolling.hdma_enable
    sta.l sell_rolling.hdma_enable
    jsr.w update_sell_scroll_hdma
    rts

_sell_hdma_already_init:
    sep #0x20
    rts

sell_disable_hdma:
"""Disarms ch5 when leaving the sell list."""
    php
    sep #0x20
    lda.l field_menu_rolling.hdma_enable
    and #0xDF  ; ~_SELL_HDMA_ENABLE_BIT, spelled out: `^` is a816's bank-byte operator, not xor
    sta.l field_menu_rolling.hdma_enable
    lda #0x00
    sta.l sell_rolling.hdma_enable
    rep #0x20
    lda.w #0xFFFF
    sta.l sell_rolling.base_scroll
    plp
    rtl

_sell_blank_slot_rows:
"""
Blanks this slot's two tilemap rows; `DrawItemSlot` writes only the cells it draws.

Entry: 16-bit A/X/Y, DB = $7E.
"""


    rep #0x30
    lda.l sell_rolling.slot_index
    and.w #0x00FF
    clc
    adc.w #_SELL_SLOT_ORIGIN
    xba
    lsr  ; (slot + 1) * 128
    clc
    adc.w #_SELL_BG3_BUFFER
    tax
    ldy.w #0x0040  ; 64 cells = two 32-tile rows

_sell_blank_cell:
    jsr.w _sell_window_cell
    sta.w 0x0000, x
    inx
    inx
    dey
    bne _sell_blank_cell
    rts

_sell_window_cell:
"""
Blank window cell (border or body) for buffer offset X; X's low 6 bits are the row offset.

Entry/exit: 16-bit A/X. Returns the cell word (attr << 8 | tile) in A.
"""


    txa
    and.w #0x003F
    lsr
    beq _sell_cell_left
    cmp.w #_SELL_BORDER_RIGHT_COL
    beq _sell_cell_right
    lda.w #( _SELL_TILEMAP_ATTR << 8 ) | _SELL_BLANK_TILE
    rts

_sell_cell_left:
    lda.w #( _SELL_TILEMAP_ATTR << 8 ) | _SELL_BORDER_LEFT_TILE
    rts

_sell_cell_right:
    lda.w #( _SELL_TILEMAP_ATTR << 8 ) | _SELL_BORDER_RIGHT_TILE
    rts

_sell_render_item_to_slot:
"""
Renders inventory item `edge_row` ($7E:1440) into $7E:D600 + (slot + 1) * 128 + 4.
"""


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
    lda.w #_SELL_BG3_BUFFER
    sta.b menu_dp.tilemap_offset
    jsr.w _sell_blank_slot_rows
    sep #0x20

; Item pointer = $7E:1440 + edge_row * 2
    lda.w sell_rolling.edge_row
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
    stz.b menu_dp.window_attr
    pla
    jsr.l check_can_use_item_trampoline

; Primary VWF tile window, unshifted: 9 slots * 10 tiles fit the $0700-byte primary flush.
    lda.w sell_rolling.slot_index
    sta.b menu_dp.item_slot
    rep #0x20
    lda.w sell_rolling.slot_index
    and.w #0x00FF
    clc
    adc.w #_SELL_SLOT_ORIGIN
    xba
    lsr
    clc
    adc.w #0x0004
    tay
    sep #0x20
    jsr.l draw_item_slot_inner_trampoline
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

update_sell_scroll_hdma:
"""
Builds the HDMA shadow table: row r shows slot (buffer_pos + r) mod 9 at BG3VOFS base_scroll + (slot - r) * 16.
"""


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
    jsr.w _sell_hdma_header
    stz.b 0x42

_sell_row_loop:
    lda.w sell_rolling.buffer_pos
    and.w #0x00FF
    clc
    adc.b 0x42

_sell_mod_loop:
    cmp.w #_SELL_BUFFER_SLOTS
    bcc _sell_mod_done
    sec
    sbc.w #_SELL_BUFFER_SLOTS
    bra _sell_mod_loop

_sell_mod_done:
    asl
    asl
    asl
    asl  ; slot * 16
    sta.b 0x40
    lda.b 0x42
    and.w #0x00FF
    asl
    asl
    asl
    asl  ; row * 16
    eor.w #0xFFFF
    inc  ; -row * 16
    clc
    adc.b 0x40
    clc
    adc.w sell_rolling.base_scroll
    sta.b 0x40
    sep #0x20
    lda #16
    sta.l SELL_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.b 0x40
    sta.l SELL_HDMA_SHADOW, x
    inx
    inx
    inc.b 0x42
    lda.b 0x42
    cmp.w #_SELL_VISIBLE_ITEMS
    bcs _sell_row_loop_done
    jmp.w _sell_row_loop

_sell_row_loop_done:
    jsr.w _sell_hdma_footer
    sep #0x20
    lda #0x00
    sta.l SELL_HDMA_SHADOW, x
    jsr.w _sell_hdma_signal
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

_sell_hdma_header:
"""Header: 88 lines above the list at base_scroll."""
    sep #0x20
    lda #88
    sta.l SELL_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w sell_rolling.base_scroll
    sta.l SELL_HDMA_SHADOW, x
    inx
    inx
    rts

_sell_hdma_footer:
"""Footer: 16 lines at base_scroll for the bottom border."""
    sep #0x20
    lda #16
    sta.l SELL_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w sell_rolling.base_scroll
    sta.l SELL_HDMA_SHADOW, x
    inx
    inx
    rts

_sell_hdma_signal:
"""Sets hdma_copy_pending for the NMI shadow copy."""
    sep #0x20
    lda #0x01
    sta.l sell_rolling.hdma_copy_pending
    rts

_sell_draw_window:
"""Pre-render hook: SelectBG3 + DrawWindow so $D600 holds a fresh window."""
    sep #0x20
    jsr.l sell_select_bg3_trampoline
    rep #0x10
    ldy.w #0xDCCE  ; the window $01:A172 itself draws
    jsr.l draw_window_trampoline
    sep #0x10
    rts

sell_init_impl:
"""
Replaces `DrawInventoryList` for the sell list: configures the profile and lets the engine draw the ring.
"""


    php
    rep #0x30
    sep #0x20
    lda.b #_SELL_VISIBLE_ITEMS
    sta.l sell_rolling.visible_rows
    lda.b #0x02
    sta.l sell_rolling.slot_height_tiles
    lda.b #0x40
    sta.l sell_rolling.item_list_ptr
    lda.b #0x14
    sta.l sell_rolling.item_list_ptr + 1
    lda.b #0x7E
    sta.l sell_rolling.item_list_ptr + 2
    lda.b #_SELL_TOTAL_ITEMS
    sta.l sell_rolling.item_count
    lda.b #0x05
    sta.l sell_rolling.hdma_channel
    lda.b #0x80
    sta.l sell_rolling.vwf_cfg_ptr
    lda.b #0x70
    sta.l sell_rolling.vwf_cfg_ptr + 1
    lda.b #0x70
    sta.l sell_rolling.vwf_cfg_ptr + 2
    lda.b #_sell_fn_render_slot_trampoline & 0xFF
    sta.l sell_rolling.fn_render_slot
    lda.b #( _sell_fn_render_slot_trampoline >> 8 ) & 0xFF
    sta.l sell_rolling.fn_render_slot + 1
    lda.b #( _sell_fn_render_slot_trampoline >> 16 ) & 0xFF
    sta.l sell_rolling.fn_render_slot + 2
    lda.b #_sell_fn_update_hdma_trampoline & 0xFF
    sta.l sell_rolling.fn_update_hdma
    lda.b #( _sell_fn_update_hdma_trampoline >> 8 ) & 0xFF
    sta.l sell_rolling.fn_update_hdma + 1
    lda.b #( _sell_fn_update_hdma_trampoline >> 16 ) & 0xFF
    sta.l sell_rolling.fn_update_hdma + 2
    lda.b #_sell_fn_draw_window_trampoline & 0xFF
    sta.l sell_rolling.fn_draw_window
    lda.b #( _sell_fn_draw_window_trampoline >> 8 ) & 0xFF
    sta.l sell_rolling.fn_draw_window + 1
    lda.b #( _sell_fn_draw_window_trampoline >> 16 ) & 0xFF
    sta.l sell_rolling.fn_draw_window + 2
    lda.b #ROLLING_MENU_ID_SELL
    sta.l sell_rolling.menu_id
    rep #0x20
    lda.w #0xFFFF
    sta.l sell_rolling.base_scroll
    plp
    php
    rep #0x10
    ldx.w #sell_rolling
    jsr.l rolling_engine.rolling_engine_init
    jsr.w _sell_ensure_hdma_initialized
    sep #0x20
    jsr.l tfr_bg3_tiles_vblank_trampoline
    plp
    rtl

_sell_fn_render_slot_trampoline:
"""Bank-20 RTL wrapper around `_sell_render_item_to_slot`."""
    php
    jsr.w _sell_render_item_to_slot
    plp
    rtl

_sell_fn_update_hdma_trampoline:
"""
Bank-20 RTL wrapper: arms ch5 once, rebuilds the band table on every call.
"""


    php
    jsr.w _sell_ensure_hdma_initialized
    jsr.w update_sell_scroll_hdma
    plp
    rtl

_sell_fn_draw_window_trampoline:
"""Bank-20 RTL wrapper around `_sell_draw_window`."""
    php
    jsr.w _sell_draw_window
    plp
    rtl

_sell_run_scroll:
"""
Runs one item's scroll to completion, blocking 8 frames like vanilla ($01:C8E3 / $01:C91C).

The frame counter lives in `_pad`: `scroll_state` stays set until `rolling_engine_finish_scroll`, so it cannot
end the loop.
"""


    php
    rep #0x10
    sep #0x20
    lda #_SELL_SCROLL_FRAMES
    sta.l sell_rolling._pad

_sell_scroll_frame:
    jsr.l wait_for_vblank_long
    ldx.w #sell_rolling
    jsr.l rolling_engine.rolling_engine_update_scroll_frame
    sep #0x20
    lda.l sell_rolling._pad
    dec
    sta.l sell_rolling._pad
    bne _sell_scroll_frame
; 8-bit A required: a 16-bit A wedges the engine and `TfrBG3TilesVblank`.
    sep #0x20
    rep #0x10
    lda.l _SELL_SCROLL_POS
    ldx.w #sell_rolling
    jsr.l rolling_engine.rolling_engine_finish_scroll
    sep #0x20
    jsr.l tfr_bg3_tiles_vblank_trampoline
    plp
    rts

sell_scroll_down_impl:
"""Scrolls the list down one item."""
    php
    rep #0x10
    lda.l _SELL_SCROLL_POS
    ldx.w #sell_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_down
    jsr.w _sell_run_scroll
    plp
    rtl

sell_scroll_up_impl:
"""Scrolls the list up one item."""
    php
    rep #0x10
    lda.l _SELL_SCROLL_POS
    ldx.w #sell_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_up
    jsr.w _sell_run_scroll
    plp
    rtl

_sell_refresh_slots_impl:
"""Re-renders every slot (after a sale changes quantities)."""
    php
    sep #0x20
    rep #0x10
    lda.l _SELL_SCROLL_POS
    ldx.w #sell_rolling
    jsr.l rolling_engine.rolling_engine_refresh_slots
    jsr.l tfr_bg3_tiles_vblank_trampoline
    plp
    rtl
}
