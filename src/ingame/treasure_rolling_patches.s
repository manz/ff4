"""
Treasure menu patches for the rolling buffers: single-column cursors, swap offsets, scroll hooks, entry/exit.

ROM landmarks:
- $01D792 TreasureMenu entry
- $01D929 redraw helper (DrawTreasureList + DrawInventoryList)
- $01D967 exchange-picker top-cursor input loop
- $01D9EA inventory-picker submenu (scrolls $1440)
- $01DA59 / $01DA8E up / down blocking scroll loops (`dec` / `inc $9f` x 8)
- $01DA85 `cmp #$14` scroll-down limit
"""
.import "core/preamble"
.import "ingame/inventory_rolling_trampolines"
.import "core/items"

; Cursor sprite X for both lists: one column, flush left of the item icon. Makes the column byte irrelevant.
.alloc at 0x01D977 {
    lda #TREASURE_CURSOR_X
}


.alloc at 0x01D97B {
    lda #TREASURE_CURSOR_X
}


.alloc at 0x01D9FE {
    lda #TREASURE_CURSOR_X
}


; Kill 2-column navigation in the inventory picker (JOY_RIGHT / JOY_LEFT).
.alloc at 0x01DA23 {
    .db 0x00
}


.alloc at 0x01DA34 {
    .db 0x00
}


; Inventory cursor column always 0: `lda $1BB6` -> `lda #$00 / nop`.
.alloc at 0x01D9F5 {
    lda #0x00
    nop
}


; Swap offset: vanilla's ((($1BB5 + $1BB7) << 1 + $1BB6) << 1 assumes 2 columns. Drop the second `asl` so it
; is ($1BB5 + $1BB7) * 2, else half the inventory is unreachable.
.alloc at 0x01DAC2 {
    nop
}


; $1BB7 limit $14 -> $2C: the top row stops at 43 = 48 - 5 ($2B would leave item 47 unpickable).
.alloc at 0x01DA86 {
    .db 0x2C
}


; Drops swap index: (cursor_row + drops_scroll_pos) * 2 into $7E:FF28, instead of vanilla's 4x2 grid math.
; Needs long addressing, so it goes through drops_swap_index; the 11-byte vanilla sequence is padded out.
.alloc at 0x01DAAC {
    jsr.w drops_swap_index
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
}


; `jsr $A172` (DrawInventoryList) call sites: $01:D81D (menu entry, full init) and $01:D933 (after a swap,
; refresh only: an init there would snap the scroll back to the top).
.alloc at 0x01D81D {
    jsr.w init_treasure_rolling_buffer
}


.alloc at 0x01D933 {
    jsr.w treasure_refresh_slots
}


.alloc at 0x01D80E {
    jsr.w drops_init
}


.alloc at 0x01D92D {
    jsr.w drops_refresh_slots
}


; drops_init already drew TreasureItemsWindow; vanilla's SelectBG4 + DrawWindow ($01:D811, 9 bytes) would draw
; it again over the items. SelectBG3 at $01:D81A still primes $29 = $D600 for the treasure init.
.alloc at 0x01D811 {
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
}


; Drops cursor Y base (vanilla `adc #$30` for the 4x2 grid).
.alloc at 0x01D96F {
    .db DROPS_CURSOR_Y_BASE
}


; Per-frame tick on the drops cursor loop's frame wait, so held UP/DOWN scrolls the drops list.
.alloc at 0x01D98B {
    jsr.w treasure_main_loop_scroll_check
}


; Drops cursor clamps become scroll triggers. UP ($01:D9D1): handler reads N from the preceding `dec`.
.alloc at 0x01D9D1 {
    jsr.w drops_up_handler
    nop
    nop
}


; DOWN ($01:D9E0, NOPs over the row `cmp`): handler gets A = row + 1, scrolls at the visible cap.
.alloc at 0x01D9E0 {
    .db 0xEA
    .db 0xEA
    jsr.w drops_down_handler
    nop
    nop
}


; Blocking 8-frame scroll loops -> state-machine triggers: up $01:DA57 (16 bytes), down $01:DA8C.
.alloc at 0x01DA57 {
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
}


.alloc at 0x01DA8C {
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
}


; Main-loop tick over `jsr $82C0` at $01:DA08: animates, freezes input while scrolling, then runs $82C0.
.alloc at 0x01DA08 {
    jsr.w treasure_main_loop_scroll_check
}


; Same at $01:DA9C and $01:DA67: the held DOWN / UP loops jump back to $DA0B and never pass $DA08.
.alloc at 0x01DA9C {
    jsr.w treasure_main_loop_scroll_check
}


.alloc at 0x01DA67 {
    jsr.w treasure_main_loop_scroll_check
}


; Menu exit over `stz $1BC6`: the hook redoes it and tears down the rolling state and HDMA ch6.
.alloc at 0x01D7E6 {
    jsr.w treasure_menu_exit_hook
}
