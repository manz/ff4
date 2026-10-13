"""
Battle item names from `items_unleashed` (symbol, name, $00 per item, `items_unleashed_ptrs` offsets): every
`lda #9 / sta $28 / jsr Mult8` becomes the offset lookup, every name copy a NUL-aware fetch padding with spaces to its
fixed count.
The equip and inventory lists' vanilla fills keep 11 cells (their buffers' width): the popup and the rolling list draw
the names again in the VWF.
"""
.import "core/items"
.import "core/bank20_helpers"

.import "core/assets"
.import "battle/equip_window"

; Each patch notes the vanilla instruction it replaces.

.include "core/bank20.i"

; btlgfx/menu, location 1
.alloc at 0x029E1A {
    jsr.l battle_item_mult8  ; lda #9 / sta $28 / jsr Mult8: the name's offset into $2A
    nop
    nop
    nop
}
; symbol, was lda $0F8000,x
.alloc at 0x029E44 {
    lda.l items_unleashed, x
}
; loop counter, was lda #$08
.alloc at 0x029E58 {
    lda #ITEM_NAME_TEXT_SIZE
}
; name after the symbol, was lda $0F8001,x
.alloc at 0x029E5C {
    jsr.l battle_item_char_after_symbol
}

; btlgfx/menu, location 2
.alloc at 0x029FEF {
    jsr.l battle_item_mult8  ; lda #9 / sta $28 / jsr Mult8: the name's offset into $2A
    nop
    nop
    nop
}
; symbol, was lda $0F8000,x
.alloc at 0x02A00C {
    lda.l items_unleashed, x
}
; loop counter, was lda #$08
.alloc at 0x02A020 {
    lda #ITEM_NAME_TEXT_SIZE
}
; name after the symbol, was lda $0F8001,x
.alloc at 0x02A024 {
    jsr.l battle_item_char_after_symbol
}

; TextVar_03: battle message item name
.alloc at 0x02A594 {
    jsr.l battle_item_mult8  ; lda #9 / sta $28 / jsr Mult8: the name's offset into $2A
    nop
    nop
    nop
}
; loop counter, was lda #$08
.alloc at 0x02A5A1 {
    lda #ITEM_UNLEASHED_TEXT_SIZE
}
; name, was lda $0F8000,x
.alloc at 0x02A5A5 {
    jsr.l battle_item_char  ; $FF past the end: TextVar_03's cmp #$FF stops there
}

; btlgfx item display
.alloc at 0x02CB77 {
    jsr.l battle_item_mult8  ; lda #9 / sta $28 / jsr Mult8: the name's offset into $2A
    nop
    nop
    nop
}
; name, was lda $0F8000,x
.alloc at 0x02CB83 {
    jsr.l battle_item_char
}
; loop counter, was cpy #$0008
.alloc at 0x02CB8C {
    cpy #ITEM_UNLEASHED_TEXT_SIZE
}

; Equipped items record width, was lda #$09 (x3)
.alloc at 0x02AB47 {
    lda #ITEM_NAME_RECORD_SIZE
}
.alloc at 0x02B442 {
    lda #ITEM_NAME_RECORD_SIZE
}
.alloc at 0x02B698 {
    lda #ITEM_NAME_RECORD_SIZE
}

; Inventory buffer stride: 48 to 60 bytes/item (12 to 15 tiles/row), into the freed magic buffer at $97A6+.
; DrawInventoryItemText stride, was lda #$30
.alloc at 0x029FAF {
    lda #0x3c  ; 60 bytes per item instead of 48
}
; DrawInventoryItemText line length, was lda #$0C
.alloc at 0x029FC4 {
    lda #0x0f  ; 15 tiles per line instead of 12
}
; TfrInventoryList: battle/inventory_rolling_patches.s replaces it.


