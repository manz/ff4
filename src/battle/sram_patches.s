; inventory buffer
*=0x02991E
    jsr.l copy_battle_char
    nop

    nop
    nop
    nop

    nop
    nop


; inventory buffer
*=0x029932
    jsr.l copy_battle_char
    nop

    nop
    nop
    nop

    nop
    nop


; patch normal display_char to include 7FFFFF based switch
*=0x02A49B
    jsr.l battle_display_char
    rts

; patch normal display_dakuten_char to include 7FFFFF based switch
*=0x02A4AC
    jsr.l battle_display_dakuten_char
    rts

; enclose jsr build_tileset_function
; with 7FFFFF switch in the items related stuff.
*=0x02A06C
    jsr.w 0xFFC2

*=0x02FFC2
    jsr.l battle_flags.set_sram_copy
    jsr 0xA455
    jsr.l battle_flags.clear_sram_copy
    rts
msg_window_draw_text_trampoline:
    jsr.l messages_vwf.init
    jsr 0xA455
    jsr.l messages_vwf.deinit
    rts

