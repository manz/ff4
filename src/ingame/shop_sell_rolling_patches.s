"""
ROM patches wiring the shop sell list to its rolling buffer.

Vanilla's sell menu ($01:C7BE) draws the whole inventory with
`DrawInventoryList` ($01:A172) and scrolls BG3VOFS over it in blocking
8-frame loops. Both assumptions break under single-column VWF rows
(see src/ingame/shop_sell_rolling.s), so the draw becomes a ring init
and each scroll loop becomes one engine-driven animation of the same
length.
"""

.include "config.i"
.if TREASURE_INVENTORY_ROLLING {

; Sell list draw, on entry and after a sale changes quantities.
.alloc at 0x01C7F0 {
        jsr.w sell_init
}
.alloc at 0x01C887 {
        jsr.w sell_init
}

; Scroll up. Vanilla's loop at $C8E3 runs `dec $9F` twice per frame for
; the 8 frames counted down in $45, calling $94A1 to push the scroll
; shadow; the engine keeps that cadence and rolls the ring instead.
;   C8E3 C2 20     rep #$20
;   C8E5 C6 9F     dec $9f
;   C8E7 C6 9F     dec $9f
;   C8E9 E2 20     sep #$20
;   C8EB 20 A1 94  jsr $94a1
;   C8EE C6 45     dec $45
;   C8F0 D0 F1     bne $c8e3
.alloc at 0x01C8E3 {
        jsr.w sell_scroll_up
        pad_nop(12)
}

; Scroll down, the same shape with `inc $9F`.
.alloc at 0x01C91C {
        jsr.w sell_scroll_down
        pad_nop(12)
}

; Shop teardown: hand ch5 back before the shop returns.
.alloc at 0x01C304 {
        jsr.w sell_leave
}
}
