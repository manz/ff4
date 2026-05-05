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

TfrBG3TilesVblank_Trampoline:
    jsr 0x9447
; vanilla @ $01:9447 — pushes BG3 buffer at $7E:D600 to VRAM $7000
; over a vblank-bounded chunked DMA. Used by the treasure rolling
; buffer: render writes go to the BG3 staging area but vanilla's
; treasure main loop only refreshes BG2/sprites mid-menu, so without
; this call the rolling-buffer slot updates never make it on screen.
    rtl

DrawItemCursors_Trampoline:
    jsr 0xA105
; vanilla @ $01:A105
    rtl

UpdateCtrlAfterScroll_Trampoline:
    jsr 0x82A5
; vanilla @ $01:82A5
    rtl

InitItemList_Trampoline:
    """Bank-$01 trampoline for vanilla InitItemList @ $01:B2D3 (filters $1440 -> $0712 by key-item ID range)."""
    jsr 0xB2D3
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

treasure_refresh_slots:
    jsr.l treasure_refresh_slots_impl
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

; Vanilla treasure already updated $1BB7 before reaching the patch site,
; so the triggers just kick off the state-machine animation.
; Force the field-menu HDMA shadow ($1BAE) ON before kicking the state
; machine so the existing field NMI hook copies the shadow→active table
; even when the rolling-buffer init at $01:D933 never ran (some treasure
; flows skip the redraw helper).
; Vanilla writes $1BB7 each frame DOWN/UP is held — no built-in debounce
; once the blocking scroll loop is gone. Gate the trigger on
; `treasure_scroll_state == 0` and undo vanilla's $1BB7 update when an
; animation is still in flight, so the rolling buffer steps once per
; press instead of advancing dozens of times per held button.
treasure_scroll_down_trigger:
    lda.w treasure_scroll_state
    bne _t_down_abort
    jsr.w treasure_force_hdma_setup
    jsr.w TreasureStartScrollDown
    rts
_t_down_abort:
    dec.w 0x1BB7
    rts

treasure_scroll_up_trigger:
    lda.w treasure_scroll_state
    bne _t_up_abort
    jsr.w treasure_force_hdma_setup
    jsr.w TreasureStartScrollUp
    rts
_t_up_abort:
    inc.w 0x1BB7
    rts

; Reconfigure HDMA channel 5 for BG3 only when we're inside the treasure
; menu (vanilla sets $1BC6 at $01:D80B on entry, clears it at $01:D7E6 on
; exit). Field-menu Items uses BG1 and reconfigures channel 5 itself; the
; key-item submenu (e.g. Baron key) is yet another context to add later.
treasure_force_hdma_setup:
    lda.w 0x1BC6
    bne _t_setup_in_treasure
    rts
_t_setup_in_treasure:
    sep #0x20
    lda #0x02
    sta.l 0x004360  ; HDMA6 ctrl: DIRECT mode, 2 bytes / scanline
    lda #0x12
    sta.l 0x004361  ; HDMA6 dest: BG3VOFS ($2112)
    rep #0x20
    lda.w #0x9800  ; shared field-menu HDMA active table at $7E:9800
    sta.l 0x004362  ; HDMA6 src lo/hi
    sep #0x20
    lda #0x7E
    sta.l 0x004364  ; HDMA6 src bank
    rep #0x20
; Capture vanilla BG3VOFS shadow ($9F) — vanilla treasure draws inventory
; rows starting at screen scanline ~120 with $9F = -120, which keeps the
; existing window/dialog tilemap content visible on the header band.
    lda.l 0x7E019F
    sta.w treasure_rolling_base_scroll
    sep #0x20
; Vanilla treasure ROM enables HDMAEN=$AD = ch7|ch5|ch3|ch2|ch0. ch2
; is an HDMA INDIRECT mode-3 channel that writes BG3HOFS+BG3VOFS for
; the drops-band parallax. Even with our scroll moved to ch6 (which
; iterates after ch2 and should "win" the BG3VOFS at scanlines past
; the drops band), the rolling buffer scroll never takes effect while
; ch2 is enabled — likely because ch2 keeps reloading entries via its
; indirect table past scanline 128. Mask ch2 entirely; the drops-band
; vanilla parallax is purely cosmetic and the drops list still lands
; at the right scanline without it.
    lda #0xE9  ; $AD & ~0x04 | $40 = ch7|ch6|ch5|ch3|ch0
    sta.l 0x7E1BAE
    rts

treasure_main_loop_scroll_check:


    """
    Replaces the vanilla `jsr $82C0` at $01:DA08. Drives the scroll
    state machine each frame  ; while scrolling it zeroes $01 so the
    downstream `and #JOY_*` input checks all branch out, freezing
    cursor / button handling until the animation settles. Always ends
    by calling the original $82C0 so vanilla per-frame work still runs.
    """
    lda.w treasure_scroll_state
    beq _treasure_main_check_xfer
    jsr.w TreasureUpdateScrollFrame
    lda.w treasure_scroll_remaining
    bne _treasure_main_block_input
    jsr.w TreasureFinishScroll
_treasure_main_check_xfer:
; Drain treasure_transfer_pending — the rolling buffer renderer writes
; to the BG3 staging buffer at $7E:D600, but vanilla's treasure main
; loop only DMAs BG2 + sprites each frame, so we have to push the BG3
; tilemap to VRAM ourselves whenever a slot was just re-rendered.
    lda.w treasure_transfer_pending
    beq _treasure_main_after_xfer
    jsr.l TfrBG3TilesVblank_Trampoline
    stz.w treasure_transfer_pending
_treasure_main_after_xfer:
    lda.w treasure_scroll_state
    beq _treasure_main_call_orig
_treasure_main_block_input:
    stz.b 0x01
_treasure_main_call_orig:
    jsr.w 0x82C0
    rts

treasure_menu_entry_hook:
    jsr.l TreasureMenuEntryHook_Impl
    rts

treasure_menu_exit_hook:
    jsr.l TreasureMenuExitHook_Impl
    rts
}
