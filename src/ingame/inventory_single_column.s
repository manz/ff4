"""
Single-column inventory: the vanilla 2-column item list becomes one column of 10 visible rows over 48 items, with
left/right column handling removed. The rolling buffer does the rendering.
"""
.import "core/preamble"
.import "ingame/free_space"

VISIBLE_ITEMS := 10
SCROLL_LIMIT := 38  ; 48 - 10

; DrawInventoryList item count (`lda #$30` operand): 10 visible + 1 pre-render.
.alloc at 0x01A17E {
    .db VISIBLE_ITEMS + 1
}
; DrawItemSlot `and #$01 / bne @a223`: never take the right-column branch.
.alloc at 0x01A1EF {
    and #0x00
}
; $01:A1BC is covered by the slot hook at $01:A1BA (inventory_rolling_patches.s).
; $01:A077 (scroll limit) is covered by the scroll hook at $01:A076 (inventory_rolling_patches.s).
; Cursor column: always 0 (replaces `lda $1B22 / beq / lda #$6c`).
.alloc at 0x01A114 {
    lda #0x00
    nop
    nop
    nop
    nop
    nop
}
; $01:9FF4 (left button) is covered by the main loop hook at $01:9FF2 (inventory_rolling_patches.s).
; Right button: `and #JOY_RIGHT` never matches.
.alloc at 0x01A005 {
    and #0x00
}
; DrawInventoryList loop: start $5A at the first visible item.
.alloc at 0x01A181 {
    jsr.w adjust_inventory_pointer
    nop
}
; Swap selection: store column 0 in $1B24 (was `lda $1B22`).
.alloc at 0x01A2CD {
    lda #0x00
    nop
}
; Item index = (row + scroll) * 2: the first ASL of `asl / adc col / asl` becomes CLC. It must be CLC, not NOP:
; the preceding CMP leaves carry set and the ADC would add 1.
; Current item
.alloc at 0x01A398 {
    clc
}
; Swap target
.alloc at 0x01A3A6 {
    clc
}
; Same item selected twice (use)
.alloc at 0x01A320 {
    clc
}
; DrawItemDesc index: drop the first ASL.
.alloc at 0x01A7CF {
    nop
}
; $1B22 (cursor column) is cleared on entry by menu_entry_hook_impl (inventory_rolling.s).
