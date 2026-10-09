"""
Battle monster names (TextCmd_0C) from their baked tiles, the slot blanked first.
"""
.import "assets"
.import "battle/monsters_reloc"
.import "battle/message"
.import "vanilla"


; transform the monster names loading routine from fixed size to pointed.

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
