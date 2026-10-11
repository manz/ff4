"""
Battle monster names (TextCmd_0C) from their baked tiles, the slot blanked first.
"""
.import "assets"
.import "battle/monsters_reloc"
.import "battle/message"
.import "vanilla"
.include "config.i"


.if BATTLE_ENABLED {
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
; DrawMonsterNames' format ($16:FF63, 4 lines of name, gap, count, newline): a thin gap (THIN_SPACE: blank,
; no width of its own, katsuji.toml) instead of the space fits the long names with their count.
    THIN_SPACE := 0x10
    .for entry := 0, 3 {
    .alloc at 0x16FF63 + entry * 6 + 2 size 1 {
    .db THIN_SPACE
    }
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
}
