"""
Unified rolling-inventory engine - bank-20 entry points.

JSL-callable entry points shared by the rolling-inventory profiles
(field items, treasure, drops, key items, sell, equip).

ABI : `X` (16-bit, bank $7E implied) holds the pointer to a
`RollingBufferState` instance. Hooks are far-callable (RTL) trampolines
resolved through the struct's per-instance far pointers (fn_render_slot,
fn_update_hdma, fn_draw_window).
"""


.import "core/items"

; The profiles call into the engine and the engine dispatches back into
; their HDMA builders, so the two sides are mutually dependent. That is
; fine across modules: each compiles against the names it declares here
; and the linker resolves them.
.extern update_menu_scroll_hdma
.extern update_treasure_scroll_hdma
.extern update_drops_scroll_hdma
.extern update_key_item_scroll_hdma
.extern update_sell_scroll_hdma
.extern update_equip_scroll_hdma
.extern clear_inventory_slot
.import "ingame/vanilla_trampolines"


.include "core/rolling_state.i"
.include "core/bank20.i"
.import "core/vanilla"

.alloc _rolling_inventory_engine_block in bank20_reloc {
    .scope rolling_engine {
    """Bank-20 rolling-inventory engine entry points."""
rolling_engine_init:
"""
    Cold init for a rolling-inventory instance.

    Zeroes the engine scratch portion of `RollingBufferState`
    (everything from top_row through transfer_pending plus the
    scroll_anim_offset word + hdma_copy_pending byte) and stamps
    `base_scroll = $FFFF` as the "not-yet-HDMA-initialised" sentinel
    the per-menu fn_update_hdma hook checks. dirty_mask is cleared too so
    the first vblank flush has nothing to fire.

    Caller-managed config fields (visible_rows, slot_height_tiles,
    item_list_ptr, item_count, hdma_channel, vwf_cfg_ptr) are NOT
    touched  ; callers fill them in before invoking this entry.

    In/out :
      X = state ptr (16-bit, bank $7E implied)
      Y = unused
      All registers clobbered.
"""


    {
    php
    sep #0x20
    rep #0x10
    lda.b #0x00
; Zero engine scratch (top_row..transfer_pending + anim offset bytes +
; hdma_copy_pending + dirty_mask).
    sta.l rolling_x.top_row, x
    sta.l rolling_x.buffer_pos, x
    sta.l rolling_x.edge_row, x
    sta.l rolling_x.slot_index, x
    sta.l rolling_x.hdma_enable, x
; _pad byte (offset 7, struct-defined as `byte _pad`) ; a816 hides
; leading-underscore field names from outer scopes, so write through
; the literal offset rather than the symbolic name.
    sta.l 0x7E0007, x
    sta.l rolling_x.scroll_state, x
    sta.l rolling_x.scroll_remaining, x
    sta.l rolling_x.scroll_direction, x
    sta.l rolling_x.transfer_pending, x
    sta.l rolling_x.scroll_anim_offset, x
    sta.l rolling_x.scroll_anim_offset + 1, x
    sta.l rolling_x.hdma_copy_pending, x
    sta.l rolling_x.dirty_mask, x
; base_scroll = $FFFF sentinel ("HDMA not yet armed").
    lda.b #0xFF
    sta.l rolling_x.base_scroll, x
    sta.l rolling_x.base_scroll + 1, x
; Fire fn_draw_window hook when armed.
    rep #0x10
    ldy.w #RollingBufferState.fn_draw_window
    jsr.w _engine_call_hook
; Fire fn_update_hdma hook (= the per-menu *_ensure_hdma_initialized).
    ldy.w #RollingBufferState.fn_update_hdma
    jsr.w _engine_call_hook
; Loop `visible_rows` times, calling fn_render_slot for each row.
; Each iteration plants edge_row + slot_index = loop counter before
; firing the hook so the per-menu render reads the right values.
    sep #0x20
    lda.b #0x00

_engine_init_render_loop:
    pha
    sta.l rolling_x.edge_row, x
    sta.l rolling_x.slot_index, x
    ldy.w #RollingBufferState.fn_render_slot
    jsr.w _engine_call_hook
    pla
    inc
    cmp.l rolling_x.visible_rows, x
    bcc _engine_init_render_loop

; Stamp transfer_pending so the per-menu main-loop hook pushes the
; freshly-rendered staging buffer to VRAM on the next vblank - same
; contract as rolling_engine_refresh_slots. Without it the init
; render stays in WRAM until the first scroll, leaving VRAM showing
; whatever vanilla's window-open upload wrote (a staircased drops
; window + a clobbered treasure row 0).
    lda.b #0x01
    sta.l rolling_x.transfer_pending, x

    plp
    rtl
    }

rolling_engine_refresh_slots:
"""
    Re-render every slot in the rolling buffer from the current `buffer_pos`
    without resetting scroll state. Iterates `(visible_rows + 1)` times (visible window + prefetch
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
    sta.l rolling_engine_scratch  ; stash scroll_pos
    lda.l rolling_x.visible_rows, x
    inc  ; buffer_slots = visible_rows + 1
    sta.l rolling_engine_scratch + 1  ; stash buffer_slots
    lda.b #0x00

_engine_refresh_loop:
    pha
    clc
    adc.l rolling_engine_scratch
    sta.l rolling_x.edge_row, x
    pla
    pha
    clc
    adc.l rolling_x.buffer_pos, x

_engine_refresh_mod:
    cmp.l rolling_engine_scratch + 1
    bcc _engine_refresh_mod_done
    sec
    sbc.l rolling_engine_scratch + 1
    bra _engine_refresh_mod

_engine_refresh_mod_done:
    sta.l rolling_x.slot_index, x
    ldy.w #RollingBufferState.fn_render_slot
    jsr.w _engine_call_hook
    pla
    inc
    cmp.l rolling_engine_scratch + 1
    bcc _engine_refresh_loop
    lda.b #0x01
    sta.l rolling_x.transfer_pending, x
    plp
    rtl
    }

rolling_engine_update_scroll_frame:
"""
    Advance the scroll animation one frame :
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

    Pixels-per-frame hardcoded at 8  ; every profile's
    *_SCROLL_PIXELS_PER_FRAME uses that value.

    In : X = state ptr (16-bit, bank $7E implied)
    Out: scroll_anim_offset / scroll_remaining advanced, HDMA shadow +
         sprite / BG2 VRAM uploads driven by the per-menu trampolines.
"""


    {
    php
    rep #0x10
    sep #0x20
    lda.l rolling_x.scroll_direction, x
    bpl _frame_positive
    rep #0x20
    lda.l rolling_x.scroll_anim_offset, x
    sec
    sbc.w #8
    sta.l rolling_x.scroll_anim_offset, x
    bra _frame_update_cursor

_frame_positive:
    rep #0x20
    lda.l rolling_x.scroll_anim_offset, x
    clc
    adc.w #8
    sta.l rolling_x.scroll_anim_offset, x

_frame_update_cursor:
    sep #0x20
    lda.l menu_cursor_data + 0x19  ; vanilla cursor-row marker
    beq _frame_no_cursor
    lda.l rolling_x.scroll_direction, x
    bpl _frame_cursor_down
    inc.w sprite_data + 0x11
    inc.w sprite_data + 0x11
    bra _frame_no_cursor

_frame_cursor_down:
    dec.w sprite_data + 0x11
    dec.w sprite_data + 0x11

_frame_no_cursor:
    lda.l rolling_x.scroll_remaining, x
    sec
    sbc.b #8
    sta.l rolling_x.scroll_remaining, x
; Dispatch per-menu update_scroll_hdma via menu_id branch. The
; profiles' update_*_scroll_hdma functions live in bank-20 alongside
; this engine, so jsr.w (3-byte) reaches them cleanly. Every id needs
; its own branch: the tail is the key-item builder, not a generic
; one, so a profile that falls through here scribbles the picker's
; table instead of its own.
    lda.l rolling_x.menu_id, x
    beq _frame_hdma_field
    cmp.b #ROLLING_MENU_ID_TREASURE
    beq _frame_hdma_treasure
    cmp.b #ROLLING_MENU_ID_DROPS
    beq _frame_hdma_drops
    cmp.b #ROLLING_MENU_ID_SELL
    beq _frame_hdma_sell
    cmp.b #ROLLING_MENU_ID_EQUIP
    beq _frame_hdma_equip
    jsr.w update_key_item_scroll_hdma
    bra _frame_hdma_done

_frame_hdma_sell:
    jsr.w update_sell_scroll_hdma
    bra _frame_hdma_done

_frame_hdma_equip:
    jsr.w update_equip_scroll_hdma
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

rolling_engine_start_scroll_down:
"""
    Kick off a non-blocking scroll-down animation. Advances buffer_pos
    with wrap, pre-renders the new bottom slot via fn_render_slot, configures
    the scroll FSM (state = 1, remaining = 16 pixels, direction = +8 =
    positive = down, anim_offset = -16), stamps transfer_pending, and
    dispatches the per-menu update_scroll_hdma to seed the first frame's
    HDMA shadow.

    In : X = state ptr, A = current scroll_pos (8-bit)
    Out: scroll state machine armed for the next 2 frames of animation.
"""


    {
    php
    rep #0x10
    sep #0x20
    sta.l rolling_engine_scratch  ; stash scroll_pos
    ldy.w #RollingBufferState.fn_update_hdma
    jsr.w _engine_call_hook
; buffer_slots = visible_rows + 1
    lda.l rolling_x.visible_rows, x
    inc
    sta.l rolling_engine_scratch + 1
; inc buffer_pos with wrap
    lda.l rolling_x.buffer_pos, x
    inc
    cmp.l rolling_engine_scratch + 1
    bcc _start_dn_buf_ok
    lda.b #0x00

_start_dn_buf_ok:
    sta.l rolling_x.buffer_pos, x
; slot_index = (buffer_pos + visible_rows - 1) % buffer_slots
    clc
    adc.l rolling_x.visible_rows, x
    dec

_start_dn_mod:
    cmp.l rolling_engine_scratch + 1
    bcc _start_dn_mod_done
    sec
    sbc.l rolling_engine_scratch + 1
    bra _start_dn_mod

_start_dn_mod_done:
    sta.l rolling_x.slot_index, x
; edge_row = scroll_pos + visible_rows - 1
    lda.l rolling_engine_scratch
    clc
    adc.l rolling_x.visible_rows, x
    dec
    sta.l rolling_x.edge_row, x
    ldy.w #RollingBufferState.fn_render_slot
    jsr.w _engine_call_hook
; FSM : scroll_state = 1, remaining = 16, direction = +8 (positive = down)
    lda.b #0x01
    sta.l rolling_x.scroll_state, x
    lda.b #16
    sta.l rolling_x.scroll_remaining, x
    lda.b #8
    sta.l rolling_x.scroll_direction, x
    rep #0x20
    lda.w #0xFFF0
    sta.l rolling_x.scroll_anim_offset, x
    sep #0x20
    lda.b #0x01
    sta.l rolling_x.transfer_pending, x
    jsr.w _engine_dispatch_update_scroll_hdma
    plp
    rtl
    }

rolling_engine_start_scroll_up:
"""
    Kick off a non-blocking scroll-up animation. Walks buffer_pos backwards
    (wrap to visible_rows = buffer_slots - 1), pre-renders the new top
    slot, configures the FSM (state = 1, remaining = 16, direction = -2 =
    $FE = negative = up, anim_offset = +16), stamps transfer_pending,
    dispatches update_scroll_hdma.

    In : X = state ptr, A = current scroll_pos (8-bit, already decremented
         by the caller)
    Out: scroll state machine armed for next 2 frames of animation.
"""


    {
    php
    rep #0x10
    sep #0x20
    sta.l rolling_engine_scratch  ; stash scroll_pos
    ldy.w #RollingBufferState.fn_update_hdma
    jsr.w _engine_call_hook
    lda.l rolling_x.buffer_pos, x
    beq _start_up_wrap
    dec
    bra _start_up_wrap_done

_start_up_wrap:
; buffer_slots - 1 == visible_rows.
    lda.l rolling_x.visible_rows, x

_start_up_wrap_done:
    sta.l rolling_x.buffer_pos, x
    sta.l rolling_x.slot_index, x
    lda.l rolling_engine_scratch  ; scroll_pos
    sta.l rolling_x.edge_row, x
    ldy.w #RollingBufferState.fn_render_slot
    jsr.w _engine_call_hook
    lda.b #0x01
    sta.l rolling_x.scroll_state, x
    lda.b #16
    sta.l rolling_x.scroll_remaining, x
    lda.b #0xFE  ; -2 (negative = up direction)
    sta.l rolling_x.scroll_direction, x
    rep #0x20
    lda.w #0x0010
    sta.l rolling_x.scroll_anim_offset, x
    sep #0x20
    lda.b #0x01
    sta.l rolling_x.transfer_pending, x
    jsr.w _engine_dispatch_update_scroll_hdma
    plp
    rtl
    }

rolling_engine_finish_scroll:
"""
    End-of-animation : pre-render the next-direction edge slot (the one
    that becomes the new prefetch after the current animation lands),
    reset scroll_state + anim_offset, refresh the HDMA shadow, fire the
    vanilla cursor + post-scroll cleanup trampolines.

    For scroll-down (direction = +N): slot_index = buffer_pos - 1 (with
    wrap to buffer_slots - 1)  ; edge_row = scroll_pos + visible_rows ;
    skip render when scroll_pos + visible_rows >= item_count (past tail).

    For scroll-up (direction < 0, $FE) : slot_index = (buffer_pos + visible)
    mod buffer_slots  ; edge_row = scroll_pos - 1 ; skip render when
    scroll_pos == 0 (past head).

    In : X = state ptr, A = current scroll_pos (8-bit)
    Out: scroll FSM cleared, prefetch slot rendered, HDMA refreshed.
"""


    {
    php
    rep #0x10
    sep #0x20
    sta.l rolling_engine_scratch  ; stash scroll_pos
; buffer_slots = visible_rows + 1
    lda.l rolling_x.visible_rows, x
    inc
    sta.l rolling_engine_scratch + 1
    lda.l rolling_x.scroll_direction, x
    bmi _finish_was_up
; --- scroll-down post-anim ---
    lda.l rolling_x.buffer_pos, x
    beq _finish_dn_wrap
    dec
    bra _finish_dn_slot_ok

_finish_dn_wrap:
; buffer_slots - 1 == visible_rows
    lda.l rolling_x.visible_rows, x

_finish_dn_slot_ok:
    sta.l rolling_x.slot_index, x
    lda.l rolling_engine_scratch  ; scroll_pos
    clc
    adc.l rolling_x.visible_rows, x
    cmp.l rolling_x.item_count, x
    bcs _finish_skip
    sta.l rolling_x.edge_row, x
    ldy.w #RollingBufferState.fn_render_slot
    jsr.w _engine_call_hook
    lda.b #0x01
    sta.l rolling_x.transfer_pending, x
    bra _finish_skip

_finish_was_up:
; --- scroll-up post-anim ---
    lda.l rolling_x.buffer_pos, x
    clc
    adc.l rolling_x.visible_rows, x

_finish_up_mod:
    cmp.l rolling_engine_scratch + 1
    bcc _finish_up_slot_ok
    sec
    sbc.l rolling_engine_scratch + 1
    bra _finish_up_mod

_finish_up_slot_ok:
    sta.l rolling_x.slot_index, x
    lda.l rolling_engine_scratch  ; scroll_pos
    beq _finish_skip
    dec
    sta.l rolling_x.edge_row, x
    ldy.w #RollingBufferState.fn_render_slot
    jsr.w _engine_call_hook
    lda.b #0x01
    sta.l rolling_x.transfer_pending, x

_finish_skip:
    lda.b #0x00
    sta.l rolling_x.scroll_state, x
    rep #0x20
    lda.w #0x0000
    sta.l rolling_x.scroll_anim_offset, x
    sep #0x20
    jsr.w _engine_dispatch_update_scroll_hdma
    jsr.l draw_item_cursors_trampoline
    jsr.l update_ctrl_after_scroll_trampoline
    plp
    rtl
    }

rolling_engine_swap_redraw:
"""
    Re-render all `visible_rows + 1` slots from current buffer_pos after
    an item swap. Slots whose item index >= item_count are cleared via
    the built-in field-items clear path (other profiles have nothing to
    clear, so the call is skipped for them). Resets scroll
    state so a mid-animation swap doesn't trigger spurious finish_scroll
    re-renders.

    In : X = state ptr, A = current scroll_pos (8-bit)
    Out: all `visible_rows + 1` slots refreshed, transfer_pending = 1,
         HDMA shadow rebuilt via per-menu update_scroll_hdma.
"""


    {
    php
    rep #0x10
    sep #0x20
    sta.l rolling_engine_scratch  ; stash scroll_pos
    ldy.w #RollingBufferState.fn_update_hdma
    jsr.w _engine_call_hook
    lda.b #0x00
    sta.l rolling_x.scroll_state, x
    sta.l rolling_x.scroll_remaining, x
    sta.l rolling_x.scroll_anim_offset, x
    sta.l rolling_x.scroll_anim_offset + 1, x
; buffer_slots = visible_rows + 1
    lda.l rolling_x.visible_rows, x
    inc
    sta.l rolling_engine_scratch + 1  ; stash buffer_slots
    lda.b #0x00

_swap_loop:
    pha
    clc
    adc.l rolling_x.buffer_pos, x

_swap_mod:
    cmp.l rolling_engine_scratch + 1
    bcc _swap_mod_done
    sec
    sbc.l rolling_engine_scratch + 1
    bra _swap_mod

_swap_mod_done:
    sta.l rolling_x.slot_index, x
    pla
    pha
    clc
    adc.l rolling_engine_scratch
    cmp.l rolling_x.item_count, x
    bcs _swap_clear
    sta.l rolling_x.edge_row, x
    ldy.w #RollingBufferState.fn_render_slot
    jsr.w _engine_call_hook
    bra _swap_next

_swap_clear:
; Only field-items has a real clear ; skip the call unless menu_id == 0.
    lda.l rolling_x.menu_id, x
    bne _swap_next
    jsr.w clear_inventory_slot

_swap_next:
    pla
    inc
    cmp.l rolling_engine_scratch + 1
    bcc _swap_loop
    lda.b #0x01
    sta.l rolling_x.transfer_pending, x
    jsr.w _engine_dispatch_update_scroll_hdma
    plp
    rtl
    }

_engine_dispatch_update_scroll_hdma:
"""
    Branches to the per-menu update_*_scroll_hdma function based on
    state.menu_id. Every id needs its own branch (see the per-frame
    dispatch above). The functions live in bank-20 alongside the engine
    so a 16-bit jsr.w is enough.
"""


    {
    lda.l rolling_x.menu_id, x
    beq _dispatch_field
    cmp.b #ROLLING_MENU_ID_TREASURE
    beq _dispatch_treasure
    cmp.b #ROLLING_MENU_ID_DROPS
    beq _dispatch_drops
    cmp.b #ROLLING_MENU_ID_SELL
    beq _dispatch_sell
    cmp.b #ROLLING_MENU_ID_EQUIP
    beq _dispatch_equip
    jsr.w update_key_item_scroll_hdma
    rts

_dispatch_sell:
    jsr.w update_sell_scroll_hdma
    rts

_dispatch_equip:
    jsr.w update_equip_scroll_hdma
    rts

_dispatch_field:
    jsr.w update_menu_scroll_hdma
    rts

_dispatch_treasure:
    jsr.w update_treasure_scroll_hdma
    rts

_dispatch_drops:
    jsr.w update_drops_scroll_hdma
    rts
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
; cell). Not direct page: FF4's menu code sets DP=$0100 before calling
; the patch, so a `sty.b 0x90` lands at $0190 = the BG1HOFS shadow and
; vanilla NMI scrolls BG1 by the hook offset (26 px for fn_render_slot).
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

    Does not touch scroll_anim_offset or render slots. No ROM caller ;
    only the engine tests exercise it.

    In  : X = state ptr
    Out : scroll_remaining decremented (if scrolling), scroll_state
          cleared + transfer_pending set when animation completes.
"""


    {
    php
    sep #0x20
    lda.l rolling_x.scroll_state, x
    beq _tick_idle
    lda.l rolling_x.scroll_remaining, x
    sec
    sbc.b #0x01
    sta.l rolling_x.scroll_remaining, x
    bne _tick_still_scrolling
    lda.b #0x00
    sta.l rolling_x.scroll_state, x
    lda.b #0x01
    sta.l rolling_x.transfer_pending, x

_tick_still_scrolling:
_tick_idle:
    plp
    rtl
    }

rolling_engine_vblank_flush:
"""
    NMI-time flush.

    Reads `state.dirty_mask`, returns immediately on $00, otherwise
    clears the mask so the next vblank starts clean. Does no DMA. No ROM
    caller ; only the engine tests exercise it.

    In  : X = state ptr
    Out : state.dirty_mask = 0 if it was non-zero, A clobbered.
"""


    {
    php
    sep #0x20
    lda.l rolling_x.dirty_mask, x
    beq _flush_clean
    lda.b #0x00
    sta.l rolling_x.dirty_mask, x

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
    lda.l rolling_x.slot_index, x
    bne _cursor_up_dec
    lda.l rolling_x.visible_rows, x

_cursor_up_dec:
    dec
    sta.l rolling_x.slot_index, x
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
    lda.l rolling_x.slot_index, x
    inc
    cmp.l rolling_x.visible_rows, x
    bcc _cursor_dn_store
    lda.b #0x00

_cursor_dn_store:
    sta.l rolling_x.slot_index, x
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
; X stays state ptr ; use Y for the shift-left tally so X stays
; bound to the struct base for the dirty_mask write below.
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
    ora.l rolling_x.dirty_mask, x
    sta.l rolling_x.dirty_mask, x
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
    sta.l rolling_x.dirty_mask, x
    plp
    rtl
    }

rolling_engine_shutdown:
"""
    Tear down state on menu close.

    Zeroes `state.hdma_enable` + `state.dirty_mask` and resets
    `state.base_scroll` to the $FFFF sentinel so the next cold-init
    fn_update_hdma hook re-arms cleanly. Does not touch HDMAEN ($420C) :
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
    sta.l rolling_x.hdma_enable, x
    sta.l rolling_x.dirty_mask, x
    sta.l rolling_x.scroll_state, x
    sta.l rolling_x.transfer_pending, x
    sta.l rolling_x.hdma_copy_pending, x
    lda.b #0xFF
    sta.l rolling_x.base_scroll, x
    sta.l rolling_x.base_scroll + 1, x
    plp
    rtl
    }
    }
}
