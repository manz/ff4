"""
Bank-$01 trampolines (jsr.l + rts) into the inventory rolling routines that live in bank $21, plus small
wrappers around original bank-$01 helpers used by the rolling code.
"""
.include "config.i"
.include "src/ingame/macros.i"

.extern items_menu_vwf.draw_field_item_name

;; Bank-$01 trampolines for inventory rolling routines living in bank $21.
;; Reclaimed space: $01:EBD2 onwards (from init_bg_scroll_hdma relocation).
;; Each trampoline = jsr.l + rts = 5 bytes.
;;
;; Bank-$01 callers (inventory_rolling_patches.s, free_space.s) jsr.w these
;; bank-$01 names; the trampoline JSLs into the bank-$21 implementation.

.pool bank01_trampolines {
    range 0x01ebd2 0x01ff34
    strategy order
}

.if INVENTORY_ROLLING_BUFFER {
    .alloc bank01_inventory_trampolines in bank01_trampolines {
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

tfr_bg3_tiles_vblank_trampoline:
    jsr 0x9447
; original @ $01:9447 - pushes BG3 buffer at $7E:D600 to VRAM $7000
; over a vblank-bounded chunked DMA. Used by the treasure rolling
; buffer: render writes go to the BG3 staging area but original's
; treasure main loop only refreshes BG2/sprites mid-menu, so without
; this call the rolling-buffer slot updates never make it on screen.
    rtl

tfr_bg4_tiles_vblank_trampoline:
    jsr 0x943A
; original @ $01:943A - pushes BG4 buffer at $7E:C600 to VRAM $7800.
; Used by the drops rolling buffer: drops items render into the BG4
; frame that already holds TreasureItemsWindow, but the treasure main
; loop never re-DMAs BG4 mid-menu so swap/scroll updates would stay
; in WRAM without this call.
    rtl

drops_select_bg4_trampoline:
    jsr 0x8485
; original SelectClearBG4 at $01:8485 - wipes BG4 staging to blank
; tiles before falling through to SelectBG4 ($8488). Without the
; clear, $C600..$CDFF holds whatever the previous menu/screen left
; there, which gets DMA'd to BG4 VRAM and bleeds across the screen
; once HDMA enables ch4 for the drops band.
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

draw_field_item_name_trampoline:
"""
Bank-$01 JSR-callable wrapper around the bank-20
`items_menu_vwf.draw_field_item_name` RTL helper. The vanilla
`DrawItemName` patch at $01:9060 / `DrawEquipItemName` at $01:9013
must stay 4 bytes (jsr.w + rts) so the very next byte at $01:9064
keeps holding the vanilla sprite-render sub-routine's `phx` opcode :
overrunning into $01:9064 with a JSL + RTS (5 bytes) replaced that
phx with the wrapper's RTS, which short-circuited the save-selection
sprite path's `jsr $9064` and parked every sprite off-screen on the
title-screen-press-A entry. Use this trampoline so the call site
stays at 3+1 bytes and the vanilla sprite routine is preserved.
"""


    jsr.l items_menu_vwf.draw_field_item_name
    rts
    }


; end .alloc bank01_inventory_trampolines
}
; end .if INVENTORY_ROLLING_BUFFER

