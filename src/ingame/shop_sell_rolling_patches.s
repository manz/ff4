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


; Shop teardown: hand ch5 back before the shop returns.
.alloc at 0x01C304 {
    jsr.w sell_leave
}
