"""
Bank-$01 trampolines (jsr.l + rts) into the inventory rolling routines that live in bank $21, plus small
wrappers around original bank-$01 helpers used by the rolling code.
"""
;; Bank-$01 trampolines for inventory rolling routines living in bank $21.
;; Reclaimed space: $01:EBD2 onwards (from init_bg_scroll_hdma relocation).
;; Each trampoline = jsr.l + rts = 5 bytes.
;;
;; Bank-$01 callers (inventory_rolling_patches.s, free_space.s) jsr.w these
;; bank-$01 names; the trampoline JSLs into the bank-$21 implementation.

.if INVENTORY_ROLLING_BUFFER {
    *=0x01EBD2
check_and_clear_count:
"""Bank-$01 trampoline: bridge to `check_and_clear_count_impl` in bank $21."""
    jsr.l check_and_clear_count_impl
    rts

init_menu_rolling_buffer:
"""Bank-$01 trampoline: initialise the rolling-buffer state held in bank $21."""
    jsr.l init_menu_rolling_buffer_impl
    rts

swap_redraw_hook_impl:
"""Bank-$01 trampoline into `swap_redraw_hook_impl_body` (bank $21)."""
    jsr.l swap_redraw_hook_impl_body
    rts

start_scroll_down:
"""Bank-$01 trampoline: kick off a scroll-down animation."""
    jsr.l start_scroll_down_impl
    rts

start_scroll_up:
"""Bank-$01 trampoline: kick off a scroll-up animation."""
    jsr.l start_scroll_up_impl
    rts

update_scroll_frame:
"""Bank-$01 trampoline: advance the rolling buffer by one animation frame."""
    jsr.l update_scroll_frame_impl
    rts

finish_scroll:
"""Bank-$01 trampoline: settle the rolling buffer at the end of a scroll."""
    jsr.l finish_scroll_impl
    rts
; --- Bank-$01 original call trampolines ---
; Bank-$21 code can't `jsr.w` into bank $01 original routines; these trampolines
; wrap a original `JSR` so bank-$21 callers can `jsr.l` and get a clean RTL
; back without stack imbalance.

draw_window_trampoline:
"""Bank-$01 RTL trampoline around original `DrawWindow` ($01:80D9)."""
    jsr 0x80D9
; original DrawWindow at $01:80D9
    rtl

check_can_use_item_trampoline:
"""Bank-$01 RTL trampoline around original `CheckCanUseItem` ($01:A25D)."""
    jsr 0xA25D
; original CheckCanUseItem at $01:A25D (sets $DB)
    rtl

draw_item_slot_inner_trampoline:
"""Bank-$01 RTL trampoline around original `DrawItemSlot` inner ($01:A1ED)."""
    jsr 0xA1ED
; original DrawItemSlot inner at $01:A1ED
    rtl

tfr_sprites_vblank_trampoline:
"""Bank-$01 RTL trampoline around original `TfrSpritesVblank` ($01:824F)."""
    jsr 0x824F
; original @ $01:824F
    rtl

tfr_bg2_tiles_vblank_trampoline:
"""Bank-$01 RTL trampoline around original `TfrBG2TilesVblank` ($01:9420)."""
    jsr 0x9420
; original @ $01:9420
    rtl

_tfr_bg3_tiles_vblank_trampoline:
    jsr 0x9447
; original @ $01:9447 — pushes BG3 buffer at $7E:D600 to VRAM $7000
; over a vblank-bounded chunked DMA. Used by the treasure rolling
; buffer: render writes go to the BG3 staging area but original's
; treasure main loop only refreshes BG2/sprites mid-menu, so without
; this call the rolling-buffer slot updates never make it on screen.
    rtl

draw_item_cursors_trampoline:
"""Bank-$01 RTL trampoline around original `DrawItemCursors` ($01:A105)."""
    jsr 0xA105
; original @ $01:A105
    rtl

update_ctrl_after_scroll_trampoline:
"""Bank-$01 RTL trampoline around original `UpdateCtrlAfterScroll` ($01:82A5)."""
    jsr 0x82A5
; original @ $01:82A5
    rtl

init_item_list_trampoline:
"""Bank-$01 trampoline for original InitItemList @ $01:B2D3 (filters $1440 -> $0712 by key-item ID range)."""
    jsr 0xB2D3
    rtl

reset_sprites_trampoline:
"""Bank-$01 RTL trampoline around original `ResetSprites` ($01:8D6A)."""
    jsr 0x8D6A
; original @ $01:8D6A
    rtl
}

