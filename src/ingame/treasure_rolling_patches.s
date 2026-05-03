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

; TODO: state-machine triggers, init replacement, bank-$01 thunks.
; Bodies live in src/ingame/treasure_rolling.s.
    .if 0 {
    *=0x01DA59
    jsr.w treasure_scroll_up_trigger

    *=0x01DA8E
    jsr.w treasure_scroll_down_trigger

    *=0x01D9EA
    jmp.w treasure_main_loop_scroll_check

    *=0x01D7E0
    jsr.w treasure_menu_entry_hook

    *=0x01D933
    jsr.w init_treasure_rolling_buffer
    }
}
