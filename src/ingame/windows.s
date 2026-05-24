"""
Field-menu window-descriptor data (equip / status / options main windows) emitted via the `menu_window` macro
at fixed bank-$01 addresses.
"""
; equip main window

.alloc at 0x01dda9 {
        menu_window(0, 0, 30, 11)

    ; char 1
}
.alloc at 0x01dd95 {
        menu_window(0, 0, 30, 11)
        ; char 2
}
.alloc at 0x01dd99 {
        menu_window(0, 5, 30, 11)
        ; char 3
}
.alloc at 0x01dd9d {
        menu_window(0, 10, 30, 11)
        ; char 4
}
.alloc at 0x01dda1 {
        menu_window(0, 15, 30, 11)
        ; char 5
}
.alloc at 0x01dda5 {
        menu_window(0, 20, 30, 11)

    ; magic
    ;*=0x01B010
    ;    ldx.w #0xFF18 + 8
}
.alloc at 0x01dd55 {
        menu_window(1, 0, 19, 7)
}
.alloc at 0x01dd59 {
        menu_window(1, 5, 19, 7)
}
.alloc at 0x01dd5d {
        menu_window(1, 10, 19, 7)
}
.alloc at 0x01dd61 {
        menu_window(1, 15, 19, 7)
}
.alloc at 0x01dd65 {
        menu_window(1, 20, 19, 7)

    ; magic kind window
}
.alloc at 0x01dd69 {
        menu_window(23, 2, 7, 7)

    ; controls the amount of scroll to apply to bg4 to move the magic window kind window
}
.alloc at 0x01af90 {
        ; 01/AF90: A9 34        LDA #$34
        ; 01/AF92: 85 AD        STA $AD
        lda #0x68

    ; scroll out of the same window.
}
.alloc at 0x01b072 {
        lda #0x68

    ; status
}
.alloc at 0x01de01 {
        menu_window(0, 1, 29, 24)
        menu_window(18, 6, 12, 4)

    ; clear next line of text in the right menu
}
.alloc at 0x01a974 {
        ldy.w #0x270
        lda #7

    ; item title
}
.alloc at 0x01dcd2 {
        menu_window(22, 0, 7, 3)
}