; UpdateEnabledItems, using item: tile count (was lda #$0C)
.alloc at 0x029F2B {
    lda #0x0f  ; 15 tiles instead of 12
}
; row 2 attribute offset, was sta $8EBF,y
.alloc at 0x029F47 {
    sta.w 0x8EC5, y  ; 0x8EA7 + 0x1E = 0x8EC5
}
; Y stride, was adc #$0018
.alloc at 0x029F54 {
    adc #0x001e  ; advance 30 bytes instead of 24
}

; UpdateEnabledItems, throw: tile count (was lda #$0C)
.alloc at 0x029F68 {
    lda #0x0f  ; 15 tiles instead of 12
}
; row 2 attribute offset, was sta $8EBF,y
.alloc at 0x029F86 {
    sta.w 0x8EC5, y
}
; Y stride, was adc #$0018
.alloc at 0x029F93 {
    adc #0x001e  ; advance 30 bytes instead of 24
}
; MenuWindowTbl entry 5 (inventory), x, y, width, height; was $01, $00, $1E, $33
.alloc at 0x16FE78 {
    .db 0x00, 0x00, 0x20, 0x0F  ; x=0, y=0, width=32, height=15 (6 items × 2 + 3 border)
}

; Hand cursor X, unchanged (left=12px, right=124px)
.alloc at 0x16FC59 {
    .db 0x0C, 0x7C  ; Keep original positions (left=12px, right=124px)
}
; Scroll arrow sprites (X, Y, tile, attr)
.alloc at 0x16FC3C {
    .db 0xec + 10, 0x90, 0x4f, 0xb1  ; up arrow 1 (X was 0xec)
    .db 0xec + 10, 0x98, 0x4e, 0xb1  ; up arrow 2
    .db 0xec + 10, 0xcc, 0x4e, 0x31  ; down arrow 1
    .db 0xec + 10, 0xd4, 0x4f, 0x31  ; down arrow 2
}
; The up arrows (sprites 6-7, 16x16) hide by their x bit 8: at our x of $F6 that parks them at -10, their right six
; columns on screen left of the monster window. The hide path also drops them below the screen; the table copy puts
; their y back every frame.
.alloc at 0x02BAE7 size 7 {
    jsr.l park_up_scroll_arrows
    bra _arrows_parked  ; $BAF6, the down arrows
    nop
}
.label _arrows_parked = 0x02BAF6

.alloc _park_up_scroll_arrows in bank20_reloc {
park_up_scroll_arrows:
"""Vanilla's hide (x bit 8 of sprites 6-7) and their y off screen. M = 8."""
    lda.l battle_oam_high + 1
    ora.b #0x50
    sta.l battle_oam_high + 1
    lda.b #0xF0
    sta.l battle_oam_scroll_arrows + 1
    sta.l battle_oam_scroll_arrows + 4 + 1
    rtl
}

; Single column: skip the left/right handlers (was cmp #$02 / bne $B55A)
.alloc at 0x02B541 {
    .db 0x80, 0x36  ; bra $B579 (skip left/right handlers)
    nop  ; Fill remaining bytes
    nop
}

; Single column: $63 moves 1 per row, so NOP the second dec/inc $63 of each up/down handler.
; up, scroll ($02B500)
.alloc at 0x02B502 {
    nop  ; NOP second DEC $63
    nop
}


; up, no scroll ($02B508)
.alloc at 0x02B50A {
    nop  ; NOP second DEC $63
    nop
}


; down, scroll ($02B530)
.alloc at 0x02B532 {
    nop  ; NOP second INC $63
    nop
}


; down, no scroll ($02B538)
.alloc at 0x02B53A {
    nop  ; NOP second INC $63
    nop
}

; Drop the 8px sprite clipping bands. Window 1 left edge, was lda #$08
.alloc at 0x028A1D {
    lda #0x00  ; left edge at pixel 0
}
; Window 1 right edge, was lda #$F8
.alloc at 0x028A22 {
    lda #0xff  ; right edge at pixel 255
}

; DrawEquipItemText tile count, 12 to 15 (symbol + 11 chars + 3 formatting tiles); was lda #$0C
.alloc at 0x029DD3 {
    lda #0x0f  ; 15 tiles instead of 12
}

; TfrEquipWindow: vanilla body $0297A6..$029824 replaced by the bank-$20 row-by-row routine
.alloc at 0x0297A6 {
    jsr.l tfr_equip_window_new
    rts
}

; EquipHandPtrs, was $00, $30
.alloc at 0x029D67 {
    .db 0x00, 0x3c  ; item 1 at 0, item 2 at 60
}

; EquipTextBufPtrs: 120 bytes per char at $9A00 (freed magic buffer); was $BC86.. stride $60
.alloc at 0x16FEC1 {
    .dw 0x9A00  ; char 0
    .dw 0x9A00 + 0x78  ; char 1 ($9A78)
    .dw 0x9A00 + 0x78 * 2  ; char 2 ($9AF0)
    .dw 0x9A00 + 0x78 * 3  ; char 3 ($9B68)
    .dw 0x9A00 + 0x78 * 4  ; char 4 ($9BE0)
}

; MenuWindowTbl entry 6 (equipped items), x, y, width, height; was $01, $00, $1E, $07
.alloc at 0x16FE7E {
    .db 0x00, 0x00, 0x20, 0x07  ; x=0 (edge), y=0, width=32, height=7
}
