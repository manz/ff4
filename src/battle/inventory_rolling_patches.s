"""
ROM patches that wire the battle inventory rolling-buffer engine into bank $02 (JSL trampolines for cross-bank
calls, JML hooks for the scroll animation, surgical NOPs / RTS overrides).
"""
.import "battle/sram_patches"
.import "battle/inventory_rolling"
.import "battle/redraw_gates"
.import "battle/render_state"
.import "battle/sram"
.import "battle/vanilla_trampolines"

.include "config.i"
.include "src/battle/bank02_trampolines.i"
.import "vanilla"

; ============================================================================
; Rolling Inventory Buffer - ROM Patches (Single Column)
; ============================================================================
;
; Patches for single-column rolling inventory buffer.
; Key change: Hook scroll START (not completion) to pre-render edge rows.
;
; IMPORTANT: Bank $02 free space is limited ($98FF-$9982 = 131 bytes)
; Only small trampolines go here. Large functions go in bank $20.
;
; See docs/ff6_rolling_inventory_analysis.md for design rationale.
;
; ============================================================================

; ============================================================================
; PATCH: InitInventoryTextBuf ($029E9C)
; ============================================================================

.alloc at 0x029E9C {
    jsr.l init_inventory_text_buf_rolling
    .db 0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4
    .db 0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4
    .db 0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4
    rts

; ============================================================================
; PATCH: TfrInventoryList ($0298FA)
; ============================================================================
; Original function is $98FA-$9982 (136 bytes). We replace with JSL+RTS (5 bytes)
; This frees $98FF-$9982 (131 bytes) for our trampolines.
}
.alloc at 0x0298FA {
    jsr.l tfr_inventory_list_rolling
    rts
}
.alloc _bank02_trampolines_block in bank02_trampolines {
_update_enabled_items_trampoline:
    jsr.w update_enabled_items
    rtl

; ============================================================================
; RELOCATED: Draw Battle Command Window (originally at $9989)
; ============================================================================
; Original function was overwritten. This must fit in bank $02 free space.

draw_battle_command_window_relocated:
; Drop the CMD_DIRTY_BIT gate. The cmd-window tilemap region at
; $C1A5+ is a mirror of the main view ($BE65+) overlaid with cmd
; tiles. ATB rotation / monster death / HP ticks etc. only write to
; main, never re-mirror, so gating left the cmd region frozen at
; battle-init state (and we kept seeing empty char-name + monster
; rows behind the cmd window). Mirror is now a single ch3 WRAM DMA
; (~400 cycles), small enough to run every frame; total cost is in
; the same ballpark as vanilla's per-frame DrawCmdWindow.
    jsr.w draw_window_render_hook  ; Draw command list (X side-effect unused now)

; Mirror main-view tilemap $BE65..$C1A4 -> $C1A5..$C4E4 via WRAM DMA
; ch3 (replaces a $340-iter lda/sta loop ; ~10K cycles -> ~400).
    jsr.l messages_vwf.mirror_main_to_cmd
    lda #0x02
    jsr.w load_menu_window_data  ; Load menu window data
    jsr.w draw_window3  ; Draw window
    lda #0x03
    ldx.w #0x0064
    jsr.w draw_cmd_list_text
; Queue the cmd tilemap upload only now that mirror + overlay are both
; in: queued earlier, an NMI between the two pushed the bare mirror (or
; a half-copied overlay) to VRAM. The VWF render used to fill that gap.
    lda.l battle_render_state.tilemap_pending_mask
    ora.b #battle_render.TILEMAP_PENDING_COMMANDS
    sta.l battle_render_state.tilemap_pending_mask
    rts

; ============================================================================
; WRAP/CLEAR TRAMPOLINE (small, stays in bank $02)
; ============================================================================
; After scroll animation completes, we need to post-render for scroll DOWN.
; For scroll down: the slot that just scrolled off-screen needs to be updated
; with the NEXT item for future scrolls.
; For scroll up: pre-rendering was already done before animation.

wrap_and_clear_trampoline:
"""Bank-$02 tail of the scroll animation: post-render and cursor visibility check."""
; FF6-style circular scroll - no reset needed!
; The wrap function in update_list_scroll_hdma_wrapped handles coordinate conversion.
;
; After scroll down, we need to post-render the next item to prepare for
; future scrolls. The off-screen slot that just scrolled off should be
; updated with the next item in the list.
    jsr.l post_scroll_down_render  ; Post-render if scroll down

; Check cursor 2 visibility for swap mode
; If first selected item scrolled out of view, hide cursor 2
    jsr.l check_cursor2_visibility_rolling

; Clear animation state
    stz.w menu_hdma_pending
    rts

; Return point for bank $20 functions that need to RTS to bank $02 callers
}

