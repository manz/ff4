"""
Bank $01 free-space landing pad ($01:FF35+): tiny utility routines that fit in the slack reclaimed by
relocating other code.
"""
.import "preamble"
.import "battle/inventory_rolling"
.import "ingame/inventory_rolling_trampolines"
.import "small_vwf/init"
.import "ingame/inventory_rolling"
.import "menus/in_game_text"
.import "menus/start_screen_text"
.import "menus/system_menus_text"
.include "src/menus/system_menus_macros.i"

; ============================================================================
; Bank $01 Free Space - starts at $01FF35
; ============================================================================

.include "config.i"
.include "src/ingame/bank01_slack.i"
.import "vanilla"

.label _select_item_9ff8 = 0x019FF8
.label _select_item_a003 = 0x01A003
.label _select_item_a0ff = 0x01A0FF
.label _select_item2_a40a = 0x01A40A


.alloc _bank01_slack_pre_inventory in bank01_slack {
draw_vwf_message:
"""Render the VWF message at the current text pointer via the items_description trampoline."""
    jsr.l items_description.draw_trampoline
    rts

draw_window_and_vwf_message:
"""
Open a menu window at the cursor and render its VWF message  ; advances Y past the window header before
delegating to `_draw_vwf_message_pos`.
"""


    jsr.w draw_window
; NOTE: quirks from the hardcore bank switching can be solved by loading the bank in A before the call.
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
Like `_draw_vwf_message_pos` but pre-loads the menu-strings bank into A so the trampoline can pick the right
asset bank.
"""


    lda.b #messages.use_on_whom >> 16

_draw_vwf_message_pos:
    jsr.l items_description.draw_trampoline_pos
    rts

    .if 0 {
transform_window_trampoline:
"""JML trampoline into `transform_window_far`."""
    jmp.l transform_window_far
    }

copy_text_with_dakuten:
"""Near-call wrapper around `copy_text_with_dakuten_far` for callers in the same bank."""
    jsr.l copy_text_with_dakuten_far
    rts

    .if DEBUG {
display_build_number:
"""Render the `BUILD_DATE + version` string at column 1, row 27 of the title screen (DEBUG builds only)."""
    {
    jsr.w draw_pos_text  ; draw text at position.
    load_system_menu_text_pointer(newgame.build_number)
    left = 1
    top = 27
    ldx.w #left * 2 + top * 64
    jsr.w copy_text  ; copy text at position.
    rts
    }
    }
}

; end .alloc _bank01_slack_pre_inventory

; ============================================================================
; Inventory Rolling Buffer Trampolines and Handlers
; ============================================================================
.alloc _bank01_slack_inventory in bank01_slack {
    .if INVENTORY_ROLLING_BUFFER {
swap_redraw_trampoline:
"""JML trampoline into `swap_redraw_hook_impl` for the inventory swap redraw path."""
    jsr.w swap_redraw_hook_impl
    jsr.w hide_item_cursor2  ; Clear second cursor (from original $A404)
    jmp.w _select_item2_a40a  ; Skip $84BA (game's sequential redraw), go to RTS

main_loop_scroll_check:


"""Called from $019FF2 via jmp.w"""
    lda.w field_menu_rolling.scroll_state
    beq _main_loop_do_input
    jsr.w update_scroll_frame
    lda.w field_menu_rolling.scroll_remaining
    bne _main_loop_skip_input
    jsr.w finish_scroll
    jmp.w _main_loop_skip_input  ; Skip input on the frame scroll finishes
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
"""--- scroll_down_trigger ---"""
    cmp #MENU_SCROLL_LIMIT
    beq _scroll_down_at_max
    inc
    sta.w inventory_scroll_pos
    jsr.w start_scroll_down
_scroll_down_at_max:
    rts

scroll_up_trigger:
"""--- scroll_up_trigger ---"""
    lda.w inventory_scroll_pos
    beq _scroll_up_at_top
    dec
    sta.w inventory_scroll_pos
    jsr.w start_scroll_up
_scroll_up_at_top:
    rts

menu_entry_hook:
"""--- menu_entry_hook ---"""
    jsr.l menu_entry_hook_impl
    rts

menu_exit_hook:
"""--- menu_exit_hook ---"""
    jsr.l menu_exit_hook_impl
    rts

_nmi_dma_transfer_check:
"""--- _nmi_dma_transfer_check ---"""
    jsr.l field_menu_nmi_dma_transfer_check_impl  ; In bank $20 (battle/inventory_rolling.s)
    rts

hdma_enable_hook:


"""
Called during NMI before HDMA enable
Must copy shadow -> active HDMA table BEFORE enabling HDMA
"""


    jsr.w _nmi_dma_transfer_check  ; Copy shadow table to active (if pending)
    .db 0xAF  ; LDA.L opcode
    .dw field_menu_rolling.hdma_enable  ; $1BAE
    .db 0x7E  ; Bank $7E
    sta.w cpu_regs.HDMAEN
    rts

adjust_inventory_pointer:


"""Adjusts $5a to point to the first visible item based on scroll position"""
    stz.b menu_dp.item_slot
    stz.b 0x5e
    lda.w inventory_scroll_pos
    asl  ; scroll_pos * sizeof(Item) = byte offset into $1440
    clc
    adc.b menu_dp.item_ptr
    sta.b menu_dp.item_ptr
    lda #0x00
    adc.b menu_dp.item_ptr + 1
    sta.b menu_dp.item_ptr + 1
    rts

item_use_refresh_hook:


"""
Called after SelectItem2 to refresh display after item use
Re-renders all visible slots to show updated quantity or empty slot
"""


    jsr.w swap_redraw_hook_impl
    rts
    }
}


; end .alloc _bank01_slack_inventory
