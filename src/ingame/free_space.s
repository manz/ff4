; ============================================================================
; Bank $01 Free Space - starts at $01FF35
; ============================================================================

*=0x01ff35
    draw_window = 0x0180d9

check_if_description_was_rendered:
"""Skip redrawing an item description if its text pointer matches `render.last_drawn_text_ptr` and the auto-counter ($4218/$4219) is non-zero."""
    pha
    lda.l 0x004218
    ora.l 0x004219
    bne _not_still
    pla
    pha

    cmp.l render.last_drawn_text_ptr
    bne _continue

_not_still:
    pla
    rts

_continue:
    sta.l render.last_drawn_text_ptr

    pla

    pha
    ldy.w #0xdcd6
    jmp _back

draw_vwf_message:
"""Render the VWF message at the current text pointer via the items_description trampoline."""
    jsr.l items_description.draw_trampoline
    rts

draw_window_and_vwf_message:
"""Open a menu window at the cursor and render its VWF message  ; advances Y past the window header before delegating to `draw_vwf_message_pos`."""

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
"""Like `draw_vwf_message_pos` but pre-loads the menu-strings bank into A so the trampoline can pick the right asset bank."""
    lda.b #messages.use_on_whom >> 16

draw_vwf_message_pos:
    jsr.l items_description.draw_trampoline_pos
    rts

.if 0 {
transform_window_trampoline:
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
    jsr.w 0x8301  ; draw text at position.
    load_system_menu_text_pointer(newgame.build_number)
    left = 1
    top = 27
    ldx.w #left * 2 + top * 64
    jsr.w 0x8798  ; copy text at position.
    rts
    }
}

; ============================================================================
; Inventory Rolling Buffer Trampolines and Handlers
; ============================================================================
.if INVENTORY_ROLLING_BUFFER {
swap_redraw_trampoline:
    jsr.w SwapRedrawHook_Impl
    jsr.w 0xA2D9  ; Clear second cursor (from original $A404)
    jmp.w 0xA40A  ; Skip $84BA (game's sequential redraw), go to RTS

main_loop_scroll_check:


    """Called from $019FF2 via jmp.w"""
    lda.w menu_scroll_state
    beq _main_loop_do_input
    jsr.w UpdateScrollFrame
    lda.w menu_scroll_remaining
    bne _main_loop_skip_input
    jsr.w FinishScroll
    jmp.w _main_loop_skip_input  ; Skip input on the frame scroll finishes
_main_loop_do_input:
    lda.b 0x01
    and #0x80
    beq _left_not_pressed
    jmp.w 0x9FF8
_left_not_pressed:
    jmp.w 0xA003
_main_loop_skip_input:
    jmp.w 0xA0FF

scroll_down_trigger:
    """--- scroll_down_trigger ---"""
    cmp #MENU_SCROLL_LIMIT
    beq _scroll_down_at_max
    inc
    sta.w 0x1B1A
    jsr.w StartScrollDown
_scroll_down_at_max:
    rts

scroll_up_trigger:
    """--- scroll_up_trigger ---"""
    lda.w 0x1B1A
    beq _scroll_up_at_top
    dec
    sta.w 0x1B1A
    jsr.w StartScrollUp
_scroll_up_at_top:
    rts

menu_entry_hook:
    """--- menu_entry_hook ---"""
    jsr.l MenuEntryHook_Impl
    rts

menu_exit_hook:
    """--- menu_exit_hook ---"""
    jsr.l MenuExitHook_Impl
    rts

nmi_dma_transfer_check:
    """--- nmi_dma_transfer_check ---"""
    jsr.l field_menu_nmi_dma_transfer_check_impl  ; In bank $20 (battle/inventory_rolling.s)
    rts

hdma_enable_hook:


    """
    Called during NMI before HDMA enable
    Must copy shadow -> active HDMA table BEFORE enabling HDMA
    """
    jsr.w nmi_dma_transfer_check  ; Copy shadow table to active (if pending)
    .db 0xAF  ; LDA.L opcode
    .dw menu_hdma_enable  ; $1BAE
    .db 0x7E  ; Bank $7E
    sta.w 0x420C
    rts

adjust_inventory_pointer:


    """Adjusts $5a to point to the first visible item based on scroll position"""
    stz.b 0x5d
    stz.b 0x5e
    lda.w 0x1B1A
    asl  ; scroll_pos * Item.__size = byte offset into $1440
    clc
    adc.b 0x5a
    sta.b 0x5a
    lda #0x00
    adc.b 0x5b
    sta.b 0x5b
    rts

item_use_refresh_hook:


    """
    Called after SelectItem2 to refresh display after item use
    Re-renders all visible slots to show updated quantity or empty slot
    """
    jsr.w SwapRedrawHook_Impl
    rts
}


END_OF_FREE_SPACE:
.if END_OF_FREE_SPACE > 0x01ffff {
    .debug 'Error: (Bank 0x01): End of free space was reached !'
}
