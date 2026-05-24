"""Options-menu patches: rename palette colours (RGB → RVB), reposition labels and adjust slider offsets."""

;RGB -> RVB :o)

.alloc at 0x01D1BB {
        lda.b #0x57

    ; déplacement du curseur principal des options
}
.alloc at 0x01D247 {
        lda.b #0x00

    ; Cursor offset in controls menu (x)
}
.alloc at 0x01D4E6 {
        lda.b #0x03

    ; cursor y
}
.alloc at 0x01D4E2 {
        adc.b #0x4C
}
.alloc at 0x01D1B0 {
        load_system_menu_text_pointer(options.title)
}
.alloc at 0x01D1A4 {
        load_system_menu_text_pointer(options.config)

    ; move controls title window
}
.alloc at 0x01E204 {
        menu_window(4, 0, 22, 2)
}
.alloc at 0x01D487 {
        ldy.w #0xE204

    ; controles
}
.alloc at 0x01D48D {
        load_system_menu_text_pointer(options.controls)
}