; end .alloc _bank02_trampolines_block

; ============================================================================
; ROM PATCHES
; ============================================================================

; Redirect callers of $9989 to relocated function
; Must use JSR (not JSL) since function ends with JMP, not RTL

.alloc at 0x0296CB {
; RedrawMainMenu's per-pass command window: the battle menu task draws it on SIG_COMMANDS (battle/tasks_patches.s)
    nop
    nop
    nop
}
.alloc at 0x029983 {
    jsr.w draw_battle_command_window_relocated

; ============================================================================
; PATCHES in ascending address order (assembler requires this)
; ============================================================================

; Scroll animation end - wrap $EF65 (4 bytes each)
; Must use JMP (not JMP.L) - 3 bytes + 1 NOP = 4 bytes
}
.alloc at 0x02A86E {
    jmp.w wrap_and_clear_trampoline
    nop

; Animation loop DECrement path ($02A872-$02A87B) - 10 bytes
; Original: LDX $EF71 / DEX / STX $EF71 / JMP CheckListCursorVisible
; NOP the LDX/DEX/STX, replace JMP with RTS (skips CheckListCursorVisible)
; CheckListCursorVisible can incorrectly hide cursor 2 with our circular buffer scroll values
}
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

; Animation loop INCrement path ($02A8AE-$02A8B7) - 10 bytes
; Original: LDX $EF71 / INX / STX $EF71 / JMP CheckListCursorVisible
; NOP the LDX/INX/STX, replace JMP with RTS (skips CheckListCursorVisible)
; CheckListCursorVisible can incorrectly hide cursor 2 with our circular buffer scroll values
}
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

; Scroll hooks - use JMP.L to bank $20 functions
}
.alloc at 0x02A8B8 {
    jmp.l scroll_list_down_hook
}
.alloc at 0x02A8CA {
    jmp.l scroll_list_up_hook

; ============================================================================
; PATCH: UpdateListScrollHDMA ($02A7F1)
; ============================================================================
; This is the KEY patch for true FF6-style circular buffer.
; Original code builds HDMA table with unbounded scroll values.
; Our replacement wraps scroll values at 96 pixels (6 rows).
;
; Original function is 32 bytes ($02A7F1-$02A810).
; We replace with JMP.L (4 bytes) + NOPs.
}
.alloc at 0x02A7F1 {
    jmp.l update_list_scroll_hdma_wrapped
; Fill remaining bytes with NOPs (32 - 4 = 28 bytes)
    .db 0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4
    .db 0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4
    .db 0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4
    .db 0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4

; ============================================================================
; PATCH: Cursor scroll limit for single-column mode
; ============================================================================

; Original code at $02B517 checks if at end of list:
;   lda $ef85 / cmp #$17 / bne @b521
; The #$17 (23) is for 2-column mode (24 items per column).
; For single-column (48 items), change to #$2B (43 = 48-5).
}
.alloc at 0x02B519 {
    .db 0x2B  ; CMP #$2B instead of CMP #$17

; ============================================================================
; PATCH: ResetListScrollHDMA ($02AAB8)
; ============================================================================
; Fill BOTH $7F74 (active table) AND $81F4 (swap table) with our converted
; scroll values. This prevents the menu animation from swapping in bad values.
;
; Original fills only $81F4 with 371-based values.
; We fill both with our 132-based values so animation swap is a no-op.
}
.alloc at 0x02AAB8 {
    jsr.l reset_list_scroll_hdma_rolling
    rts
}
