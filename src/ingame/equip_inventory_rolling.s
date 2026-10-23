"""
Equip-screen inventory list rolling buffer: 7-slot ring (6 visible + 1 prefetch) in the BG4 buffer at $7E:C600,
BG4VOFS driven per scanline by HDMA ch5. Same shape as shop_sell_rolling.s.

Replaces vanilla `DrawInventoryList` ($01:A172), which draws the whole list two items per row. The equip
screen uses no HDMA and never shows with the items list or a shop, so ch5 is free.
"""


.import "core/preamble"
.include "core/bank20.i"
.import "core/items"

.import "ingame/vanilla_trampolines"
.import "core/libmz"
.import "lib/rolling_inventory_engine"
.import "core/vanilla"

_EQUIP_VISIBLE_ITEMS := EQUIP_LIST_VISIBLE_ROWS
_EQUIP_BUFFER_SLOTS := _EQUIP_VISIBLE_ITEMS + 1
_EQUIP_TOTAL_ITEMS := EQUIP_LIST_TOTAL_ITEMS

; Vanilla's equip-list scroll position (first visible row), where its ($57) pointer resolves on this screen.
_EQUIP_SCROLL_POS := 0x7E1B2A

; HDMA ch5 driving BG4VOFS.
_EQUIP_HDMA_ENABLE_BIT := 0x20

; HDMA table ($9800 field, $9880 drops, $9900 sell / key items).
_EQUIP_HDMA_TABLE_ADDR := 0x9980
_EQUIP_HDMA_BANK := 0x7E
EQUIP_HDMA_SHADOW := 0x7E99C0

; Window in the BG4 buffer: top border on tile row 0, ring on rows 1..14, bottom border on row 24.
_EQUIP_BG4_BUFFER := 0xC600
_EQUIP_SLOT_BYTES := 0x80  ; two 32-tile tilemap rows
_EQUIP_SLOT_ORIGIN := EQUIP_LIST_ORIGIN_LINES * 8  ; byte offset of slot 0: a tile row is 8 lines, $40 bytes
_EQUIP_SLOT_PIXELS := 16
_EQUIP_NAME_OFFSET := 0x0004  ; icon at tile column 2

; Blank window cell and the side borders in the first and last columns.
_EQUIP_BLANK_TILE := 0xFF
_EQUIP_TILEMAP_ATTR := 0x00
_EQUIP_BORDER_LEFT_TILE := 0xFA
_EQUIP_BORDER_RIGHT_TILE := 0xFB
_EQUIP_BORDER_RIGHT_COL := 31

; Vanilla's BG4VOFS for the window ($99 = scroll * 16 + $FF98 at $01:BE95). The header ends after the top border.
_EQUIP_BASE_SCROLL := EQUIP_LIST_BASE_SCROLL
_EQUIP_HEADER_LINES := EQUIP_LIST_FIRST_ROW_Y
; Footer: the rest of the 224 lines, scrolled to show buffer row 24 (the off-screen bottom border) right under
; the last row, so the prefetch slot never shows.
_EQUIP_WINDOW_BOTTOM_ROW := 24
_EQUIP_FOOTER_TOP := _EQUIP_HEADER_LINES + _EQUIP_VISIBLE_ITEMS * _EQUIP_SLOT_PIXELS
_EQUIP_FOOTER_LINES := 224 - _EQUIP_FOOTER_TOP
_EQUIP_FOOTER_SCROLL := _EQUIP_WINDOW_BOTTOM_ROW * 8 - _EQUIP_FOOTER_TOP + 0x10000 - _EQUIP_BASE_SCROLL
; header + 6 row bands + footer + terminator, rounded to words.
EQUIP_HDMA_TABLE_SIZE := 26

; Vanilla's cadence: 8 frames of 2 px per item.
_EQUIP_SCROLL_FRAMES := 8

; InventoryWindow, the window $01:A172 draws.
_INVENTORY_WINDOW := 0xDCCE

