.include 'src/ingame/macros.i'

.table 'text/ff4_menus.tbl'

{
; new game window
*=0x01dfc7
    .db 0x12 ; width
    .db 0x02 ; height

; Cecil sprite position on the new game item
*=0x019904
    .db 0x85 ; x
    .db 0x04 ; y


; load game message window
*=0x01dfdc
    menu_window(23,0,7,8)

;LoadTimeWindow:
*=0x01dfe0
    menu_window(23,16,7,5)

;LoadGilWindow:
*=0x01dfe4
    menu_window(23,23,7,3)

; save number display
*=0x019A62
    sta.w 0xC8 - 0x40 + 8 ,y

*=0x019A55
    ldx.w #0x82 - 0x40


*=0x019A52
    load_system_menu_text_pointer(newgame.save)

*=0x01962E
    load_system_menu_text_pointer(newgame.new_game)

*=0x019826
    load_system_menu_text_pointer(newgame.load_this_save)

*=0x01982C
    load_system_menu_text_pointer(newgame.yes_no)

*=0x01983E
    load_system_menu_text_pointer(newgame.time_load_save)

*=0x01984D
    load_system_menu_text_pointer(newgame.gils_load_game)
    ; gils text position
    ldx.w #0x676
    jsr.w 0x82cd ; menu_draw_text
    ; gils count position
    ldy #0x062c + 2

; Time position
*=0x019838
    ldy.w #0xcb2e + 2
*=0x019AC5
    load_system_menu_text_pointer(newgame.empty_save)


*=0x01cbad
    load_system_menu_text_pointer(newgame.saves)

*=0x1cc12
    load_system_menu_text_pointer(newgame.did_not_save)


}
