"""
New-game / save-slot screen patches.

Rewires the screen's text table and pointer setup at the strings this
project relocated out of their original home, and adjusts the window
geometry and Cecil sprite position that go with them.
"""


.include "src/rom_map.i"
.include "src/menus/system_menus_text.i"

; The macro above expands to a call into the menus text module, and the
; strings it points at live in the start-screen text module.
.extern load_text_with_destination_in_x
.extern display_window_with_text
.extern display_time
.extern display_text_in_menus
.extern newgame
.extern display_build_number


.include "config.i"
.include "src/ingame/macros.i"


.table "text/ff4_menus.tbl"
{
; new game window
    .alloc at 0x01dfc7 {
    .db 0x12  ; width
    .db 0x02  ; height

; Cecil sprite position on the new game item
    }


    .alloc at 0x019904 {
    .db 0x85  ; x
    .db 0x04  ; y


; load game message window
    }


    .alloc at 0x01dfdc {
    menu_window(23, 0, 7, 8)

; LoadTimeWindow:
    }


    .alloc at 0x01dfe0 {
    menu_window(23, 16, 7, 5)

; LoadGilWindow:
    }


    .alloc at 0x01dfe4 {
    menu_window(23, 23, 7, 3)

; save number display
    }


    .alloc at 0x019A62 {
    sta.w 0xC8 - 0x40 + 8, y
    }


    .alloc at 0x019A55 {
    ldx.w #0x82 - 0x40
    }


    .alloc at 0x019A52 {
    load_system_menu_text_pointer(newgame.save)
    }


    .alloc at 0x01962E {
    load_system_menu_text_pointer(newgame.new_game)

    .if DEBUG {
    jsr.w display_build_number
    }
    }


    .alloc at 0x019826 {
    load_system_menu_text_pointer(newgame.load_this_save)

; for save menu we use the same string.
    }


    .alloc at 0x01981E {
    load_system_menu_text_pointer(newgame.load_this_save)
    }


    .alloc at 0x01982C {
    load_system_menu_text_pointer(newgame.yes_no)
    }


    .alloc at 0x01983E {
    load_system_menu_text_pointer(newgame.time_load_save)
    }


    .alloc at 0x01984D {
    load_system_menu_text_pointer(newgame.gils_load_game)
; gils text position
    ldx.w #0x676
    jsr.w 0x82cd  ; menu_draw_text
; gils count position
    ldy #0x062c + 2

; Time position
    }


    .alloc at 0x019838 {
    ldy.w #0xcb2e + 2
    }


    .alloc at 0x019AC5 {
    load_system_menu_text_pointer(newgame.empty_save)
    }


    .alloc at 0x01cbad {
    load_system_menu_text_pointer(newgame.saves)
    }


    .alloc at 0x01e050 {
    menu_window(7, 10, 19, 2)
    }


    .alloc at 0x1cc0d {
    load_system_menu_text_pointer(newgame.save_completed)
    }


    .alloc at 0x1cc12 {
    load_system_menu_text_pointer(newgame.did_not_save)
    }
}
