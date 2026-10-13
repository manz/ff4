

"""
Key-item picker (EventCmd_f7 -> ShowItemWindow $00:AF4D) as a single-column rolling buffer: 4 visible rows over
5 slots. Vanilla keeps the window, slide, cursor and scroll position; the engine owns the row contents.

Items: $7E:0712, the filtered list (48 x 2 bytes) of key-item ids [$CE..$E6] u [$EB..$FD] from $1440.
State: `key_item_rolling` at $7E:9C60. Hooks in key_item_picker_patches.s.
The HDMA scroll table on channel 4 is built but never armed.
"""


.import "core/preamble"
.import "core/vwf_ram"
.import "core/items"

.import "ingame/vanilla_trampolines"
.import "core/libmz"
.import "lib/rolling_inventory_engine"
.import "small_vwf/init"


; Four rows on screen; the engine adds the prefetch slot itself.
_KEY_ITEM_VISIBLE_ITEMS := 4
_KEY_ITEM_BUFFER_SLOTS := 5
_KEY_ITEM_TOTAL_ITEMS := 48
_KEY_ITEM_SCROLL_LIMIT := 42
_KEY_ITEM_SCROLL_PIXELS_PER_FRAME := 8
_KEY_ITEM_SCROLL_TOTAL_PIXELS := 16


_KEY_ITEM_SLIDE_OPEN_DONE := 0x08


_KEY_ITEM_SCROLL_FRAMES := 8
_KEY_ITEM_SCROLL_STEP_PX := 2
_KEY_ITEM_ROW_HEIGHT_PX := 16

; Direct page the picker renders on, off the field's own $0600.
_KEY_ITEM_RENDER_DP := 0x1D00
; NMITIMEN: $A1 = NMI + V-IRQ + joypad while open; rendering drops NMI only (the V-IRQ draws the window).
_KEY_ITEM_NMITIMEN_PICKER := 0xA1
_KEY_ITEM_NMITIMEN_RENDER := 0x21

_KEY_ITEM_HDMA_TABLE_ADDR := 0x9900
_KEY_ITEM_HDMA_TABLE := 0x7E9900
_KEY_ITEM_HDMA_SHADOW_ADDR := 0x9940
_KEY_ITEM_HDMA_SHADOW := 0x7E9940
_KEY_ITEM_HDMA_BANK := 0x7E
; Header + 6 rows + footer + terminator, rounded up to a word count.
_KEY_ITEM_HDMA_TABLE_SIZE := 40

_KEY_ITEM_FILTER_BUFFER := 0x0712

; BG3 staging page for the window body, DMA'd to BG3 plane 1 at VRAM word $2C00 (item text on rows 1/3/5/7,
; cursor in column 2).
_KEY_ITEM_STAGING_ADDR := 0xD600
; The whole ring (5 slots x 2 rows x 32 cells x 2 bytes). Plane 1 is the map's tilemap and vanilla restores
; only its window rows, so never write past this.
_KEY_ITEM_STAGING_SIZE := _KEY_ITEM_BUFFER_SLOTS * 0x80
; The window IRQ shows plane 1 with BG3VOFS = $BB (rests at $70): screen line 144 + 112 wraps to plane row 0,
; so the ring sits at the top of the plane and each $10 of $BB is one item.
_KEY_ITEM_TILEMAP_VRAM_WORD := 0x2C00
; Palette 0 + priority, so the body draws above the map.
_KEY_ITEM_TILEMAP_ATTR := 0x20
; Blank window cell.
_KEY_ITEM_BLANK_TILE := 0xFF
; Window row in plane 1: $00 in columns 0-1 / 30-31, borders $19 / $1A in columns 2 / 29, blank body between.
_KEY_ITEM_OUTSIDE_TILE := 0x00
_KEY_ITEM_BORDER_LEFT_TILE := 0x19
_KEY_ITEM_BORDER_RIGHT_TILE := 0x1A
_KEY_ITEM_BORDER_LEFT_COL := 2
_KEY_ITEM_BORDER_RIGHT_COL := 29

