.macro bank_switch() {
    cpy.w #0x8000
    bmi moved_text
    lda.b #0x01 ; this assumes we shoud load data from bank 1
    pha
    bra jump_to_original

moved_text:
    pha
    rep #0x20
    tya
    adc.w #0x8000
    tay
    sep #0x20
    pla
    phk ; this assumes that the text lives in the same bank as this routine.

jump_to_original:
    plb
}

.macro bank_switch_with_jump(jump_to) {
    bank_switch()
    jmp.l jump_to
}


display_text_in_menus:
{

    phb
    phd
    phx
    ldx.w #0x100
    phx
    pld

    bank_switch_with_jump(0x01830B)
}

load_text_with_destination_in_x:

    phb
    phd
    phx
    phx
    ldx.w #0x0100
    phx
    pld
    plx

    rep #0x20

    txa
    clc
    adc 0x29
    tax
    sep #0x20

    bank_switch_with_jump(0x018318)


display_window_with_text:
    phy
    phb
    bank_switch_with_jump(0x0180DD)

display_time:
    phb
    bank_switch()
    rep #0x20
    jmp.l 0x01879D

disable_save:
    lda.b #0x24
    sta 0xCA31    ;S
    sta 0xCA33    ;a
    sta 0xCA35    ;u
    sta 0xCA37    ;v
    sta 0xCA39    ;e
    sta 0xCA3B    ;r
    jmp.l 0x018947

load_classes_pointer:
    phx
    rep #0x20

    and.w #0x00FF
    asl
    tax

    lda.l assets_classes_ptr, x
    sep #0x20

    plx
    rtl

load_dextrelity_pointer:
    rep #0x20
    lda (0x60)
    and.w #0x00c0
    lsr
    lsr
    lsr
    lsr
    lsr
    phx
    tax
    lda.l 0x01e2d9, x
    plx
    tay
    sep #0x20
    rtl
