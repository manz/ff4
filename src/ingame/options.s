
;RGB -> RVB :o)
*=0x01D1BB
    lda.b #0x57

; déplacement du curseur principal des options
*=0x01D247
    lda.b #0x00

; Cursor offset in controls menu (x)
*=0x01D4E6
    lda.b #0x03

; cursor y
*=0x01D4E2
    adc.b #0x4C

*=0x01D1B0
    load_system_menu_text_pointer(options.title)

*=0x01D1A4
    load_system_menu_text_pointer(options.config)
    ;jsr.w draw_window_and_vwf_message


; move controls title window
*=0x01E204
    .db 0x50
    .db 0x00
    .db 0x0B
    .db 0x02

*=0x01D487
    ldy.w #0xE204

; controles
*=0x01D48D
    load_system_menu_text_pointer(options.controls)