_KEY_ITEM_HDMA_CHANNEL_BIT := 0x10

.include "core/rolling_state.i"

.include "core/bank20.i"
.import "core/vanilla"

.alloc _key_item_picker_block in bank20_reloc {
_key_item_ensure_hdma_initialized:
"""
    Captures $9F (BG3VOFS shadow) into base_scroll on first call. Never arms ch4: the picker returns to the field
    without teardown, and a live ch4 splits the field's BG3.
"""


    rep #0x20
    lda.l key_item_rolling.base_scroll
    cmp.w #0xFFFF
    bne _key_item_hdma_already_init
    lda.l 0x7E019F
    sta.l key_item_rolling.base_scroll
    sep #0x20
; Build the table only; driving BG3VOFS would fight vanilla's window placement.
    jsr.w update_key_item_scroll_hdma
    rts

_key_item_hdma_already_init:
    sep #0x20
    rts

_key_item_init_hdma_channel:
"""Configure HDMA ch4: DIRECT mode, dest BG3VOFS ($2112), source = picker shadow table at $7E:9900."""
    php
    sep #0x20
    jsr.w update_key_item_scroll_hdma
    lda #0x02
    sta.l dma_ch4.DMAP
    lda #PPU.BG3VOFS
    sta.l dma_ch4.BBAD
    rep #0x20
    lda.w #_KEY_ITEM_HDMA_TABLE_ADDR
    sta.l dma_ch4.A1TL
    sep #0x20
    lda #_KEY_ITEM_HDMA_BANK
    sta.l dma_ch4.A1B
    plp
    rts

_key_item_blank_slot_rows:
"""
Fills this slot's two tilemap rows with the blank window cell; the renderer writes only the cells it draws, so
the map would show through the rest.

Entry: 16-bit A/X/Y, DB = $7E. Clobbers X/Y.
"""


    rep #0x30
    lda.l key_item_rolling.slot_index
    and.w #0x00FF
    xba
    lsr  ; slot * 128 : two 32-tile rows, 2 bytes per cell
    clc
    adc.w #0xD600
    tax
    ldy.w #0x0040  ; 64 cells = 2 tilemap rows

_blank_cell:
    jsr.w _key_item_window_cell
    sta.w 0x0000, x
    inx
    inx
    dey
    bne _blank_cell
    rts

_key_item_window_cell:
"""
Blank window cell (outside, border or body) for the staging byte offset X; X's low 6 bits are the row offset.

Entry/exit: 16-bit A/X. Returns the cell word (attr << 8 | tile) in A.
"""


    txa
    and.w #0x003F
    lsr
    cmp.w #_KEY_ITEM_BORDER_LEFT_COL
    bcc _cell_outside
    beq _cell_left
    cmp.w #_KEY_ITEM_BORDER_RIGHT_COL
    bcc _cell_body
    beq _cell_right

_cell_outside:
    lda.w #( _KEY_ITEM_TILEMAP_ATTR << 8 ) | _KEY_ITEM_OUTSIDE_TILE
    rts

_cell_left:
    lda.w #( _KEY_ITEM_TILEMAP_ATTR << 8 ) | _KEY_ITEM_BORDER_LEFT_TILE
    rts

_cell_right:
    lda.w #( _KEY_ITEM_TILEMAP_ATTR << 8 ) | _KEY_ITEM_BORDER_RIGHT_TILE
    rts

_cell_body:
    lda.w #( _KEY_ITEM_TILEMAP_ATTR << 8 ) | _KEY_ITEM_BLANK_TILE
    rts

key_item_cursor_slot_impl:
"""
Cursor row for `DrawItemSelectCursor` ($00:B11A) as a ring slot: $4B = ($BA + $8C) mod _KEY_ITEM_BUFFER_SLOTS.
Vanilla's unbounded row walks the hand off the window once the ring wraps.

Replaces `lda $ba / clc / adc $8c / sta $4b` at $00:B13D; vanilla resumes at $00:B144.
"""


    php
    sep #0x20
    lda.b 0xBA
    clc
    adc.b menu_dp.bg2_vscroll

_cursor_slot_mod:
    cmp.b #_KEY_ITEM_BUFFER_SLOTS
    bcc _cursor_slot_done
    sec
    sbc.b #_KEY_ITEM_BUFFER_SLOTS
    bra _cursor_slot_mod

_cursor_slot_done:
    sta.b 0x4B
    plp
    rtl

_key_item_render_item_to_slot:
"""Renders item $7E:0712 + edge_row * 2 into the staging page at $7E:D600 + slot_index * 128."""
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
    lda.w #0xD600
    sta.b menu_dp.tilemap_offset
    jsr.w _key_item_blank_slot_rows
    sep #0x20
    lda.l key_item_rolling.edge_row
    asl
    clc
    adc #0x12
    sta.b menu_dp.item_ptr
    lda #0x07
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
    lda.l key_item_rolling.slot_index
    sta.b menu_dp.item_slot
; Attr for the fixed cells (symbol, colon, quantity), matching the window body.
    lda #_KEY_ITEM_TILEMAP_ATTR
    sta.b menu_dp.item_usable
    stz.b menu_dp.window_attr
; Secondary flush (BG3 $6800): on the field map the primary target ($2800) is the BG3 tilemap.
    lda #VWF_CTX_KEY_ITEM
    sta.l vwf_engine.caller_ctx
    rep #0x20
    lda.l key_item_rolling.slot_index
    and.w #0x00FF
    xba
    lsr
; Y = slot * 128 + 6: symbol in column 3, name from column 4 (column 2 is the cursor), on row 2N+1.
    clc
    adc.w #0x0006
    tay
    sep #0x20
    jsr.l draw_item_slot_inner_trampoline
    lda #VWF_CTX_PRIMARY
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

_key_item_render_all:
"""
    Inits the ring and keeps HDMA off. Unreferenced: the picker renders from `key_item_after_open_impl`.
"""


    php
    rep #0x10
    sep #0x20
    jsr.l _key_item_init_impl
; HDMA off: its bands don't match the picker rows.
    lda #0x00
    sta.l field_menu_rolling.hdma_enable
    lda #0x00
    sta.l cpu_regs.HDMAEN
    plp
    rtl

_clear_key_item_slot:
"""Blank one tilemap row at slot_index in the BG3 buffer."""
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
    lda.w #0xD600
    sta.b menu_dp.tilemap_offset
    lda.l key_item_rolling.slot_index
    and.w #0x00FF
    xba
    lsr
    clc
    adc.w #0x0044
    tay
    sep #0x20
    ldx.w #0x0000

_clear_key_loop:
    lda #0x00
    sta.b (menu_dp.tilemap_offset), y
    iny
    inx
    cpx.w #0x0040
    bne _clear_key_loop
    rep #0x20
    pla
    sta.b menu_dp.tilemap_offset
    rep #0x10
    ply
    plx
    pla
    plb
    plp
    rts

_key_item_init_filter:
"""
    Port of InitItemList ($00:B2D5): copies (id, qty) of key items [$CE..$E6] u [$EB..$FD] from $1440 to $0712.
    Sets key_item_count.
"""


    php
    phb
    sep #0x20
    rep #0x10
    lda #0x7E
    pha
    plb
    ldx.w #0x0000

_filter_clear:
    stz.w item_select_list, x
    inx
    cpx.w #0x0060
    bne _filter_clear
    ldx.w #0x0000
    ldy.w #0x0000

_filter_walk:
    lda.w field_inventory.id, x
    cmp #0xCE
    bcc _filter_next
    cmp #0xE7
    bcc _filter_accept
    cmp #0xEB
    bcc _filter_next
    cmp #0xFE
    bcs _filter_next

_filter_accept:
    sta.w item_select_list, y
    lda.w field_inventory.qty, x
    sta.w item_select_list + 1, y
    iny
    iny

_filter_next:
    inx
    inx
    cpx.w #0x0060
    bne _filter_walk
; Y = 2 * count.
    tya
    lsr
    sta.l key_item_count
    plb
    plp
    rts

update_key_item_scroll_hdma:
"""Build the key-item HDMA shadow table."""
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
    jsr.w _key_item_hdma_header
    stz.b 0x42

_row_loop:
    lda.l key_item_rolling.buffer_pos
    and.w #0x00FF
    clc
    adc.b 0x42

_mod_loop:
    cmp.w #_KEY_ITEM_BUFFER_SLOTS
    bcc _mod_done
    sec
    sbc.w #_KEY_ITEM_BUFFER_SLOTS
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
    adc.l key_item_rolling.base_scroll
    sta.b 0x40
    sep #0x20
    lda #16
    sta.l _KEY_ITEM_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.b 0x40
    sta.l _KEY_ITEM_HDMA_SHADOW, x
    inx
    inx
    rep #0x20
    inc.b 0x42
    lda.b 0x42
    cmp.w #_KEY_ITEM_VISIBLE_ITEMS
    bcs _row_loop_done
    jmp.w _row_loop

_row_loop_done:
    jsr.w _key_item_hdma_footer
    sep #0x20
    lda #0x00
    sta.l _KEY_ITEM_HDMA_SHADOW, x
    jsr.w _key_item_hdma_signal
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

_key_item_hdma_header:
"""HDMA header: 112 lines at base scroll (field map above the window)."""
    sep #0x20
    lda #112
    sta.l _KEY_ITEM_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.l key_item_rolling.base_scroll
    sta.l _KEY_ITEM_HDMA_SHADOW, x
    inx
    inx
    rts

_key_item_hdma_footer:
"""HDMA footer: 16 lines at base + 16, hiding the prefetch slot."""
    sep #0x20
    lda #16
    sta.l _KEY_ITEM_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.l key_item_rolling.base_scroll
    clc
    adc.w #16
    sta.l _KEY_ITEM_HDMA_SHADOW, x
    inx
    inx
    rts

_key_item_hdma_signal:
"""Sets hdma_copy_pending."""
    sep #0x20
    lda #0x01
    sta.l key_item_rolling.hdma_copy_pending
    rts

_key_item_init_impl:
"""
    Filters the list, fills `key_item_rolling` ($7E:9C60) and inits the engine.
"""


    jsr.w _key_item_init_filter
    php
    rep #0x30
    sep #0x20
; Visible rows, not slots: the engine adds the prefetch slot.
    lda.b #_KEY_ITEM_VISIBLE_ITEMS
    sta.l key_item_rolling.visible_rows
    lda.b #0x02
    sta.l key_item_rolling.slot_height_tiles
; item_list_ptr = $7E:0712
    lda.b #0x12
    sta.l key_item_rolling.item_list_ptr
    lda.b #0x07
    sta.l key_item_rolling.item_list_ptr + 1
    lda.b #0x7E
    sta.l key_item_rolling.item_list_ptr + 2
    lda.l key_item_count
    sta.l key_item_rolling.item_count
    lda.b #0x04
    sta.l key_item_rolling.hdma_channel
    lda.b #0x80
    sta.l key_item_rolling.vwf_cfg_ptr
    lda.b #0x70
    sta.l key_item_rolling.vwf_cfg_ptr + 1
    lda.b #0x70
    sta.l key_item_rolling.vwf_cfg_ptr + 2
    lda.b #_key_item_fn_render_slot_trampoline & 0xFF
    sta.l key_item_rolling.fn_render_slot
    lda.b #( _key_item_fn_render_slot_trampoline >> 8 ) & 0xFF
    sta.l key_item_rolling.fn_render_slot + 1
    lda.b #( _key_item_fn_render_slot_trampoline >> 16 ) & 0xFF
    sta.l key_item_rolling.fn_render_slot + 2
    lda.b #_key_item_fn_update_hdma_trampoline & 0xFF
    sta.l key_item_rolling.fn_update_hdma
    lda.b #( _key_item_fn_update_hdma_trampoline >> 8 ) & 0xFF
    sta.l key_item_rolling.fn_update_hdma + 1
    lda.b #( _key_item_fn_update_hdma_trampoline >> 16 ) & 0xFF
    sta.l key_item_rolling.fn_update_hdma + 2
    lda.b #_key_item_fn_draw_window_trampoline & 0xFF
    sta.l key_item_rolling.fn_draw_window
    lda.b #( _key_item_fn_draw_window_trampoline >> 8 ) & 0xFF
    sta.l key_item_rolling.fn_draw_window + 1
    lda.b #( _key_item_fn_draw_window_trampoline >> 16 ) & 0xFF
    sta.l key_item_rolling.fn_draw_window + 2
    lda.b #ROLLING_MENU_ID_KEY_ITEM
    sta.l key_item_rolling.menu_id
    plp
    php
    rep #0x10
    ldx.w #key_item_rolling
    jsr.l rolling_engine.rolling_engine_init
    plp
    rtl

key_item_after_open_impl:
"""
Per-frame picker hook over `lda #$01 / sta $7D` at $00:AF7E (top of the input loop). Must stay cheap.

Renders only on two edges: slide counter $DA reaching fully open (init + render) and scroll position $BA
changing (refresh). Leave vanilla's `jsr $912F` before the hook alone: replacing it breaks the frame pacing.
"""


    php
    sep #0x20
    rep #0x10
    lda #0x01
    sta.b 0x7D  ; the store this hook displaced
    lda.b 0xDA  ; DP-relative: the caller's direct page, whatever it is
    cmp.l key_item_open_slide_seen
    beq _check_scroll
    sta.l key_item_open_slide_seen
    cmp.b #_KEY_ITEM_SLIDE_OPEN_DONE
    bne _after_open_done
    lda.b 0xBA
    sta.l key_item_last_scroll
    sta.l key_item_scroll_pos
    jsr.w _key_item_save_vram
    jsr.w _key_item_enter_render
    rep #0x30
    jsr.l _key_item_init_impl
    bra _finish_render

_check_scroll:
    lda.b 0xBA
    cmp.l key_item_last_scroll
    beq _after_open_done
    sta.l key_item_last_scroll
    sta.l key_item_scroll_pos
; Refresh only if init ran (menu_id matches): the slide marker survives a close, so a later open can reach
; this edge with stale hook far-pointers.
    lda.l key_item_rolling.menu_id
    cmp.b #ROLLING_MENU_ID_KEY_ITEM
    bne _render_from_scratch
    jsr.w _key_item_enter_render
    rep #0x30
    jsr.l _key_item_refresh_slots_impl
    bra _finish_render

_render_from_scratch:
    jsr.w _key_item_enter_render
    rep #0x30
    jsr.l _key_item_init_impl

_finish_render:
    sep #0x20
    rep #0x10
    jsr.w _key_item_push_window
    jsr.w _key_item_leave_render

_after_open_done:
    plp
    rtl

_key_item_enter_render:
"""
Field-safe render setup: NMI off, DMA ch3 saved, and D moved to a copy of the field page at $1D00 (free RAM).

The menu renderer scratches DP bytes the field uses every frame. A snapshot/restore of the field page would
also rewind what the window V-IRQ advanced meanwhile, so the render writes a throwaway copy instead. Both
interrupt handlers set their own D ($0600).
"""


    sep #0x20
; Drop NMI only: the V-IRQ draws the window, so clearing it blinks the window on every scroll.
    lda #_KEY_ITEM_NMITIMEN_RENDER
    sta.l cpu_regs.NMITIMEN
    jsr.w _key_item_save_dma
    rep #0x30
    tdc
    sta.l key_item_dp_prev
    tax
    ldy.w #_KEY_ITEM_RENDER_DP
    lda.w #0x00FF
; MVN changes DB.
    phb
    mvn 0x7E, 0x7E
    plb
    lda.w #_KEY_ITEM_RENDER_DP
    tcd
    rts

_key_item_leave_render:
"""Restores the caller's D, DMA ch3 and NMI."""
    rep #0x20
    lda.l key_item_dp_prev
    tcd
    sep #0x20
    rep #0x10
    jsr.w _key_item_restore_dma
    sep #0x20
    lda #_KEY_ITEM_NMITIMEN_PICKER
    sta.l cpu_regs.NMITIMEN
    rts

key_item_scroll_limit_impl:
"""
Scroll ceiling from the real item count: replaces `lda $ba / cmp #$11` at $00:B00D (vanilla's fixed 17).

Entry: 8-bit A, caller's D. Exit: Z set when $BA is already at the bottom (tested by `bne $B016`).
"""


    lda.l key_item_count
    sec
    sbc.b #_KEY_ITEM_VISIBLE_ITEMS
    bcs _limit_ready
; Fewer items than the window shows: there is nothing to scroll.
    lda.b #0x00

_limit_ready:
    cmp.b 0xBA
    rtl

key_item_scroll_down_impl:
"""
Replaces ScrollItemListDown ($00:B09E): animates $BB +2 px x 8 frames, steps it back one row and re-renders
the ring at the new scroll position.
"""


    php
    sep #0x20
    rep #0x10
    lda #_KEY_ITEM_SCROLL_FRAMES
    sta.l key_item_scroll_frames

_scroll_down_loop:
    jsr.l wait_for_vblank_long
    sep #0x20
    lda.b 0xBB
    clc
    adc.b #_KEY_ITEM_SCROLL_STEP_PX
    sta.b 0xBB
    lda.l key_item_scroll_frames
    dec
    sta.l key_item_scroll_frames
    bne _scroll_down_loop
    lda.b 0xBB
    sec
    sbc.b #_KEY_ITEM_ROW_HEIGHT_PX
    sta.b 0xBB
    jsr.w _key_item_rerender
    plp
    rtl

key_item_scroll_up_impl:
"""Mirror of `key_item_scroll_down_impl`."""
    php
    sep #0x20
    rep #0x10
    lda #_KEY_ITEM_SCROLL_FRAMES
    sta.l key_item_scroll_frames

_scroll_up_loop:
    jsr.l wait_for_vblank_long
    sep #0x20
    lda.b 0xBB
    sec
    sbc.b #_KEY_ITEM_SCROLL_STEP_PX
    sta.b 0xBB
    lda.l key_item_scroll_frames
    dec
    sta.l key_item_scroll_frames
    bne _scroll_up_loop
    lda.b 0xBB
    clc
    adc.b #_KEY_ITEM_ROW_HEIGHT_PX
    sta.b 0xBB
    jsr.w _key_item_rerender
    plp
    rtl

_key_item_save_dma:
"""
Saves DMA ch3's registers: the picker's transfers reprogram ch3, which a map HDMA effect (mosaic) may own.
"""


    php
    sep #0x20
    rep #0x10
    ldx.w #0x0000

_save_dma_loop:
    lda.l dma_ch3.DMAP, x
    sta.l key_item_dma_save, x
    inx
    cpx.w #0x000B
    bne _save_dma_loop
    plp
    rts

_key_item_restore_dma:
"""Put channel 3's registers back."""
    php
    sep #0x20
    rep #0x10
    ldx.w #0x0000

_restore_dma_loop:
    lda.l key_item_dma_save, x
    sta.l dma_ch3.DMAP, x
    inx
    cpx.w #0x000B
    bne _restore_dma_loop
    plp
    rts

_key_item_vram_to_sram:
"""
Copies a VRAM slice to the `key_item_chr_save` bank. A = VRAM word address, X = SRAM address, Y = byte count.
Must run in vblank.
"""


    php
    rep #0x20
    sta.l ppu.VMADDL  ; VMADD
    sep #0x20
    lda #0x80
    sta.l ppu.VMAIN  ; VMAIN: increment after the high byte
    lda.l ppu.VMDATALREAD  ; prime the read latch (discarded)
    lda #0x81  ; DMAP: PPU -> CPU, two registers
    sta.l dma_ch3.DMAP
    lda #PPU.VMDATALREAD
    sta.l dma_ch3.BBAD
    rep #0x20
    txa
    sta.l dma_ch3.A1TL
    sep #0x20
    lda #key_item_chr_save >> 16
    sta.l dma_ch3.A1B
    rep #0x20
    tya
    sta.l dma_ch3.DASL
    sep #0x20
    lda #0x08
    sta.l cpu_regs.MDMAEN  ; MDMAEN ch3
    plp
    rts

_key_item_sram_to_vram:
"""Write one saved slice back. Same register contract as the save."""
    php
    rep #0x20
    sta.l ppu.VMADDL
    sep #0x20
    lda #0x80
    sta.l ppu.VMAIN
    lda #0x01  ; DMAP: CPU -> PPU, two registers
    sta.l dma_ch3.DMAP
    lda #PPU.VMDATAL
    sta.l dma_ch3.BBAD
    rep #0x20
    txa
    sta.l dma_ch3.A1TL
    sep #0x20
    lda #key_item_chr_save >> 16
    sta.l dma_ch3.A1B
    rep #0x20
    tya
    sta.l dma_ch3.DASL
    sep #0x20
    lda #0x08
    sta.l cpu_regs.MDMAEN
    plp
    rts

_key_item_save_vram:
"""Saves the glyph CHR the picker is about to overwrite."""
    php
    jsr.w _key_item_save_dma
    sep #0x20
    rep #0x10
; Not the tilemap: vanilla has already drawn its window there and restores the map itself on close.
    jsr.l wait_for_vblank_long
    rep #0x20
    lda.w #KEY_ITEM_VWF_VRAM_DEST_WORD
    ldx.w #key_item_chr_save & 0xFFFF
    ldy.w #KEY_ITEM_VWF_BYTE_COUNT
    jsr.w _key_item_vram_to_sram
    jsr.w _key_item_restore_dma
    plp
    rts

key_item_close_impl:
"""
Restores the saved CHR on close. Hooked over `lda #$01 / sta $ec` at the end of the close animation ($00:B05D).
"""


    php
    jsr.w _key_item_save_dma
    sep #0x20
    rep #0x10
    jsr.l wait_for_vblank_long
    rep #0x20
    lda.w #KEY_ITEM_VWF_VRAM_DEST_WORD
    ldx.w #key_item_chr_save & 0xFFFF
    ldy.w #KEY_ITEM_VWF_BYTE_COUNT
    jsr.w _key_item_sram_to_vram
    jsr.w _key_item_restore_dma
    sep #0x20
    lda #0x01
    sta.b 0xEC  ; the store this hook displaced
    plp
    rtl

_key_item_rerender:
"""Redraw the ring at vanilla's current scroll position ($BA)."""
    sep #0x20
    rep #0x10
    lda.b 0xBA
    sta.l key_item_last_scroll
    sta.l key_item_scroll_pos
    jsr.w _key_item_enter_render
    rep #0x30
    jsr.l _key_item_refresh_slots_impl
    sep #0x20
    rep #0x10
    jsr.w _key_item_push_window
    jsr.w _key_item_leave_render
    rts

_key_item_fn_render_slot_trampoline:
"""Bank-20 RTL wrapper around `_key_item_render_item_to_slot`."""
    php
    jsr.w _key_item_render_item_to_slot
    plp
    rtl

_key_item_fn_update_hdma_trampoline:
"""Bank-20 RTL wrapper around `_key_item_ensure_hdma_initialized`."""
    php
    jsr.w _key_item_ensure_hdma_initialized
    plp
    rtl

_key_item_fn_draw_window_trampoline:
"""Bank-20 RTL wrapper around `_key_item_draw_window`."""
    php
    jsr.w _key_item_draw_window
    plp
    rtl

_key_item_draw_window:
"""
Fills the staging page with the blank window body (rebuilt, so no VRAM reads).
"""


    php
    phb
    rep #0x30
    lda.w #0x7E7E
    pha
    plb
    plb
    ldx.w #0x0000

_draw_window_loop:
    jsr.w _key_item_window_cell
    sta.w _KEY_ITEM_STAGING_ADDR, x
    inx
    inx
    cpx.w #_KEY_ITEM_STAGING_SIZE
    bne _draw_window_loop
    sep #0x20
    plb
    plp
    rts

_key_item_push_window:
"""
On `transfer_pending`, flushes the glyph CHR, DMAs the staging page to BG3 $2C00 and copies the HDMA table, in
one vblank. No vanilla NMI push exists on the field.
"""


    php
    sep #0x20
    rep #0x10
    lda.l key_item_rolling.transfer_pending
    beq _push_window_done
    lda #0x00
    sta.l key_item_rolling.transfer_pending
    jsr.l wait_for_vblank_long
    jsr.w render.flush_chr_to_vram  ; RTS-ending, same bank-20 region
    rep #0x20
    lda.w #_KEY_ITEM_TILEMAP_VRAM_WORD
    sta.l ppu.VMADDL  ; VMADD
    sep #0x20
    lda #0x80
    sta.l ppu.VMAIN  ; VMAIN: word access, +1 word per write
    lda #0x01
    sta.l dma_ch3.DMAP  ; DMAP: word transfer
    lda #PPU.VMDATAL
    sta.l dma_ch3.BBAD
    rep #0x20
    lda.w #_KEY_ITEM_STAGING_ADDR
    sta.l dma_ch3.A1TL
    sep #0x20
    lda #0x7E
    sta.l dma_ch3.A1B
    rep #0x20
    lda.w #_KEY_ITEM_STAGING_SIZE
    sta.l dma_ch3.DASL
    sep #0x20
    lda #0x08
    sta.l cpu_regs.MDMAEN  ; MDMAEN ch3

; Publish the scroll table (shadow -> active).
    rep #0x30
    ldx.w #0x0000

_push_hdma_copy:
    lda.l _KEY_ITEM_HDMA_SHADOW, x
    sta.l _KEY_ITEM_HDMA_TABLE, x
    inx
    inx
    cpx.w #_KEY_ITEM_HDMA_TABLE_SIZE
    bcc _push_hdma_copy
    sep #0x20

_push_window_done:
    plp
    rts

_key_item_start_scroll_down_impl:
"""Starts the engine's scroll-down."""
    php
    rep #0x10
    lda.l key_item_scroll_pos
    ldx.w #key_item_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_down
    plp
    rtl

_key_item_start_scroll_up_impl:
"""Starts the engine's scroll-up."""
    php
    rep #0x10
    lda.l key_item_scroll_pos
    ldx.w #key_item_rolling
    jsr.l rolling_engine.rolling_engine_start_scroll_up
    plp
    rtl

_key_item_update_scroll_frame_impl:
"""Per-frame scroll tick."""
    php
    rep #0x10
    ldx.w #key_item_rolling
    jsr.l rolling_engine.rolling_engine_update_scroll_frame
    plp
    rtl

_key_item_finish_scroll_impl:
"""Finishes the engine scroll."""
    php
    rep #0x10
    lda.l key_item_scroll_pos
    ldx.w #key_item_rolling
    jsr.l rolling_engine.rolling_engine_finish_scroll
    plp
    rtl

_key_item_refresh_slots_impl:
"""Re-renders all slots."""
    php
    sep #0x20
    rep #0x10
    lda.l key_item_scroll_pos
    ldx.w #key_item_rolling
    jsr.l rolling_engine.rolling_engine_refresh_slots
    plp
    rtl
}
