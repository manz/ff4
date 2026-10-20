"""
Bank-$01 slack routines: VWF message helpers, build number, and the field inventory's rolling-buffer hooks.
"""
.import "core/preamble"
.import "battle/inventory_rolling"
.import "ingame/inventory_rolling_trampolines"
.import "small_vwf/init"
.import "ingame/inventory_rolling"
.import "ingame/menu_fade"
.import "menus/in_game_text"
.import "menus/start_screen_text"
.import "menus/system_menus_text"
.include "menus/system_menus_macros.i"

.include "ingame/bank01_slack.i"
.import "core/vanilla"

.label _select_item_9ff8 = 0x019FF8
.label _select_item_a003 = 0x01A003
.label _select_item_a0ff = 0x01A0FF
.label _select_item2_a40a = 0x01A40A


.alloc _bank01_slack_pre_inventory in bank01_slack {
draw_vwf_message:
"""Renders the VWF message at the current text pointer."""
    jsr.l items_description.draw_trampoline
    rts

draw_window_and_vwf_message:
"""
Draws the window at Y, then its VWF message right after the window header.
"""


    jsr.w draw_window
    pha
    rep #0x20
    tya
    adc.w #0x8000
    tay
    sep #0x20
    pla

    iny
    iny
    iny
    iny

draw_vwf_message_pos_with_bank:
"""
`_draw_vwf_message_pos` with A = the menu strings' bank.
"""


    lda.b #messages.use_on_whom >> 16

_draw_vwf_message_pos:
    jsr.l items_description.draw_trampoline_pos
    rts


display_build_number:
"""Render the version (after the build date in DEBUG builds) at column 1, row 27 of the title screen."""
    {
        jsr.w draw_pos_text
        load_system_menu_text_pointer(newgame.build_number)
        left = 1
        top = 27
        ldx.w #left * 2 + top * 64
        jsr.w copy_text
        rts
    }
}

.alloc _bank01_slack_inventory in bank01_slack {
swap_redraw_trampoline:
"""After a swap: rolling redraw, hide the second cursor, skip vanilla's redraw ($84BA)."""
    jsr.w swap_redraw_hook_impl
    jsr.w hide_item_cursor2
    jmp.w _select_item2_a40a

main_loop_scroll_check:


"""SelectItem input loop ($01:9FF2): runs a scroll frame, skipping input while scrolling."""
    lda.w field_menu_rolling.scroll_state
    beq _main_loop_do_input
    jsr.w update_scroll_frame
    lda.w field_menu_rolling.scroll_remaining
    bne _main_loop_skip_input
    jsr.w finish_scroll
    jmp.w _main_loop_skip_input  ; also on the frame the scroll finishes
_main_loop_do_input:
    lda.b 0x01
    and #0x80
    beq _left_not_pressed
    jmp.w _select_item_9ff8
_left_not_pressed:
    jmp.w _select_item_a003
_main_loop_skip_input:
    jmp.w _select_item_a0ff

scroll_down_trigger:
"""A = scroll position; starts a scroll down unless at the limit."""
    cmp #MENU_SCROLL_LIMIT
    beq _scroll_down_at_max
    inc
    sta.w inventory_scroll_pos
    jsr.w start_scroll_down
_scroll_down_at_max:
    rts

scroll_up_trigger:
"""Starts a scroll up unless at the top."""
    lda.w inventory_scroll_pos
    beq _scroll_up_at_top
    dec
    sta.w inventory_scroll_pos
    jsr.w start_scroll_up
_scroll_up_at_top:
    rts

menu_entry_hook:
"""Item menu entry."""
    jsr.l menu_entry_hook_impl
    rts

menu_exit_hook:
"""
Item menu exit: fade out before the teardown drops the scroll HDMA, or the window visibly jumps first.
"""
    jsr.w menu_fade_out
    jsr.l menu_exit_hook_impl
    rts

_nmi_dma_transfer_check:
"""Pending HDMA shadow -> active copy."""
    jsr.l field_menu_nmi_dma_transfer_check_impl
    rts

hdma_enable_hook:


"""NMI: copy the HDMA shadow table to active, then write HDMAEN from the shadow."""


    jsr.w _nmi_dma_transfer_check
    .db 0xAF  ; lda.l field_menu_rolling.hdma_enable
    .dw field_menu_rolling.hdma_enable
    .db 0x7E
    sta.w cpu_regs.HDMAEN
    rts

adjust_inventory_pointer:


"""Points $5A at the first visible item."""
    stz.b menu_dp.item_slot
    stz.b 0x5e
    lda.w inventory_scroll_pos
    asl  ; 2 bytes per item
    clc
    adc.b menu_dp.item_ptr
    sta.b menu_dp.item_ptr
    lda #0x00
    adc.b menu_dp.item_ptr + 1
    sta.b menu_dp.item_ptr + 1
    rts

item_use_refresh_hook:


"""After SelectItem2: re-render the visible slots (new quantity or empty slot)."""


    jsr.w swap_redraw_hook_impl
    rts
}
