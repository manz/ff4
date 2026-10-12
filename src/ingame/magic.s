"""
Field-menu magic screen patches: column-offset tweaks, per-character spell-list pointer setup and hooks into
the magic-render path.
"""
.import "preamble"
.import "ingame/free_space"
.import "menus/in_game_text"
.import "menus/system_menus_text"
.import "vanilla"
.include "src/menus/system_menus_macros.i"

.include "src/ingame/macros.i"

; Columns offsets

.alloc at 0x1efebd {
    _first_column := 0x0248 - 4
    .dw _first_column + 10 * 2 * 2, _first_column + 10 * 2, _first_column

; columns cursor postion
}
.alloc at 0x01b211 {
    .db 0x0, 10 * 8, 10 * 8 * 2

; White spells
}
.alloc at 0x01AFA2 {
    load_system_menu_text_pointer(spells.white)

; Black spells
}
.alloc at 0x01AFB6 {
    load_system_menu_text_pointer(spells.black)

; summons
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


; Grisement des types sorts : 'Blancs' 'Noirs' etc ...
}
; The type highlight ($01:B418, 7 cells for the French titles) is small_vwf/menu_text.s's tint_cells.

; Spells type cursor offset
.alloc at 0x01B0CE {
    lda.b #0x10  ; two tiles in, left of the centred titles

; Spells cost before char
}
.alloc at 0x01B0F7 {
    sta.w 0xC816 + 0x40 + 2

; Spells cost
}
.alloc at 0x01B0E6 {
    ldy.w #0x021A + 0x40 + 2


; [use spell] Choose Spell character target window.
}
.alloc at 0x01dd6d {
    menu_window(8, 0, 22, 26)


; [use spell] Use spell on whom window.
}
.alloc at 0x01dd71 {
    menu_window(0, 8, 8, 5)

; [use spell] Magic name position.
}
.alloc at 0x01b4a7 {
; the spell name in the cast window ($01:DD75): its first inside column, 2
    ldx.w #0x0044
}
; move character blocks one tile back

; do not display on whom window
.alloc at 0x01b498 {
    nop
    nop
    nop

; do not display to "on whom ?" text
}
.alloc at 0x01b4ad {
    nop
    nop
    nop
; load_system_menu_text_pointer(use_spell.use_on_whom)
;ldy.w #0xdd79
    nop
    nop
    nop
}
.alloc at 0x01b4b3 {
    load_system_menu_text_pointer(use_spell.mp_cost)

; moves the magic target cursor X 8 pixels
}
.alloc at 0x01B5FF {
    lda #0x40 + 8
}
