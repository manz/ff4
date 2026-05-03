;; Bank-$01 trampolines for inventory rolling routines living in bank $21.
;; Reclaimed space: $01:EBD2 onwards (from init_bg_scroll_hdma relocation).
;; Each trampoline = jsr.l + rts = 5 bytes.
;;
;; Bank-$01 callers (inventory_rolling_patches.s, free_space.s) jsr.w these
;; bank-$01 names; the trampoline JSLs into the bank-$21 implementation.

.if INVENTORY_ROLLING_BUFFER {
    *=0x01EBD2

    check_and_clear_count:
    jsr.l CheckAndClearCount_Impl
    rts

    init_menu_rolling_buffer:
    jsr.l init_menu_rolling_buffer_impl
    rts

    SwapRedrawHook_Impl:
    jsr.l SwapRedrawHook_Impl_Body
    rts

    StartScrollDown:
    jsr.l start_scroll_down_impl
    rts

    StartScrollUp:
    jsr.l start_scroll_up_impl
    rts

    UpdateScrollFrame:
    jsr.l update_scroll_frame_impl
    rts

    FinishScroll:
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


