

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
DROPS_SCROLL_LIMIT := 4
DROPS_SCROLL_PIXELS_PER_FRAME := 8
DROPS_SCROLL_TOTAL_PIXELS := 16

drops_rolling := 0x1BE0
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
drops_scroll_pos := 0x1BEF

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
"""Capture $9F (BG3VOFS shadow) + configure ch4 on first call. STUB."""
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
    ; Pin $29 = $B600 (BG1 staging). SelectBG1 at $01:84A2 sets the same
    ; value before original DrawTreasureList. Inner reads ($29),y so the
    ; tilemap base must be live in DP at the time of the indirect.
    lda.w #0xB600
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
    lda.w drops_rolling_slot_index
    sta.b 0x5d
    rep #0x20
    lda.w drops_rolling_slot_index
    and.w #0x00FF
    xba
    lsr
    clc
    adc.w #0x0104
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

clear_drops_slot:
"""Blank a single drops tilemap slot. STUB."""
    rts

update_drops_scroll_hdma:
"""Build the drops HDMA shadow table via the shared engine."""
    engine_update_scroll_hdma(drops_rolling, DROPS_HDMA_SHADOW, DROPS_BUFFER_SLOTS, DROPS_VISIBLE_ITEMS, _drops_hdma_header, _drops_hdma_footer, _drops_hdma_signal)  ; noqa: E501

_drops_hdma_header:
"""Drops HDMA header band — top dialog frame at BASE scroll. STUB."""
    rts

_drops_hdma_footer:
"""Drops HDMA footer — locks scanlines past prefetch slot. STUB."""
    rts

_drops_hdma_signal:
"""NMI shadow-copy signal for drops channel. STUB."""
    rts


; --- Engine instantiations -------------------------------------------------

drops_init_impl:
"""
Init drops rolling buffer. Drops sit inside the treasure-menu window the inventory init already drew, so the
draw_window hook is a no-op.
"""
    engine_init_rolling_buffer(drops_rolling, DROPS_VISIBLE_ITEMS, _drops_draw_window_noop, drops_ensure_hdma_initialized, drops_render_item_to_slot)  ; noqa: E501


_drops_draw_window_noop:
"""Drops live inside the existing treasure-menu window — no frame to draw."""
    rts

drops_scroll_down_prepare:
"""Drops profile scroll-down pre-render."""
    engine_scroll_down_prepare(drops_rolling, drops_scroll_pos, DROPS_SCROLL_LIMIT, DROPS_VISIBLE_ITEMS, DROPS_BUFFER_SLOTS, drops_ensure_hdma_initialized, drops_render_item_to_slot, update_drops_scroll_hdma)  ; noqa: E501

drops_scroll_up_prepare:
"""Drops profile scroll-up pre-render."""
    engine_scroll_up_prepare(drops_rolling, drops_scroll_pos, DROPS_BUFFER_SLOTS, drops_ensure_hdma_initialized, drops_render_item_to_slot, update_drops_scroll_hdma)  ; noqa: E501

drops_start_scroll_down_impl:
"""Drops profile: kick scroll-down state machine."""
    engine_start_scroll_down(drops_rolling, drops_scroll_pos, DROPS_VISIBLE_ITEMS, DROPS_BUFFER_SLOTS, DROPS_SCROLL_TOTAL_PIXELS, DROPS_SCROLL_PIXELS_PER_FRAME, drops_ensure_hdma_initialized, drops_render_item_to_slot, update_drops_scroll_hdma)  ; noqa: E501

drops_start_scroll_up_impl:
"""Drops profile: kick scroll-up state machine."""
    engine_start_scroll_up(drops_rolling, drops_scroll_pos, DROPS_BUFFER_SLOTS, DROPS_SCROLL_TOTAL_PIXELS, drops_ensure_hdma_initialized, drops_render_item_to_slot, update_drops_scroll_hdma)  ; noqa: E501

drops_update_scroll_frame_impl:
"""Drops profile: per-frame scroll animation tick."""
    engine_update_scroll_frame(drops_rolling, DROPS_SCROLL_PIXELS_PER_FRAME, update_drops_scroll_hdma)

drops_finish_scroll_impl:
"""Drops profile: end-of-animation pre-render + cleanup."""
    engine_finish_scroll(drops_rolling, drops_scroll_pos, DROPS_VISIBLE_ITEMS, DROPS_BUFFER_SLOTS, DROPS_TOTAL_ITEMS, drops_render_item_to_slot, update_drops_scroll_hdma)  ; noqa: E501

drops_refresh_slots_impl:
"""Drops profile: re-render all 5 slots (original redraw helper path)."""
    engine_refresh_slots(drops_rolling, drops_scroll_pos, DROPS_BUFFER_SLOTS, drops_render_item_to_slot)

drops_swap_redraw_impl:
"""Drops profile: post-swap re-render."""
    engine_swap_redraw(drops_rolling, drops_scroll_pos, DROPS_BUFFER_SLOTS, DROPS_TOTAL_ITEMS, drops_ensure_hdma_initialized, drops_render_item_to_slot, clear_drops_slot, update_drops_scroll_hdma)  ; noqa: E501
