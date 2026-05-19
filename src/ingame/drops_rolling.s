

"""
Treasure-menu drops list rolling buffer (single column, 4 visible).

Drops are the 8-item array at $7E:FF28 shown in the upper window of
the treasure menu (Tente / Baguette / etc.). Original renders them as
a 4-row x 2-col grid via DrawTreasureList ($01:A15C). Item names in
French don't fit two columns, so drops moves to a single-column
rolling buffer matching the treasure inventory below it — engine
configured with 4 visible / 8 total / 5 buffer slots.

The drops buffer lives on BG3 alongside the treasure inventory  ; both
share VRAM tilemap $7000 with separate row bands. HDMA channel 4 is
free in original treasure (original uses ch7|ch5|ch3|ch2|ch0  ; ch6 is
ours for inventory) so drops drives BG3VOFS through ch4 over its
scanline band.

Wiring (TODO, separate commit):
  - Replace `jsr $A15C` at $01:D80E (entry) and $01:D92D (redraw
    helper) with `jsr.w drops_init` / `jsr.w drops_refresh_slots`.
  - Kill the BG2 window draw at $01:D7FC region (drops window
    becomes part of the BG3 single-layer flatten).
  - Re-record screenshot goldens once geometry settles.

State RAM layout (12 bytes from $1BE0, struct: RollingBufferState):
  $1BE0  top_row
  $1BE1  buffer_pos
  $1BE2  edge_row
  $1BE3  slot_index
  $1BE4  base_scroll (word)
  $1BE6  hdma_enable
  $1BE7  _pad
  $1BE8  scroll_state
  $1BE9  scroll_remaining
  $1BEA  scroll_direction
  $1BEB  transfer_pending
  $1BEC  scroll_anim_offset (word)
  $1BEE  hdma_copy_pending
"""


DROPS_VISIBLE_ITEMS := 5
DROPS_BUFFER_SLOTS := 6
DROPS_TOTAL_ITEMS := 8
DROPS_SCROLL_LIMIT := 3
DROPS_SCROLL_PIXELS_PER_FRAME := 8
DROPS_SCROLL_TOTAL_PIXELS := 16

; Drops rolling state moved out of $1B00-$1BFF (vanilla menu / sprite
; code writes to bytes past $1BEB) to clean $7E:9C30. Engine path needs
; the full 35-byte struct ; the macro path only ever touched the first
; 12 bytes so the original $1BE0 base worked there.
drops_rolling := 0x9C30
drops_rolling_top_row := drops_rolling + RollingBufferState.top_row
drops_rolling_buffer_pos := drops_rolling + RollingBufferState.buffer_pos
drops_rolling_edge_row := drops_rolling + RollingBufferState.edge_row
drops_rolling_slot_index := drops_rolling + RollingBufferState.slot_index
drops_rolling_base_scroll := drops_rolling + RollingBufferState.base_scroll
drops_hdma_enable := drops_rolling + RollingBufferState.hdma_enable
drops_scroll_state := drops_rolling + RollingBufferState.scroll_state
drops_scroll_remaining := drops_rolling + RollingBufferState.scroll_remaining
drops_scroll_direction := drops_rolling + RollingBufferState.scroll_direction
drops_transfer_pending := drops_rolling + RollingBufferState.transfer_pending
drops_scroll_anim_offset := drops_rolling + RollingBufferState.scroll_anim_offset
drops_hdma_copy_pending := drops_rolling + RollingBufferState.hdma_copy_pending

; Drops scroll position lives one byte past the state block so it
; doesn't collide with the engine's RollingBufferState fields. Other
; profiles read scroll_pos from a original menu byte ($1B1A field /
; $1BB7 treasure inventory); drops has no original equivalent.
drops_scroll_pos := 0x9C5F

; HDMA channel 4 (free in original treasure: enabled mask is $AD =
; ch7|ch5|ch3|ch2|ch0). Treasure inventory took ch6.
DROPS_HDMA4_CTRL := 0x4340
DROPS_HDMA4_DEST := 0x4341
DROPS_HDMA4_SRC_LO := 0x4342
DROPS_HDMA4_SRC_HI := 0x4343
DROPS_HDMA4_SRC_BANK := 0x4344

