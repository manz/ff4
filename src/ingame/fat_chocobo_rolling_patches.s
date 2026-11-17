"""
Fat Chocobo's lists (`Déposer` / `Retirer`, $01:CEAB) on their rolling buffer: ring init in place of both list
draws, engine scrolls in place of the blocking loops, single-column cursor and index math
(src/ingame/fat_chocobo_rolling.s).
"""


.include "core/libmz.i"
.import "core/items"
.import "ingame/fat_chocobo_rolling"

_FAT_BAG_SCROLL_LIMIT := FAT_CHOCOBO_BAG_ITEMS - FAT_CHOCOBO_LIST_VISIBLE_ROWS
_FAT_STORED_SCROLL_LIMIT := FAT_CHOCOBO_STORED_ITEMS - FAT_CHOCOBO_LIST_VISIBLE_ROWS


; The bag's draw, on opening `Déposer` and after a deposit.
.alloc at 0x01CE90 {
    jsr.w fat_chocobo_init
}


.alloc at 0x01D014 {
    jsr.w fat_chocobo_init
}


; His slots' draw ($01:D052, on opening `Retirer` and after taking one back): the ring takes the `$1340` draw...
.alloc at 0x01D058 {
    jsr.w fat_chocobo_init
}


; ...and vanilla's row streaming from its BG2 strip into BG4 goes: it would write over the ring.
.alloc at 0x01D05B {
    pad_nop(4)
}


; The same streaming on every cursor draw ($01:CF7F).
.alloc at 0x01CFA1 {
    pad_nop(4)
}


; The last scroll position, $E2: one column of 48 / 126 rows, 7 on screen (vanilla's 2-column $11 / $38). $E2
; also tells the lists apart at A ($01:CED6).
.alloc at 0x01CE94 {
    .db _FAT_BAG_SCROLL_LIMIT
}


.alloc at 0x01CED7 {
    .db _FAT_BAG_SCROLL_LIMIT
}


.alloc at 0x01D075 {
    .db _FAT_STORED_SCROLL_LIMIT
}


; Kill the RIGHT / LEFT column toggles (`and #$01` / `and #$02`).
.alloc at 0x01CEE5 {
    .db 0x00
}


.alloc at 0x01CEF8 {
    .db 0x00
}


; Cursor X: always the first column's (`beq` past the second column's `lda #$78` becomes `bra`).
.alloc at 0x01CF8E {
    .db 0x80
}


; Item index (scroll + row) * 2, the `adc $1BB1 / asl` of the second column gone.
.alloc at 0x01CFAE {
    pad_nop(4)
}


; Scroll up: replaces the 24-byte loop moving $99 2 px x 8 frames (with the cursor redrawn each frame), then
; branches past the rest to vanilla's `jsr $82C0` at $01:CF33. The 18 bytes left feed fat_chocobo_slack.
.alloc at 0x01CF1B {
    jsl fat_chocobo_scroll_up_impl
    .db 0x80, 0x01CF33 - 0x01CF21  ; bra $CF33
}


; Scroll down, same with `inc $99`, on to $01:CF6F.
.alloc at 0x01CF57 {
    jsl fat_chocobo_scroll_down_impl
    .db 0x80, 0x01CF6F - 0x01CF5D  ; bra $CF6F
}


; The screen IRQ's BG4VOFS write at line $58: skipped while HDMA drives BG4VOFS. On to $01:CE7B.
.alloc at 0x01CE6A {
    jsl fat_chocobo_irq_scroll
    .db 0x80, 0x01CE7B - 0x01CE70  ; bra $CE7B
}


; What those three hooks left of vanilla's code, never reached: the bank-$01 trampolines below.
.pool fat_chocobo_slack {
    range 0x01CF21 0x01CF32
    range 0x01CF5D 0x01CF6E
    range 0x01CE70 0x01CE7A
    strategy order
}


; Leaving the screen (B on the `Déposer` / `Retirer` choice): disarm ch5 on the way out.
.alloc at 0x01CDDF {
    jsr.w fat_chocobo_exit_check
    pad_nop(4)
}


; Bank-$01 trampolines (`jsr.l` + `rts`) into the bank-$20 code: the bank01 pools are full.
.alloc _fat_chocobo_init_trampoline in fat_chocobo_slack {
fat_chocobo_init:
"""Trampoline to `fat_chocobo_init_impl` (replaces either Fat Chocobo list draw)."""
    jsr.l fat_chocobo_init_impl
    rts

}


.alloc _fat_chocobo_exit_trampoline in fat_chocobo_slack {
fat_chocobo_exit_check:
"""
Vanilla's `lda $01 / and #$80 / beq / rts` at $01:CDDF: on B, disarms ch5 and returns from the screen itself (the
caller's return address dropped), else carries on.
"""


    lda.b 0x01
    and #0x80
    beq _fat_chocobo_stay
    jsr.l fat_chocobo_disable_hdma
    pla
    pla

_fat_chocobo_stay:
    rts
}
