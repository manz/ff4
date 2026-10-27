"""
Bank-$01 trampolines (`jsr.l` + `rts`, 5 bytes) into the bank-$20 rolling code, in the space freed at $01:EBD2 by
the init_bg_scroll_hdma relocation. Bank-$01 patches `jsr.w` these names.
"""

.import "core/preamble"
.import "ingame/vanilla_trampolines"
.import "ingame/drops_rolling"
.import "ingame/treasure_rolling"
.import "small_vwf/init"
.import "menus/tools_shop_text"
.import "ingame/shop_sell_rolling"
.import "ingame/equip_inventory_rolling"
.import "ingame/inventory_rolling"
.import "ingame/items_menu_vwf"
.import "core/items"

.include "ingame/macros.i"

.include "ingame/bank01_trampolines.i"
.import "core/vanilla"
.include "core/bank20.i"

_SELL_NAME_SLOT := 9  ; tiles $100 + 9 * 10

.alloc _bank01_inventory_trampolines in bank01_trampolines {
check_and_clear_count:
"""Trampoline to `check_and_clear_count_impl`."""
    jsr.l check_and_clear_count_impl
    rts

init_menu_rolling_buffer:
"""Trampoline to `init_menu_rolling_buffer_impl`."""
    jsr.l init_menu_rolling_buffer_impl
    rts

swap_redraw_hook_impl:
"""Trampoline to `swap_redraw_hook_impl_body`."""
    jsr.l swap_redraw_hook_impl_body
    rts

start_scroll_down:
"""Trampoline to `start_scroll_down_impl`."""
    jsr.l start_scroll_down_impl
    rts

start_scroll_up:
"""Trampoline to `start_scroll_up_impl`."""
    jsr.l start_scroll_up_impl
    rts

update_scroll_frame:
"""Trampoline to `update_scroll_frame_impl`."""
    jsr.l update_scroll_frame_impl
    rts

finish_scroll:
"""Trampoline to `finish_scroll_impl`."""
    jsr.l finish_scroll_impl
    rts

sell_init:
"""Trampoline to `sell_init_impl` (replaces DrawInventoryList)."""
    jsr.l sell_init_impl
    rts

sell_scroll_up:
"""Sell list scroll up, replacing vanilla's $9F loop."""
    jsr.l sell_scroll_up_impl
    rts

sell_scroll_down:
"""Sell list scroll down, replacing vanilla's $9F loop."""
    jsr.l sell_scroll_down_impl
    rts

sell_leave:
"""
Shop teardown over `jsr $873F` at $01:C304: reissues the displaced call, then disarms ch5 (left set, the shared
`field_menu_rolling.hdma_enable` would arm it over the field's BG3).
"""


    jsr.w restore_dlg_gfx_far
    jsr.l sell_disable_hdma
    rts

equip_init:
"""Trampoline to `equip_init_impl` (replaces DrawInventoryList)."""
    jsr.l equip_init_impl
    rts

equip_scroll_up:
"""Equip list scroll up, replacing vanilla's $99 loop."""
    jsr.l equip_scroll_up_impl
    rts

equip_scroll_down:
"""Equip list scroll down, replacing vanilla's $99 loop."""
    jsr.l equip_scroll_down_impl
    rts

equip_leave:
"""
Equip list teardown over `jsr $A2DC` at $01:BE70 (both exits of the list): disarms ch5, reissues the call.
"""


    jsr.l equip_disable_hdma
    jsr.w hide_cursor2
    rts

draw_field_item_name_trampoline:
"""
Trampoline to `items_menu_vwf.draw_field_item_name`. The $01:9060 patch must stay 4 bytes (`jsr.w` + `rts`):
$01:9064 is the entry of a vanilla sprite routine, and overwriting it hides the save-select sprites.
"""


    jsr.l items_menu_vwf.draw_field_item_name
    rts
}


