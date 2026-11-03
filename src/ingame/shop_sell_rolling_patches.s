"""
Shop sell list ($01:C7BE) hooks: the `DrawInventoryList` draw becomes a ring init, and each blocking 8-frame
BG3VOFS scroll loop becomes an engine scroll of the same length (src/ingame/shop_sell_rolling.s).
"""


.import "ingame/inventory_rolling_trampolines"
.include "core/libmz.i"


; Sell list draw, on entry and after a sale changes quantities.
.alloc at 0x01C7F0 {
    jsr.w sell_init
}


.alloc at 0x01C887 {
    jsr.w sell_init
}


; Scroll up: replaces the 15-byte loop `dec $9F` x 2 / `jsr $94A1` per frame, 8 frames counted in $45.
.alloc at 0x01C8E3 {
    jsr.w sell_scroll_up
    pad_nop(12)
}


; Scroll down: same loop with `inc $9F`.
.alloc at 0x01C91C {
    jsr.w sell_scroll_down
    pad_nop(12)
}


; Vanilla's sell list has two columns of 24 rows: RIGHT and LEFT toggle the column ($1B95), the scroll ($1B96)
; stops at 16 and the sale indexes (row + scroll) * 2 + column. The list here is one column of 48 rows.

; RIGHT, LEFT: `beq` past the column toggle becomes `bra`.
.alloc at 0x01C8A7 {
    .db 0x80
}


.alloc at 0x01C8B8 {
    .db 0x80
}


; Scroll down stops with the last of the 48 rows on the bottom line.
.alloc at 0x01C911 {
    cmp #48 - 8 + 1
}


; The sale's slot: (row + scroll) * 2 bytes, the `asl` / `adc $1B95` x 2 of the second column gone.
.alloc at 0x01C942 {
    pad_nop(7)
}


; Shop teardown: hand ch5 back before the shop returns.
.alloc at 0x01C304 {
    jsr.w sell_leave
}
