

"""
Shared rolling-buffer engine (single-column profile).

Each profile (field-menu items, treasure inventory, treasure drops,
key-item picker) instantiates the macros below with its own state RAM
base, HDMA shadow buffer, slot/visible counts, and per-profile hooks
for the bits that legitimately differ (HDMA header band layout,
copy-pending shadow signalling, etc.).

Conventions:
  - Macro-internal labels start with `_` so a816 keeps them scope-local
    (a816 1.1.0a13 promotes plain labels through `.scope` and macro
    invocations  ; underscores stay private).
  - State RAM access goes through the `RollingBufferState` struct
    (defined in src/items.i) so profile state blocks share layout.
  - Hooks are passed as label symbols and invoked via `jsr.w` so the
    65816 indirection cost is one extra jsr/rts pair per call site.
"""


; Default held-DOWN cadence shared between the field and treasure
; inventory rolling buffers. Single retune knob — bumping these here
; changes the feel for both menus.
;   PIXELS_PER_FRAME = 8 / TOTAL_PIXELS = 16 → 2-frame animation per
;   row, ≈20 rows/sec under held DOWN once the post-anim 1-frame
;   settle is counted.
INVENTORY_SCROLL_PIXELS_PER_FRAME := 8
INVENTORY_SCROLL_TOTAL_PIXELS := 16


