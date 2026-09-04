"""
Shop sell-list rolling buffer (single column, 8 visible).

The sell list is the player's own inventory, drawn by vanilla
`DrawInventoryList` ($01:A172) into the BG3 buffer at $7E:D600 and
scrolled by moving BG3VOFS ($9F) over it - vanilla lays the whole
48-item list down once, two items per 16-byte row, and never redraws.

That model cannot survive single-column VWF rows: ours are 128 bytes
each (two 32-tile tilemap rows), so 48 of them want 6 KB against a
2 KB buffer. Worse, `DrawItemSlot` is globally patched to single-column
(`$01:A1F0` col mask, `$01:A1BA` slot calc) while $A172 still walks the
array two items at a time, so the sell list rendered every second item
and stopped after six.

So sell gets its own profile, same shape as the other three: a 9-slot
ring (8 visible + 1 pre-render) in the BG3 buffer, with BG3VOFS driven
per scanline by HDMA so the ring wraps invisibly. The shop enables no
HDMA of its own - `hdma_enable_hook` at $01:8081 is the only writer of
$420C while a shop is open, and it runs 128 times across an open/sell
round trip - so channel 5 is free and the shared
`field_menu_rolling.hdma_enable` signal arms it exactly as it does for
the field menu.
"""

.include "../bank20.i"
.include "config.i"

SELL_VISIBLE_ITEMS := 8
SELL_BUFFER_SLOTS := 9
SELL_TOTAL_ITEMS := 48

; State block in the shared $7E:99xx arena, past drops ($9C30) and the
; key-item picker ($9C60); the field profile sits at $9C90.
sell_rolling := (0x7E9CC0 as RollingBufferState)

; Vanilla's own sell scroll position ($1B96, "first visible row") and
; cursor row ($1B94). The profile reads them rather than keeping its
; own copy so vanilla's bounds checks stay authoritative.
SELL_SCROLL_POS := 0x7E1B96

; HDMA channel 5 driving BG3VOFS ($2112). Nothing else in the shop
; touches HDMA.
SELL_HDMA5_CTRL := 0x4350
SELL_HDMA5_DEST := 0x4351
SELL_HDMA5_SRC_LO := 0x4352
SELL_HDMA5_SRC_HI := 0x4353
SELL_HDMA5_SRC_BANK := 0x4354
SELL_HDMA_ENABLE_BIT := 0x20

; Own table slot in the HDMA scratch area ($9800 treasure, $9880 drops).
SELL_HDMA_TABLE_ADDR := 0x9900
SELL_HDMA_SHADOW_ADDR := 0x9940
SELL_HDMA_BANK := 0x7E
SELL_HDMA_SHADOW := 0x7E9940
SELL_HDMA_TABLE := 0x7E9900

; BG3 buffer, and the window vanilla's $A172 draws into it: top border
; on buffer slot 0, body from slot 1, bottom border on slot 12. The ring
; therefore occupies slots 1..9, one 128-byte slot per item.
SELL_BG3_BUFFER := 0xD600
SELL_SLOT_ORIGIN := 1

; Blank window cell, as every drawn window leaves it in the buffer.
SELL_BLANK_TILE := 0xFF
SELL_TILEMAP_ATTR := 0x00

; BG3VOFS with the window frame parked where vanilla puts it: vanilla
; seeds $9F with $FFB8 at $01:C7C1.
SELL_BASE_SCROLL := 0xFFB8

; Vanilla's scroll cadence: 8 frames of 2px for one 16px item.
SELL_SCROLL_FRAMES := 8