; Drops HDMA tables share field-menu/treasure-inventory shadow region
; ($7E:9800 / $7E:9840). The active table for drops is built into a
; separate slot in the same WRAM area at $7E:9880 / shadow $7E:98C0
; so the two BG3VOFS-driven channels (ch4 drops + ch6 inventory)
; don't fight over a single buffer.
DROPS_HDMA_TABLE_ADDR := 0x9880
DROPS_HDMA_TABLE := 0x7E9880
DROPS_HDMA_SHADOW_ADDR := 0x98C0
DROPS_HDMA_SHADOW := 0x7E98C0
DROPS_HDMA_BANK := 0x7E

DROPS_SCROLL_STATE_IDLE := 0
DROPS_SCROLL_STATE_SCROLLING := 1


; --- Profile hooks (stubs, real implementations land alongside the
;     drops geometry + tilemap layout work) -----------------------------------

drops_ensure_hdma_initialized:
"""Lazy init: pin BG4VOFS shadow to 0 + configure ch4 driving BG4VOFS on first scroll."""
    rep #0x20
    lda.w drops_rolling_base_scroll
    cmp.w #0xFFFF
    bne _drops_hdma_already_init

; treasure_drops_window is anchored at BG (0, 0): top border at BG
; row 0 = BG line 0. The HDMA header band offsets BG4VOFS so the
; window appears on screen at y=24 (matching where the original
; TreasureItemsWindow at $01:E275 lived). Items render at staging
; rows 4,6,8,10 — engine body math uses base_scroll=0 so screen
; y=32..95 reads exactly those rows.
    lda.w #0xFFE8
    ; -24: drops band starts at screen y=24. Items render at staging
    ; rows 2,4,6,8 (DrawItemName lays glyphs into the row pointed at by
    ; $1d = $29 + $40, so slot 0 with Y=$44 lands at row 2, not row 1).
    ; Engine body math `scroll = base + slot*16 - row*16` collapses to
    ; base for visible row 0..3 with buffer_pos=0; VOFS=-24 maps screen
    ; y=32..95 to BG lines 8..71. Item 0 at BG row 2 = lines 16..23 lies
    ; in the upper half of the body row 0 band (y=32..47).
    sta.w drops_rolling_base_scroll

; Configure HDMA channel 4: DIRECT mode 2 bytes, dest BG4VOFS ($2114),
; src $7E:9880 (drops active table).
    sep #0x20
    lda #0x02
    sta.l DROPS_HDMA4_CTRL
    lda #0x14
    sta.l DROPS_HDMA4_DEST
    rep #0x20
    lda.w #DROPS_HDMA_TABLE_ADDR
    sta.l DROPS_HDMA4_SRC_LO
    sep #0x20
    lda #DROPS_HDMA_BANK
    sta.l DROPS_HDMA4_SRC_BANK

; Enable ch4 (BG4VOFS) only. TM HDMA mask via ch1 disabled — writes
; to $212C per-scanline blank the screen for reasons not yet
; understood (probably PPU/HDMA timing quirk in BGMODE 0). For now
; rely on BG4 staging being zero-filled past the drops content (tile
; 0 = transparent if CHR slot 0 is blank); residual bleed is the
; trade-off.
    lda.l 0x7E1BAE
    ora #0x10
    sta.l 0x7E1BAE
    sta.w drops_hdma_enable
    ; Build the initial HDMA shadow table + signal the NMI shadow→active
    ; copy so ch4 has valid scroll values on the very first frame, not
    ; just after the first scroll-trigger update.
    jsr.w update_drops_scroll_hdma
    rts

_drops_hdma_already_init:
    sep #0x20
    rts

