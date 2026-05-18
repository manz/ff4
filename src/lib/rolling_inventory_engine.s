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

Phase 1: stub. Returns immediately. Phase 2 will wire this up to
zero the engine scratch portion of `RollingBufferState`, draw the
window via `fn_draw_window`, pre-render the visible slots and arm
the per-instance HDMA channel.

In/out :
  X = state ptr (16-bit, bank $7E implied)
  Y = initial top_row (usually 0)
"""


    rtl

rolling_engine_tick:
"""
Per-frame state-machine tick (phase 1 stub).

Phase 2 will read the pad-down bits in A.b, advance the scroll
animation, mark dirty rows, and schedule the next slot to pre-render
when scrolling past the buffer edge.

In : X = state ptr, A.b = pad-down bits
"""


    rtl

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
"""Tear down HDMA channel + flush dirty rows on menu close (phase 1 stub)."""
    rtl
}
