"""
Fat Chocobo's item lists (`Déposer`: the bag, `Retirer`: his 126 slots) on a rolling buffer: 8-slot ring (7 visible
+ 1 prefetch) in the BG4 buffer at $7E:C600, BG4VOFS driven per scanline by HDMA ch5. Same shape as
equip_inventory_rolling.s.

Vanilla draws the bag with `DrawInventoryList` ($01:A172) and his slots with its `$1340` entry ($01:A167) into a
tall strip, scrolled by $99 through the screen's IRQ ($01:CE6A writes BG4VOFS at line $58); his 126 slots go to
the BG2 buffer and stream into BG4 by rows ($1E:FC28 / $1E:FC41). Both lists are one column of rows here.
"""


.import "core/preamble"
.import "core/wram_layout"
.include "core/bank20.i"
.import "core/items"

.import "ingame/vanilla_trampolines"
.import "core/libmz"
.import "lib/rolling_inventory_engine"
.import "core/vanilla"

_FAT_VISIBLE_ITEMS := FAT_CHOCOBO_LIST_VISIBLE_ROWS
_FAT_BUFFER_SLOTS := _FAT_VISIBLE_ITEMS + 1

; Vanilla's list state: first visible row, and which list (0 the bag, 1 his slots).
_FAT_SCROLL_POS := 0x7E1BB2
_FAT_LIST_MODE := 0x7E1BAF
_FAT_BAG := 0x1440
_FAT_STORED := 0x1340

; The IRQ's copy of the list scroll ($0199 on the menu's direct page).
_FAT_IRQ_SCROLL := 0x000199

; HDMA ch5 driving BG4VOFS.
_FAT_HDMA_ENABLE_BIT := 0x20

; The equip list's tables (wram_layout.s): the two screens never show together.
_FAT_HDMA_TABLE_ADDR := EQUIP_HDMA_TABLE & 0xFFFF
_FAT_HDMA_BANK := 0x7E
_FAT_HDMA_SHADOW := EQUIP_HDMA_SHADOW

; Window in the BG4 buffer: top border on tile row 0, ring on rows 1..16, bottom border on row 24.
_FAT_BG4_BUFFER := 0xC600
_FAT_SLOT_BYTES := 0x80  ; two 32-tile tilemap rows
_FAT_SLOT_ORIGIN := FAT_CHOCOBO_LIST_ORIGIN_LINES * 8  ; byte offset of slot 0: a tile row is 8 lines, $40 bytes
_FAT_SLOT_PIXELS := 16
_FAT_NAME_OFFSET := 0x0004  ; icon at tile column 2

; Blank window cell and the side borders in the first and last columns. Priority set, as vanilla's DrawWindow
; draws them: BG4 shows above the BG3 window body ($01:CE9C) only with it.
_FAT_BLANK_TILE := 0xFF
_FAT_TILEMAP_ATTR := 0x20
_FAT_BORDER_LEFT_TILE := 0xFA
_FAT_BORDER_RIGHT_TILE := 0xFB
_FAT_BORDER_RIGHT_COL := 31

