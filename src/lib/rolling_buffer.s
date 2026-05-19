

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
