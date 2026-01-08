; ============================================================================
; Bank $01 Free Space - starts at $01FF34
; ============================================================================
*=0x01ff34
draw_window = 0x0180d9

check_if_description_was_rendered:
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
    jsr.l items_description.draw_trampoline
    rts
draw_window_and_vwf_message:

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
    lda.b #messages.use_on_whom >> 16

draw_vwf_message_pos:
    jsr.l items_description.draw_trampoline_pos
    rts

.if 0 {
transform_window_trampoline:
    jmp.l transform_window_far
}

copy_text_with_dakuten:
    jsr.l copy_text_with_dakuten_far
    rts

.if DEBUG {
display_build_number:
{
    jsr.w 0x8301 ; draw text at position.
    load_system_menu_text_pointer(newgame.build_number)
    left = 1
    top = 27
    ldx.w #left * 2 + top * 64
    jsr.w 0x8798 ; copy text at position.
    rts
}
}

; ============================================================================
; Inventory Rolling Buffer Trampolines and Handlers
; ============================================================================
.if INVENTORY_ROLLING_BUFFER {

SwapRedrawTrampoline:
    jsr.l   SwapRedrawHook_Impl
    jmp.w   0xA404

; --- MainLoopScrollCheck ---
; Called from $019FF2 via jmp.w
MainLoopScrollCheck:
    lda.w   menu_scroll_state
    beq     _main_loop_do_input
    jsr.w   UpdateScrollFrame
    lda.w   menu_scroll_remaining
    bne     _main_loop_skip_input
    jsr.w   FinishScroll
_main_loop_do_input:
    lda.b   0x01
    and     #0x80
    beq     _left_not_pressed
    jmp.w   0x9FF8
_left_not_pressed:
    jmp.w   0xA003
_main_loop_skip_input:
    jmp.w   0xA0FF

; --- ScrollDownTrigger ---
ScrollDownTrigger:
    cmp     #MENU_SCROLL_LIMIT
    beq     _scroll_down_at_max
    inc
    sta.w   0x1B1A
    jsr.w   StartScrollDown
_scroll_down_at_max:
    rts

; --- ScrollUpTrigger ---
ScrollUpTrigger:
    lda.w   0x1B1A
    beq     _scroll_up_at_top
    dec
    sta.w   0x1B1A
    jsr.w   StartScrollUp
_scroll_up_at_top:
    rts

; --- MenuEntryHook ---
MenuEntryHook:
    jsr.l   MenuEntryHook_Impl
    rts

; --- MenuExitHook ---
MenuExitHook:
    jsr.l   MenuExitHook_Impl
    rts

; --- NmiDmaTransferCheck ---
NmiDmaTransferCheck:
    jsr.l   NmiDmaTransferCheck_Impl
    rts

; --- HdmaEnableHook ---
; Called during NMI before HDMA enable
; Must copy shadow -> active HDMA table BEFORE enabling HDMA
HdmaEnableHook:
    jsr.w   NmiDmaTransferCheck     ; Copy shadow table to active (if pending)
    .db 0xAF                        ; LDA.L opcode
    .dw menu_hdma_enable            ; $1BAE
    .db 0x7E                        ; Bank $7E
    sta.w   0x420C
    rts

; --- AdjustInventoryPointer ---
; Adjusts $5a to point to the first visible item based on scroll position
AdjustInventoryPointer:
    stz.b   0x5d
    stz.b   0x5e
    lda.w   0x1B1A
    asl
    clc
    adc.b   0x5a
    sta.b   0x5a
    lda     #0x00
    adc.b   0x5b
    sta.b   0x5b
    rts

}


    END_OF_FREE_SPACE:
    .if END_OF_FREE_SPACE > 0x01ffff {
        .debug 'Error: (Bank 0x01): End of free space was reached !'
    }
