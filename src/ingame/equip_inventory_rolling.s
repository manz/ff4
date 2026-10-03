"""
Equip screen inventory list rolling buffer (single column, 6 visible).

Once a slot is picked, the field equip screen lists the inventory under
it: vanilla `SelectItemFromInventory` ($01:BE89) draws the whole list
once with `DrawInventoryList` ($01:A172) into the BG4 buffer at
$7E:C600, then scrolls BG4VOFS ($99) over it in blocking 8-frame loops.

That breaks the same way the shop sell list did (see
src/ingame/shop_sell_rolling.s): `DrawItemSlot` is globally patched to
single-column 128-byte rows while $A172 still walks the array two items
at a time, so only every second item rendered, the draw stopped after a
page, and scrolling just moved BG4 over blank rows.

So equip gets its own profile, same shape as sell: a 7-slot ring
(6 visible + 1 pre-render) in the BG4 buffer, with BG4VOFS driven per
scanline by HDMA so the ring wraps invisibly. The equip screen arms no
HDMA of its own and never shows alongside the field items list or a
shop, so channel 5 is free and the shared `field_menu_rolling.hdma_enable`
signal arms it, as for sell.
"""


.include "../bank20.i"
.include "config.i"
.import "items"

.extern check_can_use_item_trampoline
.extern draw_item_slot_inner_trampoline
.extern draw_window_trampoline
.extern tfr_bg4_tiles_vblank_trampoline
.extern equip_select_bg4_trampoline
.extern wait_for_vblank_long
.extern rolling_engine

EQUIP_VISIBLE_ITEMS := EQUIP_LIST_VISIBLE_ROWS
EQUIP_BUFFER_SLOTS := EQUIP_VISIBLE_ITEMS + 1
EQUIP_TOTAL_ITEMS := EQUIP_LIST_TOTAL_ITEMS

; State block in the shared $7E:9Cxx arena, after sell ($9CC0). The
; engine addresses every instance as bank $7E + X, so it cannot live in
; the cart-RAM rolling_state pool.
equip_rolling := (0x7E9CF0 as RollingBufferState)

; Vanilla's own equip-list scroll position ("first visible row"), the
; byte its ($57) pointer resolves to on this screen.
EQUIP_SCROLL_POS := 0x7E1B2A

; HDMA channel 5 driving BG4VOFS ($2114).
EQUIP_HDMA5_CTRL := 0x4350
EQUIP_HDMA5_DEST := 0x4351
EQUIP_HDMA5_SRC_LO := 0x4352
EQUIP_HDMA5_SRC_BANK := 0x4354
EQUIP_HDMA_ENABLE_BIT := 0x20
BG4VOFS_REG := 0x14

; Own table slot in the HDMA scratch area ($9800 field, $9880 drops,
; $9900 sell / key items).
EQUIP_HDMA_TABLE_ADDR := 0x9980
EQUIP_HDMA_BANK := 0x7E
EQUIP_HDMA_SHADOW := 0x7E99C0

; BG4 buffer and the window vanilla's $A172 draws into it: top border on
; buffer slot 0, body from slot 1. The ring occupies slots 1..7.
EQUIP_BG4_BUFFER := 0xC600
EQUIP_SLOT_ORIGIN := 1
EQUIP_SLOT_BYTES := 0x80  ; two 32-tile tilemap rows
EQUIP_SLOT_PIXELS := 16
EQUIP_NAME_OFFSET := 0x0004  ; icon at tile column 2

; Blank window cell and the side borders vanilla's window keeps in the
; first and last columns of every body row.
EQUIP_BLANK_TILE := 0xFF
EQUIP_TILEMAP_ATTR := 0x00
EQUIP_BORDER_LEFT_TILE := 0xFA
EQUIP_BORDER_RIGHT_TILE := 0xFB
EQUIP_BORDER_RIGHT_COL := 31

