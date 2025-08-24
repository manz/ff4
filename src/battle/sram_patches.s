; inventory buffer
;*=0x02991E
;    jsr.l copy_battle_char
;    nop
;
;    nop
;    nop
;    nop
;
;    nop
;    nop
;
;
;; inventory buffer
;*=0x029932
;    jsr.l copy_battle_char
;    nop
;
;    nop
;    nop
;    nop
;
;    nop
;    nop


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
;*=0x02A06C
;   jsr.w sram_draw_text

; magic should be drawn to sram
;*=0x02A128
;   jsr.w sram_draw_text


; patches show attack window
*=0x02c99c + 4
    .dw attack_names

;; monster names vwf try but being clear at every monster
;; needs a way to have immortal renders and temporary ones (used only for a few instants)
;*=0x02a409
;    jsr.w msg_window_draw_text_trampoline
;
;; render attack names
;*=0x029d63
;    jsr.w msg_window_draw_text_trampoline

;; snatch play sound call to init the battle buffer
;*=0x038229
;    jsr.l render_allocator.init_battle_far

*=0x02FFC2
;sram_draw_text:
;    jsr.l battle_flags.set_sram_copy
;    jsr 0xA455
;    jsr.l battle_flags.clear_sram_copy
;    rts
msg_window_draw_text_trampoline:
    jsr.l messages_vwf.init
    jsr 0xA455
    jsr.l messages_vwf.deinit
    rts
attack_names:
    jsr.l messages_vwf.init
    jsr 0xcb32
    jsr.l messages_vwf.deinit
    rts