; Treasure-menu trampolines (bodies in treasure_rolling.s).
.alloc _bank01_treasure_trampolines in bank01_trampolines {
_treasure_check_and_clear_count:
    jsr.l treasure_check_and_clear_count_impl
    rts

init_treasure_rolling_buffer:
"""Trampoline to `init_treasure_rolling_buffer_impl`."""
    jsr.l init_treasure_rolling_buffer_impl
    rts

treasure_refresh_slots:
"""Trampoline to `treasure_refresh_slots_impl`."""
    jsr.l treasure_refresh_slots_impl
    rts

_treasure_swap_redraw_hook_impl:
    jsr.l treasure_swap_redraw_hook_impl_body
    rts

_treasure_start_scroll_down:
    jsr.l treasure_start_scroll_down_impl
    rts

_treasure_start_scroll_up:
    jsr.l treasure_start_scroll_up_impl
    rts

_treasure_update_scroll_frame:
    jsr.l treasure_update_scroll_frame_impl
    rts

_treasure_finish_scroll:
    jsr.l treasure_finish_scroll_impl
    rts

_treasure_arm_cooldown:
"""Reload the held-DOWN debounce after a scroll trigger fired."""
    sep #0x20
    lda.b #TREASURE_SCROLL_COOLDOWN_FRAMES
    sta.w treasure_scroll_cooldown
    rts

_treasure_wait_vblank:
"""
Waits one vblank on a debounced abort. Without it the input loop spins unpaced: game time ($16A3) and the
cooldown freeze, and hold-to-scroll stops after one item.
"""


    jsr.w wait_vblank
    rts

treasure_scroll_down_trigger:
"""
Scroll-down trigger. Vanilla already moved $1BB7; while a scroll or the cooldown is running, undo that and wait a
frame, so a held button steps once per cooldown. Forces HDMA setup since some flows skip the init at $01:D933.
"""
    lda.w treasure_rolling.scroll_state
    bne _t_down_abort
    lda.w treasure_scroll_cooldown
    bne _t_down_abort
    jsr.l treasure_force_hdma_setup_far
    jsr.w _treasure_start_scroll_down
    jsr.w _treasure_arm_cooldown
    rts
_t_down_abort:
    dec.w menu_cursor_data + 0xb7
    jsr.w _treasure_wait_vblank
    rts

treasure_scroll_up_trigger:
"""Mirror of `treasure_scroll_down_trigger`."""
    lda.w treasure_rolling.scroll_state
    bne _t_up_abort
    lda.w treasure_scroll_cooldown
    bne _t_up_abort
    jsr.l treasure_force_hdma_setup_far
    jsr.w _treasure_start_scroll_up
    jsr.w _treasure_arm_cooldown
    rts
_t_up_abort:
    inc.w menu_cursor_data + 0xb7
    jsr.w _treasure_wait_vblank
    rts

treasure_main_loop_scroll_check:
"""
Replaces `jsr $82C0` at $01:DA08: ticks the scroll state machines, zeroing the input mask $01 while one runs,
then tail-jumps to $82C0.
"""
    jsr.l treasure_main_loop_far
    jmp.w update_ctrl_menu

_treasure_menu_entry_hook:
    jsr.l treasure_menu_entry_hook_impl
    rts

treasure_menu_exit_hook:
"""Trampoline to `treasure_menu_exit_hook_impl`."""
    jsr.l treasure_menu_exit_hook_impl
    rts

shop_draw_item_name:
"""
Sets $5D = row (the VWF slot) before DrawItemName; the shop list loop ($01:C4A0) keeps the item id there.
Entry: X = row * 2, A = item id (passed through).
"""


    pha
    txa
    lsr
    sta.b menu_dp.item_slot
    pla
    jmp.w draw_item_name

shop_sell_item_name:
"""
ConfirmSell ($01:CA02) item name in VWF slot 9 (tiles $15A-$163), clear of the list's slots.
Entry: A = item id (passed through). Preserves $5D.
"""
    pha
    lda.b #_SELL_NAME_SLOT
    sta.b menu_dp.item_slot
    pla
    pha
    jsr.w draw_item_name
    pla
    sta.b menu_dp.item_slot
    rts

drops_swap_index:
"""
Drops swap index for $01:DAAC: X = (cursor_row + drops_scroll_pos) * 2 into $7E:FF28.
"""


    lda.w menu_cursor_data + 0xb3
    clc
    adc.l drops_scroll_pos
    asl
    jsr.w tax16
    rts

drops_init:
"""Trampoline to `drops_init_impl`."""
    jsr.l drops_init_impl
    rts

drops_refresh_slots:
"""
Re-renders the drops slots, then sends BG4: the replaced redraw ($01:D929, after Tout prendre) sends only BG1/BG3.
"""
    jsr.l drops_refresh_slots_impl
    jmp.w tfr_bg4_tiles_vblank

drops_down_handler:
"""
Clamp site $01:D9E0, A = $1BB3 + 1: stores the row if visible, else starts a drops scroll-down.
"""
    jsr.l drops_down_handler_far
    rts

drops_up_handler:
"""
Clamp site $01:D9D1, A = $1BB3 - 1: stores the row if non-negative (N clear), else starts a drops scroll-up.
"""
    jsr.l drops_up_handler_far
    rts
}