.alloc sell_rolling_block in bank20_reloc {

sell_ensure_hdma_initialized:
"""
Lazy init: park base_scroll and configure ch5 driving BG3VOFS.

Long addressing throughout - the engine's `_engine_call_hook` enters
with the caller's DB, so absolute reads would land in ROM.
"""
    rep #0x20
    lda.l sell_rolling.base_scroll
    cmp.w #0xFFFF
    bne _sell_hdma_already_init
    lda.w #SELL_BASE_SCROLL
    sta.l sell_rolling.base_scroll

    sep #0x20
    lda #0x02          ; direct mode, 2 bytes per write
    sta.l SELL_HDMA5_CTRL
    lda #0x12          ; BG3VOFS
    sta.l SELL_HDMA5_DEST
    rep #0x20
    lda.w #SELL_HDMA_TABLE_ADDR
    sta.l SELL_HDMA5_SRC_LO
    sep #0x20
    lda #SELL_HDMA_BANK
    sta.l SELL_HDMA5_SRC_BANK

; Arm ch5 through the shared menu-HDMA signal the NMI hook ORs into
; $420C, and mark this profile's own gate.
    lda.l field_menu_rolling.hdma_enable
    ora #SELL_HDMA_ENABLE_BIT
    sta.l field_menu_rolling.hdma_enable
    sta.l sell_rolling.hdma_enable
    jsr.w update_sell_scroll_hdma
    rts

_sell_hdma_already_init:
    sep #0x20
    rts

sell_disable_hdma:
"""Drop ch5 again on the way out of the sell list."""
    php
    sep #0x20
    lda.l field_menu_rolling.hdma_enable
    and #0xDF          ; ~SELL_HDMA_ENABLE_BIT, spelled out: `^` is a816's bank-byte operator, not xor
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
Wipe this slot's two tilemap rows to the window's blank cell.

`DrawItemSlot` writes only the cells it draws - the name, the colon and
the quantity digits - so anything else in the row keeps what the
previous occupant left there. On a rolling ring that is the item that
used to live in this slot, which shows up as fragments of a longer name
trailing a shorter one.

Entry: 16-bit A/X/Y, DB = $7E.
"""
    rep #0x30
    lda.l sell_rolling.slot_index
    and.w #0x00FF
    clc
    adc.w #SELL_SLOT_ORIGIN
    xba
    lsr                ; (slot + 1) * 128
    clc
    adc.w #SELL_BG3_BUFFER
    tax
    lda.w #( SELL_TILEMAP_ATTR << 8 ) | SELL_BLANK_TILE
    ldy.w #0x0040      ; 64 cells = two 32-tile rows

_sell_blank_cell:
    sta.w 0x0000, x
    inx
    inx
    dey
    bne _sell_blank_cell
    rts

sell_render_item_to_slot:
"""
Render inventory item `edge_row` into ring slot `slot_index`.

Item data comes from the vanilla inventory array at $7E:1440; the
tilemap goes to the BG3 buffer at ($7E:D600) + (slot + 1) * 128 + 4,
one slot below the window's top border.
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
    lda.b 0x5a
    pha
    lda.b 0x29
    pha
    lda.b 0x45
    pha
    lda.b 0x33
    pha
    sep #0x20
    lda.b 0x5d
    pha
    lda.b 0xDB
    pha
    rep #0x20
    lda.w #SELL_BG3_BUFFER
    sta.b 0x29
    jsr.w _sell_blank_slot_rows
    sep #0x20

; Item pointer = $7E:1440 + edge_row * Item.__size
    lda.w sell_rolling.edge_row
    asl
    clc
    adc #0x40
    sta.b 0x5a
    lda #0x14
    adc #0x00
    sta.b 0x5b
    rep #0x20
    lda.b 0x5a
    tax
    sep #0x20
    lda.l 0x7E0000 + Item.id, x
    pha
    lda.l 0x7E0000 + Item.qty, x
    sta.b 0x5C
    stz.b 0x34
    pla
    jsr.l check_can_use_item_trampoline

; The sell list is the only rolling menu on screen, so it takes the
; primary VWF tile window unshifted: 9 slots * 10 tiles fits the
; $0700-byte primary flush descriptor.
    lda.w sell_rolling.slot_index
    sta.b 0x5d
    rep #0x20
    lda.w sell_rolling.slot_index
    and.w #0x00FF
    clc
    adc.w #SELL_SLOT_ORIGIN
    xba
    lsr
    clc
    adc.w #0x0004
    tay
    sep #0x20
    jsr.l draw_item_slot_inner_trampoline
    pla
    sta.b 0xDB
    pla
    sta.b 0x5d
    rep #0x20
    pla
    sta.b 0x33
    pla
    sta.b 0x45
    pla
    sta.b 0x29
    pla
    sta.b 0x5a
    rep #0x10
    ply
    plx
    pla
    plb
    plp
    rts

update_sell_scroll_hdma:
"""
Build the sell HDMA shadow table: one band per visible row.

Row r shows ring slot (buffer_pos + r) mod 9, whose content sits at BG
line (slot + 1) * 16. The band's BG3VOFS is therefore
`base_scroll + slot * 16 - r * 16`, the same body math the drops and
treasure profiles use.
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
    lda.w sell_rolling + RollingBufferState.buffer_pos
    and.w #0x00FF
    clc
    adc.b 0x42

_sell_mod_loop:
    cmp.w #SELL_BUFFER_SLOTS
    bcc _sell_mod_done
    sec
    sbc.w #SELL_BUFFER_SLOTS
    bra _sell_mod_loop

_sell_mod_done:
    asl
    asl
    asl
    asl                ; slot * 16
    sta.b 0x40
    lda.b 0x42
    and.w #0x00FF
    asl
    asl
    asl
    asl                ; row * 16
    eor.w #0xFFFF
    inc                ; -row * 16
    clc
    adc.b 0x40
    clc
    adc.w sell_rolling + RollingBufferState.base_scroll
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
    cmp.w #SELL_VISIBLE_ITEMS
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
"""Header: the 88 lines above the list - offscreen rows plus the window's top border - held at base_scroll."""
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
"""Footer: 16 lines back at base_scroll so the window's bottom border lands where vanilla drew it."""
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
"""Ask the menu NMI hook to copy shadow to active during the next vblank."""
    sep #0x20
    lda #0x01
    sta.l sell_rolling.hdma_copy_pending
    rts

_sell_draw_window:
"""Pre-render hook: SelectBG3 + DrawWindow(inventory window) so $29 = $D600 holds a fresh frame."""
    sep #0x20
    jsr.l sell_select_bg3_trampoline
    rep #0x10
    ldy.w #0xDCCE      ; the window $01:A172 itself draws
    jsr.l draw_window_trampoline
    sep #0x10
    rts

sell_init_impl:
"""
Replace vanilla `DrawInventoryList` for the sell list: configure the
profile and let the engine draw the ring.
"""
    php
    rep #0x30
    sep #0x20
    lda.b #SELL_VISIBLE_ITEMS
    sta.l sell_rolling + RollingBufferState.visible_rows
    lda.b #0x02
    sta.l sell_rolling + RollingBufferState.slot_height_tiles
    lda.b #0x40
    sta.l sell_rolling + RollingBufferState.item_list_ptr
    lda.b #0x14
    sta.l sell_rolling + RollingBufferState.item_list_ptr + 1
    lda.b #0x7E
    sta.l sell_rolling + RollingBufferState.item_list_ptr + 2
    lda.b #SELL_TOTAL_ITEMS
    sta.l sell_rolling + RollingBufferState.item_count
    lda.b #0x05
    sta.l sell_rolling + RollingBufferState.hdma_channel
    lda.b #0x80
    sta.l sell_rolling + RollingBufferState.vwf_cfg_ptr
    lda.b #0x70
    sta.l sell_rolling + RollingBufferState.vwf_cfg_ptr + 1
    lda.b #0x70
    sta.l sell_rolling + RollingBufferState.vwf_cfg_ptr + 2
    lda.b #sell_fn_render_slot_trampoline & 0xFF
    sta.l sell_rolling + RollingBufferState.fn_render_slot
    lda.b #( sell_fn_render_slot_trampoline >> 8 ) & 0xFF
    sta.l sell_rolling + RollingBufferState.fn_render_slot + 1
    lda.b #( sell_fn_render_slot_trampoline >> 16 ) & 0xFF
    sta.l sell_rolling + RollingBufferState.fn_render_slot + 2
    lda.b #sell_fn_update_hdma_trampoline & 0xFF
    sta.l sell_rolling + RollingBufferState.fn_update_hdma
    lda.b #( sell_fn_update_hdma_trampoline >> 8 ) & 0xFF
    sta.l sell_rolling + RollingBufferState.fn_update_hdma + 1
    lda.b #( sell_fn_update_hdma_trampoline >> 16 ) & 0xFF
    sta.l sell_rolling + RollingBufferState.fn_update_hdma + 2
    lda.b #sell_fn_draw_window_trampoline & 0xFF
    sta.l sell_rolling + RollingBufferState.fn_draw_window
    lda.b #( sell_fn_draw_window_trampoline >> 8 ) & 0xFF
    sta.l sell_rolling + RollingBufferState.fn_draw_window + 1
    lda.b #( sell_fn_draw_window_trampoline >> 16 ) & 0xFF
    sta.l sell_rolling + RollingBufferState.fn_draw_window + 2
    lda.b #ROLLING_MENU_ID_SELL
    sta.l sell_rolling + RollingBufferState.menu_id
    rep #0x20
    lda.w #0xFFFF
    sta.l sell_rolling.base_scroll
    plp
    php
    rep #0x10
    ldx.w #sell_rolling
    jsr.l rolling_engine.rolling_engine_init
    jsr.w sell_ensure_hdma_initialized
    sep #0x20
    jsr.l tfr_bg3_tiles_vblank_trampoline
    plp
    rtl

sell_fn_render_slot_trampoline:
"""Bank-20 RTL wrapper around `sell_render_item_to_slot`."""
    php
    jsr.w sell_render_item_to_slot
    plp
    rtl

sell_fn_update_hdma_trampoline:
"""
Bank-20 RTL wrapper: arm ch5 on the first call, rebuild the band table
on every one.

`sell_ensure_hdma_initialized` is a one-shot - it bails as soon as
base_scroll is set - so calling only that left the table holding the
offsets from the frame the list opened on, and the ring rolled
underneath a scroll that never moved.
"""
    php
    jsr.w sell_ensure_hdma_initialized
    jsr.w update_sell_scroll_hdma
    plp
    rtl

sell_fn_draw_window_trampoline:
"""Bank-20 RTL wrapper around `_sell_draw_window`."""
    php
    jsr.w _sell_draw_window
    plp
    rtl

_sell_run_scroll:
"""
Run one item's worth of scroll animation to completion.

Vanilla's own loops at $01:C8E3 / $01:C91C spend 8 frames moving $9F by
2px; the engine's state machine keeps that cadence, so the replacement
blocks for the same 8 frames and the shop's input loop sees no change
in timing.

The frame count lives in the profile's own spare byte rather than in
the SRAM pool - the loop has to survive whatever the engine leaves in
the registers, and a counter that reads back wrong never terminates.
It is kept here rather than read back off the engine:
`rolling_engine_update_scroll_frame` only winds `scroll_remaining`
down and leaves `scroll_state` set for `rolling_engine_finish_scroll`
to clear, so a loop waiting on the state never exits and one waiting on
`scroll_remaining` has to know the per-frame step anyway.
"""
    php
    rep #0x10
    sep #0x20
    lda #SELL_SCROLL_FRAMES
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
; 8-bit A from here on: the engine takes the scroll position in A, and
; `TfrBG3TilesVblank` is vanilla bank-$01 code that runs its chunked DMA
; with an 8-bit accumulator - handing either a 16-bit A wedges the loop.
    sep #0x20
    rep #0x10
    lda.l SELL_SCROLL_POS
    ldx.w #sell_rolling
    jsr.l rolling_engine.rolling_engine_finish_scroll
    sep #0x20
    jsr.l tfr_bg3_tiles_vblank_trampoline
    plp
    rts

sell_scroll_down_impl:
"""Sell profile: scroll the list down one item."""
    php
    rep #0x10
    lda.l SELL_SCROLL_POS
    ldx.w #sell_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_down
    jsr.w _sell_run_scroll
    plp
    rtl

sell_scroll_up_impl:
"""Sell profile: scroll the list up one item."""
    php
    rep #0x10
    lda.l SELL_SCROLL_POS
    ldx.w #sell_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_up
    jsr.w _sell_run_scroll
    plp
    rtl

sell_refresh_slots_impl:
"""Sell profile: re-render every slot (after a sale changes quantities)."""
    php
    sep #0x20
    rep #0x10
    lda.l SELL_SCROLL_POS
    ldx.w #sell_rolling
    jsr.l rolling_engine.rolling_engine_refresh_slots
    jsr.l tfr_bg3_tiles_vblank_trampoline
    plp
    rtl
}
