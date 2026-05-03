;; Bank-$01 trampolines for inventory rolling routines living in bank $21.
;; Reclaimed space: $01:EBD2 onwards (from init_bg_scroll_hdma relocation).
;; Each trampoline = jsr.l + rts = 5 bytes.
;;
;; Bank-$01 callers (inventory_rolling_patches.s, free_space.s) jsr.w these
;; bank-$01 names; the trampoline JSLs into the bank-$21 implementation.

.if INVENTORY_ROLLING_BUFFER {
    *=0x01EBD2

check_and_clear_count:
    """Bank-$01 trampoline: bridge to `CheckAndClearCount_Impl` in bank $21."""
    jsr.l CheckAndClearCount_Impl
    rts

init_menu_rolling_buffer:
    """Bank-$01 trampoline: initialise the rolling-buffer state held in bank $21."""
    jsr.l init_menu_rolling_buffer_impl
    rts

SwapRedrawHook_Impl:
    """Bank-$01 trampoline into `SwapRedrawHook_Impl_Body` (bank $21)."""
    jsr.l SwapRedrawHook_Impl_Body
    rts

StartScrollDown:
    """Bank-$01 trampoline: kick off a scroll-down animation."""
    jsr.l start_scroll_down_impl
    rts

StartScrollUp:
    """Bank-$01 trampoline: kick off a scroll-up animation."""
    jsr.l start_scroll_up_impl
    rts

UpdateScrollFrame:
    """Bank-$01 trampoline: advance the rolling buffer by one animation frame."""
    jsr.l update_scroll_frame_impl
    rts

FinishScroll:
    """Bank-$01 trampoline: settle the rolling buffer at the end of a scroll."""
    jsr.l finish_scroll_impl
    rts
; --- Bank-$01 vanilla call trampolines ---
; Bank-$21 code can't `jsr.w` into bank $01 vanilla routines; these trampolines
; wrap a vanilla `JSR` so bank-$21 callers can `jsr.l` and get a clean RTL
; back without stack imbalance.

DrawWindow_Trampoline:
    jsr 0x80D9
; vanilla DrawWindow at $01:80D9
    rtl

CheckCanUseItem_Trampoline:
    jsr 0xA25D
; vanilla CheckCanUseItem at $01:A25D (sets $DB)
    rtl

DrawItemSlotInner_Trampoline:
    jsr 0xA1ED
; vanilla DrawItemSlot inner at $01:A1ED
    rtl

TfrSpritesVblank_Trampoline:
    jsr 0x824F
; vanilla @ $01:824F
    rtl

TfrBG2TilesVblank_Trampoline:
    jsr 0x9420
; vanilla @ $01:9420
    rtl

DrawItemCursors_Trampoline:
    jsr 0xA105
; vanilla @ $01:A105
    rtl

UpdateCtrlAfterScroll_Trampoline:
    jsr 0x82A5
; vanilla @ $01:82A5
    rtl

ResetSprites_Trampoline:
    jsr 0x8D6A
; vanilla @ $01:8D6A
    rtl
}

;; Bank-$01 thunks + wrappers for the treasure exchange rolling buffer.
;; Mirror the field-menu set above but call the treasure_-prefixed bodies
;; in src/ingame/treasure_rolling.s. Both menus are mutually exclusive on
;; screen so the HDMA channel + tilemap buffer + WRAM shadow tables are
;; reused; only the per-menu state RAM differs.
.if TREASURE_INVENTORY_ROLLING {
treasure_check_and_clear_count:
    jsr.l TreasureCheckAndClearCount_Impl
    rts

init_treasure_rolling_buffer:
    jsr.l init_treasure_rolling_buffer_impl
    rts

TreasureSwapRedrawHook_Impl:
    jsr.l TreasureSwapRedrawHook_Impl_Body
    rts

TreasureStartScrollDown:
    jsr.l treasure_start_scroll_down_impl
    rts

TreasureStartScrollUp:
    jsr.l treasure_start_scroll_up_impl
    rts

TreasureUpdateScrollFrame:
    jsr.l treasure_update_scroll_frame_impl
    rts

TreasureFinishScroll:
    jsr.l treasure_finish_scroll_impl
    rts

treasure_scroll_down_trigger:
    cmp #TREASURE_SCROLL_LIMIT
    beq _treasure_down_at_max
    inc
    sta.w 0x1BB7
    jsr.w TreasureStartScrollDown
_treasure_down_at_max:
    rts

treasure_scroll_up_trigger:
    lda.w 0x1BB7
    beq _treasure_up_at_top
    dec
    sta.w 0x1BB7
    jsr.w TreasureStartScrollUp
_treasure_up_at_top:
    rts

treasure_main_loop_scroll_check:


    """
    Hook at $01D9EA. Drives per-frame scroll animation  ; falls back into
    the vanilla input check at $01DA0B when idle so the existing
    JOY_UP/JOY_DOWN handlers can fire.
    """
    lda.w treasure_scroll_state
    beq _treasure_main_do_input
    jsr.w TreasureUpdateScrollFrame
    lda.w treasure_scroll_remaining
    bne _treasure_main_skip_input
    jsr.w TreasureFinishScroll
_treasure_main_skip_input:
    jmp.w 0x01DAA9  ; settled-or-still-animating: skip input this frame
_treasure_main_do_input:
    jmp.w 0x01DA0B  ; resume vanilla input loop entry

treasure_menu_entry_hook:
    jsr.l TreasureMenuEntryHook_Impl
    rts

treasure_menu_exit_hook:
    jsr.l TreasureMenuExitHook_Impl
    rts
}
