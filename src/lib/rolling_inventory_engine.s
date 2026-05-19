"""
Unified rolling-inventory engine — bank-20 entry points.

Phase 1 skeleton : declares the JSL-callable entry points specified in
plans/rolling_inventory_engine.md. Each entry currently delegates to
the existing macro-driven `engine_*` machinery in
`src/lib/rolling_buffer.s`, so callers can opt-in incrementally.

ABI : `X` (16-bit, bank $7E implied) holds the pointer to a
`RollingBufferState` instance. Hooks live in bank-01 as far-callable
trampolines and are resolved through the struct's per-instance far
pointers (`vwf_cfg_ptr`, hook ptrs, ...).

Phases 2..5 will port field-items / shop / key-items / drops + treasure
through these entries one by one  ; phase 6 deletes the duplicated macro
sites that remain in the per-menu source files.
"""


.scope rolling_engine {
    """Bank-20 rolling-inventory engine entry points (phase 1 stubs)."""
rolling_engine_init:
"""
Cold init for a rolling-inventory instance.

Zeroes the 12-byte engine scratch portion of `RollingBufferState`
(everything from top_row through transfer_pending plus the
scroll_anim_offset word + hdma_copy_pending byte) and stamps
`base_scroll = $FFFF` as the "not-yet-HDMA-initialised" sentinel
the per-menu ensure_hdma_hook checks. dirty_mask is cleared too so
the first vblank flush has nothing to fire.

Caller-managed config fields (visible_rows, slot_height_tiles,
item_list_ptr, item_count, hdma_channel, vwf_cfg_ptr) are NOT
touched  ; callers fill them in before invoking this entry and the
phase-2 render path will read them back.

In/out :
  X = state ptr (16-bit, bank $7E implied)
  Y = initial top_row (unused in phase 1  ; phase 2 will route this
      into the scroll-position pre-render)
  All registers clobbered.
"""


    {
    php
    sep #0x20
    rep #0x10
    lda.b #0x00
; Zero engine scratch (top_row..transfer_pending + anim offset bytes +
; hdma_copy_pending + dirty_mask).
    sta.l 0x7E0000 + RollingBufferState.top_row, x
    sta.l 0x7E0000 + RollingBufferState.buffer_pos, x
    sta.l 0x7E0000 + RollingBufferState.edge_row, x
    sta.l 0x7E0000 + RollingBufferState.slot_index, x
    sta.l 0x7E0000 + RollingBufferState.hdma_enable, x
; _pad byte (offset 7, struct-defined as `byte _pad`) ; a816 hides
; leading-underscore field names from outer scopes, so write through
; the literal offset rather than the symbolic name.
    sta.l 0x7E0007, x
    sta.l 0x7E0000 + RollingBufferState.scroll_state, x
    sta.l 0x7E0000 + RollingBufferState.scroll_remaining, x
    sta.l 0x7E0000 + RollingBufferState.scroll_direction, x
    sta.l 0x7E0000 + RollingBufferState.transfer_pending, x
    sta.l 0x7E0000 + RollingBufferState.scroll_anim_offset, x
    sta.l 0x7E0000 + RollingBufferState.scroll_anim_offset + 1, x
    sta.l 0x7E0000 + RollingBufferState.hdma_copy_pending, x
    sta.l 0x7E0000 + RollingBufferState.dirty_mask, x
; base_scroll = $FFFF sentinel ("HDMA not yet armed").
    lda.b #0xFF
    sta.l 0x7E0000 + RollingBufferState.base_scroll, x
    sta.l 0x7E0000 + RollingBufferState.base_scroll + 1, x
; Fire fn_draw_window hook when armed.
    rep #0x10
    ldy.w #RollingBufferState.fn_draw_window
    jsr.w _engine_call_hook
; Fire fn_update_hdma hook (= per-menu ensure_hdma_initialized in the
; field-items wiring). Phase 3+ may split this into ensure-once vs
; per-scroll-update hooks ; for now both share the slot.
    ldy.w #RollingBufferState.fn_update_hdma
    jsr.w _engine_call_hook
; Loop `visible_rows` times, calling fn_render_slot for each row.
; Each iteration plants edge_row + slot_index = loop counter before
; firing the hook so the per-menu render reads the right values.
    sep #0x20
    lda.b #0x00

_engine_init_render_loop:
    pha
    sta.l 0x7E0000 + RollingBufferState.edge_row, x
    sta.l 0x7E0000 + RollingBufferState.slot_index, x
    ldy.w #RollingBufferState.fn_render_slot
    jsr.w _engine_call_hook
    pla
    inc
    cmp.l 0x7E0000 + RollingBufferState.visible_rows, x
    bcc _engine_init_render_loop

    plp
    rtl
    }

rolling_engine_refresh_slots:
"""
Re-render every slot in the rolling buffer from the current `buffer_pos`
without resetting scroll state. Mirrors the legacy `engine_refresh_slots`
macro : iterates `(visible_rows + 1)` times (visible window + prefetch
slot), each iteration setting edge_row = scroll_pos + counter and
slot_index = (buffer_pos + counter) % buffer_slots, then firing
fn_render_slot. Stamps `transfer_pending = 1` on exit so the per-menu
NMI hook DMAs the BG staging buffer next vblank.

In : X = state ptr (16-bit, bank $7E implied)
     A = current scroll_pos value (8-bit)
Out: all `visible_rows + 1` slots re-rendered, transfer_pending set.
"""


    {
    php
    sep #0x20
    rep #0x10
    sta.l 0x001F84  ; stash scroll_pos
    lda.l 0x7E0000 + RollingBufferState.visible_rows, x
    inc  ; buffer_slots = visible_rows + 1
    sta.l 0x001F85  ; stash buffer_slots
    lda.b #0x00

_engine_refresh_loop:
    pha
    clc
    adc.l 0x001F84
    sta.l 0x7E0000 + RollingBufferState.edge_row, x
    pla
    pha
    clc
    adc.l 0x7E0000 + RollingBufferState.buffer_pos, x

_engine_refresh_mod:
    cmp.l 0x001F85
    bcc _engine_refresh_mod_done
    sec
    sbc.l 0x001F85
    bra _engine_refresh_mod

_engine_refresh_mod_done:
    sta.l 0x7E0000 + RollingBufferState.slot_index, x
    ldy.w #RollingBufferState.fn_render_slot
    jsr.w _engine_call_hook
    pla
    inc
    cmp.l 0x001F85
    bcc _engine_refresh_loop
    lda.b #0x01
    sta.l 0x7E0000 + RollingBufferState.transfer_pending, x
    plp
    rtl
    }

rolling_engine_update_scroll_frame:
"""
Advance the scroll animation one frame. Mirrors the legacy
`engine_update_scroll_frame` macro :
  - scroll_anim_offset += (scroll_direction < 0 ? -8 : +8)
  - if vanilla cursor-row marker $1B19 != 0, bump cursor sprite Y at
    $0311 by 2 pixels in the matching direction (down for negative
    direction, up for positive)
  - scroll_remaining -= 8 (animation timer countdown)
  - per-menu update_scroll_hdma trampoline rebuilds the HDMA shadow
    table (dispatched via state.menu_id)
  - tfr_sprites_vblank_trampoline + tfr_bg2_tiles_vblank_trampoline
    push sprite OAM + BG2 tiles into VRAM so the animation frame
    becomes visible.

Pixels-per-frame hardcoded at 8  ; every existing caller
(INVENTORY_SCROLL_PIXELS_PER_FRAME / TREASURE / DROPS / KEY_ITEM) uses
that value, so the constant moves into the engine.

In : X = state ptr (16-bit, bank $7E implied)
Out: scroll_anim_offset / scroll_remaining advanced, HDMA shadow +
     sprite / BG2 VRAM uploads driven by the per-menu trampolines.
"""


    {
    php
    rep #0x10
    sep #0x20
    lda.l 0x7E0000 + RollingBufferState.scroll_direction, x
    bpl _frame_positive
    rep #0x20
    lda.l 0x7E0000 + RollingBufferState.scroll_anim_offset, x
    sec
    sbc.w #8
    sta.l 0x7E0000 + RollingBufferState.scroll_anim_offset, x
    bra _frame_update_cursor

_frame_positive:
    rep #0x20
    lda.l 0x7E0000 + RollingBufferState.scroll_anim_offset, x
    clc
    adc.w #8
    sta.l 0x7E0000 + RollingBufferState.scroll_anim_offset, x

_frame_update_cursor:
    sep #0x20
    lda.l 0x7E1B19  ; vanilla cursor-row marker
    beq _frame_no_cursor
    lda.l 0x7E0000 + RollingBufferState.scroll_direction, x
    bpl _frame_cursor_down
    inc.w 0x0311
    inc.w 0x0311
    bra _frame_no_cursor

_frame_cursor_down:
    dec.w 0x0311
    dec.w 0x0311

_frame_no_cursor:
    lda.l 0x7E0000 + RollingBufferState.scroll_remaining, x
    sec
    sbc.b #8
    sta.l 0x7E0000 + RollingBufferState.scroll_remaining, x
; Dispatch per-menu update_scroll_hdma via menu_id branch. The four
; profiles' update_*_scroll_hdma functions live in bank-20 alongside
; this engine, so jsr.w (3-byte) reaches them cleanly.
    lda.l 0x7E0000 + RollingBufferState.menu_id, x
    beq _frame_hdma_field
    cmp.b #ROLLING_MENU_ID_TREASURE
    beq _frame_hdma_treasure
    cmp.b #ROLLING_MENU_ID_DROPS
    beq _frame_hdma_drops
    jsr.w update_key_item_scroll_hdma
    bra _frame_hdma_done

_frame_hdma_field:
    jsr.w update_menu_scroll_hdma
    bra _frame_hdma_done

_frame_hdma_treasure:
    jsr.w update_treasure_scroll_hdma
    bra _frame_hdma_done

_frame_hdma_drops:
    jsr.w update_drops_scroll_hdma

_frame_hdma_done:
    jsr.l tfr_sprites_vblank_trampoline
    jsr.l tfr_bg2_tiles_vblank_trampoline
    plp
    rtl
    }

_engine_call_hook:
"""
Internal helper. JSLs through a hook far-ptr stored at
`state[X + Y]`.

In  : X = state ptr (16-bit, bank $7E implied)
      Y = struct offset of the 3-byte hook field
      M = 8 (caller-managed)
Out : hook RTLs back to caller of _engine_call_hook. A clobbered.
      Hook is skipped if all three bytes are zero  ; null-safe.
"""


    {
    phx
    phy
; Stash hook-field offset at $00:1F83 (next to the $1F80-82 jmp-vec
; cell). Direct-page `sty.b 0x90` looked tempting but FF4's menu code
; sets DP=$0100 before calling our patch, so the store actually
; landed at $0190 = the BG1HOFS shadow ; vanilla NMI then scrolled
; BG1 by the hook offset (26 px for fn_render_slot) on every render.
    rep #0x20
    tya
    sta.l 0x001F83
    txa
    clc
    adc.l 0x001F83
    tax  ; X now points at the hook field's first byte
    sep #0x20
    lda.l 0x7E0000, x
    sta.l 0x001F80
    lda.l 0x7E0001, x
    sta.l 0x001F81
    lda.l 0x7E0002, x
    sta.l 0x001F82
    ora.l 0x001F80
    ora.l 0x001F81
    beq _engine_call_hook_null
    phk
    rep #0x20
    pea.w ( _engine_call_hook_return - 1 ) & 0xFFFF
    sep #0x20
    jmp [0x001F80]

_engine_call_hook_return:
_engine_call_hook_null:
    ply
    plx
    rts
    }

rolling_engine_tick:
"""
Per-frame state-machine tick.

Advances the scroll animation by one frame when scroll_state != 0 :
decrements scroll_remaining and, when it hits zero, clears
scroll_state and stamps transfer_pending = 1 so the next vblank
flush picks up the final frame. Returns immediately when
scroll_state is idle.

Phase 1.3 scope. Phase 2 will additionally drive scroll_anim_offset,
read the pad-down bits in A.b to start fresh scrolls, and route the
new edge slot through fn_render_slot once that hook lands in the
struct.

In  : X = state ptr
Out : scroll_remaining decremented (if scrolling), scroll_state
      cleared + transfer_pending set when animation completes.
"""


    {
    php
    sep #0x20
    lda.l 0x7E0000 + RollingBufferState.scroll_state, x
    beq _tick_idle
    lda.l 0x7E0000 + RollingBufferState.scroll_remaining, x
    sec
    sbc.b #0x01
    sta.l 0x7E0000 + RollingBufferState.scroll_remaining, x
    bne _tick_still_scrolling
    lda.b #0x00
    sta.l 0x7E0000 + RollingBufferState.scroll_state, x
    lda.b #0x01
    sta.l 0x7E0000 + RollingBufferState.transfer_pending, x

_tick_still_scrolling:
_tick_idle:
    plp
    rtl
    }

rolling_engine_vblank_flush:
"""
NMI-time flush.

Phase 1.4 scope : reads `state.dirty_mask`, returns immediately on
$00, otherwise clears the mask so the next vblank starts clean.
Phase 2 will wedge the real DMA-from-VWF-stage-to-VRAM dance in
between, driven by the `vwf_cfg_ptr` config and a small bank-01
trampoline  ; the dirty-mask gate + clear stays valid regardless of
how the DMA path lands.

Must run inside force-blank or the HDMA gap window so the DMA
doesn't tear visible scanlines (phase 2 concern).

In  : X = state ptr
Out : state.dirty_mask = 0 if it was non-zero, A clobbered.
"""


    {
    php
    sep #0x20
    lda.l 0x7E0000 + RollingBufferState.dirty_mask, x
    beq _flush_clean
    lda.b #0x00
    sta.l 0x7E0000 + RollingBufferState.dirty_mask, x

_flush_clean:
    plp
    rtl
    }

rolling_engine_cursor_up:
"""
Decrement slot_index, wrapping to (visible_rows - 1) at zero.

In  : X = state ptr (bank $7E implied)
Out : state.slot_index updated, A clobbered
"""


    {
    php
    sep #0x20
    lda.l 0x7E0000 + RollingBufferState.slot_index, x
    bne _cursor_up_dec
    lda.l 0x7E0000 + RollingBufferState.visible_rows, x

_cursor_up_dec:
    dec
    sta.l 0x7E0000 + RollingBufferState.slot_index, x
    plp
    rtl
    }

rolling_engine_cursor_down:
"""
Increment slot_index, wrapping to 0 when it would equal visible_rows.

In  : X = state ptr
Out : state.slot_index updated, A clobbered
"""


    {
    php
    sep #0x20
    lda.l 0x7E0000 + RollingBufferState.slot_index, x
    inc
    cmp.l 0x7E0000 + RollingBufferState.visible_rows, x
    bcc _cursor_dn_store
    lda.b #0x00

_cursor_dn_store:
    sta.l 0x7E0000 + RollingBufferState.slot_index, x
    plp
    rtl
    }

rolling_engine_invalidate_slot:
"""
Mark one slot dirty for the next vblank flush.

In : X = state ptr, A.b = slot index 0..visible_rows-1
Out : state.dirty_mask gets bit (1 << A) set
"""


    {
    php
    sep #0x20
    pha
; X stays state ptr ; use Y for the shift-left tally so we can keep
; X bound to the struct base for the dirty_mask write below.
    phx
    tay
    lda.b #0x01

_inv_slot_shift:
    cpy.w #0x0000
    beq _inv_slot_done
    asl
    dey
    bra _inv_slot_shift

_inv_slot_done:
    plx
    ora.l 0x7E0000 + RollingBufferState.dirty_mask, x
    sta.l 0x7E0000 + RollingBufferState.dirty_mask, x
    pla
    plp
    rtl
    }

rolling_engine_invalidate_all:
"""
Mark every visible slot dirty by setting dirty_mask = $FF.

In : X = state ptr
Out : state.dirty_mask = $FF, A clobbered
"""


    {
    php
    sep #0x20
    lda.b #0xFF
    sta.l 0x7E0000 + RollingBufferState.dirty_mask, x
    plp
    rtl
    }

rolling_engine_shutdown:
"""
Tear down state on menu close.

Zeroes `state.hdma_enable` + `state.dirty_mask` and resets
`state.base_scroll` to the $FFFF sentinel so the next cold-init
ensure_hdma_hook re-arms cleanly. Does not touch HDMAEN ($420C) :
the per-menu exit hook owns that bit (it knows which channel mask
to clear via `hdma_channel`).

In : X = state ptr
Out : engine state half-reset, A clobbered.
"""


    {
    php
    sep #0x20
    rep #0x10
    lda.b #0x00
    sta.l 0x7E0000 + RollingBufferState.hdma_enable, x
    sta.l 0x7E0000 + RollingBufferState.dirty_mask, x
    sta.l 0x7E0000 + RollingBufferState.scroll_state, x
    sta.l 0x7E0000 + RollingBufferState.transfer_pending, x
    sta.l 0x7E0000 + RollingBufferState.hdma_copy_pending, x
    lda.b #0xFF
    sta.l 0x7E0000 + RollingBufferState.base_scroll, x
    sta.l 0x7E0000 + RollingBufferState.base_scroll + 1, x
    plp
    rtl
    }
}
