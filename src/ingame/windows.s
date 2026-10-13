"""
Field-menu window descriptors (equip, magic, status, items) at their bank-$01 addresses.
"""
.import "core/preamble"
.include "ingame/macros.i"

; Equip main window
.alloc at 0x01dda9 {
    menu_window(0, 0, 30, 11)
}
; Equip, chars 1-5
.alloc at 0x01dd95 {
    menu_window(0, 0, 30, 11)
}
.alloc at 0x01dd99 {
    menu_window(0, 5, 30, 11)
}
.alloc at 0x01dd9d {
    menu_window(0, 10, 30, 11)
}
.alloc at 0x01dda1 {
    menu_window(0, 15, 30, 11)
}
.alloc at 0x01dda5 {
    menu_window(0, 20, 30, 11)
}
; Magic, chars 1-5
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
}
; Magic kind window
.alloc at 0x01dd69 {
    menu_window(23, 2, 7, 7)
}
; BG4 scroll ($AD, vanilla $34) sliding the magic kind window in, then out
.alloc at 0x01af90 {
    lda #0x68
}
.alloc at 0x01b072 {
    lda #0x68
}
; Status
.alloc at 0x01de01 {
    menu_window(0, 1, 29, 24)
    menu_window(18, 6, 12, 4)
}
; Clear the next text line in the right panel
.alloc at 0x01a974 {
    ldy.w #0x270
    lda #7
}
; Item title
.alloc at 0x01dcd2 {
    menu_window(22, 0, 7, 3)
}