.macro engine_update_scroll_hdma(
    state_base,
    hdma_shadow_addr,
    buffer_slots,
    visible,
    header_hook,
    footer_hook,
    signal_hook,
) {
    """
    Build the rolling-buffer HDMA scroll table in `hdma_shadow_addr`, based on
    `state_base.buffer_pos` / `base_scroll`. Profile supplies header_hook
    (above item rows), footer_hook (below item rows), signal_hook (NMI shadow
    -> active copy pending).
    """
    php
    rep #0x30
    pha
    phx
    phy
; Save DP scratch ($40-$43)
    lda.b 0x40
    pha
    lda.b 0x42
    pha
    ldx.w #0x0000
; Profile-specific top-of-table band(s).
    jsr.w header_hook
; Per-row entries: vram_slot = (buffer_pos + row) % buffer_slots
    stz.b 0x42
_row_loop:
    lda.w state_base + RollingBufferState.buffer_pos
    and.w #0x00FF
    clc
    adc.b 0x42
_mod_loop:
    cmp.w #buffer_slots
    bcc _mod_done
    sec
    sbc.w #buffer_slots
    bra _mod_loop
_mod_done:
; A = vram_slot (0..buffer_slots-1)
    asl
    asl
    asl
    asl
; A = vram_slot * 16
    sta.b 0x40
; row * 16 = scanline_offset
    lda.b 0x42
    and.w #0x00FF
    asl
    asl
    asl
    asl
; -scanline_offset
    eor.w #0xFFFF
    inc
    clc
    adc.b 0x40
    clc
    adc.w state_base + RollingBufferState.base_scroll
    sta.b 0x40
    sep #0x20
    lda #16
    sta.l hdma_shadow_addr, x
    inx
    rep #0x20
    lda.b 0x40
    sta.l hdma_shadow_addr, x
    inx
    inx
    rep #0x20
    inc.b 0x42
    lda.b 0x42
    cmp.w #visible
    bcs _row_loop_done
    jmp.w _row_loop
_row_loop_done:
; Profile-specific bottom-of-table band.
    jsr.w footer_hook
; End marker
    sep #0x20
    lda #0x00
    sta.l hdma_shadow_addr, x
; Profile-specific NMI signal (sets copy_pending shadow).
    jsr.w signal_hook
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


.macro engine_init_rolling_buffer(state_base, render_count, draw_window_hook, ensure_hdma_hook, render_slot_hook) {
    """
    Initialise the rolling buffer on menu entry: zero the 12-byte state block,
    mark base_scroll = $FFFF (sentinel), draw the inventory window border,
    run the profile's `ensure_hdma_hook`, then render `render_count` slots via
    `render_slot_hook` (each call sees `slot_index` already populated).
    Field menu uses VISIBLE_ITEMS  ; treasure uses BUFFER_SLOTS.
    """
    php
    pha
    jsr.w draw_window_hook
    lda.b 0x46
    pha
; Zero 12-byte rolling state, then mark base_scroll = $FFFF sentinel
    rep #0x20
    lda.w #0x0000
    sta.w state_base
    sta.w state_base + 2
    sta.w state_base + 4
    sta.w state_base + 6
    sta.w state_base + 8
    sta.w state_base + 10
    lda.w #0xFFFF
    sta.w state_base + RollingBufferState.base_scroll
    sep #0x20
    jsr.w ensure_hdma_hook
    lda #0x00
    sta.b 0x46
_init_loop:
    lda.b 0x46
    sta.w state_base + RollingBufferState.edge_row
    sta.w state_base + RollingBufferState.slot_index
    jsr.w render_slot_hook
    inc.b 0x46
    lda.b 0x46
    cmp #render_count
    bne _init_loop
    pla
    sta.b 0x46
    pla
    plp
    rtl
}


.macro engine_scroll_down_prepare(
    state_base,
    scroll_pos_addr,
    scroll_limit,
    visible,
    buffer_slots,
    ensure_hdma_hook,
    render_slot_hook,
    update_hdma_hook,
) {
    """
    Pre-render the new bottom item before a scroll-down animation begins. The slot vacated at top (buffer_pos)
    is reused for the new bottom  ; buffer_pos then advances modulo buffer_slots.
    """
    php
    sep #0x20
    jsr.w ensure_hdma_hook
    lda.w scroll_pos_addr
    cmp #scroll_limit
    bcs _down_done
    clc
    adc #visible
    sta.w state_base + RollingBufferState.edge_row
    lda.w state_base + RollingBufferState.buffer_pos
    sta.w state_base + RollingBufferState.slot_index
    jsr.w render_slot_hook
    inc.w state_base + RollingBufferState.buffer_pos
    lda.w state_base + RollingBufferState.buffer_pos
    cmp #buffer_slots
    bcc _down_buf_ok
    stz.w state_base + RollingBufferState.buffer_pos
_down_buf_ok:
    jsr.w update_hdma_hook
_down_done:
    plp
    rts
}


.macro engine_scroll_up_prepare(
    state_base,
    scroll_pos_addr,
    buffer_slots,
    ensure_hdma_hook,
    render_slot_hook,
    update_hdma_hook,
) {
    """
    Pre-render the new top item after the scroll-up state machine has decremented scroll_pos. buffer_pos walks
    backwards (with wrap) so the slot leaving the bottom edge is reused for the new top.
    """
    php
    sep #0x20
    jsr.w ensure_hdma_hook
    lda.w state_base + RollingBufferState.buffer_pos
    beq _up_wrap
    dec
    bra _up_wrap_done
_up_wrap:
    lda #buffer_slots - 1
_up_wrap_done:
    sta.w state_base + RollingBufferState.buffer_pos
    sta.w state_base + RollingBufferState.slot_index
    lda.w scroll_pos_addr
    sta.w state_base + RollingBufferState.edge_row
    jsr.w render_slot_hook
    jsr.w update_hdma_hook
    plp
    rts
}


.macro engine_start_scroll_down(
    state_base,
    scroll_pos_addr,
    visible,
    buffer_slots,
    total_pixels,
    pixels_per_frame,
    ensure_hdma_hook,
    render_slot_hook,
    update_hdma_hook,
) {
    """
    Kick off a non-blocking scroll-down animation: advance buffer_pos with wrap, pre-render the new bottom
    item, configure the scroll state machine (-16 anim offset, +pixels_per_frame direction).
    """
    php
    sep #0x20
    jsr.w ensure_hdma_hook
    inc.w state_base + RollingBufferState.buffer_pos
    lda.w state_base + RollingBufferState.buffer_pos
    cmp #buffer_slots
    bcc _start_dn_buf_ok
    stz.w state_base + RollingBufferState.buffer_pos
    lda #0x00
_start_dn_buf_ok:
    clc
    adc #visible - 1
_start_dn_mod:
    cmp #buffer_slots
    bcc _start_dn_mod_done
    sec
    sbc #buffer_slots
    bra _start_dn_mod
_start_dn_mod_done:
    sta.w state_base + RollingBufferState.slot_index
    lda.w scroll_pos_addr
    clc
    adc #visible - 1
    sta.w state_base + RollingBufferState.edge_row
    jsr.w render_slot_hook
    lda #0x01
    sta.w state_base + RollingBufferState.scroll_state
    lda #total_pixels
    sta.w state_base + RollingBufferState.scroll_remaining
    lda #pixels_per_frame
    sta.w state_base + RollingBufferState.scroll_direction
    rep #0x20
    lda.w #0xFFF0
    sta.w state_base + RollingBufferState.scroll_anim_offset
    sep #0x20
    lda #0x01
    sta.w state_base + RollingBufferState.transfer_pending
    jsr.w update_hdma_hook
    plp
    rtl
}


.macro engine_start_scroll_up(
    state_base,
    scroll_pos_addr,
    buffer_slots,
    total_pixels,
    ensure_hdma_hook,
    render_slot_hook,
    update_hdma_hook,
) {
    """
    Kick off a non-blocking scroll-up animation: walk buffer_pos backwards (wrap to buffer_slots-1),
    pre-render the new top item, configure the state machine (+16 anim offset, -2 direction).
    """
    php
    sep #0x20
    jsr.w ensure_hdma_hook
    lda.w state_base + RollingBufferState.buffer_pos
    beq _start_up_wrap
    dec
    bra _start_up_wrap_done
_start_up_wrap:
    lda #buffer_slots - 1
_start_up_wrap_done:
    sta.w state_base + RollingBufferState.buffer_pos
    sta.w state_base + RollingBufferState.slot_index
    lda.w scroll_pos_addr
    sta.w state_base + RollingBufferState.edge_row
    jsr.w render_slot_hook
    lda #0x01
    sta.w state_base + RollingBufferState.scroll_state
    lda #total_pixels
    sta.w state_base + RollingBufferState.scroll_remaining
    lda #0xFE
    sta.w state_base + RollingBufferState.scroll_direction
    rep #0x20
    lda.w #0x0010
    sta.w state_base + RollingBufferState.scroll_anim_offset
    sep #0x20
    lda #0x01
    sta.w state_base + RollingBufferState.transfer_pending
    jsr.w update_hdma_hook
    plp
    rtl
}


.macro engine_update_scroll_frame(state_base, pixels_per_frame, update_hdma_hook) {
    """
    One animation frame: advance scroll_anim_offset by pixels_per_frame towards 0 (sign-aware), nudge cursor
    sprite at $0311 if 'second item' mode is active, decrement scroll_remaining, refresh HDMA, then push
    sprites + BG2 to VRAM.
    """
    php
    rep #0x20
    lda.w state_base + RollingBufferState.scroll_anim_offset
    sep #0x20
    lda.w state_base + RollingBufferState.scroll_direction
    bpl _frame_positive
    rep #0x20
    lda.w state_base + RollingBufferState.scroll_anim_offset
    sec
    sbc.w #pixels_per_frame
    sta.w state_base + RollingBufferState.scroll_anim_offset
    bra _frame_update_cursor
_frame_positive:
    rep #0x20
    lda.w state_base + RollingBufferState.scroll_anim_offset
    clc
    adc.w #pixels_per_frame
    sta.w state_base + RollingBufferState.scroll_anim_offset
_frame_update_cursor:
    sep #0x20
    lda.w 0x1B19
    beq _frame_no_cursor
    lda.w state_base + RollingBufferState.scroll_direction
    bpl _frame_cursor_down
    inc.w 0x0311
    inc.w 0x0311
    bra _frame_no_cursor
_frame_cursor_down:
    dec.w 0x0311
    dec.w 0x0311
_frame_no_cursor:
    lda.w state_base + RollingBufferState.scroll_remaining
    sec
    sbc #pixels_per_frame
    sta.w state_base + RollingBufferState.scroll_remaining
    jsr.w update_hdma_hook
    jsr.l tfr_sprites_vblank_trampoline
    jsr.l tfr_bg2_tiles_vblank_trampoline
    plp
    rtl
}


.macro engine_finish_scroll(
    state_base,
    scroll_pos_addr,
    visible,
    buffer_slots,
    total_items,
    render_slot_hook,
    update_hdma_hook,
) {
    """
    End-of-animation: pre-render the next-scroll-direction edge slot (skip past list ends), reset scroll_state
    and anim_offset, refresh HDMA, run original cursor + post-scroll cleanup.
    """
    php
    sep #0x20
    lda.w state_base + RollingBufferState.scroll_direction
    bmi _finish_was_up
    lda.w state_base + RollingBufferState.buffer_pos
    beq _finish_dn_wrap
    dec
    bra _finish_dn_slot_ok
_finish_dn_wrap:
    lda #buffer_slots - 1
_finish_dn_slot_ok:
    sta.w state_base + RollingBufferState.slot_index
    lda.w scroll_pos_addr
    clc
    adc #visible
    cmp #total_items
    bcs _finish_skip
    sta.w state_base + RollingBufferState.edge_row
    jsr.w render_slot_hook
    lda #0x01
    sta.w state_base + RollingBufferState.transfer_pending
    bra _finish_skip
_finish_was_up:
    lda.w state_base + RollingBufferState.buffer_pos
    clc
    adc #visible
_finish_up_mod:
    cmp #buffer_slots
    bcc _finish_up_slot_ok
    sec
    sbc #buffer_slots
    bra _finish_up_mod
_finish_up_slot_ok:
    sta.w state_base + RollingBufferState.slot_index
    lda.w scroll_pos_addr
    beq _finish_skip
    dec
    sta.w state_base + RollingBufferState.edge_row
    jsr.w render_slot_hook
    lda #0x01
    sta.w state_base + RollingBufferState.transfer_pending
_finish_skip:
    stz.w state_base + RollingBufferState.scroll_state
    rep #0x20
    stz.w state_base + RollingBufferState.scroll_anim_offset
    sep #0x20
    jsr.w update_hdma_hook
    jsr.l draw_item_cursors_trampoline
    jsr.l update_ctrl_after_scroll_trampoline
    plp
    rtl
}


.macro engine_swap_redraw(
    state_base,
    scroll_pos_addr,
    buffer_slots,
    total_items,
    ensure_hdma_hook,
    render_slot_hook,
    clear_slot_hook,
    update_hdma_hook,
) {
    """
    Re-render all `buffer_slots` slots from the current buffer_pos after an item swap. Out-of-range items
    (scroll_pos+row >= total_items) are blanked via `clear_slot_hook` so the prefetch row doesn't show stale
    tiles. Resets scroll state so a mid-animation swap doesn't trigger spurious finish_scroll re-renders.
    """
    php
    sep #0x20
    jsr.w ensure_hdma_hook
    stz.w state_base + RollingBufferState.scroll_state
    stz.w state_base + RollingBufferState.scroll_remaining
    stz.w state_base + RollingBufferState.scroll_anim_offset
    stz.w state_base + RollingBufferState.scroll_anim_offset + 1
    lda.b 0x46
    pha
    lda #0x00
    sta.b 0x46
_swap_loop:
    lda.w state_base + RollingBufferState.buffer_pos
    clc
    adc.b 0x46
_swap_mod:
    cmp #buffer_slots
    bcc _swap_mod_done
    sec
    sbc #buffer_slots
    bra _swap_mod
_swap_mod_done:
    sta.w state_base + RollingBufferState.slot_index
    lda.w scroll_pos_addr
    clc
    adc.b 0x46
    cmp #total_items
    bcs _swap_clear
    sta.w state_base + RollingBufferState.edge_row
    jsr.w render_slot_hook
    bra _swap_next
_swap_clear:
    jsr.w clear_slot_hook
_swap_next:
    inc.b 0x46
    lda.b 0x46
    cmp #buffer_slots
    bne _swap_loop
    pla
    sta.b 0x46
    lda #0x01
    sta.w state_base + RollingBufferState.transfer_pending
    jsr.w update_hdma_hook
    plp
    rtl
}


.macro engine_refresh_slots(state_base, scroll_pos_addr, buffer_slots, render_slot_hook) {
    """
    Re-render all `buffer_slots` from current buffer_pos without resetting scroll state. Used by treasure's
    original redraw helper (post-swap rebuild path) where the engine itself didn't trigger the redraw.
    """
    php
    rep #0x10
    sep #0x20
    lda #0x00
    sta.b 0x46
_refresh_loop:
    lda.w scroll_pos_addr
    clc
    adc.b 0x46
    sta.w state_base + RollingBufferState.edge_row
    lda.w state_base + RollingBufferState.buffer_pos
    clc
    adc.b 0x46
_refresh_mod:
    cmp #buffer_slots
    bcc _refresh_mod_done
    sec
    sbc #buffer_slots
    bra _refresh_mod
_refresh_mod_done:
    sta.w state_base + RollingBufferState.slot_index
    jsr.w render_slot_hook
    inc.b 0x46
    lda.b 0x46
    cmp #buffer_slots
    bne _refresh_loop
    lda #0x01
    sta.w state_base + RollingBufferState.transfer_pending
    plp
    rtl
}
