"""
Battle graphics asset patches: MISS sprite glyphs, defend/row text overrides and other small tile fixups that
piggyback on `defend_row` data.
"""
.import "core/assets"
.import "battle/graphics"
.include "battle_labels.i"  ; build/gen: utils/battle_labels.py
.include "strings.i"  ; src/lang/<lang>


; MISS sprite graphics

.alloc at 0x0cfc60 {
    .incbin "fonts/miss.bin"
}
.alloc at 0x16fb87 {
    {
; chars copied from the font to the battle 4bpp tileset
        .table "text/ff4_menus.tbl"
        .db 0x76, 0x77
        .text "/"
        battle_label_font_codes()  ; Garde, Rang and Coût PM, pre-rendered in the small VWF
        .db 0x8c, 0x90, 0x7f
        .db 0x80, 0x81, 0x82
        .db 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x16, 0x17, 0x18, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff
    }
}
.alloc at 0x02975d {
; the MP cost window's label
    battle_label_mp_cost()
}
; Defend / Row window content
.alloc at 0x29a90 {
; the Row label's first cell: vanilla's, its window back at vanilla's x
    ldx.w #0xd61c
}
.alloc at 0x29a8b {
    ldx.w #0xd5e8
}
.alloc at 0x029a98 {
    lda.l defend_row.defend_text, x
}
.alloc at 0x029a9e {
    lda.l defend_row.row_text, x
}
.alloc at 0x029aa7 {
    cpx.w #defend_row.defend_row_length * 2
}
.alloc at 0x029aac {
    cpx.w #defend_row.defend_row_length
}
.alloc at 0x02b96a {
    lda.b #0x0c
}
.alloc at 0x16fe5a + 6 * 8 {
; defend window: 3 cells inside, Garde's baked tiles (vanilla 6 wide, 4 inside)
    .db 0x00, 0x09, 0x05, 0x04
}
.alloc at 0x16fe5a + 6 * 9 {
; row window: 3 cells inside, Rang's baked tiles; vanilla's x, right of the hand cursor
    .db 0x1A, 0x09, 0x05, 0x04
}
; Hands text (layout: tfr_equip_window_new, equip_window.s)
.alloc at 0x16fed5 {
    {
        .table "text/ff4_menus.tbl"
hand_text:
        hand_texts()
    }
}
.alloc at 0x02A51C {
    lda.l battle_statuses, x
    sta.b 0x00
    lda.l battle_statuses + 1, x
    sta.b 0x01
    lda.b #battle_statuses >> 16
}
