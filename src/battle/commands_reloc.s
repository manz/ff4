"""
Relocated battle-command-list renderer (`draw_command_list_for_character`) plus its private command-build
loop, called by the patched bank-$02 hook.
"""
.extern messages_vwf
.extern messages_vwf.init_commands_list
.extern _draw_text_battle_far
.extern assets_battle_commands_nul_ptr
.extern assets_battle_commands_nul_dat
.extern command_buffer_ptr

mult8_far := 0x2855c

.if BATTLE_CMD_VWF {
    command_length = 6
} else {
    command_length = 10
}

draw_command_list_for_character:
"""Public RTL entry: render the per-character battle command list for the active character."""
    ; Skip command rendering if inventory is active (bit 2 of $4A)
    ; This prevents format buffer ($74FD) conflicts with inventory code
    lda.l 0x7E004A
    and #0x04
    bne _skip_commands

    lda 0x1822  ; selected character slot
    sta 0x1816
    phx
    jsr.w _draw_command_list_for_character
    plx

_skip_commands:
    rtl

_draw_command_list_for_character:
{
    stz.w 0x1817
    ldy #0x74FD  ; keep the pointer in Y this will allow to run _draw_single_command multiple times
; to build {tile_flag}cmd1\n{tile_flag}cmd2\n{tile_flag}cmd3\n{tile_flag}cmd4\n{tile_flag}cmd5\0
; to issue a single draw text call to the command list region.
    lda 0x1817  ; battle command slot
    sta 0x26
    lda.b #command_length * 2
    sta 0x28
    jsr.l mult8_far  ; command_id * (command_length * 2)


    lda 0x1817  ; slot ID
    asl
    asl
    tax
    stx 0x00

;lda     0x1816       ; character id
;asl
;tax

;rep #0x20
;ldx.w #command_buffer_ptr - 10
;lda.l     0x16fead,x ;cmd_text_buf_ptrs,x
;stx     0xef52 ; destination ptr ?

_loop:
    tdc
    lda 0x1817  ; slot ID
    asl
    asl
    tax
    stx 0x00

    lda 0x1816  ; character id

    rep #0x20
    asl
    tax
    lda.l 0x16feb7, x
    clc
    adc.b 0x00
    tax
    sep #0x20

    jsr.w _draw_single_command
    inc 0x1817
    lda 0x1817
    cmp #5
    beq _exit
    lda #1
    sta.w 0x0000, y
    iny
    bra _loop
_exit:

    tdc
    sta.w 0x0000, y

    sta 0xef55

    ldx.w #command_buffer_ptr
    stx 0xef52  ; destination

    rep #0x20

; Fill the window with 0x00ff before rendering
    lda.w #command_length * 4 * 5
    sta 0x00

_clear_buffer_loop:
    lda.w #0x00ff
    sta.l 0x7e0000 + command_length * 4 * 5, x
    dex
    dex
    dec 0
    bne _clear_buffer_loop

    sep #0x20

    ldx #0x74fd  ; text buffer
    stx 0xef50
    lda.b #command_length  ; draw text line length used for newline
    sta 0xef54

    jsr.l messages_vwf.init_commands_list
    jsr.l _draw_text_battle_far
    rts
}

_draw_single_command:
{
    tdc
    sep #0x20
    lda.w 0x0001, x  ; 0x3303

    cmp #0xff
    bne _continue
    bra _exit
_continue:
    asl
    tax
    tdc
    lda.l assets_battle_commands_nul_ptr, x
    tax

    lda #0x00  ; white text
    and #0x80
    beq _active_command
    lda #0x04  ; gray text

_active_command:
    sta.w 0x0001, y
    lda #0x0e  ; change tile flags
    sta.w 0x0000, y
    iny
    iny

_battle_command_loop:
    {
_loop:
    lda.l assets_battle_commands_nul_dat, x
    cmp #0
    beq _exit_command_loop
    sta.w 0x0000, y

    inx
    iny
    bra _loop
    }

_exit_command_loop:
_pad_loop:


_exit:
    rts
}
