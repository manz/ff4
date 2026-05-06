; Treasure inventory rolling-buffer ROM patches.
;

; ROM landmarks (vanilla, confirmed via xdds):
;   $01D792 TreasureMenu entry
;   $01D929 redraw helper (DrawTreasureList + DrawInventoryList)
;   $01D967 exchange-picker top-cursor input loop
;   $01D9EA inventory-picker submenu (scrolls $1440)
;   $01DA22 `lda $01 / and #$01` JOY_RIGHT
;   $01DA33 `lda $01 / and #$02` JOY_LEFT
;   $01DA59 up-scroll blocking loop (`dec $9f` × 8)
;   $01DA85 `cmp #$14` scroll-down limit (vanilla 20)
;   $01DA8E down-scroll blocking loop (`inc $9f` × 8)
;
; Flag-gated off until the entry/exit/trigger thunks are wired up.

.if TREASURE_INVENTORY_ROLLING {
; Kill 2-col navigation in the inventory picker (JOY_RIGHT / JOY_LEFT).
    *=0x01DA23
    .db 0x00

    *=0x01DA34
    .db 0x00

; Force inventory cursor X to always 0 (left column).
; Original $01D9F5: `lda $1BB6` (AD B6 1B) → `lda #$00 / nop`.
    *=0x01D9F5
    lda #0x00
    nop

; Single-column swap-offset: vanilla _01daac computes
;   index = ((($1bb5 + $1bb7) << 1 + $1bb6) << 1
; for the 2-column inventory ($1bb5 = visible row, $1bb7 = scroll row,
; $1bb6 = column 0/1). The double-shift assumes 2 cols × 2 bytes/item;
; with our forced single-column ($1bb6=0) it multiplies by 4 instead of
; the 2 bytes/item we actually need, so the swap reads/writes
; even-numbered items only and half the inventory becomes unreachable.
; NOP the second `asl` at $01DAC2 so the offset becomes
; ($1bb5 + $1bb7) * 2 = byte index into $1440.
    *=0x01DAC2
    nop

; Extend $1BB7 max from $14 (20) to $2B (43 = 48 - 5).
    *=0x01DA86
    .db 0x2B

; Replace `jsr $01A172` (vanilla DrawInventoryList) at TWO call sites:
;   - $01:D81D — treasure menu entry (`_01d7f2` flow), fires once on enter
;     → full init (zero state, render slots 0..5).
;   - $01:D933 — `_01d929` redraw helper, fires after every successful
;     swap. Vanilla rebuilds the whole 48-item list here; we only need
;     to re-render the 6 buffer slots from the mutated $1440. Crucially
;     this MUST NOT reset buffer_pos / $1BB7 / HDMA shadow — otherwise
;     swapping with an item past visible row 4 snaps the scroll back to
;     the top because init re-zeroes the rolling state.
    *=0x01D81D
    jsr.w init_treasure_rolling_buffer
    *=0x01D933
    jsr.w treasure_refresh_slots

; Drops engine adoption: trampolines + render hook ready in
; drops_rolling.s, but the BG2 layer mask isn't set up so engine
; renders collide with the parent treasure-menu BG1 header. Keep
; the patches commented until BG2 mask setup or BG3-flatten lands.
;
;     *=0x01D80E
;     jsr.w drops_init
;     *=0x01D92D
;     jsr.w drops_refresh_slots

; Replace the up-scroll blocking 8-frame loop ($01:DA57-$01:DA66 = 16
; bytes) with our state-machine trigger.
    *=0x01DA57
    jsr.w treasure_scroll_up_trigger
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

; Same for the down-scroll loop at $01:DA8C-$01:DA9B.
    *=0x01DA8C
    jsr.w treasure_scroll_down_trigger
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

; Main-loop hook replaces `jsr $82C0` at $01:DA08. The hook drives the
; per-frame scroll animation, freezes input via `stz $01` while
; animating, and forwards to the original $82C0 so vanilla per-frame
; work still runs.
    *=0x01DA08
    jsr.w treasure_main_loop_scroll_check

; Same hook at $01:DA9C. The down/up scroll branch ends with
;   $DA9C jsr $82C0 / ldx $02 / stx $00 / $DAA3 jmp $DA0B
; which loops back to the input check WITHOUT passing through $DA08.
; While DOWN/UP is held, control bounces between $DA0B and $DAA3
; forever, so the $DA08 hook never fires and the scroll animation
; never ticks. Replacing the second $82C0 with our hook drives the
; state machine on the held-button inner loop too, matching the
; field-menu scroll cadence (every frame).
    *=0x01DA9C
    jsr.w treasure_main_loop_scroll_check

; Up-scroll branch: same pattern as the down branch, ends with
;   $DA67 jsr $82C0 / ldx $02 / stx $00 / $DA6E bra $DA0B
; Tick the state machine here too so held-UP scroll animates at the
; same cadence as held-DOWN.
    *=0x01DA67
    jsr.w treasure_main_loop_scroll_check

; Treasure menu exit. Vanilla: `stz $1BC6` (3 bytes) clears the in-menu flag.
; Replace with our exit hook (also 3 bytes), which restores vanilla state and
; additionally tears down the rolling-buffer state + HDMA ch6 registers so
; the next menu mode (field, key-item picker, battle) starts from a clean
; slate. The hook itself re-runs the `stz $1BC6` to preserve vanilla contract.
    *=0x01D7E6
    jsr.w treasure_menu_exit_hook
}