;; Bank-$01 thunks + wrappers for the treasure exchange rolling buffer.
;; Mirror the field-menu set above but call the treasure_-prefixed bodies
;; in src/ingame/treasure_rolling.s. Both menus are mutually exclusive on
;; screen so the HDMA channel + tilemap buffer + WRAM shadow tables are
;; reused; only the per-menu state RAM differs.
.if TREASURE_INVENTORY_ROLLING {
_treasure_check_and_clear_count:
    jsr.l treasure_check_and_clear_count_impl
    rts

init_treasure_rolling_buffer:
"""Treasure profile: trampoline into `init_treasure_rolling_buffer_impl`."""
    jsr.l init_treasure_rolling_buffer_impl
    rts

treasure_refresh_slots:
"""Treasure profile: trampoline into `treasure_refresh_slots_impl`."""
    jsr.l treasure_refresh_slots_impl
    rts

_treasure_swap_redraw_hook_impl:
    jsr.l treasure_swap_redraw_hook_impl_body
    rts

_treasure_start_scroll_down:
    jsr.l treasure_start_scroll_down_impl
    rts

_treasure_start_scroll_up:
    jsr.l treasure_start_scroll_up_impl
    rts

_treasure_update_scroll_frame:
    jsr.l treasure_update_scroll_frame_impl
    rts

_treasure_finish_scroll:
    jsr.l treasure_finish_scroll_impl
    rts

; Original treasure already updated $1BB7 before reaching the patch site,
; so the triggers just kick off the state-machine animation.
; Force the field-menu HDMA shadow ($1BAE) ON before kicking the state
; machine so the existing field NMI hook copies the shadow→active table
; even when the rolling-buffer init at $01:D933 never ran (some treasure
; flows skip the redraw helper).
; Original writes $1BB7 each frame DOWN/UP is held — no built-in debounce
; once the blocking scroll loop is gone. Gate the trigger on
; `treasure_scroll_state == 0` and undo original's $1BB7 update when an
; animation is still in flight, so the rolling buffer steps once per
; press instead of advancing dozens of times per held button.
treasure_scroll_down_trigger:
"""Treasure profile: input-driven scroll-down trigger."""
    lda.w treasure_scroll_state
    bne _t_down_abort
    jsr.w _treasure_force_hdma_setup
    jsr.w _treasure_start_scroll_down
    rts
_t_down_abort:
    dec.w 0x1BB7
    rts

treasure_scroll_up_trigger:
"""Treasure profile: input-driven scroll-up trigger."""
    lda.w treasure_scroll_state
    bne _t_up_abort
    jsr.w _treasure_force_hdma_setup
    jsr.w _treasure_start_scroll_up
    rts
_t_up_abort:
    inc.w 0x1BB7
    rts

_treasure_force_hdma_setup:


"""
Reconfigure HDMA channel 5 for BG3 only when we're inside the treasure
menu (original sets $1BC6 at $01:D80B on entry, clears it at $01:D7E6 on
exit). Field-menu Items uses BG1 and reconfigures channel 5 itself  ; the
key-item submenu (e.g. Baron key) is yet another context to add later.
"""


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
; Capture original BG3VOFS shadow ($9F) — original treasure draws inventory
; rows starting at screen scanline ~120 with $9F = -120, which keeps the
; existing window/dialog tilemap content visible on the header band.
    lda.l 0x7E019F
    sta.w treasure_rolling_base_scroll
    sep #0x20
; Original treasure ROM enables HDMAEN=$AD = ch7|ch5|ch3|ch2|ch0. ch2
; is an HDMA INDIRECT mode-3 channel that writes BG3HOFS+BG3VOFS for
; the drops-band parallax. Even with our scroll moved to ch6 (which
; iterates after ch2 and should "win" the BG3VOFS at scanlines past
; the drops band), the rolling buffer scroll never takes effect while
; ch2 is enabled — likely because ch2 keeps reloading entries via its
; indirect table past scanline 128. Mask ch2 entirely; the drops-band
; original parallax is purely cosmetic and the drops list still lands
; at the right scanline without it.
    lda #0xE9  ; $AD & ~0x04 | $40 = ch7|ch6|ch5|ch3|ch0
    sta.l 0x7E1BAE
    rts

treasure_main_loop_scroll_check:


"""
Replaces the original `jsr $82C0` at $01:DA08. Drives the scroll
state machine each frame  ; while scrolling it zeroes $01 so the
downstream `and #JOY_*` input checks all branch out, freezing
cursor / button handling until the animation settles. Always ends
by calling the original $82C0 so original per-frame work still runs.
"""


    lda.w treasure_scroll_state
    beq _treasure_main_check_drops_tick
    jsr.w _treasure_update_scroll_frame
    lda.w treasure_scroll_remaining
    bne _treasure_main_block_input
    jsr.w _treasure_finish_scroll
_treasure_main_check_drops_tick:
; Drops scroll state machine shares the treasure menu's per-frame
; tick. While drops is animating, zero $01 (input mask) so cursor
; input is frozen until the scroll lands — same shape as the
; treasure-inventory branch above.
    lda.w drops_scroll_state
    beq _treasure_main_check_xfer
    jsr.l drops_update_scroll_frame_impl
    lda.w drops_scroll_remaining
    bne _treasure_main_block_input
    jsr.l drops_finish_scroll_impl
_treasure_main_check_xfer:
; Drain treasure_transfer_pending — the rolling buffer renderer writes
; to the BG3 staging buffer at $7E:D600, but original's treasure main
; loop only DMAs BG2 + sprites each frame, so we have to push the BG3
; tilemap to VRAM ourselves whenever a slot was just re-rendered.
; Drops shares the same BG3 buffer; OR its transfer_pending in so a
; single DMA drains both render writes per frame.
    lda.w treasure_transfer_pending
    ora.w drops_transfer_pending
    beq _treasure_main_after_xfer
    jsr.l _tfr_bg3_tiles_vblank_trampoline
    stz.w treasure_transfer_pending
    stz.w drops_transfer_pending
_treasure_main_after_xfer:
    lda.w treasure_scroll_state
    beq _treasure_main_call_orig
_treasure_main_block_input:
    stz.b 0x01
_treasure_main_call_orig:
    jsr.w 0x82C0
    rts

_treasure_menu_entry_hook:
    jsr.l treasure_menu_entry_hook_impl
    rts

treasure_menu_exit_hook:
"""Treasure profile: menu-exit hook trampoline."""
    jsr.l treasure_menu_exit_hook_impl
    rts

drops_init:
"""Bank-$01 trampoline: kick the drops rolling buffer init (filter+render via engine)."""
    jsr.l drops_init_impl
    rts

drops_refresh_slots:
"""Bank-$01 trampoline: re-render all drops slots (engine refresh path, no scroll-state reset)."""
    jsr.l drops_refresh_slots_impl
    rts

drops_down_handler:


"""
Bank-$01 cursor-row store + DOWN-scroll trigger. Called from the
hijacked clamp site at $01:D9E0 with the candidate cursor row in A
(= $1BB3 + 1). Stores the row when below the visible cap  ; otherwise
fires the engine scroll-down state machine so items past row 4
reveal. Returns with the row stored or an animation kicked.
"""


    cmp #DROPS_VISIBLE_ITEMS
    bcc _drops_down_store
    pha
    lda.l drops_scroll_state
    bne _drops_down_busy
; Clamp scroll_pos at TOTAL - VISIBLE (3 for 8-total / 5-visible).
    lda.l drops_scroll_pos
    cmp #DROPS_TOTAL_ITEMS - DROPS_VISIBLE_ITEMS
    bcs _drops_down_busy
    inc
    sta.l drops_scroll_pos
    pla
    jsr.l drops_start_scroll_down_impl
    rts
_drops_down_busy:
    pla
    rts
_drops_down_store:
    sta.w 0x1BB3
    rts

drops_up_handler:


"""
Bank-$01 cursor-row store + UP-scroll trigger. Called from the
hijacked clamp site at $01:D9D1 with the decremented row in A
(= $1BB3 - 1). Stores the row when non-negative  ; if it underflowed
(N flag set, row was 0) fires the scroll-up state machine to pull
a fresh top row down.
"""


    bmi _drops_up_scroll
    sta.w 0x1BB3
    rts
_drops_up_scroll:
    pha
    lda.l drops_scroll_state
    bne _drops_up_busy
    lda.l drops_scroll_pos
    beq _drops_up_busy  ; already at top
    dec
    sta.l drops_scroll_pos
    pla
    jsr.l drops_start_scroll_up_impl
    rts
_drops_up_busy:
    pla
    rts
}
