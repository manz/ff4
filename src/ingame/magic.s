"""
Field-menu magic screen patches: column-offset tweaks, per-character spell-list pointer setup and hooks into
the magic-render path.
"""
.include "src/ingame/macros.i"

; Columns offsets

.alloc at 0x1efebd {
    first_column := 0x0248 - 4
    .dw first_column + 10 * 2 * 2, first_column + 10 * 2, first_column

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
        ldx.w #0x020A
        ldy.w #spells.mp_needed & 0xffff
        jsr.w copy_text_with_dakuten


    ; Grisement des types sorts : 'Blancs' 'Noirs' etc ...
}
.alloc at 0x01B419 {
        ldy.w #0x0007
        sta.w 0xC5FF + 2, x

    ; Spells type cursor offset
}
.alloc at 0x01B0CE {
        lda.b #0x00

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
        ldx.w #0x0042

    ; move character blocks one tile back
    .if 0 {
    .alloc at 0x01b4c5 {
            ldx.w #0x02e0 - 2
    }
    .alloc at 0x01b4ce {
            ldx.w #0x0060 - 2
    }
    .alloc at 0x01b4d7 {
            ldx.w #0x0560 - 2
    }
    .alloc at 0x01b4e0 {
            ldx.w #0x01a0 - 2
    }
    .alloc at 0x01b4e9 {
            ldx.w #0x0420 - 2
        ; moves character portrait 8 pixels back
    }
    .alloc at 0x1efea9 {
            delta = 8
            .db 0x58 - delta, 0x68
            .db 0x58 - delta, 0x18
            .db 0x58 - delta, 0xb8
            .db 0x60 - delta, 0x40
            .db 0x60 - delta, 0x90  ; 3 front/2 back
            .db 0x60 - delta, 0x68
            .db 0x60 - delta, 0x18
            .db 0x60 - delta, 0xb8
            .db 0x58 - delta, 0x40
            .db 0x58 - delta, 0x90  ; 2 front/3 back
    }
    }
    ; do not display on whom window
}
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