.alloc _equip_rolling_block in bank20_reloc {
_equip_ensure_hdma_initialized:
"""
One-shot: sets base_scroll, configures ch5 -> BG4VOFS and arms it. Long addressing: entered with the caller's DB.
"""


    rep #0x20
    lda.l equip_rolling.base_scroll
    cmp.w #0xFFFF
    bne _equip_hdma_already_init
    lda.w #_EQUIP_BASE_SCROLL
    sta.l equip_rolling.base_scroll

    sep #0x20
    lda #0x02  ; direct mode, 2 bytes per write
    sta.l dma_ch5.DMAP
    lda #PPU.BG4VOFS
    sta.l dma_ch5.BBAD
    rep #0x20
    lda.w #_EQUIP_HDMA_TABLE_ADDR
    sta.l dma_ch5.A1TL
    sep #0x20
    lda #_EQUIP_HDMA_BANK
    sta.l dma_ch5.A1B

; Arm ch5 via the shared signal the NMI hook ORs into $420C.
    lda.l field_menu_rolling.hdma_enable
    ora #_EQUIP_HDMA_ENABLE_BIT
    sta.l field_menu_rolling.hdma_enable
    sta.l equip_rolling.hdma_enable
    jsr.w update_equip_scroll_hdma
    rts

_equip_hdma_already_init:
    sep #0x20
    rts

equip_disable_hdma:
"""Disarms ch5 when the list closes."""
    php
    sep #0x20
    lda.l field_menu_rolling.hdma_enable
    and #0xDF  ; ~_EQUIP_HDMA_ENABLE_BIT, spelled out: `^` is a816's bank-byte operator
    sta.l field_menu_rolling.hdma_enable
    lda #0x00
    sta.l equip_rolling.hdma_enable
    rep #0x20
    lda.w #0xFFFF
    sta.l equip_rolling.base_scroll
    plp
    rtl

_equip_blank_slot_rows:
"""
Blanks this slot's two tilemap rows (borders kept). Entry: 16-bit A/X/Y, DB = $7E.
"""


    rep #0x30
    lda.l equip_rolling.slot_index
    and.w #0x00FF
    xba
    lsr  ; slot * _EQUIP_SLOT_BYTES
    clc
    adc.w #_EQUIP_BG4_BUFFER + _EQUIP_SLOT_ORIGIN
    tax
    ldy.w #_EQUIP_SLOT_BYTES >> 1  ; cells in two 32-tile rows

_equip_blank_cell:
    jsr.w _equip_window_cell
    sta.w 0x0000, x
    inx
    inx
    dey
    bne _equip_blank_cell
    rts

_equip_window_cell:
"""
Blank window cell (border or body) for buffer offset X. Entry/exit: 16-bit A/X; returns the cell word in A.
"""


    txa
    and.w #0x003F
    lsr
    beq _equip_cell_left
    cmp.w #_EQUIP_BORDER_RIGHT_COL
    beq _equip_cell_right
    lda.w #( _EQUIP_TILEMAP_ATTR << 8 ) | _EQUIP_BLANK_TILE
    rts

_equip_cell_left:
    lda.w #( _EQUIP_TILEMAP_ATTR << 8 ) | _EQUIP_BORDER_LEFT_TILE
    rts

_equip_cell_right:
    lda.w #( _EQUIP_TILEMAP_ATTR << 8 ) | _EQUIP_BORDER_RIGHT_TILE
    rts

_equip_render_item_to_slot:
"""
Renders inventory item `edge_row` ($7E:1440) into $7E:C600 + _EQUIP_SLOT_ORIGIN + slot * 128 + 4, greyed when
the character cannot equip it.
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
    lda.w #_EQUIP_BG4_BUFFER
    sta.b menu_dp.tilemap_offset
    jsr.w _equip_blank_slot_rows
    sep #0x20

; At the bottom the prefetch slot is past the list: nothing to draw.
    lda.w equip_rolling.edge_row
    cmp #_EQUIP_TOTAL_ITEMS
    bcs _equip_render_done

; Item pointer = $7E:1440 + edge_row * 2
    lda.w equip_rolling.edge_row
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

; Primary VWF tile window ($100..); the equip names above use the drops region.
    lda.w equip_rolling.slot_index
    sta.b menu_dp.item_slot
    rep #0x20
    lda.w equip_rolling.slot_index
    and.w #0x00FF
    xba
    lsr  ; slot * _EQUIP_SLOT_BYTES
    clc
    adc.w #_EQUIP_SLOT_ORIGIN + _EQUIP_NAME_OFFSET
    tay
    sep #0x20
    jsr.l draw_item_slot_inner_trampoline

_equip_render_done:
    sep #0x20
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

update_equip_scroll_hdma:
"""
Builds the HDMA shadow table: row r shows slot (buffer_pos + r) mod 7 at BG4VOFS base_scroll + (slot - r) * 16.
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
        lda.w #_EQUIP_HEADER_LINES
        jsr.w _equip_hdma_base_band
        stz.b 0x42

_equip_row_loop:
        lda.w equip_rolling.buffer_pos
        and.w #0x00FF
        clc
        adc.b 0x42

_equip_mod_loop:
        cmp.w #_EQUIP_BUFFER_SLOTS
        bcc _equip_mod_done
        sec
        sbc.w #_EQUIP_BUFFER_SLOTS
        bra _equip_mod_loop

_equip_mod_done:
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
        adc.w equip_rolling.base_scroll
        sta.b 0x40
        sep #0x20
        lda #_EQUIP_SLOT_PIXELS
        sta.l EQUIP_HDMA_SHADOW, x
        inx
        rep #0x20
        lda.b 0x40
        sta.l EQUIP_HDMA_SHADOW, x
        inx
        inx
        inc.b 0x42
        lda.b 0x42
        cmp.w #_EQUIP_VISIBLE_ITEMS
        bcs _equip_row_loop_done
        jmp.w _equip_row_loop

_equip_row_loop_done:
        sep #0x20
        lda #_EQUIP_FOOTER_LINES
        sta.l EQUIP_HDMA_SHADOW, x
        inx
        rep #0x20
        lda.w equip_rolling.base_scroll
        clc
        adc.w #_EQUIP_FOOTER_SCROLL
        sta.l EQUIP_HDMA_SHADOW, x
        inx
        inx
        sep #0x20
        lda #0x00
        sta.l EQUIP_HDMA_SHADOW, x
        lda #0x01
        sta.l equip_rolling.hdma_copy_pending
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

_equip_hdma_base_band:
"""
One band of A lines at base_scroll. Entry: 16-bit A = line count, X = shadow offset.
"""


    sep #0x20
    sta.l EQUIP_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w equip_rolling.base_scroll
    sta.l EQUIP_HDMA_SHADOW, x
    inx
    inx
    rts

_equip_draw_window:
"""Pre-render hook: SelectBG4 + DrawWindow so $C600 holds a fresh window."""
    sep #0x20
    jsr.l equip_select_bg4_trampoline
    rep #0x10
    ldy.w #_INVENTORY_WINDOW
    jsr.l draw_window_trampoline
    sep #0x10
    rts

equip_init_impl:
"""
Replaces `DrawInventoryList` for the equip list: configures the profile, inits the ring, then re-renders it at
the scroll position kept from the last visit.
"""


    php
    rep #0x30
    sep #0x20
    lda.b #_EQUIP_VISIBLE_ITEMS
    sta.l equip_rolling.visible_rows
    lda.b #0x02
    sta.l equip_rolling.slot_height_tiles
    lda.b #0x40
    sta.l equip_rolling.item_list_ptr
    lda.b #0x14
    sta.l equip_rolling.item_list_ptr + 1
    lda.b #0x7E
    sta.l equip_rolling.item_list_ptr + 2
    lda.b #_EQUIP_TOTAL_ITEMS
    sta.l equip_rolling.item_count
    lda.b #0x05
    sta.l equip_rolling.hdma_channel
    lda.b #0x80
    sta.l equip_rolling.vwf_cfg_ptr
    lda.b #0x70
    sta.l equip_rolling.vwf_cfg_ptr + 1
    lda.b #0x70
    sta.l equip_rolling.vwf_cfg_ptr + 2
    lda.b #_equip_fn_render_slot_trampoline & 0xFF
    sta.l equip_rolling.fn_render_slot
    lda.b #( _equip_fn_render_slot_trampoline >> 8 ) & 0xFF
    sta.l equip_rolling.fn_render_slot + 1
    lda.b #( _equip_fn_render_slot_trampoline >> 16 ) & 0xFF
    sta.l equip_rolling.fn_render_slot + 2
    lda.b #_equip_fn_update_hdma_trampoline & 0xFF
    sta.l equip_rolling.fn_update_hdma
    lda.b #( _equip_fn_update_hdma_trampoline >> 8 ) & 0xFF
    sta.l equip_rolling.fn_update_hdma + 1
    lda.b #( _equip_fn_update_hdma_trampoline >> 16 ) & 0xFF
    sta.l equip_rolling.fn_update_hdma + 2
    lda.b #_equip_fn_draw_window_trampoline & 0xFF
    sta.l equip_rolling.fn_draw_window
    lda.b #( _equip_fn_draw_window_trampoline >> 8 ) & 0xFF
    sta.l equip_rolling.fn_draw_window + 1
    lda.b #( _equip_fn_draw_window_trampoline >> 16 ) & 0xFF
    sta.l equip_rolling.fn_draw_window + 2
    lda.b #ROLLING_MENU_ID_EQUIP
    sta.l equip_rolling.menu_id
    rep #0x20
    lda.w #0xFFFF
    sta.l equip_rolling.base_scroll
    plp
    php
    rep #0x10
    ldx.w #equip_rolling
    jsr.l rolling_engine.rolling_engine_init
    jsr.w _equip_ensure_hdma_initialized
; Init draws items 0..5; redraw from the kept scroll position.
    sep #0x20
    rep #0x10
    lda.l _EQUIP_SCROLL_POS
    ldx.w #equip_rolling
    jsr.l rolling_engine.rolling_engine_refresh_slots
    sep #0x20
    jsr.l tfr_bg4_tiles_vblank_trampoline
    plp
    rtl

_equip_fn_render_slot_trampoline:
"""Bank-20 RTL wrapper around `_equip_render_item_to_slot`."""
    php
    jsr.w _equip_render_item_to_slot
    plp
    rtl

_equip_fn_update_hdma_trampoline:
"""Bank-20 RTL wrapper: arms ch5 once, rebuilds the band table on every call."""
    php
    jsr.w _equip_ensure_hdma_initialized
    jsr.w update_equip_scroll_hdma
    plp
    rtl

_equip_fn_draw_window_trampoline:
"""Bank-20 RTL wrapper around `_equip_draw_window`."""
    php
    jsr.w _equip_draw_window
    plp
    rtl

_equip_run_scroll:
"""
Runs one item's scroll to completion in vanilla's 8 frames, then pushes BG4. Frame count in `_pad`, as for sell.
"""


    php
    rep #0x10
    sep #0x20
    lda #_EQUIP_SCROLL_FRAMES
    sta.l equip_rolling._pad

_equip_scroll_frame:
    jsr.l wait_for_vblank_long
    ldx.w #equip_rolling
    jsr.l rolling_engine.rolling_engine_update_scroll_frame
    sep #0x20
    lda.l equip_rolling._pad
    dec
    sta.l equip_rolling._pad
    bne _equip_scroll_frame
    sep #0x20
    rep #0x10
    lda.l _EQUIP_SCROLL_POS
    ldx.w #equip_rolling
    jsr.l rolling_engine.rolling_engine_finish_scroll
    sep #0x20
    jsr.l tfr_bg4_tiles_vblank_trampoline
    plp
    rts

equip_scroll_down_impl:
"""Scrolls the list down one item."""
    php
    rep #0x10
    lda.l _EQUIP_SCROLL_POS
    ldx.w #equip_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_down
    jsr.w _equip_run_scroll
    plp
    rtl

equip_scroll_up_impl:
"""Scrolls the list up one item."""
    php
    rep #0x10
    lda.l _EQUIP_SCROLL_POS
    ldx.w #equip_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_up
    jsr.w _equip_run_scroll
    plp
    rtl
}
