"""
Bank-$01 trampolines (jsr.l + rts) into the inventory rolling routines that live in bank $21, plus small
wrappers around original bank-$01 helpers used by the rolling code.
"""

.import "preamble"
.import "ingame/vanilla_trampolines"
.import "ingame/drops_rolling"
.import "ingame/treasure_rolling"
.import "small_vwf/init"
.import "menus/tools_shop_text"
.import "ingame/shop_sell_rolling"
.import "ingame/equip_inventory_rolling"
.import "ingame/inventory_rolling"
.import "ingame/items_menu_vwf"
.import "items"

; Typed views over the profiles' state blocks. A cast is compile-time,
; so it cannot be imported the way a label is: each module that reads
; these fields binds its own view over the same addresses, the way
; battle/inventory_rolling.s already does.

.include "config.i"
.include "src/ingame/macros.i"


;; Bank-$01 trampolines for inventory rolling routines living in bank $21.
;; Reclaimed space: $01:EBD2 onwards (from init_bg_scroll_hdma relocation).
;; Each trampoline = jsr.l + rts = 5 bytes.
;;
;; Bank-$01 callers (inventory_rolling_patches.s, free_space.s) jsr.w these
;; bank-$01 names; the trampoline JSLs into the bank-$21 implementation.

.include "src/ingame/bank01_trampolines.i"
.import "vanilla"

