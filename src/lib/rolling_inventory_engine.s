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
    plp
    rtl
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
NMI-time flush (phase 1 stub).

Walks `state.dirty_mask`, DMAs each dirty slot's VWF stage region to
VRAM and writes the tilemap entries. Must run inside force-blank or
the HDMA gap window. Phase 1 returns immediately.

In : X = state ptr
"""


    rtl

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