drops_render_item_to_slot:
"""Render one drops item from $7E:FF28 + edge_row*Item.__size into the BG3 buffer at $7E:D600 + slot_index*128 + 4."""
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
    ; Pin $29 = $C600 (BG4 staging). TreasureItemsWindow is already
    ; drawn on BG4 by original at $01:D817, so rendering drops items
    ; INTO that same BG4 frame keeps the layout self-contained: one
    ; window + items on one layer, one DMA path to VRAM.
    lda.w #0xC600
    sta.b 0x29
    sep #0x20
    lda.w drops_rolling_edge_row
    asl
    clc
    adc #0x28
    sta.b 0x5a
    lda #0xFF
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
    ; --- VWF tile-id offset for drops (disjoint from treasure inventory) ---
    ; `items_menu_vwf.draw_field_item_name` computes
    ; `tile_id_base = FIELD_ITEM_VWF_TILE_BASE + $5D * K`. Treasure inventory
    ; calls the same helper with $5D = treasure_slot_index ; if drops were
    ; to pass its raw slot_index too, both panels would land on the same
    ; tile_ids in BG3 CHR ($5000..$56E0) and the second renderer of each
    ; frame would overwrite the first one's glyphs (the garbage-tiles bug
    ; visible in the chest-with-monster-drop screen). Offset by 11 so
    ; drops slots 0..5 land at tile_ids $16E..$1A9 (CHR $56E0..$5A90),
    ; past treasure's 6-buffer-slot region at $100..$13B. drops's tilemap
    ; target stays at $7E:C600 (its own BG3 staging surface) so the offset
    ; only affects CHR allocation, not where the glyphs land on screen.
    ;
    ; VWF_CALLER_CTX=1 also tells items_menu_vwf to write the SECONDARY
    ; flush descriptor (DROPS_VWF_VRAM_DEST_WORD + DROPS_VWF_BYTE_COUNT +
    ; DROPS_VWF_CHR_SRC_OFFSET) and redirect VWF_CHR_DIRTY -> DIRTY_B so
    ; the NMI flush hits drops's VRAM range without trampling treasure's
    ; primary descriptor. Cleared after the render so subsequent
    ; treasure-side calls fall back to primary.
    lda.w drops_rolling_slot_index
    clc
    adc #DROPS_VWF_TILE_SLOT_OFFSET
    sta.b 0x5d
    lda #0x01
    sta.l VWF_CALLER_CTX
    rep #0x20
    lda.w drops_rolling_slot_index
    and.w #0x00FF
    xba
    lsr
    clc
    adc.w #0x0044
    tay
    sep #0x20
    jsr.l draw_item_slot_inner_trampoline
    lda #0x00
    sta.l VWF_CALLER_CTX
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

clear_drops_slot:
"""Blank a single drops tilemap slot. STUB."""
    rts

update_drops_scroll_hdma:
"""Build the drops HDMA shadow table via the shared engine."""
    engine_update_scroll_hdma(drops_rolling, DROPS_HDMA_SHADOW, DROPS_BUFFER_SLOTS, DROPS_VISIBLE_ITEMS, _drops_hdma_header, _drops_hdma_footer, _drops_hdma_signal)  ; noqa: E501

_drops_hdma_header:
"""Header: 32 lines at base (-24) — off-screen 24 lines + 8 lines top border."""
    sep #0x20
    lda #32
    sta.l DROPS_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w drops_rolling_base_scroll
    sta.l DROPS_HDMA_SHADOW, x
    inx
    inx
    rts

