sram_base = 0x707000
.macro long_sram_store(src) {
    phy
    phx

    php
    rep #0x20
    pha
    tya
    clc
    adc.b src
    tax
    pla
    sep #0x20
    plp
    sta.l sram_base, x

    plx
    ply
}

BATTLE_FLAGS = 0x7FFFFF
.macro battle_flags_set(value) {
    lda.b #value
    ora.l BATTLE_FLAGS
    sta.l BATTLE_FLAGS
}

.macro battle_flags_clear(value) {
    lda.b #value
    eor.l BATTLE_FLAGS
    sta.l BATTLE_FLAGS
}

.macro battle_flags_test(value) {
    pha
    lda.l BATTLE_FLAGS
    and #value
    pla
}

.macro battle_flag_switch(jump_table) {
    pha
    phx
    lda.l BATTLE_FLAGS
    asl
    tax
    lda.l jump_table, x
    sta 0x04
    lda.l jump_table + 1, x
    sta 0x05
;    sep #0x20
    plx
    pla
    jmp.w (0x0004)
}
