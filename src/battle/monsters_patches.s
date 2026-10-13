"""
Battle monster names (TextCmd_0C) from their baked tiles, the slot blanked first.
"""
.import "core/assets"
.import "battle/monsters_reloc"
.import "battle/message"
.import "core/vanilla"
.import "core/wram_layout"


.alloc at 0x02a7d7 {
; TextCmd_0C: the monster name's baked tiles
    jsr.l messages_vwf.draw_monster_name_baked
    rts
}
.alloc at 0x02a7c2 {
    jsr.l initialize_monster_slot
    rts

; escape code 0x05 tab followed by a number of chars
}
; The monster window takes the free tile column on its left (x 1 -> 0, 12 -> 13 wide) and the name window the one
; on its right (18 -> 19 wide). MenuWindowTbl ($16:FE5A): x, y, width,
; height, buffer; entries 0/1 in the command window's buffer, 3/4 in the main window's.
.alloc at 0x16FE5A + 0 * 6 size 3 {
    .db 0x00, 0x00, 0x0D
}
.alloc at 0x16FE5A + 1 * 6 + 2 size 1 {
    .db 0x13
}
.alloc at 0x16FE5A + 3 * 6 size 3 {
    .db 0x00, 0x00, 0x0D
}
.alloc at 0x16FE5A + 4 * 6 + 2 size 1 {
    .db 0x13
}

; Main menu text updates ($16:FE42: bytes a row, rows, source, destination): the monster names from their wider
; buffer into the wider window. HP stays put: the item/spell target window copies it at vanilla's column.
.alloc at 0x16FE42 size 6 {
    .db MONSTER_LINE_CELLS * 2, 8
    .dw monster_names_text & 0xFFFF
    .dw 0xBEA8
}

; Battle menu text buffer data ($16:FF43: text, destination, cells a line, flags): the monster names' buffer.
.alloc at 0x16FF43 + 2 size 3 {
    .dw monster_names_text & 0xFFFF
    .db MONSTER_LINE_CELLS
}

.alloc at 0x02A6B3 {
    jsr.l tab_escape_code
    nop

; dec 0
    nop
    nop
; bne a6b3
    nop
    nop
}
