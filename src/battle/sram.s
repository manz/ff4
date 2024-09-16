.include 'src/battle/sram.i'

BATTLE_DAKUTEN_TABLE = 0x16FA40

.scope battle_flags {
    set_sram_copy:
        battle_flags_set(0x01)
        rtl

    clear_sram_copy:
        battle_flags_clear(0x01)
        rtl

    set_vwf_render:
        battle_flags_set(0x02)
        rtl

    clear_vwf_render:
        battle_flags_clear(0x02)
        rtl
}

copy_battle_char:
    lda.l sram_base + 0x2E00, x
    sta (0x00),Y
    lda.l sram_base + 0x2E00 + 0x30, x
    sta (0x02),Y
    rtl

.scope wram {
put_char:
    phx
    sta (0x34),Y
    lda #0xFF
    sta (0x32),Y
    iny
    lda 0x36
    sta (0x32),Y
    sta (0x34),Y
    iny
    plx
    rtl

put_char_with_dakuten:
    phx
    sec
    sbc #0xF
    asl
    tax
    lda.l BATTLE_DAKUTEN_TABLE, x
    sta (0x32), y
    lda.l BATTLE_DAKUTEN_TABLE + 1, x
    sta (0x34), y
    iny
    lda 0x36
    sta (0x32), y
    sta (0x34), y
    iny
    plx
    rtl
}

.scope sram {
put_char:
    phx
    long_sram_store(0x34)
    lda #0xFF
    long_sram_store(0x32)
    iny
    lda 0x36
    long_sram_store(0x32)
    long_sram_store(0x34)
    iny
    plx
    rtl

put_char_with_dakuten:
    phx
    sec
    sbc #0x0F
    asl
    tax
    lda.l BATTLE_DAKUTEN_TABLE, x
    long_sram_store(0x32)
    lda.l BATTLE_DAKUTEN_TABLE + 1, x
    long_sram_store(0x34)
    iny
    lda 0x36
    long_sram_store(0x32)
    long_sram_store(0x34)
    iny
    plx
    rtl
}

battle_display_char:
{
    battle_flag_switch(battle_flags_jump_table)
battle_flags_jump_table:
    .dw wram.put_char
    .dw sram.put_char
    .dw messages_vwf.put_fixed_char_dakuten_far
}

battle_display_dakuten_char:
{
    battle_flag_switch(battle_flags_jump_table)
battle_flags_jump_table:
    .dw wram.put_char_with_dakuten
    .dw sram.put_char_with_dakuten
    .dw messages_vwf.put_fixed_char_no_dakuten_far
}

sink:
    rtl


