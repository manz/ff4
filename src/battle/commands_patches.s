command_length = 10
command_buffer_ptr = 0x97a6  + 0x601 ; old spell lists buffers
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
    .dw command_buffer_ptr    ; read address
    .dw 0xC1F4 - 4    ; write address
}

{
; ram position of the prebuilt battle windows
*=0x16FEAD
battle_data_size = command_length * 4 * 5
.dw command_buffer_ptr
.dw command_buffer_ptr + battle_data_size
.dw command_buffer_ptr + battle_data_size * 2
.dw command_buffer_ptr + battle_data_size * 3
.dw command_buffer_ptr + battle_data_size * 4

*=0x02999F
     ldx.w #battle_data_size

; Command window
*=0x16fe5a + 6 * 2
    .db 0x04, 0x00 ,command_length + 2, 0x0d
}