.if INVENTORY_ROLLING_BUFFER {
    .if INVENTORY_ROLLING_BUFFER {
    _SELL_NAME_SLOT := 9  ; tiles $100 + 9 * 10

    .alloc _bank01_inventory_trampolines in bank01_trampolines {
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

sell_init:
"""Bank-$01 trampoline: replace DrawInventoryList for the sell list."""
    jsr.l sell_init_impl
    rts

sell_scroll_up:
"""Bank-$01 trampoline: sell list scroll up, in place of vanilla's $9F loop."""
    jsr.l sell_scroll_up_impl
    rts

sell_scroll_down:
"""Bank-$01 trampoline: sell list scroll down, in place of vanilla's $9F loop."""
    jsr.l sell_scroll_down_impl
    rts

sell_leave:
"""
Shop teardown: restore the dialogue window graphics, then drop ch5.

Hooked over the `JSR $873F` at $01:C304, the last call the shop menu
makes before returning - the displaced call is reissued here. The sell
list's HDMA bit lives in the shared `field_menu_rolling.hdma_enable`,
so leaving it set would arm ch5 over the field's own BG3.
"""


    jsr.w restore_dlg_gfx_far
    jsr.l sell_disable_hdma
    rts

equip_init:
"""Bank-$01 trampoline: replace DrawInventoryList for the equip list."""
    jsr.l equip_init_impl
    rts

equip_scroll_up:
"""Bank-$01 trampoline: equip list scroll up, in place of vanilla's $99 loop."""
    jsr.l equip_scroll_up_impl
    rts

equip_scroll_down:
"""Bank-$01 trampoline: equip list scroll down, in place of vanilla's $99 loop."""
    jsr.l equip_scroll_down_impl
    rts

equip_leave:
"""
Equip list teardown: drop ch5, then reissue the displaced call.

Hooked over the `JSR $A2DC` at $01:BE70, where both ways out of the
list (B, or an equip/remove) land before the screen clears BG4.
"""


    jsr.l equip_disable_hdma
    jsr.w hide_cursor2
    rts

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


; end .alloc _bank01_inventory_trampolines
    }
; end .if INVENTORY_ROLLING_BUFFER

;; Bank-$01 thunks + wrappers for the treasure exchange rolling buffer.
;; Mirror the field-menu set above but call the treasure_-prefixed bodies
;; in src/ingame/treasure_rolling.s. Both menus are mutually exclusive on
;; screen so the HDMA channel + tilemap buffer + WRAM shadow tables are
;; reused; only the per-menu state RAM differs.
    .if TREASURE_INVENTORY_ROLLING {
    .alloc _bank01_treasure_trampolines in bank01_trampolines {
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
_treasure_arm_cooldown:
"""Reload the held-DOWN debounce after a scroll trigger fired."""
    sep #0x20
    lda.b #TREASURE_SCROLL_COOLDOWN_FRAMES
    sta.w treasure_scroll_cooldown
    rts

_treasure_wait_vblank:
"""
Burn one frame on the debounced-abort path (vanilla `WaitVblank`,
$01:818A).

Vanilla scrolled inside a blocking 8-frame loop, which also paced the
surrounding input loop. Our trigger returns immediately instead, so
while the debounce holds a press off, the loop spins with no vblank
wait at all: game time ($16A3) freezes, the cooldown never ticks and
hold-to-scroll dies after the first item. One wait per aborted
trigger restores vanilla's pacing.
"""


    jsr.w wait_vblank
    rts

treasure_scroll_down_trigger:
"""Treasure profile: input-driven scroll-down trigger."""
    lda.w treasure_rolling.scroll_state
    bne _t_down_abort
    lda.w treasure_scroll_cooldown
    bne _t_down_abort
    jsr.w _treasure_force_hdma_setup
    jsr.w _treasure_start_scroll_down
    jsr.w _treasure_arm_cooldown
    rts
_t_down_abort:
    dec.w menu_cursor_data + 0xb7
    jsr.w _treasure_wait_vblank
    rts

treasure_scroll_up_trigger:
"""Treasure profile: input-driven scroll-up trigger."""
    lda.w treasure_rolling.scroll_state
    bne _t_up_abort
    lda.w treasure_scroll_cooldown
    bne _t_up_abort
    jsr.w _treasure_force_hdma_setup
    jsr.w _treasure_start_scroll_up
    jsr.w _treasure_arm_cooldown
    rts
_t_up_abort:
    inc.w menu_cursor_data + 0xb7
    jsr.w _treasure_wait_vblank
    rts

_treasure_force_hdma_setup:


"""
Reconfigure HDMA channel 5 for BG3 only when we're inside the treasure
menu (original sets $1BC6 at $01:D80B on entry, clears it at $01:D7E6 on
exit). Field-menu Items uses BG1 and reconfigures channel 5 itself  ; the
key-item submenu (e.g. Baron key) is yet another context to add later.
"""


    lda.w menu_cursor_data + 0xc6
    bne _t_setup_in_treasure
    rts
_t_setup_in_treasure:
    sep #0x20
    lda #0x02
    sta.l dma_ch6.DMAP  ; HDMA6 ctrl: DIRECT mode, 2 bytes / scanline
    lda #PPU.BG3VOFS
    sta.l dma_ch6.BBAD
    rep #0x20
    lda.w #0x9800  ; shared field-menu HDMA active table at $7E:9800
    sta.l dma_ch6.A1TL  ; HDMA6 src lo/hi
    sep #0x20
    lda #0x7E
    sta.l dma_ch6.A1B  ; HDMA6 src bank
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
    lda #0xF1  ; $AD & ~0x04 | $40 | $10, minus ch3 = ch7|ch6|ch5|ch4|ch0
; ch3 stays out of the mask: it carries the one-shot VWF CHR flush
; (src/small_vwf/render.s) and was never configured as an HDMA
; channel, so arming it fed the PPU a garbage table.
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


; Cooldown tick, gated on vanilla's per-frame game-time byte. This
; loop runs once per frame while input flows but ~20 times inside the
; frame that ends a scroll animation (blocking input with `stz $01`
; costs the vanilla loop its pacing), and a per-call `dec` drained the
; whole debounce in that one frame - so one held DOWN scrolled twice.
    sep #0x20
    lda.l menu_frame_time
    cmp.w treasure_scroll_frame_seen
    beq _t_main_cd_done
    sta.w treasure_scroll_frame_seen
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
    jsr.w update_ctrl_menu
    rts

_treasure_menu_entry_hook:
    jsr.l treasure_menu_entry_hook_impl
    rts

treasure_menu_exit_hook:
"""Treasure profile: menu-exit hook trampoline."""
    jsr.l treasure_menu_exit_hook_impl
    rts

shop_draw_item_name:
"""
Hand the shop's row index to the VWF renderer, then draw the name.

`items_menu_vwf.draw_field_item_name` reads DP $5D as the slot index and
gives each slot its own tile-id window. The shop's list loop
($01:C4A0) keeps the item id in $5D instead, so a high id asked for a
tile base past the CHR buffer and rows shared or overran each other's
tiles. At the call site X holds row * 2 (index into the tilemap-offset
table at $01:C58E) and A holds the item id, which must reach vanilla
`DrawItemName` untouched.
"""


    pha
    txa
    lsr
    sta.b menu_dp.item_slot
    pla
    jmp.w draw_item_name

shop_sell_item_name:
"""
The sell confirmation's item name (ConfirmSell, $01:CA02) in the last field-item tile window, slot 9 ($15A-$163):
ConfirmSell leaves the item id in $5D, which the VWF renderer reads as the slot, and the list under the window
keeps the low slots on screen. A = the item id, kept for DrawItemName; $5D comes back as ConfirmSell left it.
"""
    pha
    lda.b #_SELL_NAME_SLOT
    sta.b menu_dp.item_slot
    pla
    pha
    jsr.w draw_item_name
    pla
    sta.b menu_dp.item_slot
    rts

drops_swap_index:
"""
Bank-$01 helper for the drops swap byte-index recompute at $01:DAAC.

X = (cursor_row + drops_scroll_pos) * 2, the byte index into the
drops array at $7E:FF28. Lives here rather than inline at the patch
site because `drops_scroll_pos` needs long addressing ($7E:9C5F) and
the 11-byte vanilla sequence has no room for the extra opcode byte.
"""


    lda.w menu_cursor_data + 0xb3
    clc
    adc.l drops_scroll_pos
    asl
    jsr.w tax16  ; A -> X via scratch $43
    rts

drops_init:
"""Bank-$01 trampoline: kick the drops rolling buffer init (filter+render via engine)."""
    jsr.l drops_init_impl
    rts

drops_refresh_slots:
"""
Bank-$01 trampoline: re-render all drops slots (engine refresh path), then send BG4. The drops draw into BG4's
buffer ($7E:C600) but the redraw it replaces ($01:D929, after Tout prendre) only sends BG1 and BG3: an emptied
slot kept its colon and count on screen.
"""
    jsr.l drops_refresh_slots_impl
    jmp.w tfr_bg4_tiles_vblank

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
    sta.w menu_cursor_data + 0xb3
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
    sta.w menu_cursor_data + 0xb3
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
    }


; end .alloc _bank01_treasure_trampolines
    }
; end .if TREASURE_INVENTORY_ROLLING

    .alloc _bank01_shop_trampolines in bank01_trampolines {
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


; the small-VWF menu text first: its render resets the engine state the description's upload is waiting in
    ldy.w #shops.quantity - 0x8000
    jsr.w draw_pos_text  ; draw text at position (= display_text_in_menus thunk)
    ldy.w #shops.que_desirez_vous
    jsr.l items_description.draw_trampoline_pos
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


; the small-VWF menu text first: its render resets the engine state the description's upload is waiting in
    ldy.w #shops.welcome_and_actions - 0x8000
    jsr.w draw_pos_text
    ldy.w #shops.puis_je_vous_aider
    jsr.l items_description.draw_trampoline_pos
    rts

shop_thanks_text_hook:
"""
Draw the thank-you window via the vanilla `$82FB` (which expects an
empty trailing text block  ; see `thank_you_window` data), then render
the actual 'Merci !' copy through the small-VWF description region.

Called in place of the original `jsr $82FB` at $01:C751. The matching
`LDY #shops.thank_you_window` at $01:C74E is left in place.
"""


    jsr.w draw_window_text  ; draw window + (empty) text
    ldy.w #shops.merci
    jsr.l items_description.draw_trampoline_pos
    rts
    }
}
