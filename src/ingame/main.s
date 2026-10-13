"""
Main field-menu layout patches: windows, menu text pointers, HP/MP/level/time positions.
"""
.import "core/preamble"
.import "core/items"
.import "dialog/dakuten"
.import "core/assets"
.import "menus/in_game_text"
.import "menus/system_menus_text"
.include "menus/system_menus_macros.i"

.include "ingame/macros.i"
.import "core/vanilla"
.import "ingame/menu_vram"


{
    .alloc at 0x01DB61 {
    .scope _main_menu {
characters_window:
    menu_window(0, 0, 22, 26)
gil_window:
    menu_window(22, 23, 8, 3)
time_window:
    menu_window(23, 19, 7, 2)
menu:
    menu_window(23, 0, 7, 17)
    }
    }


    .alloc at 0x01dd51 {
    menu_window(1, 8, 29, 17)
    }


    .alloc at 0x01892E {
    load_system_menu_text_pointer(in_game_menu.menu)
    }


; Gil
    .alloc at 0x0187CE {
    load_system_menu_text_pointer(in_game_menu.gils)
    ldx.w #29 * 2 + 25 * 64  ; two columns right of vanilla's (27, 25): clear of the number
    }


    .alloc at 0x0187DA {
    ldy.w #0x062A + 4
    }


; Time
    .alloc at 0x0187C5 {
    ldx.w #0x52E + 2
    load_system_menu_text_pointer(in_game_menu.time)
    }


; Disable the Save entry text
    .alloc at 0x018939 {
    jmp.l disable_save
    }


; Class name on the next line
    .alloc at 0x018C1A {
    adc.w #0x004e
    }


; Disable class name
    .alloc at 0x018b30 {
    rts
    }


    .alloc at 0x018FD3 {
    jsr.l load_classes_pointer
    nop
    sta 0x45
    xba
    sta 0x46
    ldx 0x45
    lda #0x0F
    }


; DrawClassName's copy loop ($01:8FE3) draws in the small VWF: small_vwf/menu_text.s.


; Level offset
    .alloc at 0x0189b9 {
    adc.w #0x0044 - 2
    }


    .alloc at 0x018a03 {
    draw_hp_mp = 0x018a2a
    lda.w #0x0046 + 0x40
    ldy.w #0x0007  ; current hp
    jsr.w draw_hp_mp
    lda.w #0x0050 + 0x40
    ldy.w #0x0009  ; max hp
    jsr.w draw_hp_mp
    lda.w #0x0086 + 0x40
    ldy.w #0x000b  ; current mp
    jsr.w draw_hp_mp
    lda.w #0x0090 + 0x40
    ldy.w #0x000d  ; max mp
    jsr.w draw_hp_mp
    }


; Level
    .alloc at 0x0189C3 {
    {
    level_offset = 7 * 2
    lda #0xFF
    sta.w 0 + level_offset, x
    lda #0x4F  ; N
    sta.w 2 + level_offset, x
    lda #0x57  ; V
    sta.w 4 + level_offset, x
    lda #0xFF
    sta.w 6 + level_offset, x
    nop

    lda #0x57  ; H 49 V 57
    sta.w 0x40 + 2 + 0x40, x
    lda #0x51  ; P
    sta.w 0x42 - 2 + 0x40, x
    sta.w 0x82 - 2 + 0x40, x
    lda #0x4E  ; M
    sta.w 0x80 + 2 + 0x40, x
    lda #0xC7  ; /
    sta.w 0x4E + 0x40, x
    sta.w 0x8E + 0x40, x
    }
    }


; Level lower in the digest
    .alloc at 0x0189FA {
    sta.w 0x0016, x
    xba
    sta.w 0x0018, x
    }


; DrawCharName ($01:83AB) draws in the small VWF: small_vwf/menu_text.s.


    .alloc at 0x018B2A {
    load_system_menu_text_pointer(in_game_menu.cant_fight)
    }


; Grey out more tiles on the first line of the char block
    .alloc at 0x018C30 {
    lda #15
    }


; Time offset
    .alloc at 0x018BC1 {
    lda.b #0x80
    sta.w 0x0578, y
    xba
    sta.w 0x057A, y
    rep #0x20
    lda.b 0x73
    sep #0x20
    jsr.w hex_to_dec4
    lda.b 0x5B
    sta.w 0x0570, y
    lda.b 0x5D
    sta.w 0x0572, y
    lda.b 0x5E
    sta.w 0x0574, y
    lda.b #0xC8
    sta.w 0x0576, y
    }
}

; DrawMagicName's copy loop ($01:B305 on) draws baked spell names: small_vwf/menu_text.s.

.alloc at 0x018E32 {
    jsr.l lookup_dakuten
    rts
}
.alloc at 0x00b670 {
    jsr.l lookup_dakuten
    xba
    rts
}
