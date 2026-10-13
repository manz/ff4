"""
Field-menu magic screen patches: spell columns, list titles, cost and target-window positions.
"""
.import "core/preamble"
.import "ingame/free_space"
.import "menus/in_game_text"
.import "menus/system_menus_text"
.import "core/vanilla"
.include "menus/system_menus_macros.i"

.include "ingame/macros.i"

; Column offsets
.alloc at 0x1efebd {
    _first_column := 0x0248 - 4
    .dw _first_column + 10 * 2 * 2, _first_column + 10 * 2, _first_column
}
; Column cursor positions
.alloc at 0x01b211 {
    .db 0x0, 10 * 8, 10 * 8 * 2
}
; Spell list titles: white, black, summon, ninja, kokan
.alloc at 0x01AFA2 {
    load_system_menu_text_pointer(spells.white)
}
.alloc at 0x01AFB6 {
    load_system_menu_text_pointer(spells.black)
}
.alloc at 0x01AFCA {
    load_system_menu_text_pointer(spells.summon)
}
.alloc at 0x01AFDE {
    load_system_menu_text_pointer(spells.ninja)
}
.alloc at 0x1d95e {
    load_system_menu_text_pointer(spells.kokan)
}
.alloc at 0x01b0ec {
    ldx.w #0x020A + 0x40  ; the glyph row: the VWF has no dakuten row above it
    load_system_menu_text_pointer(spells.mp_needed)
    jsr.w copy_text  ; the small VWF's CopyText hook draws it
}
; The type highlight ($01:B418, 7 cells for the French titles) is small_vwf/menu_text.s's tint_cells.

; Spell type cursor offset
.alloc at 0x01B0CE {
    lda.b #0x10  ; two tiles in, left of the centred titles
}
; Spell cost, before the character
.alloc at 0x01B0F7 {
    sta.w 0xC816 + 0x40 + 2
}
; Spell cost
.alloc at 0x01B0E6 {
    ldy.w #0x021A + 0x40 + 2
}
; [use spell] character target window
.alloc at 0x01dd6d {
    menu_window(8, 0, 22, 26)
}
; [use spell] "on whom" window
.alloc at 0x01dd71 {
    menu_window(0, 8, 8, 5)
}
; [use spell] spell name in the cast window ($01:DD75), inside column 2
.alloc at 0x01b4a7 {
    ldx.w #0x0044
}
; Hide the "on whom" window
.alloc at 0x01b498 {
    nop
    nop
    nop
}
; Hide the "on whom ?" text
.alloc at 0x01b4ad {
    nop
    nop
    nop
    nop
    nop
    nop
}
.alloc at 0x01b4b3 {
    load_system_menu_text_pointer(use_spell.mp_cost)
}
; Magic target cursor 8 px right
.alloc at 0x01B5FF {
    lda #0x40 + 8
}
