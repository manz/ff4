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

; Extend $1BB7 max from $14 (20) to $2B (43 = 48 - 5).
    *=0x01DA86
    .db 0x2B

; Replace `jsr $01A172` (vanilla DrawInventoryList) with rolling-buffer
; init. The init body sets up HDMA via the shared field shadow at
; $1BAE so the existing field NMI hook drives the channel-5 copy.
    *=0x01D933
    jsr.w init_treasure_rolling_buffer

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
}