_drops_hdma_footer:
"""
Footer: 25 lines bottom border + 87 lines trail keeping BG4 off content.

Header (32) + body (5 visible × 16 = 80) + footer (25 + 87 = 112) = 224 visible scanlines.

The border zone runs 25 lines (vs the natural 16) to step the trail's starting BG line past
the bottom-border row. With the border zone @ -8, scanlines y=112..136 read BG rows 13..15
(border + 2 blank padding rows). The trail @ -24 then starts at y=137, reading BG row 14
— past the border row 13 — so the border tile doesn't get repeated for several scanlines as
the trail kicks in.

The +1 odd count (25 vs even) shifts the trail boundary to y=137 instead of y=136. ch6
(treasure BG3VOFS) has a band boundary at y=136 (border-to-body)  ; the +1 keeps ch4 (drops)
and ch6 from reloading on the same scanline.
"""


    sep #0x20
    lda #25
    sta.l DROPS_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w #0xFFF8
    ; -8: bottom border (BG row 13) at screen y=112..137. 25 lines covers BG rows 13..15
    ; (border + 2 blank padding) so the trail @ -24 starts at y=137 reading BG row 14
    ; instead of looping back to row 13 — prevents the border tile repeating visually.
    sta.l DROPS_HDMA_SHADOW, x
    inx
    inx
    sep #0x20
    lda #87
    sta.l DROPS_HDMA_SHADOW, x
    inx
    rep #0x20
    lda.w #0xFFE8
    ; -24 again: y=137..223 reads BG rows 14..24 (empty padding) so BG4 stays off content.
    sta.l DROPS_HDMA_SHADOW, x
    inx
    inx
    rts

_drops_hdma_signal:
"""NMI shadow-copy signal for the drops ch4 table."""
    sep #0x20
    lda #0x01
    sta.w drops_hdma_copy_pending
    rts


; --- Engine instantiations -------------------------------------------------

drops_init_impl:
"""
Init drops rolling buffer via the bank-20 engine. State + hook
far-ptrs live at $7E:9C30 (relocated out of $1B00-$1BFF). Drops render
onto BG4 staging ($7E:C600) alongside TreasureItemsWindow ($01:E275
def_window 1, 3, 27, 10) which the draw_window hook redraws first so
the engine can write items into the just-drawn frame without the
original $01:D817 DrawWindow call clobbering them.
"""
    php
    rep #0x30
    sep #0x20
    lda.b #DROPS_VISIBLE_ITEMS
    sta.l 0x7E0000 + drops_rolling + RollingBufferState.visible_rows
    lda.b #0x02
    sta.l 0x7E0000 + drops_rolling + RollingBufferState.slot_height_tiles
    ; item_list_ptr = $7E:FF28 (treasure drops table)
    lda.b #0x28
    sta.l 0x7E0000 + drops_rolling + RollingBufferState.item_list_ptr
    lda.b #0xFF
    sta.l 0x7E0000 + drops_rolling + RollingBufferState.item_list_ptr + 1
    lda.b #0x7E
    sta.l 0x7E0000 + drops_rolling + RollingBufferState.item_list_ptr + 2
    lda.b #DROPS_TOTAL_ITEMS
    sta.l 0x7E0000 + drops_rolling + RollingBufferState.item_count
    lda.b #0x04
    sta.l 0x7E0000 + drops_rolling + RollingBufferState.hdma_channel
    lda.b #0x80
    sta.l 0x7E0000 + drops_rolling + RollingBufferState.vwf_cfg_ptr
    lda.b #0x70
    sta.l 0x7E0000 + drops_rolling + RollingBufferState.vwf_cfg_ptr + 1
    lda.b #0x70
    sta.l 0x7E0000 + drops_rolling + RollingBufferState.vwf_cfg_ptr + 2
    lda.b #drops_fn_render_slot_trampoline & 0xFF
    sta.l 0x7E0000 + drops_rolling + RollingBufferState.fn_render_slot
    lda.b #( drops_fn_render_slot_trampoline >> 8 ) & 0xFF
    sta.l 0x7E0000 + drops_rolling + RollingBufferState.fn_render_slot + 1
    lda.b #( drops_fn_render_slot_trampoline >> 16 ) & 0xFF
    sta.l 0x7E0000 + drops_rolling + RollingBufferState.fn_render_slot + 2
    lda.b #drops_fn_update_hdma_trampoline & 0xFF
    sta.l 0x7E0000 + drops_rolling + RollingBufferState.fn_update_hdma
    lda.b #( drops_fn_update_hdma_trampoline >> 8 ) & 0xFF
    sta.l 0x7E0000 + drops_rolling + RollingBufferState.fn_update_hdma + 1
    lda.b #( drops_fn_update_hdma_trampoline >> 16 ) & 0xFF
    sta.l 0x7E0000 + drops_rolling + RollingBufferState.fn_update_hdma + 2
    lda.b #drops_fn_draw_window_trampoline & 0xFF
    sta.l 0x7E0000 + drops_rolling + RollingBufferState.fn_draw_window
    lda.b #( drops_fn_draw_window_trampoline >> 8 ) & 0xFF
    sta.l 0x7E0000 + drops_rolling + RollingBufferState.fn_draw_window + 1
    lda.b #( drops_fn_draw_window_trampoline >> 16 ) & 0xFF
    sta.l 0x7E0000 + drops_rolling + RollingBufferState.fn_draw_window + 2
    lda.b #ROLLING_MENU_ID_DROPS
    sta.l 0x7E0000 + drops_rolling + RollingBufferState.menu_id
    plp
    php
    rep #0x10
    ldx.w #drops_rolling
    jsr.l rolling_engine.rolling_engine_init
    plp
    rtl

