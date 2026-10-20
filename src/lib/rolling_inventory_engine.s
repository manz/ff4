"""
Rolling-inventory engine: bank-$20 JSL entry points shared by the field items, treasure, drops, key-item, sell and
equip profiles.

ABI: X (16-bit, bank $7E) points at a `RollingBufferState`. Hooks are RTL trampolines reached through the state's
far pointers (fn_render_slot, fn_update_hdma, fn_draw_window).
"""


.import "core/items"

; The engine and the profiles call each other; the linker resolves the names declared here.
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
    Cold init: zero the engine scratch (top_row..transfer_pending, scroll_anim_offset, hdma_copy_pending,
    dirty_mask) and set base_scroll = $FFFF ("HDMA not armed", checked by fn_update_hdma). Config fields
    (visible_rows, slot_height_tiles, item_list_ptr, item_count, hdma_channel, vwf_cfg_ptr) must be filled first.
    In: X = state ptr. All registers clobbered.
"""


        {
            php
            sep #0x20
            rep #0x10
            lda.b #0x00
            sta.l rolling_x.top_row, x
            sta.l rolling_x.buffer_pos, x
            sta.l rolling_x.edge_row, x
            sta.l rolling_x.slot_index, x
            sta.l rolling_x.hdma_enable, x
; _pad (offset 7): a816 hides leading-underscore fields from outer scopes, so use the literal offset.
            sta.l 0x7E0007, x
            sta.l rolling_x.scroll_state, x
            sta.l rolling_x.scroll_remaining, x
            sta.l rolling_x.scroll_direction, x
            sta.l rolling_x.transfer_pending, x
            sta.l rolling_x.scroll_anim_offset, x
            sta.l rolling_x.scroll_anim_offset + 1, x
            sta.l rolling_x.hdma_copy_pending, x
            sta.l rolling_x.dirty_mask, x
            lda.b #0xFF
            sta.l rolling_x.base_scroll, x
            sta.l rolling_x.base_scroll + 1, x
            rep #0x10
            ldy.w #RollingBufferState.fn_draw_window
            jsr.w _engine_call_hook
; fn_update_hdma = the profile's *_ensure_hdma_initialized
            ldy.w #RollingBufferState.fn_update_hdma
            jsr.w _engine_call_hook
; fn_render_slot for each of visible_rows, with edge_row = slot_index = the counter.
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

; Push the init render to VRAM next vblank, or VRAM keeps vanilla's window-open upload until the first scroll
; (staircased drops window, clobbered treasure row 0).
            lda.b #0x01
            sta.l rolling_x.transfer_pending, x

            plp
            rtl
        }

rolling_engine_refresh_slots:
"""
    Re-render the visible_rows + 1 slots from buffer_pos without resetting the scroll state: edge_row =
    scroll_pos + n, slot_index = (buffer_pos + n) % buffer_slots. Sets transfer_pending.
    In: X = state ptr, A = scroll_pos (8-bit).
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
    Advance the scroll animation one frame: scroll_anim_offset +-= 8, the cursor sprite Y ($0311) by 2 when the
    cursor-row marker $1B19 is set, scroll_remaining -= 8, then the profile's HDMA shadow rebuild and the sprite /
    BG2 VRAM uploads. 8 px per frame matches every profile's *_SCROLL_PIXELS_PER_FRAME.
    In: X = state ptr.
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
; Per-profile HDMA builder by menu_id. Every id needs its own branch: the fall-through is the key-item builder,
; so a missing branch scribbles the picker's table.
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
    Start a scroll-down: advance buffer_pos (wrapping), pre-render the new bottom slot, arm the FSM (state 1,
    remaining 16, direction +8, anim_offset -16), set transfer_pending and seed the HDMA shadow.
    In: X = state ptr, A = scroll_pos (8-bit).
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
    Start a scroll-up: step buffer_pos back (wrapping to visible_rows), pre-render the new top slot, arm the FSM
    (state 1, remaining 16, direction $FE, anim_offset +16), set transfer_pending and seed the HDMA shadow.
    In: X = state ptr, A = scroll_pos (8-bit, already decremented by the caller).
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
    End of animation: pre-render the next prefetch slot, clear scroll_state and anim_offset, refresh the HDMA
    shadow and run vanilla's cursor and post-scroll trampolines.
      down: slot_index = buffer_pos - 1 (wrapping), edge_row = scroll_pos + visible_rows, skipped past the tail
      up:   slot_index = (buffer_pos + visible_rows) % buffer_slots, edge_row = scroll_pos - 1, skipped at 0
    In: X = state ptr, A = scroll_pos (8-bit).
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
    Re-render all visible_rows + 1 slots after an item swap; slots past item_count are cleared (field items
    only). Resets the scroll state so a mid-animation swap triggers no finish_scroll re-render.
    In: X = state ptr, A = scroll_pos (8-bit).
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
"""Jump to the profile's update_*_scroll_hdma by menu_id (bank $20, jsr.w). Every id needs its own branch."""


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
    JSL through the 3-byte hook at state + Y; skipped when all three bytes are zero.
    In: X = state ptr, Y = hook field offset, M = 8. A clobbered.
"""


        {
            phx
            phy
; Hook offset at $00:1F83, not DP: menu code runs with D = $0100, so DP $90 is the BG1HOFS shadow and NMI would
; scroll BG1 by the offset.
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
    Per-frame tick: while scroll_state != 0, decrement scroll_remaining; at zero, clear scroll_state and set
    transfer_pending. No ROM caller (engine tests only). In: X = state ptr.
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
"""Clear state.dirty_mask if set; no DMA. No ROM caller (engine tests only). In: X = state ptr. A clobbered."""


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
"""Decrement slot_index, wrapping to visible_rows - 1. In: X = state ptr. A clobbered."""


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
"""Increment slot_index, wrapping to 0 at visible_rows. In: X = state ptr. A clobbered."""


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
"""Set bit A (slot 0..visible_rows-1, 8-bit) in state.dirty_mask. In: X = state ptr."""


        {
            php
            sep #0x20
            pha
; Y counts the shift so X stays on the state.
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
"""Mark every slot dirty (dirty_mask = $FF). In: X = state ptr. A clobbered."""


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
    Menu close: clear hdma_enable and dirty_mask, base_scroll = $FFFF so the next init re-arms. HDMAEN is left to
    the profile's exit hook, which knows its channel. In: X = state ptr. A clobbered.
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