; BG4VOFS with the window frame parked where vanilla puts it: vanilla
; seeds $99 with scroll * 16 + $FF98 at $01:BE95. The header covers the
; screen down to the end of the window's top-border slot.
EQUIP_BASE_SCROLL := EQUIP_LIST_BASE_SCROLL
EQUIP_HEADER_LINES := EQUIP_LIST_FIRST_ROW_Y
; What is left of the 224-line screen below the six rows: the top half
; of buffer slot 7, which only ever holds a blank row.
EQUIP_FOOTER_LINES := 224 - EQUIP_HEADER_LINES - EQUIP_VISIBLE_ITEMS * EQUIP_SLOT_PIXELS
; header + 6 row bands + footer + terminator, rounded to words.
EQUIP_HDMA_TABLE_SIZE := 26

; Vanilla's scroll cadence: 8 frames of 2px for one 16px item.
EQUIP_SCROLL_FRAMES := 8

; The window $01:A172 draws (InventoryWindow), as sell redraws it too.
INVENTORY_WINDOW := 0xDCCE

.alloc equip_rolling_block in bank20_reloc {
equip_ensure_hdma_initialized:
"""
Lazy init: park base_scroll and configure ch5 driving BG4VOFS.

Long addressing throughout - the engine's `_engine_call_hook` enters
with the caller's DB, so absolute reads would land in ROM.
"""


    rep #0x20
    lda.l equip_rolling.base_scroll
    cmp.w #0xFFFF
    bne _equip_hdma_already_init
    lda.w #EQUIP_BASE_SCROLL
    sta.l equip_rolling.base_scroll

    sep #0x20
    lda #0x02  ; direct mode, 2 bytes per write
    sta.l EQUIP_HDMA5_CTRL
    lda #BG4VOFS_REG
    sta.l EQUIP_HDMA5_DEST
    rep #0x20
    lda.w #EQUIP_HDMA_TABLE_ADDR
    sta.l EQUIP_HDMA5_SRC_LO
    sep #0x20
    lda #EQUIP_HDMA_BANK
    sta.l EQUIP_HDMA5_SRC_BANK

; Arm ch5 through the shared menu-HDMA signal the NMI hook ORs into
; $420C, and mark this profile's own gate.
    lda.l field_menu_rolling.hdma_enable
    ora #EQUIP_HDMA_ENABLE_BIT
    sta.l field_menu_rolling.hdma_enable
    sta.l equip_rolling.hdma_enable
    jsr.w update_equip_scroll_hdma
    rts

_equip_hdma_already_init:
    sep #0x20
    rts

equip_disable_hdma:
"""Drop ch5 again when the list closes."""
    php
    sep #0x20
    lda.l field_menu_rolling.hdma_enable
    and #0xDF  ; ~EQUIP_HDMA_ENABLE_BIT, spelled out: `^` is a816's bank-byte operator
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
Wipe this slot's two tilemap rows to the window's blank cell, keeping
the side borders, so a shorter name never trails the previous one.

Entry: 16-bit A/X/Y, DB = $7E.
"""


    rep #0x30
    lda.l equip_rolling.slot_index
    and.w #0x00FF
    clc
    adc.w #EQUIP_SLOT_ORIGIN
    xba
    lsr  ; (slot + 1) * EQUIP_SLOT_BYTES
    clc
    adc.w #EQUIP_BG4_BUFFER
    tax
    ldy.w #EQUIP_SLOT_BYTES >> 1  ; cells in two 32-tile rows

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
Blank window cell for the buffer byte at X: side border in the first
and last columns, body elsewhere. Entry/exit: 16-bit A/X.
"""


    txa
    and.w #0x003F
    lsr
    beq _equip_cell_left
    cmp.w #EQUIP_BORDER_RIGHT_COL
    beq _equip_cell_right
    lda.w #( EQUIP_TILEMAP_ATTR << 8 ) | EQUIP_BLANK_TILE
    rts

_equip_cell_left:
    lda.w #( EQUIP_TILEMAP_ATTR << 8 ) | EQUIP_BORDER_LEFT_TILE
    rts

_equip_cell_right:
    lda.w #( EQUIP_TILEMAP_ATTR << 8 ) | EQUIP_BORDER_RIGHT_TILE
    rts

equip_render_item_to_slot:
"""
Render inventory item `edge_row` into ring slot `slot_index`.

Item data comes from the vanilla inventory array at $7E:1440  ; the
tilemap goes to the BG4 buffer at $7E:C600 + (slot + 1) * 128 + 4, one
slot below the window's top border. `check_can_use_item` sets the
greyed palette for items this character cannot equip, as vanilla's
$A172 pass did.
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
    lda.w #EQUIP_BG4_BUFFER
    sta.b 0x29
    jsr.w _equip_blank_slot_rows
    sep #0x20

; The pre-render slot runs one row past the list at the bottom scroll
; position; past the inventory there is nothing to draw.
    lda.w equip_rolling.edge_row
    cmp #EQUIP_TOTAL_ITEMS
    bcs _equip_render_done

; Item pointer = $7E:1440 + edge_row * Item.__size
    lda.w equip_rolling.edge_row
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

; The list takes the primary VWF tile window ($100..): the equip names
; above it borrow the drops region through their own context.
    lda.w equip_rolling.slot_index
    sta.b 0x5d
    rep #0x20
    lda.w equip_rolling.slot_index
    and.w #0x00FF
    clc
    adc.w #EQUIP_SLOT_ORIGIN
    xba
    lsr
    clc
    adc.w #EQUIP_NAME_OFFSET
    tay
    sep #0x20
    jsr.l draw_item_slot_inner_trampoline

_equip_render_done:
    sep #0x20
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

update_equip_scroll_hdma:
"""
Build the equip HDMA shadow table: one band per visible row.

Row r shows ring slot (buffer_pos + r) mod 7, whose content sits at BG
line (slot + 1) * 16, so the band's BG4VOFS is
`base_scroll + slot * 16 - r * 16`, the sell/drops body math.
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
    lda.w #EQUIP_HEADER_LINES
    jsr.w _equip_hdma_base_band
    stz.b 0x42

_equip_row_loop:
    lda.w equip_rolling + RollingBufferState.buffer_pos
    and.w #0x00FF
    clc
    adc.b 0x42

_equip_mod_loop:
    cmp.w #EQUIP_BUFFER_SLOTS
    bcc _equip_mod_done
    sec
    sbc.w #EQUIP_BUFFER_SLOTS
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
    adc.w equip_rolling + RollingBufferState.base_scroll
    sta.b 0x40
    sep #0x20
    lda #EQUIP_SLOT_PIXELS
    sta.l EQUIP_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.b 0x40
    sta.l EQUIP_HDMA_SHADOW, x
    inx
    inx
    inc.b 0x42
    lda.b 0x42
    cmp.w #EQUIP_VISIBLE_ITEMS
    bcs _equip_row_loop_done
    jmp.w _equip_row_loop

_equip_row_loop_done:
    lda.w #EQUIP_FOOTER_LINES
    jsr.w _equip_hdma_base_band
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
One band of A lines held at base_scroll (header above the list, footer
below it). Entry: 16-bit A = line count, X = shadow offset.
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
"""Pre-render hook: SelectBG4 + DrawWindow(inventory window) so $29 = $C600 holds a fresh frame."""
    sep #0x20
    jsr.l equip_select_bg4_trampoline
    rep #0x10
    ldy.w #INVENTORY_WINDOW
    jsr.l draw_window_trampoline
    sep #0x10
    rts

equip_init_impl:
"""
Replace vanilla `DrawInventoryList` for the equip list: configure the
profile, let the engine draw the ring, then re-render it from the
scroll position the screen kept from its last visit.
"""


    php
    rep #0x30
    sep #0x20
    lda.b #EQUIP_VISIBLE_ITEMS
    sta.l equip_rolling + RollingBufferState.visible_rows
    lda.b #0x02
    sta.l equip_rolling + RollingBufferState.slot_height_tiles
    lda.b #0x40
    sta.l equip_rolling + RollingBufferState.item_list_ptr
    lda.b #0x14
    sta.l equip_rolling + RollingBufferState.item_list_ptr + 1
    lda.b #0x7E
    sta.l equip_rolling + RollingBufferState.item_list_ptr + 2
    lda.b #EQUIP_TOTAL_ITEMS
    sta.l equip_rolling + RollingBufferState.item_count
    lda.b #0x05
    sta.l equip_rolling + RollingBufferState.hdma_channel
    lda.b #0x80
    sta.l equip_rolling + RollingBufferState.vwf_cfg_ptr
    lda.b #0x70
    sta.l equip_rolling + RollingBufferState.vwf_cfg_ptr + 1
    lda.b #0x70
    sta.l equip_rolling + RollingBufferState.vwf_cfg_ptr + 2
    lda.b #equip_fn_render_slot_trampoline & 0xFF
    sta.l equip_rolling + RollingBufferState.fn_render_slot
    lda.b #( equip_fn_render_slot_trampoline >> 8 ) & 0xFF
    sta.l equip_rolling + RollingBufferState.fn_render_slot + 1
    lda.b #( equip_fn_render_slot_trampoline >> 16 ) & 0xFF
    sta.l equip_rolling + RollingBufferState.fn_render_slot + 2
    lda.b #equip_fn_update_hdma_trampoline & 0xFF
    sta.l equip_rolling + RollingBufferState.fn_update_hdma
    lda.b #( equip_fn_update_hdma_trampoline >> 8 ) & 0xFF
    sta.l equip_rolling + RollingBufferState.fn_update_hdma + 1
    lda.b #( equip_fn_update_hdma_trampoline >> 16 ) & 0xFF
    sta.l equip_rolling + RollingBufferState.fn_update_hdma + 2
    lda.b #equip_fn_draw_window_trampoline & 0xFF
    sta.l equip_rolling + RollingBufferState.fn_draw_window
    lda.b #( equip_fn_draw_window_trampoline >> 8 ) & 0xFF
    sta.l equip_rolling + RollingBufferState.fn_draw_window + 1
    lda.b #( equip_fn_draw_window_trampoline >> 16 ) & 0xFF
    sta.l equip_rolling + RollingBufferState.fn_draw_window + 2
    lda.b #ROLLING_MENU_ID_EQUIP
    sta.l equip_rolling + RollingBufferState.menu_id
    rep #0x20
    lda.w #0xFFFF
    sta.l equip_rolling.base_scroll
    plp
    php
    rep #0x10
    ldx.w #equip_rolling
    jsr.l rolling_engine.rolling_engine_init
    jsr.w equip_ensure_hdma_initialized
; The engine's init draws items 0..5; the screen keeps its scroll
; position between visits, so lay the ring down from there instead.
    sep #0x20
    rep #0x10
    lda.l EQUIP_SCROLL_POS
    ldx.w #equip_rolling
    jsr.l rolling_engine.rolling_engine_refresh_slots
    sep #0x20
    jsr.l tfr_bg4_tiles_vblank_trampoline
    plp
    rtl

equip_fn_render_slot_trampoline:
"""Bank-20 RTL wrapper around `equip_render_item_to_slot`."""
    php
    jsr.w equip_render_item_to_slot
    plp
    rtl

equip_fn_update_hdma_trampoline:
"""Bank-20 RTL wrapper: arm ch5 on the first call, rebuild the band table on every one."""
    php
    jsr.w equip_ensure_hdma_initialized
    jsr.w update_equip_scroll_hdma
    plp
    rtl

equip_fn_draw_window_trampoline:
"""Bank-20 RTL wrapper around `_equip_draw_window`."""
    php
    jsr.w _equip_draw_window
    plp
    rtl

_equip_run_scroll:
"""
Run one item's worth of scroll animation to completion, in the 8
frames vanilla's own loop took, then push BG4 (see sell's
`_sell_run_scroll` for why the frame count is kept in `_pad`).
"""


    php
    rep #0x10
    sep #0x20
    lda #EQUIP_SCROLL_FRAMES
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
    lda.l EQUIP_SCROLL_POS
    ldx.w #equip_rolling
    jsr.l rolling_engine.rolling_engine_finish_scroll
    sep #0x20
    jsr.l tfr_bg4_tiles_vblank_trampoline
    plp
    rts

equip_scroll_down_impl:
"""Equip profile: scroll the list down one item."""
    php
    rep #0x10
    lda.l EQUIP_SCROLL_POS
    ldx.w #equip_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_down
    jsr.w _equip_run_scroll
    plp
    rtl

equip_scroll_up_impl:
"""Equip profile: scroll the list up one item."""
    php
    rep #0x10
    lda.l EQUIP_SCROLL_POS
    ldx.w #equip_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_up
    jsr.w _equip_run_scroll
    plp
    rtl
}