drops_fn_render_slot_trampoline:
"""Bank-20 RTL wrapper around `drops_render_item_to_slot`."""
    php
    jsr.w drops_render_item_to_slot
    plp
    rtl

drops_fn_update_hdma_trampoline:
"""Bank-20 RTL wrapper around `drops_ensure_hdma_initialized`."""
    php
    jsr.w drops_ensure_hdma_initialized
    plp
    rtl

drops_fn_draw_window_trampoline:
"""Bank-20 RTL wrapper around `_drops_draw_window`."""
    php
    jsr.w _drops_draw_window
    plp
    rtl


_drops_draw_window:
"""Pre-render hook: SelectBG4 + DrawWindow(treasure_drops_window) so $29=$C600 is live before items render."""
    sep #0x20
    jsr.l _drops_select_bg4_trampoline
    rep #0x10
    ldy.w #treasure_drops_window
    jsr.l draw_window_trampoline
    sep #0x10
    rts

drops_start_scroll_down_impl:
"""Drops profile: kick scroll-down state machine."""
    engine_start_scroll_down(drops_rolling, drops_scroll_pos, DROPS_VISIBLE_ITEMS, DROPS_BUFFER_SLOTS, DROPS_SCROLL_TOTAL_PIXELS, DROPS_SCROLL_PIXELS_PER_FRAME, drops_ensure_hdma_initialized, drops_render_item_to_slot, update_drops_scroll_hdma)  ; noqa: E501

drops_start_scroll_up_impl:
"""Drops profile: kick scroll-up state machine."""
    engine_start_scroll_up(drops_rolling, drops_scroll_pos, DROPS_BUFFER_SLOTS, DROPS_SCROLL_TOTAL_PIXELS, drops_ensure_hdma_initialized, drops_render_item_to_slot, update_drops_scroll_hdma)  ; noqa: E501

drops_update_scroll_frame_impl:
"""Drops profile: per-frame scroll animation tick."""
    php
    rep #0x10
    ldx.w #drops_rolling
    jsr.l rolling_engine.rolling_engine_update_scroll_frame
    plp
    rtl

drops_finish_scroll_impl:
"""Drops profile: end-of-animation pre-render + cleanup."""
    engine_finish_scroll(drops_rolling, drops_scroll_pos, DROPS_VISIBLE_ITEMS, DROPS_BUFFER_SLOTS, DROPS_TOTAL_ITEMS, drops_render_item_to_slot, update_drops_scroll_hdma)  ; noqa: E501

drops_refresh_slots_impl:
"""Drops profile: re-render all 6 slots via the bank-20 engine."""
    php
    sep #0x20
    rep #0x10
    lda.l 0x7E0000 + drops_scroll_pos
    ldx.w #drops_rolling
    jsr.l rolling_engine.rolling_engine_refresh_slots
    plp
    rtl

drops_swap_redraw_impl:
"""Drops profile: post-swap re-render."""
    engine_swap_redraw(drops_rolling, drops_scroll_pos, DROPS_BUFFER_SLOTS, DROPS_TOTAL_ITEMS, drops_ensure_hdma_initialized, drops_render_item_to_slot, clear_drops_slot, update_drops_scroll_hdma)  ; noqa: E501
