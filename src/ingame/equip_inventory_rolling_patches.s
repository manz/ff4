"""
ROM patches wiring the equip screen's inventory list to its rolling buffer.

Vanilla `SelectItemFromInventory` ($01:BE89) draws the whole inventory
with `DrawInventoryList` ($01:A172) as two items per row and scrolls
BG4VOFS over it in blocking 8-frame loops. The list becomes a ring
init, each scroll loop becomes one engine-driven animation of the same
length (see src/ingame/equip_inventory_rolling.s), and the two-column
cursor and index math collapse to one column.
"""


.include "src/libmz.i"
.import "items"
.import "ingame/inventory_rolling_trampolines"


.include "config.i"
.if TREASURE_INVENTORY_ROLLING {
; List draw on entry.
    .alloc at 0x01BEA6 {
    jsr.w equip_init
    }


; Cursor sprite X. Vanilla picks one of two columns from ($54)
;   BEC0 B2 54     lda ($54)
;   BEC2 F0 02     beq +
;   BEC4 A9 68     lda #$68
;   BEC6 69 08   + adc #$08
; and single-column rows have one, flush left of the item icon.
    .alloc at 0x01BEC0 {
    lda #EQUIP_LIST_CURSOR_X
    pad_nop(6)
    }


; Cursor sprite Y base (`adc #$76` at $01:BEBC): vanilla's names sat on
; the slot's top tile row, VWF rows draw them on the bottom one.
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


; Scroll up. Vanilla's loop moves $99 2px per frame for the 8 frames
; counted down in A, calling $94A1 to push the scroll shadow:
;   BF03 A9 08     lda #$08
;   BF05 C2 20     rep #$20
;   BF07 C6 99     dec $99
;   BF09 C6 99     dec $99
;   BF0B E2 20     sep #$20
;   BF0D 20 A1 94  jsr $94a1
;   BF10 3A        dec
;   BF11 D0 F2     bne $bf05
    .alloc at 0x01BF03 {
    jsr.w equip_scroll_up
    pad_nop(13)
    }


; Scroll-down bound on the first visible row (vanilla: $13 for 24
; two-item rows).
    .alloc at 0x01BF2D {
    .db EQUIP_LIST_SCROLL_LIMIT
    }


; Scroll down, the same shape with `inc $99`.
    .alloc at 0x01BF32 {
    jsr.w equip_scroll_down
    pad_nop(13)
    }


; Item index on A. Vanilla: ((row + scroll) * 2 + col) * 2
;   BF5A 0A        asl
;   BF5B 72 54     adc ($54)
;   BF5D 0A        asl
; One column: (row + scroll) * 2. `clc` keeps the add carry-free, and
; the column byte may still hold a 1 from a vanilla save.
    .alloc at 0x01BF5A {
    clc
    adc #0x00
    }


; Teardown: both ways out of the list return here before BG4 clears.
    .alloc at 0x01BE70 {
    jsr.w equip_leave
    }
}
