; Shared rolling-buffer engine (single-column profile).
;
; Each profile (field-menu items, treasure inventory, treasure drops,
; key-item picker) instantiates the macros below with its own state RAM
; base, HDMA shadow buffer, slot/visible counts, and per-profile hooks
; for the bits that legitimately differ (HDMA header band layout,
; copy-pending shadow signalling, etc.).
;

; Conventions:
;   - Macro-internal labels start with `_` so a816 keeps them scope-local
;     (PR 38 in a816 1.1.0a12 promotes plain labels through `.scope` and
;     macro invocations; underscores stay private).
;   - State RAM access goes through the `RollingBufferState` struct
;     (defined in src/items.i) so profile state blocks share layout.
;   - Hooks are passed as label symbols and invoked via `jsr.w` so the
;     65816 indirection cost is one extra jsr/rts pair per call site.

; Builds the rolling-buffer HDMA scroll table in `hdma_shadow_addr`

; based on `state_base`'s buffer_pos / base_scroll. Profile supplies:
;   - `header_hook`: writes the "above the item rows" entries (one or
;     more), advancing X.
;   - `footer_hook`: writes the "below the item rows" entry/entries.
;   - `signal_hook`: marks the NMI shadow→active copy pending (some
;     profiles also mirror to a shared flag).
;
; Caller wraps a profile-specific entry-point label around this macro.
.macro engine_update_scroll_hdma(state_base, hdma_shadow_addr, buffer_slots, visible, header_hook, footer_hook, signal_hook) {
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


; Initialise the rolling buffer on menu entry. Zeroes the 12-byte state
; block, marks base_scroll with the $FFFF sentinel (lazy-capture path),
; draws the inventory window border, calls the profile's HDMA setup
; hook, then renders `render_count` slots via the profile's render
; hook.
;

; Profile supplies:
;   - `ensure_hdma_hook`: captures $93 (BG VOFS shadow) and configures
;     the profile's HDMA channel + shadow on first call.
;   - `render_slot_hook`: writes one item slot into the BG tilemap
;     buffer; called with `slot_index` already populated.
;
; `render_count` controls how many slots are filled at init. Field
; menu uses VISIBLE_ITEMS (skips the prefetch slot to avoid a one-frame
; leak below the window border); treasure uses BUFFER_SLOTS (no leak
; risk because vanilla redraws over the buffer before HDMA enables).
.macro engine_init_rolling_buffer(state_base, render_count, ensure_hdma_hook, render_slot_hook) {
    php
    pha
    rep #0x10
    ldy.w #0xDCCE
    jsr.l DrawWindow_Trampoline
    sep #0x10
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


.macro engine_scroll_down_prepare(state_base, scroll_pos_addr, scroll_limit, visible, buffer_slots, ensure_hdma_hook, render_slot_hook, update_hdma_hook) {
    """Pre-render the new bottom item before a scroll-down animation begins. The slot vacated at top (buffer_pos) is reused for the new bottom  ; buffer_pos then advances modulo buffer_slots."""
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


.macro engine_scroll_up_prepare(state_base, scroll_pos_addr, buffer_slots, ensure_hdma_hook, render_slot_hook, update_hdma_hook) {
    """Pre-render the new top item after the scroll-up state machine has decremented scroll_pos. buffer_pos walks backwards (with wrap) so the slot leaving the bottom edge is reused for the new top."""
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