;; Bank-$01 thunks + wrappers for the treasure exchange rolling buffer.
;; Mirror the field-menu set above but call the treasure_-prefixed bodies
;; in src/ingame/treasure_rolling.s. Both menus are mutually exclusive on
;; screen so the HDMA channel + tilemap buffer + WRAM shadow tables are
;; reused; only the per-menu state RAM differs.
.if TREASURE_INVENTORY_ROLLING {
    .alloc bank01_treasure_trampolines in bank01_trampolines {
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
; Original writes $1BB7 each frame DOWN/UP is held - no built-in debounce
; once the blocking scroll loop is gone. Gate the trigger on
; `treasure_rolling.scroll_state == 0` and undo original's $1BB7 update when an
; animation is still in flight, so the rolling buffer steps once per
; press instead of advancing dozens of times per held button.
treasure_scroll_down_trigger:
"""Treasure profile: input-driven scroll-down trigger."""
    lda.w treasure_rolling.scroll_state
    bne _t_down_abort
    lda.w treasure_scroll_cooldown
    bne _t_down_abort
    jsr.w _treasure_force_hdma_setup
    jsr.w _treasure_start_scroll_down
    sep #0x20
    lda.b #TREASURE_SCROLL_COOLDOWN_FRAMES
    sta.w treasure_scroll_cooldown
    rts
_t_down_abort:
    dec.w 0x1BB7
    rts

treasure_scroll_up_trigger:
"""Treasure profile: input-driven scroll-up trigger."""
    lda.w treasure_rolling.scroll_state
    bne _t_up_abort
    lda.w treasure_scroll_cooldown
    bne _t_up_abort
    jsr.w _treasure_force_hdma_setup
    jsr.w _treasure_start_scroll_up
    sep #0x20
    lda.b #TREASURE_SCROLL_COOLDOWN_FRAMES
    sta.w treasure_scroll_cooldown
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
; Capture original BG3VOFS shadow ($9F) - original treasure draws inventory
; rows starting at screen scanline ~120 with $9F = -120, which keeps the
; existing window/dialog tilemap content visible on the header band.
    lda.l 0x7E019F
    sta.w treasure_rolling.base_scroll
    sep #0x20
; Original treasure ROM enables HDMAEN=$AD = ch7|ch5|ch3|ch2|ch0. ch2
; is an HDMA INDIRECT mode-3 channel that writes BG3HOFS+BG3VOFS for
; the drops-band parallax. Even with our scroll moved to ch6 (which
; iterates after ch2 and should "win" the BG3VOFS at scanlines past
; the drops band), the rolling buffer scroll never takes effect while
; ch2 is enabled - likely because ch2 keeps reloading entries via its
; indirect table past scanline 128. Mask ch2 entirely; the drops-band
; original parallax is purely cosmetic and the drops list still lands
; at the right scanline without it.
    lda #0xF9  ; $AD & ~0x04 | $40 | $10 = ch7|ch6|ch5|ch4|ch3|ch0 (drops on ch4)
    sta.l field_menu_rolling.hdma_enable
    rts

treasure_main_loop_scroll_check:


"""
Replaces the original `jsr $82C0` at $01:DA08. Drives the scroll
state machine each frame  ; while scrolling it zeroes $01 so the
downstream `and #JOY_*` input checks all branch out, freezing
cursor / button handling until the animation settles. Always ends
by calling the original $82C0 so original per-frame work still runs.
"""


; Cooldown tick : runs every popup frame regardless of button state
; so the held-DOWN debounce drains uniformly. Without this the
; trigger path's per-call dec only fired while DOWN was held, which
; let auto-repeat consume the cooldown in 2-3 frames and scrolled
; the treasure inv two items per visible tap.
    sep #0x20
    lda.w treasure_scroll_cooldown
    beq _t_main_cd_done
    dec.w treasure_scroll_cooldown

_t_main_cd_done:
    lda.w treasure_rolling.scroll_state
    beq _treasure_main_check_drops_tick
    jsr.w _treasure_update_scroll_frame
    lda.w treasure_rolling.scroll_remaining
    bne _treasure_main_block_input
    jsr.w _treasure_finish_scroll
_treasure_main_check_drops_tick:
; Drops scroll state machine shares the treasure menu's per-frame
; tick. While drops is animating, zero $01 (input mask) so cursor
; input is frozen until the scroll lands - same shape as the
; treasure-inventory branch above.
    lda.w drops_rolling.scroll_state
    beq _treasure_main_check_xfer
    jsr.l drops_update_scroll_frame_impl
    lda.w drops_rolling.scroll_remaining
    bne _treasure_main_block_input
    jsr.l drops_finish_scroll_impl
_treasure_main_check_xfer:
; Drain treasure_rolling.transfer_pending - the rolling buffer renderer writes
; to the BG3 staging buffer at $7E:D600, but original's treasure main
; loop only DMAs BG2 + sprites each frame, so we have to push the BG3
; tilemap to VRAM ourselves whenever a slot was just re-rendered.
    lda.w treasure_rolling.transfer_pending
    beq _treasure_main_after_bg3
    jsr.l tfr_bg3_tiles_vblank_trampoline
    stz.w treasure_rolling.transfer_pending
_treasure_main_after_bg3:
; Drain drops_rolling.transfer_pending - drops render into BG4 staging at
; $7E:C600 (alongside TreasureItemsWindow), so push BG4 to VRAM
; whenever drops re-rendered.
    lda.w drops_rolling.transfer_pending
    beq _treasure_main_after_xfer
    jsr.l tfr_bg4_tiles_vblank_trampoline
    stz.w drops_rolling.transfer_pending
_treasure_main_after_xfer:
    lda.w treasure_rolling.scroll_state
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
"""Bank-$01 trampoline: re-render all drops slots (engine refresh path)."""
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
    lda.l drops_rolling.scroll_state
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
    lda.l drops_rolling.scroll_state
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

; Custom InventoryWindow data for the treasure inventory list. Built
; via menu_window(left, top, width, height) so the layout matches
; original window blobs (cursor word + width/height byte pair).
; DrawWindowTiles emits 1 + height + 1 BG rows. height = 12 →
; 14 rows total → bottom border at BG row 13, lining up with the
; rolling-buffer footer scanlines (BASE + 16 = -104 with BASE = -120
; → screen 208-223 reads BG line 104-119 = rows 13-14).
treasure_inventory_window:
"""Bank-$01 window data for the treasure inventory list (5 visible rows, BG3)."""
    menu_window(0, 0, 30, 12)

; Drops band window anchored at BG (0, 0). HDMA shifts BG4VOFS by
; -24 so the window appears on screen at y=24 (matching where the
; original TreasureItemsWindow at $01:E275 lived). Anchoring at the
; tilemap origin keeps the per-row HDMA offsets consistent with the
; treasure-inventory layout - same shape, easier math.
treasure_drops_window:
"""
Bank-$01 window data for the treasure drops list (5 visible rows, BG4).

Body height 12 = staging rows 1..12 with bottom border at row 13. Items
render at staging rows 1,3,5,7,9 and the HDMA footer reads -8 to land
the bottom border at screen y=112..120 (just below the 5th item).
"""


    menu_window(0, 0, 30, 12)
    }


; end .alloc bank01_treasure_trampolines
}
; end .if TREASURE_INVENTORY_ROLLING

