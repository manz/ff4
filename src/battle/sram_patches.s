.extern draw_command_list_for_character
.extern battle_display_char
.extern battle_display_dakuten_char
.extern clear_names_window_buffer
.extern battle_render
.extern messages_vwf

; inventory buffer
;*=0x02991E
;    jsr.l copy_battle_char
;    nop
;
;    nop
;    nop
;    nop
;
;    nop
;    nop
;
;
;; inventory buffer
;*=0x029932
;    jsr.l copy_battle_char
;    nop
;
;    nop
;    nop
;    nop
;
;    nop
;    nop
; disable dakuten check ?

*=0x02A497
    cmp #0xA0
    bcs 0x02A4AC

; patch normal display_char to include 7FFFFF based switch

*=0x02A49B
    jsr.l battle_display_char
    rts

; patch normal display_dakuten_char to include 7FFFFF based switch

*=0x02A4AC
    jsr.l battle_display_dakuten_char
    rts

; enclose jsr build_tileset_function
; with 7FFFFF switch in the items related stuff.
;*=0x02A06C
;   jsr.w sram_draw_text

; magic should be drawn to sram
;*=0x02A128
;   jsr.w sram_draw_text


; patches show attack window

*=0x02c99c + 4
    .dw attack_names


; disable menu forced update every loop that might be too much
;*=0x028230
;    nop
;    nop
;    nop
.if BATTLE_MONSTERS_VWF {
;; monster names vwf try but being clear at every monster
;; needs a way to have immortal renders and temporary ones (used only for a few instants)
    *=0x02a40d
    jsr.w msg_monster_window_trampoline

    *=0x029486 + 12
    .dw 0x949a  ; noop for monster names
}


.if BATTLE_NAMES_VWF {
; this gets redrawn quite often
; char names
    *=0x02A29D
    jsr.w msg_names_window_trampoline
; wait frame runs a shite load of updates
    *=0x029486 + 2
    .dw 0x949a  ; noop for char names

    *=0x0296c0
    .dw 0x949a  ; noop for periodic names update

    *=0x0296b0 + 16
    .dw 0x949a  ; noop for periodic names update

    *=0x02A299
    jsr.l clear_names_window_buffer
}
; that's battle graphics 0xf that's a wait frame
;*=0x028517
;    nop
;    nop
;    nop
;    nop


; disable periodic updates
;*=0x0296fa
;    rts

;; render attack names
;*=0x029d63
;    jsr.w msg_window_draw_text_trampoline

;; snatch play sound call to init the battle buffer
;*=0x038229
;    jsr.l render_allocator.init_battle_far

.if BATTLE_NAMES_VWF + BATTLE_MONSTERS_VWF + BATTLE_CMD_VWF > 0 {
;patches the newline control code handler to clear bitsleft on the current tile, allowing the monster string to be rendered.
    *=0x02a637
    jsr.l messages_vwf.new_line_escape_code_handler
    rts
}


.if BATTLE_CMD_VWF {
    *=0x0296b0 + 2
    .dw 0x949a  ; noop for periodic cmd window

;*=0x029CBF
;    jsr.l draw_command_list_for_character
;    rts

; nukes the draw all command list (pre renders all the windows)
    *=0x029ca1
    rts

; always use the same buffer for all chars command list,
; the buffer shall be updated if before the window is opened
; due to those updates being quite costly now, we may want to avoid to re render too often

    *=0x0299f1
    pha
    lda #0
    nop

    *=0x029989
    jsr.w draw_window_render_hook
}


*=0x02FFC2

draw_window_render_hook:
    jsr.w draw_command_list
    ldx.w #0x0340
    rts

draw_command_list:
    jsr.l draw_command_list_for_character
    rts

msg_monster_window_trampoline:
    jsr.l messages_vwf.init_monsters
    bra _draw_text_battle

msg_names_window_trampoline:
    ; Skip names rendering if inventory is active (bit 2 of $4A)
    lda 0x4A
    and #0x04
    bne _skip_names
    jsr.l messages_vwf.init_names
    bra _draw_text_battle

_skip_names:
    rts

msg_window_draw_text_trampoline:
    jsr.l messages_vwf.init

_draw_text_battle:
    jsr 0xA455
    jsr.l messages_vwf.deinit
    rts

_draw_text_battle_far:
    jsr.w _draw_text_battle
    rtl

attack_names:
    jsr.l messages_vwf.init
    jsr 0xcb32
    jsr.l messages_vwf.deinit
    rts
{
_end:
    .debug '{_end} < 0x02FFFF ?'
}
