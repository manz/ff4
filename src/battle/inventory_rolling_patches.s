"""
ROM patches that wire the battle inventory rolling-buffer engine into bank $02 (JSL trampolines for cross-bank
calls, JML hooks for the scroll animation, surgical NOPs / RTS overrides).

Single-column rolling buffer: the scroll hook fires on scroll start (not completion) to pre-render the edge rows.
Bank $02 free space is limited ($98FF-$9982, 131 bytes, freed by the TfrInventoryList patch): only small
trampolines go there, larger functions live in bank $20.
"""
.import "battle/sram_patches"
.import "battle/inventory_rolling"
.import "battle/redraw_gates"
.import "battle/render_state"
.import "battle/sram"
.import "battle/vanilla_trampolines"

.include "battle/bank02_trampolines.i"
.import "core/vanilla"

; InitInventoryTextBuf
.alloc at 0x029E9C {
    jsr.l init_inventory_text_buf_rolling
    .db 0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4
    .db 0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4
    .db 0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4
    rts
}

; TfrInventoryList ($98FA-$9982): JSL + RTS frees $98FF-$9982 for the trampolines
.alloc at 0x0298FA {
    jsr.l tfr_inventory_list_rolling
    rts
}
.alloc _bank02_trampolines_block in bank02_trampolines {
_update_enabled_items_trampoline:
    jsr.w update_enabled_items
    rtl

; Draw battle command window, relocated from $9989
draw_battle_command_window_relocated:
; No CMD_DIRTY_BIT gate on the mirror: ATB rotation, deaths, HP ticks only write the main view ($BE65+), so a gated
; mirror would freeze the cmd region ($C1A5+) at its battle-init state. One MVN (~5800 cycles) per frame is cheap.
    jsr.w draw_window_render_hook  ; Draw command list (X side-effect unused)

    jsr.l messages_vwf.mirror_main_to_cmd
    lda #0x02
    jsr.w load_menu_window_data  ; Load menu window data
    jsr.w draw_window3  ; Draw window
    lda #0x03
    ldx.w #0x0064
    jsr.w draw_cmd_list_text
; Queue the cmd tilemap only once mirror + overlay are both in: an NMI in between pushed a half-built window.
    lda.l battle_render_state.tilemap_pending_mask
    ora.b #battle_render.TILEMAP_PENDING_COMMANDS
    sta.l battle_render_state.tilemap_pending_mask
    rts

wrap_and_clear_trampoline:
"""Bank-$02 tail of the scroll animation: post-render and cursor visibility check."""
    jsr.l post_scroll_down_render  ; Post-render if scroll down

; hide cursor 2 if the first swap selection scrolled out of view
    jsr.l check_cursor2_visibility_rolling

    stz.w menu_hdma_pending
    rts
}


.alloc at 0x0296CB {
; RedrawMainMenu's per-pass command window: the battle menu task draws it on SIG_COMMANDS (battle/tasks_patches.s)
    nop
    nop
    nop
}
; Callers of $9989: JSR, the relocated function ends in RTS
.alloc at 0x029983 {
    jsr.w draw_battle_command_window_relocated
}

; Scroll animation end: 3-byte JMP + NOP (4 bytes)
.alloc at 0x02A86E {
    jmp.w wrap_and_clear_trampoline
    nop
}

; Animation loop dec path ($02A872, 10 bytes): ldx/dex/stx $EF71 NOPed, and RTS instead of jmp CheckListCursorVisible,
; which hides cursor 2 wrongly with our scroll values.
.alloc at 0x02A872 {
_nop_patch_dec:
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    rts  ; Skip CheckListCursorVisible (was JMP $A82D)
    nop  ; Fill remaining 2 bytes of JMP
    nop
}
.alloc at 0x02A8AA {
    jmp.w wrap_and_clear_trampoline
    nop
}

; Animation loop inc path ($02A8AE): same as the dec path
.alloc at 0x02A8AE {
_nop_patch_inc:
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    rts  ; Skip CheckListCursorVisible (was JMP $A82D)
    nop  ; Fill remaining 2 bytes of JMP
    nop
}

; Scroll hooks (bank $20)
.alloc at 0x02A8B8 {
    jmp.l scroll_list_down_hook
}
.alloc at 0x02A8CA {
    jmp.l scroll_list_up_hook
}

; UpdateListScrollHDMA ($02A7F1-$02A810): the replacement wraps scroll values at 96 px (6 rows)
.alloc at 0x02A7F1 {
    jmp.l update_list_scroll_hdma_wrapped
    .db 0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4
    .db 0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4
    .db 0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4
    .db 0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4
}

; End-of-list check at $02B517 (lda $ef85 / cmp #$17): 48 single-column items, last top row 43
.alloc at 0x02B519 {
    .db 0x2B  ; CMP #$2B instead of CMP #$17
}

; ResetListScrollHDMA: fill both the active ($7F74) and swap ($81F4) tables, so the animation swap is a no-op
.alloc at 0x02AAB8 {
    jsr.l reset_list_scroll_hdma_rolling
    rts
}
