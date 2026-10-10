"""
Top-level field-menu patches (entry point fixups, palette setup, frame timing) that drive the rest of the
in-game menu wiring.
"""
.import "preamble"
.import "items"
.import "dakuten"
.import "assets"
.import "menus/in_game_text"
.import "menus/system_menus_text"
.include "config.i"
.include "src/menus/system_menus_macros.i"

.include "src/ingame/macros.i"
.import "vanilla"
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
; ptr 0xdb6d
    menu_window(23, 0, 7, 17)
    }
    }


    .alloc at 0x01dd51 {
    menu_window(1, 8, 29, 17)
    }


    .alloc at 0x01892E {
    load_system_menu_text_pointer(in_game_menu.menu)
; jsr.w draw_window_and_vwf_message

; Gils
    }


    .alloc at 0x0187CE {
    load_system_menu_text_pointer(in_game_menu.gils)
    ldx.w #28 * 2 + 25 * 64  ; one column right of vanilla's (27, 25): clear of the number

; moves gils two chars on the right
    }


    .alloc at 0x0187DA {
    ldy.w #0x062A + 4

; TIME
    }


    .alloc at 0x0187C5 {
    ldx.w #0x52E + 2
    load_system_menu_text_pointer(in_game_menu.time)

; disable Save text
    }


    .alloc at 0x018939 {
    jmp.l disable_save

; Moves the classes on the next line
    }


    .alloc at 0x018C1A {
    adc.w #0x004e

; disable class name
    }


    .alloc at 0x018b30 {
    rts

;*=0x0188d0
;    ldx.w #0x02CE
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


    .alloc at 0x0189b9 {
; Level offset
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

; LEVEL
    }


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

; Moves the level down in the digest
    }


    .alloc at 0x0189FA {
    sta.w 0x0016, x
    xba
    sta.w 0x0018, x

;; Move character name.
    }


; DrawCharName ($01:83AB) draws in the small VWF: small_vwf/menu_text.s.
; translate can't fight text


    .alloc at 0x018B2A {
    load_system_menu_text_pointer(in_game_menu.cant_fight)

; grey out more tiles for the first line in char block
    }


    .alloc at 0x018C30 {
    lda #15


;*=0x018b6b
;  lda     #0x42


; Time offset
    }


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
; The save / restore themselves live in src/ingame/menu_vram.s.

.alloc at 0x018E32 {
    jsr.l lookup_dakuten
    rts
}
.alloc at 0x00b670 {
    jsr.l lookup_dakuten
    xba
    rts

;*=0x00b66e
;jsr.l lookup_dakuten
;rts

;                     --------sub start--------
;018E32  DA             PHX
;018E33  C9 42          CMP #$42
;018E35  B0 15          BCS $018E4C
;018E37  38             SEC
;018E38  E9 0F          SBC #$0F
;018E3A  0A             ASL
;018E3B  EB             XBA
;018E3C  A9 00          LDA #$00
;018E3E  EB             XBA
;018E3F  AA             TAX
;018E40  BF 1F FE 1E    LDA $1EFE1F,X
;018E44  EB             XBA
;018E45  BF 1E FE 1E    LDA $1EFE1E,X
;018E49  EB             XBA
;018E4A  FA             PLX
;018E4B  60             RTS
;                     ----------------
;018E4C  EB             XBA
;018E4D  A9 FF          LDA #$FF
;018E4F  FA             PLX
;018E50  60             RTS
;                     ----------------
}