_FAT_BASE_SCROLL := FAT_CHOCOBO_LIST_BASE_SCROLL
_FAT_HEADER_LINES := FAT_CHOCOBO_LIST_FIRST_ROW_Y
; Footer: the rest of the 224 lines, scrolled to show buffer row 24 (the window's bottom border) right under the
; last row, so the prefetch slot never shows.
_FAT_WINDOW_BOTTOM_ROW := 24
_FAT_FOOTER_TOP := _FAT_HEADER_LINES + _FAT_VISIBLE_ITEMS * _FAT_SLOT_PIXELS
_FAT_FOOTER_LINES := 224 - _FAT_FOOTER_TOP
_FAT_FOOTER_SCROLL := _FAT_WINDOW_BOTTOM_ROW * 8 - _FAT_FOOTER_TOP + 0x10000 - _FAT_BASE_SCROLL
; header + 8 row bands (mid-scroll, one more than the rows) + footer + terminator.
.assert 3 * ( _FAT_VISIBLE_ITEMS + 3 ) + 1 <= MENU_HDMA_SPAN, "the band table outgrew its span"

; Vanilla's cadence: 8 frames of 2 px per item.
_FAT_SCROLL_FRAMES := 8

; InventoryWindow, the window $01:A172 draws.
_INVENTORY_WINDOW := 0xDCCE

.alloc _fat_chocobo_rolling_block in bank20_reloc {
fat_chocobo_irq_scroll:
"""
The screen IRQ's BG4VOFS write at line $58 ($01:CE6A), skipped while ch5 drives BG4VOFS: it would override the
band the line falls in. Entry: 8-bit A, DB = $00, X/Y untouched (the IRQ does not save them).
"""


    lda.l fat_chocobo_rolling.hdma_enable
    bne _fat_irq_scroll_done
    lda.l _FAT_IRQ_SCROLL + 1
    xba
    lda.l _FAT_IRQ_SCROLL
    sta.l ppu.BG4VOFS
    sta.l ppu.BG4VOFS
    xba
    sta.l ppu.BG4VOFS

_fat_irq_scroll_done:
    rtl

_fat_ensure_hdma_initialized:
"""
One-shot: sets base_scroll, configures ch5 -> BG4VOFS and arms it. Long addressing: entered with the caller's DB.
"""


    rep #0x20
    lda.l fat_chocobo_rolling.base_scroll
    cmp.w #0xFFFF
    bne _fat_hdma_already_init
    lda.w #_FAT_BASE_SCROLL
    sta.l fat_chocobo_rolling.base_scroll

    sep #0x20
    lda #0x02  ; direct mode, 2 bytes per write
    sta.l dma_ch5.DMAP
    lda #PPU.BG4VOFS
    sta.l dma_ch5.BBAD
    rep #0x20
    lda.w #_FAT_HDMA_TABLE_ADDR
    sta.l dma_ch5.A1TL
    sep #0x20
    lda #_FAT_HDMA_BANK
    sta.l dma_ch5.A1B

; Arm ch5 via the shared signal the NMI hook ORs into $420C.
    lda.l field_menu_rolling.hdma_enable
    ora #_FAT_HDMA_ENABLE_BIT
    sta.l field_menu_rolling.hdma_enable
    sta.l fat_chocobo_rolling.hdma_enable
    jsr.w update_fat_scroll_hdma
    rts

_fat_hdma_already_init:
    sep #0x20
    rts

fat_chocobo_disable_hdma:
"""Disarms ch5 when the Fat Chocobo screen closes."""
    php
    sep #0x20
    lda.l field_menu_rolling.hdma_enable
    and #0xDF  ; ~_FAT_HDMA_ENABLE_BIT, spelled out: `^` is a816's bank-byte operator
    sta.l field_menu_rolling.hdma_enable
    lda #0x00
    sta.l fat_chocobo_rolling.hdma_enable
    rep #0x20
    lda.w #0xFFFF
    sta.l fat_chocobo_rolling.base_scroll
    plp
    rtl

_fat_blank_slot_rows:
"""
Blanks this slot's two tilemap rows (borders kept). Entry: 16-bit A/X/Y, DB = $7E.
"""


    rep #0x30
    lda.l fat_chocobo_rolling.slot_index
    and.w #0x00FF
    xba
    lsr  ; slot * _FAT_SLOT_BYTES
    clc
    adc.w #_FAT_BG4_BUFFER + _FAT_SLOT_ORIGIN
    tax
    ldy.w #_FAT_SLOT_BYTES >> 1  ; cells in two 32-tile rows

_fat_blank_cell:
    jsr.w _fat_window_cell
    sta.w 0x0000, x
    inx
    inx
    dey
    bne _fat_blank_cell
    rts

_fat_window_cell:
"""
Blank window cell (border or body) for buffer offset X. Entry/exit: 16-bit A/X; returns the cell word in A.
"""


    txa
    and.w #0x003F
    lsr
    beq _fat_cell_left
    cmp.w #_FAT_BORDER_RIGHT_COL
    beq _fat_cell_right
    lda.w #( _FAT_TILEMAP_ATTR << 8 ) | _FAT_BLANK_TILE
    rts

_fat_cell_left:
    lda.w #( _FAT_TILEMAP_ATTR << 8 ) | _FAT_BORDER_LEFT_TILE
    rts

_fat_cell_right:
    lda.w #( _FAT_TILEMAP_ATTR << 8 ) | _FAT_BORDER_RIGHT_TILE
    rts

_fat_render_item_to_slot:
"""
Renders item `edge_row` of the list `item_list_ptr` into $7E:C600 + _FAT_SLOT_ORIGIN + slot * 128 + 4.
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
    lda.w #_FAT_BG4_BUFFER
    sta.b menu_dp.tilemap_offset
    jsr.w _fat_blank_slot_rows
    sep #0x20

; At the bottom the prefetch slot is past the list: nothing to draw.
    lda.w fat_chocobo_rolling.edge_row
    cmp.w fat_chocobo_rolling.item_count
    bcs _fat_render_done

; Item pointer = item_list_ptr + edge_row * 2 (his list runs past 128 rows: 16-bit).
    rep #0x20
    lda.w fat_chocobo_rolling.edge_row
    and.w #0x00FF
    asl
    clc
    adc.w fat_chocobo_rolling.item_list_ptr
    sta.b menu_dp.item_ptr
    tax
    sep #0x20
    lda.l item_x.id, x
    pha
    lda.l item_x.qty, x
    sta.b 0x5C
    lda #_FAT_TILEMAP_ATTR
    sta.b menu_dp.window_attr
    pla
    jsr.l check_can_use_item_trampoline

; Primary VWF tile window ($100..): 8 slots * 10 tiles.
    lda.w fat_chocobo_rolling.slot_index
    sta.b menu_dp.item_slot
    rep #0x20
    lda.w fat_chocobo_rolling.slot_index
    and.w #0x00FF
    xba
    lsr  ; slot * _FAT_SLOT_BYTES
    clc
    adc.w #_FAT_SLOT_ORIGIN + _FAT_NAME_OFFSET
    tay
    sep #0x20
    jsr.l draw_item_slot_inner_trampoline

_fat_render_done:
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

update_fat_scroll_hdma:
"""
Builds the HDMA shadow table: header, the row bands (rolling_engine_hdma_rows, slid mid-scroll), footer.
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
        lda.w #_FAT_HEADER_LINES
        jsr.w _fat_hdma_base_band
        txy
        lda.w #_FAT_HDMA_SHADOW & 0xFFFF
        sta.b 0x40
        lda.w #_FAT_HDMA_SHADOW >> 16
        sta.b 0x42
        lda.w #0
        ldx.w #fat_chocobo_rolling
        jsr.l rolling_engine.rolling_engine_hdma_rows
        tyx
        sep #0x20
        lda #_FAT_FOOTER_LINES
        sta.l _FAT_HDMA_SHADOW, x
        inx
        rep #0x20
        lda.w fat_chocobo_rolling.base_scroll
        clc
        adc.w #_FAT_FOOTER_SCROLL
        sta.l _FAT_HDMA_SHADOW, x
        inx
        inx
        sep #0x20
        lda #0x00
        sta.l _FAT_HDMA_SHADOW, x
        lda #0x01
        sta.l fat_chocobo_rolling.hdma_copy_pending
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

_fat_hdma_base_band:
"""
One band of A lines at base_scroll. Entry: 16-bit A = line count, X = shadow offset.
"""


    sep #0x20
    sta.l _FAT_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w fat_chocobo_rolling.base_scroll
    sta.l _FAT_HDMA_SHADOW, x
    inx
    inx
    rts

_fat_draw_window:
"""Pre-render hook: SelectBG4 + DrawWindow so $C600 holds a fresh window."""
    sep #0x20
    jsr.l equip_select_bg4_trampoline
    rep #0x10
    ldy.w #_INVENTORY_WINDOW
    jsr.l draw_window_trampoline
    sep #0x10
    rts

fat_chocobo_init_impl:
"""
Replaces the list draw of either list ($01:A172 the bag, $01:A167 his slots): configures the profile for the list
`$1BAF` names, inits the ring, then re-renders it at vanilla's scroll position (kept across a deposit).
"""


    php
    rep #0x30
    sep #0x20
    lda.b #_FAT_VISIBLE_ITEMS
    sta.l fat_chocobo_rolling.visible_rows
    lda.b #0x02
    sta.l fat_chocobo_rolling.slot_height_tiles
    lda.l _FAT_LIST_MODE
    bne _fat_init_stored
    rep #0x20
    lda.w #_FAT_BAG
    sta.l fat_chocobo_rolling.item_list_ptr
    sep #0x20
    lda.b #FAT_CHOCOBO_BAG_ITEMS
    bra _fat_init_count

_fat_init_stored:
    rep #0x20
    lda.w #_FAT_STORED
    sta.l fat_chocobo_rolling.item_list_ptr
    sep #0x20
    lda.b #FAT_CHOCOBO_STORED_ITEMS

_fat_init_count:
    sta.l fat_chocobo_rolling.item_count
    lda.b #0x7E
    sta.l fat_chocobo_rolling.item_list_ptr + 2
    lda.b #0x05
    sta.l fat_chocobo_rolling.hdma_channel
    lda.b #0x80
    sta.l fat_chocobo_rolling.vwf_cfg_ptr
    lda.b #0x70
    sta.l fat_chocobo_rolling.vwf_cfg_ptr + 1
    lda.b #0x70
    sta.l fat_chocobo_rolling.vwf_cfg_ptr + 2
    lda.b #_fat_fn_render_slot_trampoline & 0xFF
    sta.l fat_chocobo_rolling.fn_render_slot
    lda.b #( _fat_fn_render_slot_trampoline >> 8 ) & 0xFF
    sta.l fat_chocobo_rolling.fn_render_slot + 1
    lda.b #( _fat_fn_render_slot_trampoline >> 16 ) & 0xFF
    sta.l fat_chocobo_rolling.fn_render_slot + 2
    lda.b #_fat_fn_update_hdma_trampoline & 0xFF
    sta.l fat_chocobo_rolling.fn_update_hdma
    lda.b #( _fat_fn_update_hdma_trampoline >> 8 ) & 0xFF
    sta.l fat_chocobo_rolling.fn_update_hdma + 1
    lda.b #( _fat_fn_update_hdma_trampoline >> 16 ) & 0xFF
    sta.l fat_chocobo_rolling.fn_update_hdma + 2
    lda.b #_fat_fn_draw_window_trampoline & 0xFF
    sta.l fat_chocobo_rolling.fn_draw_window
    lda.b #( _fat_fn_draw_window_trampoline >> 8 ) & 0xFF
    sta.l fat_chocobo_rolling.fn_draw_window + 1
    lda.b #( _fat_fn_draw_window_trampoline >> 16 ) & 0xFF
    sta.l fat_chocobo_rolling.fn_draw_window + 2
    lda.b #ROLLING_MENU_ID_FAT_CHOCOBO
    sta.l fat_chocobo_rolling.menu_id
    rep #0x20
    lda.w #0xFFFF
    sta.l fat_chocobo_rolling.base_scroll
    plp
    php
    rep #0x10
    ldx.w #fat_chocobo_rolling
    jsr.l rolling_engine.rolling_engine_init
    jsr.w _fat_ensure_hdma_initialized
; Init draws rows 0..6; redraw from vanilla's scroll position, the prefetch slot too.
    sep #0x20
    rep #0x10
    lda.l _FAT_SCROLL_POS
    ldx.w #fat_chocobo_rolling
    jsr.l rolling_engine.rolling_engine_refresh_slots
    sep #0x20
    jsr.l tfr_bg4_tiles_vblank_trampoline
    plp
    rtl

_fat_fn_render_slot_trampoline:
"""Bank-20 RTL wrapper around `_fat_render_item_to_slot`."""
    php
    jsr.w _fat_render_item_to_slot
    plp
    rtl

_fat_fn_update_hdma_trampoline:
"""Bank-20 RTL wrapper: arms ch5 once, rebuilds the band table on every call."""
    php
    jsr.w _fat_ensure_hdma_initialized
    jsr.w update_fat_scroll_hdma
    plp
    rtl

_fat_fn_draw_window_trampoline:
"""Bank-20 RTL wrapper around `_fat_draw_window`."""
    php
    jsr.w _fat_draw_window
    plp
    rtl

_fat_run_scroll:
"""
Runs one item's scroll to completion in vanilla's 8 frames, then pushes BG4. Frame count in `_pad`, as for equip.
"""


    php
    rep #0x10
    sep #0x20
    lda #_FAT_SCROLL_FRAMES
    sta.l fat_chocobo_rolling._pad
; The row scrolling in, rendered by start_scroll: on screen before it slides in, not popped in at the end.
    jsr.l tfr_bg4_tiles_vblank_trampoline

_fat_scroll_frame:
; update_scroll_frame waits for the vblank itself (TfrBG2TilesVblank): one step a frame, as vanilla
    ldx.w #fat_chocobo_rolling
    jsr.l rolling_engine.rolling_engine_update_scroll_frame
    sep #0x20
    lda.l fat_chocobo_rolling._pad
    dec
    sta.l fat_chocobo_rolling._pad
    bne _fat_scroll_frame
    sep #0x20
    rep #0x10
    lda.l _FAT_SCROLL_POS
    ldx.w #fat_chocobo_rolling
    jsr.l rolling_engine.rolling_engine_finish_scroll
    sep #0x20
    jsr.l tfr_bg4_tiles_vblank_trampoline
    plp
    rts

fat_chocobo_scroll_down_impl:
"""Scrolls the list down one item (vanilla already moved $1BB2)."""
    php
    rep #0x10
    sep #0x20
    lda.l _FAT_SCROLL_POS
    ldx.w #fat_chocobo_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_down
    jsr.w _fat_run_scroll
    plp
    rtl

fat_chocobo_scroll_up_impl:
"""Scrolls the list up one item (vanilla already moved $1BB2)."""
    php
    rep #0x10
    sep #0x20
    lda.l _FAT_SCROLL_POS
    ldx.w #fat_chocobo_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_up
    jsr.w _fat_run_scroll
    plp
    rtl
}