.alloc _bank01_treasure_bodies in bank20_reloc {
"""
Treasure trampoline bodies, in bank $20: the bank-$01 space ($01:EBD2-$01:ED61) is only 400 bytes, and past it is
vanilla battle-animation code that is still called.
"""
treasure_main_loop_far:
; Cooldown ticks once per frame (game-time byte), not per call: the loop runs ~20 times in the frame a scroll ends.
    sep #0x20
    lda.l menu_frame_time
    cmp.w treasure_scroll_frame_seen
    beq _t_main_cd_done
    sta.w treasure_scroll_frame_seen
    lda.w treasure_scroll_cooldown
    beq _t_main_cd_done
    dec.w treasure_scroll_cooldown

_t_main_cd_done:
    lda.w treasure_rolling.scroll_state
    beq _treasure_main_check_drops_tick
    jsr.l treasure_update_scroll_frame_impl
    lda.w treasure_rolling.scroll_remaining
    bne _treasure_main_block_input
    jsr.l treasure_finish_scroll_impl
_treasure_main_check_drops_tick:
; Drops scroll tick, input blocked the same way.
    lda.w drops_rolling.scroll_state
    beq _treasure_main_check_xfer
    jsr.l drops_update_scroll_frame_impl
    lda.w drops_rolling.scroll_remaining
    bne _treasure_main_block_input
    jsr.l drops_finish_scroll_impl
_treasure_main_check_xfer:
; Re-rendered slots: push BG3 ($7E:D600); vanilla's loop only sends BG2 and sprites.
    lda.w treasure_rolling.transfer_pending
    beq _treasure_main_after_bg3
    jsr.l tfr_bg3_tiles_vblank_trampoline
    stz.w treasure_rolling.transfer_pending
_treasure_main_after_bg3:
; Drops: push BG4 ($7E:C600).
    lda.w drops_rolling.transfer_pending
    beq _treasure_main_after_xfer
    jsr.l tfr_bg4_tiles_vblank_trampoline
    stz.w drops_rolling.transfer_pending
_treasure_main_after_xfer:
    lda.w treasure_rolling.scroll_state
    beq _treasure_main_call_orig
_treasure_main_block_input:
    stz.b 0x01
_treasure_main_call_orig:
    rtl

treasure_force_hdma_setup_far:
"""
Configures HDMA ch6 -> BG3VOFS from $7E:9800, only in the treasure menu ($1BC6 set at $01:D80B, cleared at $01:D7E6).
"""


    lda.w menu_cursor_data + 0xc6
    bne _t_setup_in_treasure
    rtl
_t_setup_in_treasure:
    sep #0x20
    lda #0x02
    sta.l dma_ch6.DMAP  ; direct, 2 bytes
    lda #PPU.BG3VOFS
    sta.l dma_ch6.BBAD
    rep #0x20
    lda.w #0x9800  ; shared active table
    sta.l dma_ch6.A1TL
    sep #0x20
    lda #0x7E
    sta.l dma_ch6.A1B
    rep #0x20
; base_scroll = vanilla's BG3VOFS shadow ($9F, -120).
    lda 0x7E019F
    sta.w treasure_rolling.base_scroll
    sep #0x20
; Vanilla's $AD (ch7|ch5|ch3|ch2|ch0) + ch6 + ch4, minus ch2 (its BG3VOFS parallax overrides the ring scroll)
; and ch3 (the VWF CHR flush's DMA channel, no HDMA table).
    lda #0xF1
    sta.l field_menu_rolling.hdma_enable
    rtl

drops_down_handler_far:
    cmp #DROPS_VISIBLE_ITEMS
    bcc _drops_down_store
    pha
    lda.l drops_rolling.scroll_state
    bne _drops_down_busy
    lda.l drops_scroll_pos
    cmp #DROPS_TOTAL_ITEMS - DROPS_VISIBLE_ITEMS
    bcs _drops_down_busy
    inc
    sta.l drops_scroll_pos
    pla
    jsr.l drops_start_scroll_down_impl
    rtl
_drops_down_busy:
    pla
    rtl
_drops_down_store:
    sta.w menu_cursor_data + 0xb3
    rtl


drops_up_handler_far:
    bmi _drops_up_scroll
    sta.w menu_cursor_data + 0xb3
    rtl
_drops_up_scroll:
    pha
    lda.l drops_rolling.scroll_state
    bne _drops_up_busy
    lda.l drops_scroll_pos
    beq _drops_up_busy  ; already at top
    dec
    sta.l drops_scroll_pos
    pla
    jsr.l drops_start_scroll_up_impl
    rtl
_drops_up_busy:
    pla
    rtl
}


.alloc _bank01_shop_trampolines in bank01_trampolines {
shop_quantity_text_hook:
"""
Replaces `jsr $8301` at $01:C442 (buy) / $01:C7E7 (sell): draws the quantity block (its "1" in the 8x8 font),
then 'Que désirez vous ?' in the small-VWF description region.
"""


; Menu text first: its render resets the engine state the description's upload waits in.
    ldy.w #shops.quantity - 0x8000
    jsr.w draw_pos_text
    ldy.w #shop_quantity_one - 0x8000
    jsr.w draw_pos_text
    ldy.w #shops.que_desirez_vous
    jsr.l items_description.draw_trampoline_pos
    rts

shop_welcome_text_hook:
"""
Replaces `jmp $8301` at $01:C353: draws the action labels, then 'Puis-je vous aider ?' in the description region.
"""


; Menu text first: its render resets the engine state the description's upload waits in.
    ldy.w #shops.welcome_and_actions - 0x8000
    jsr.w draw_pos_text
    ldy.w #shops.puis_je_vous_aider
    jsr.l items_description.draw_trampoline_pos
    rts

shop_thanks_text_hook:
"""
Replaces `jsr $82FB` at $01:C751: draws the window (empty text block), then 'Merci !' in the description region.
"""


    jsr.w draw_window_text
    ldy.w #shops.merci
    jsr.l items_description.draw_trampoline_pos
    rts
}
