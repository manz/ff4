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
.extern update_fat_scroll_hdma
.extern clear_inventory_slot
.extern field_menu_nmi_dma_transfer_check_impl
.import "ingame/vanilla_trampolines"


.include "core/rolling_state.i"
.include "lib/rolling_buffer.i"
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
            sta 0x7E0007, x
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
Advance the scroll animation one frame by the list's step (_scroll_step_by_menu): scroll_anim_offset +-= step,
the cursor sprite Y ($0311) by as much when the cursor-row marker $1B19 is set, scroll_remaining -= step, then the
profile's HDMA shadow rebuild (the list slid by scroll_anim_offset) and the sprite / BG2 VRAM uploads.
In: X = state ptr.
"""


        {
            php
            rep #0x10
            sep #0x20
            lda.l rolling_x.menu_id, x
            phx
            rep #0x20
            and.w #0x00FF
            tax
            lda.l _scroll_step_by_menu, x
            and.w #0x00FF
            sta.l rolling_engine_scratch  ; the step, a word
            plx
            sep #0x20
            lda.l rolling_x.scroll_direction, x
            bpl _frame_positive
            rep #0x20
            lda.l rolling_x.scroll_anim_offset, x
            sec
            sbc.l rolling_engine_scratch
            sta.l rolling_x.scroll_anim_offset, x
            bra _frame_update_cursor

_frame_positive:
            rep #0x20
            lda.l rolling_x.scroll_anim_offset, x
            clc
            adc.l rolling_engine_scratch
            sta.l rolling_x.scroll_anim_offset, x

_frame_update_cursor:
            sep #0x20
            lda.l menu_cursor_data + 0x19  ; vanilla cursor-row marker
            beq _frame_no_cursor
            lda.l rolling_x.scroll_direction, x
            bpl _frame_cursor_down
            lda.w sprite_data + 0x11
            clc
            adc.l rolling_engine_scratch
            sta.w sprite_data + 0x11
            bra _frame_no_cursor

_frame_cursor_down:
            lda.w sprite_data + 0x11
            sec
            sbc.l rolling_engine_scratch
            sta.w sprite_data + 0x11

_frame_no_cursor:
            lda.l rolling_x.scroll_remaining, x
            sec
            sbc.l rolling_engine_scratch
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
            cmp.b #ROLLING_MENU_ID_FAT_CHOCOBO
            beq _frame_hdma_fat_chocobo
            jsr.w update_key_item_scroll_hdma
            bra _frame_hdma_done

_frame_hdma_sell:
            jsr.w update_sell_scroll_hdma
            bra _frame_hdma_done

_frame_hdma_equip:
            jsr.w update_equip_scroll_hdma
            bra _frame_hdma_done

_frame_hdma_fat_chocobo:
            jsr.w update_fat_scroll_hdma
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
; One vblank per step: the sprites, then the pending HDMA tables and VWF CHR, which would otherwise ride the menu
; loop's next 4 KB tilemap copy ($01:8078 hook) and run it past vblank, where the PPU drops it. No BG2 upload: no
; list draws there.
            jsr.l tfr_sprites_vblank_trampoline
            jsr.l field_menu_nmi_dma_transfer_check_impl
            plp
            rtl
        }

_scroll_step_by_menu:
; Pixels a scroll frame, by menu_id: field, treasure, drops, key items, sell, equip, Fat Chocobo.
        .db INVENTORY_SCROLL_PIXELS_PER_FRAME, INVENTORY_SCROLL_PIXELS_PER_FRAME, INVENTORY_SCROLL_PIXELS_PER_FRAME
        .db INVENTORY_SCROLL_PIXELS_PER_FRAME, VANILLA_SCROLL_PIXELS_PER_FRAME, VANILLA_SCROLL_PIXELS_PER_FRAME
        .db VANILLA_SCROLL_PIXELS_PER_FRAME

rolling_engine_hdma_rows:
"""
Write a list's row bands into its HDMA table: the visible_rows * 16 screen lines from content line
scroll_anim_offset (-16..16, 0 at rest). Band k shows ring slot (buffer_pos + k) mod (visible_rows + 1) at
BGnVOFS base_scroll + A + (slot - k) * 16 + scroll_anim_offset. At rest that is one 16-line band a row;
mid-scroll the first and last bands are partial, so the list slides by the pixel. k runs from -1 (the old top
row a scroll-down leaves) to visible_rows (the old bottom row a scroll-up leaves): both are the ring's spare slot.
In: 16-bit A/X/Y. X = state ptr, Y = table offset, DP $40-$42 = the table's long address, A = scroll added to
every row (the sell list's header shift). Out: Y = table offset past the bands. A clobbered, DP $44-$4B kept.
"""


        {
            php
            rep #0x30
            pha  ; the extra scroll
            lda.b 0x44
            pha
            lda.b 0x46
            pha
            lda.b 0x48
            pha
            lda.b 0x4A
            pha
            lda.l rolling_x.visible_rows, x
            and.w #0x00FF
            inc
            pha  ; buffer slots, at 1,s; the extra scroll at 11,s
; $44 = the scroll every band shares: base_scroll + extra + anim_offset
            lda 11, s
            clc
            adc.l rolling_x.base_scroll, x
            clc
            adc.l rolling_x.scroll_anim_offset, x
            sta.b 0x44
; $46 = k of the first band, (anim_offset + 16) / 16 - 1; $48 = the lines of it above the screen, mod 16
            lda.l rolling_x.scroll_anim_offset, x
            clc
            adc.w #16
            sta.b 0x48
            lsr
            lsr
            lsr
            lsr
            dec
            sta.b 0x46
            lda.b 0x48
            and.w #0x000F
            sta.b 0x48
; $4A = the screen lines left
            lda.l rolling_x.visible_rows, x
            and.w #0x00FF
            asl
            asl
            asl
            asl
            sta.b 0x4A

_hdma_rows_band:
            lda.w #16
            sec
            sbc.b 0x48
            cmp.b 0x4A
            bcc _hdma_rows_height
            lda.b 0x4A

_hdma_rows_height:
            sta.b 0x48
            sep #0x20
            sta [0x40], y
            rep #0x20
            iny
; slot = (buffer_pos + k + slots) mod slots, k >= -1
            lda.l rolling_x.buffer_pos, x
            and.w #0x00FF
            clc
            adc.b 0x46
            clc
            adc 1, s

_hdma_rows_mod:
            cmp 1, s
            bcc _hdma_rows_slot
            sec
            sbc 1, s
            bra _hdma_rows_mod

_hdma_rows_slot:
            sec
            sbc.b 0x46
            asl
            asl
            asl
            asl  ; (slot - k) * 16
            clc
            adc.b 0x44
            sta [0x40], y
            iny
            iny
            lda.b 0x4A
            sec
            sbc.b 0x48
            sta.b 0x4A
            inc.b 0x46
            stz.b 0x48
            lda.b 0x4A
            bne _hdma_rows_band
            pla
            pla
            sta.b 0x4A
            pla
            sta.b 0x48
            pla
            sta.b 0x46
            pla
            sta.b 0x44
            pla
            plp
            rtl
        }

rolling_engine_start_scroll_down:
"""
Start a scroll-down: advance buffer_pos (wrapping), pre-render the new bottom slot, arm the FSM (state 1,
remaining 16, direction +, anim_offset -16), set transfer_pending and seed the HDMA shadow.
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
            lda.l rolling_x.menu_id, x
            pha
            jsr.w _engine_dispatch_update_scroll_hdma
; Only the item menu (field, key items) gets its cursors redrawn and the pad read here. Treasure, drops, sell and
; equip scroll inside vanilla loops that read the pad themselves right after ($01:DA08, $01:C8F2, $01:BF42): a second
; read restarts the key repeat, and the item menu's cursors would land in their OAM slot 0.
            sep #0x20
            pla
            beq _finish_item_menu
            cmp.b #ROLLING_MENU_ID_KEY_ITEM
            bne _finish_done

_finish_item_menu:
            jsr.l draw_item_cursors_trampoline
            jsr.l update_ctrl_after_scroll_trampoline

_finish_done:
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
            cmp.b #ROLLING_MENU_ID_FAT_CHOCOBO
            beq _dispatch_fat_chocobo
            jsr.w update_key_item_scroll_hdma
            rts

_dispatch_sell:
            jsr.w update_sell_scroll_hdma
            rts

_dispatch_equip:
            jsr.w update_equip_scroll_hdma
            rts

_dispatch_fat_chocobo:
            jsr.w update_fat_scroll_hdma
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
            lda 0x7E0000, x
            sta.l 0x001F80
            lda 0x7E0001, x
            sta.l 0x001F81
            lda 0x7E0002, x
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
