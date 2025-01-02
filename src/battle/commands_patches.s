command_length = 11

; move command cursor on the moved window
*=0x2b990
    lda.b #0x18
{
*=0x029CD6
    lda.b #command_length

*=0x029D15
    lda.b #command_length

*=0x029D42
    cpy.w #command_length + 2

*=0x029D5A
    cpy.w #command_length + 2

*=0x029D39
    lda.l assets_battle_commands_dat, x

*=0x029CE0
    lda.b #command_length * 4

; patches source & length of battle commands used in display attack window.
*=0x02cb49
    lda.b #command_length

*=0x02cb54
    lda.l assets_battle_commands_dat, x

*=0x02cb5d
    cpy.w #command_length

*=0x16FE54
    .db command_length * 2
    .db 0x0a
    .dw 0x8CB2    ; read address
    .dw 0xC1F4 - 4    ; write address
}

{
; ram position of the prebuilt battle windows
*=0x16FEAD
battle_data_size = command_length * 4 * 5
.dw 0x8CB2
.dw 0x8CB2 + battle_data_size
.dw 0x8CB2 + battle_data_size * 2
.dw 0x8CB2 + battle_data_size * 3
.dw 0x8CB2 + battle_data_size * 4

*=0x02999F
     ldx.w #battle_data_size

 ; move items ram location
*=0x029FBB
    battle_items_position = 0x2E00
    adc.w #battle_items_position
}