.alloc bank01_shop_trampolines in bank01_trampolines {
shop_quantity_text_hook:
"""
Render the owner welcome ('Que désirez vous ?') through the small-VWF
description region, then fall through to the vanilla menu-text engine
for the rest of the quantity block (Quantité + initial '1' digit).

Called in place of the original `jsr $8301` at the buy ($01:C442) and
sell ($01:C7E7) entry points  ; the matching `LDY #shops.quantity` at
$01:C43F / $01:C7E4 is left in place so an unrelated future caller
could still chain into $8301 with the slimmed block.
"""


    ldy.w #shops.que_desirez_vous
    jsr.l items_description.draw_trampoline_pos
    ldy.w #shops.quantity - 0x8000
    jsr.w 0x8301  ; draw text at position (= display_text_in_menus thunk)
    rts

shop_welcome_text_hook:
"""
Render the shop owner's greeting ('Puis-je vous aider ?') through the
small-VWF description region, then tail-jump to the vanilla menu-text
engine for the remaining `Achat Vente Sortir` action labels.

Called in place of the original `jmp $8301` at $01:C353. The matching
`LDY #shops.welcome_and_actions` at $01:C350 is left in place  ; the
slimmed `welcome_and_actions` block now holds only the action line.
"""


    ldy.w #shops.puis_je_vous_aider
    jsr.l items_description.draw_trampoline_pos
    ldy.w #shops.welcome_and_actions - 0x8000
    jmp.w 0x8301  ; tail-call to draw positioned text

shop_thanks_text_hook:
"""
Draw the thank-you window via the vanilla `$82FB` (which expects an
empty trailing text block  ; see `thank_you_window` data), then render
the actual 'Merci !' copy through the small-VWF description region.

Called in place of the original `jsr $82FB` at $01:C751. The matching
`LDY #shops.thank_you_window` at $01:C74E is left in place.
"""


    jsr.w 0x82FB  ; draw window + (empty) text
    ldy.w #shops.merci
    jsr.l items_description.draw_trampoline_pos
    rts
}
