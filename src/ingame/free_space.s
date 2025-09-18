*=0x01ff40
draw_window = 0x0180d9
check_if_description_was_rendered:
    pha

    cmp.l render.last_drawn_text_ptr
    bne _continue
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
{
    END_OF_FREE_SPACE:
    .if END_OF_FREE_SPACE > 0x01ffff {
        .debug '(Bank 0x01): End of free space was reached !'
    }
}