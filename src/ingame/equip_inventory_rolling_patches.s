"""
Equip-screen inventory list (`SelectItemFromInventory`, $01:BE89) on its rolling buffer: ring init, engine
scrolls in place of the blocking loops, single-column cursor and index math.
"""


.include "core/libmz.i"
.import "core/items"
.import "ingame/inventory_rolling_trampolines"


; List draw on entry.
.alloc at 0x01BEA6 {
    jsr.w equip_init
}


; Cursor sprite X: one column, flush left of the item icon (replaces the 8-byte column pick from ($54)).
.alloc at 0x01BEC0 {
    lda #EQUIP_LIST_CURSOR_X
    pad_nop(6)
}


; Cursor sprite Y base (`adc #$76` at $01:BEBC): VWF names sit on the slot's bottom tile row.
.alloc at 0x01BEBD {
    .db EQUIP_LIST_CURSOR_Y_BASE
}


; Kill the RIGHT / LEFT column toggles (`and #$01` / `and #$02`).
.alloc at 0x01BED6 {
    .db 0x00
}


.alloc at 0x01BEE5 {
    .db 0x00
}


; Scroll up: replaces the 16-byte loop moving $99 2 px x 8 frames.
.alloc at 0x01BF03 {
    jsr.w equip_scroll_up
    pad_nop(13)
}


; Scroll-down bound on the first visible row (vanilla $13).
.alloc at 0x01BF2D {
    .db EQUIP_LIST_SCROLL_LIMIT
}


; Scroll down, same with `inc $99`.
.alloc at 0x01BF32 {
    jsr.w equip_scroll_down
    pad_nop(13)
}


; Item index (row + scroll) * 2, replacing `asl / adc ($54) / asl`. Ignores the column byte (may be 1 from a
; vanilla save).
.alloc at 0x01BF5A {
    clc
    adc #0x00
}


; Teardown: both ways out of the list return here before BG4 clears.
.alloc at 0x01BE70 {
    jsr.w equip_leave
}
