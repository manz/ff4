"""
ROM patches that route every battle-text draw call (commands, monster names, char names, attack names, message
window) through our messages-VWF init/deinit trampolines.
"""

.import "battle/commands_reloc"
.import "battle/sram"
.import "battle/redraw_writer_patches"
.import "battle/redraw_gates"
.import "core/vanilla"

; disable dakuten check
.alloc at 0x02A497 {
    cmp #0xA0
    bcs 0x02A4AC
}

; display_char with the battle_flags switch
.alloc at 0x02A49B {
    jsr.l battle_display_char
    rts
}

; display_dakuten_char with the battle_flags switch
.alloc at 0x02A4AC {
    jsr.l battle_display_dakuten_char
    rts
}

; attack window
.alloc at 0x02c99c + 4 {
    .dw attack_names
}

; monster names: gated trampoline, renders only when the monsters region is dirty
.alloc at 0x02a40d {
    jsr.w msg_monster_window_gated
}


.alloc at 0x029486 + 12 {
    .dw 0x949a  ; noop for monster names
}


; char names (redrawn often)
.alloc at 0x02A29D {
    jsr.w msg_names_window_gated
}


.alloc at 0x029486 + 2 {
    .dw 0x949a  ; noop for char names
}


.alloc at 0x0296c0 {
    .dw 0x949a  ; noop for periodic names update
}


.alloc at 0x02A299 {
    jsr.l gated_clear_names_window_buffer
}

; _newline control code: clear bitsleft on the current tile so the monster string renders
.alloc at 0x02a637 {
    jsr.l messages_vwf.new_line_escape_code_handler
    rts
}


.alloc at 0x0296b0 + 2 {
    .dw 0x949a  ; noop for periodic cmd window
}


; nuke the draw-all command list (pre-renders every window)
.alloc at 0x029ca1 {
    rts
}


; one shared command-list buffer for all chars; CMD_DIRTY_BIT gates the re-render (battle/commands_reloc.s)
.alloc at 0x0299f1 {
    pha
    lda #0
    nop
}


.alloc at 0x029989 {
    jsr.w draw_window_render_hook
}
.alloc at 0x02FFC2 {
draw_window_render_hook:
"""Battle-command-window render hook: render command list, then load X with original loop count."""
    jsr.w _draw_command_list
    ldx.w #0x0340
    rts

_draw_command_list:
    jsr.l draw_command_list_for_character
    rts

_msg_monster_window_trampoline:
"""Ungated monster-name window draw; the $02:A40D patch site calls `msg_monster_window_gated` instead."""
    jsr.l messages_vwf.init_monsters
    bra _draw_text_battle

_msg_names_window_trampoline:
; skip names rendering while inventory is open (bit 2 of $4A)
    lda.b btlgfx_dp.menu_windows_open
    and #0x04
    bne _skip_names
    jsr.l messages_vwf.init_names
    bra _draw_text_battle

_skip_names:
    rts

msg_window_draw_text_trampoline:
"""Trampoline patched into the message-window draw."""
    jsr.l messages_vwf.init

_draw_text_battle:
    jsr.w draw_text
    jsr.l messages_vwf.deinit
    rts

draw_text_battle_far:
    jsr.w _draw_text_battle
    rtl

attack_names:
"""Trampoline for attack-name window: messages-VWF init, attack-name draw, deinit."""
    jsr.l messages_vwf.init
    jsr.w show_msg_02
    jsr.l messages_vwf.deinit
    rts
    {
_end:
    .debug '{_end} < 0x02FFFF ?'
    }
}
