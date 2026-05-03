.extern load_monster_pointer
.extern initialize_monster_slot
.extern tab_escape_code

; transform the monster names loading routine from fixed size to pointed.

*=0x02a7d7
{
    jsr.l load_monster_pointer

_loop:
    lda.l assets_monsters_long_dat, x
    beq _exit
    jsr.w 0xA497
; draw text
; jsr.w msg_monster_window_trampoline
    inx
    bra _loop

_exit:
    rts

_end:
    .debug '{_end} < 0x02A7F0 ?'
}


*=0x02a7c2
    jsr.l initialize_monster_slot
    rts

; escape code 0x05 tab followed by a number of chars

*=0x02A6B3
    jsr.l tab_escape_code
    nop

; dec 0
    nop
    nop
    ; bne a6b3
    nop
    nop
