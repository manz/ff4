"""
Battle SRAM layout helpers: long SRAM store macro + battle-flags set/clear/test/switch macros over
`BATTLE_FLAGS` ($704F00).
"""
sram_base = 0x707000
.macro _long_sram_store(src) {
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

BATTLE_FLAGS = 0x704F00
.macro battle_flags_set(value) {
    """OR `value` into the battle-flags byte at BATTLE_FLAGS."""
    lda.b #value
    ora.l BATTLE_FLAGS
    sta.l BATTLE_FLAGS
}

.macro battle_flags_clear(value) {
    """AND `~value` into the battle-flags byte at BATTLE_FLAGS."""
    lda.l BATTLE_FLAGS
    and.b #( ~ value & 0xFF )
    sta.l BATTLE_FLAGS
}

.macro _battle_flags_test(value) {
    pha
    lda.l BATTLE_FLAGS
    and #value
    pla
}

.macro battle_flag_switch(jump_table) {
    """Indirect-jump dispatch on the battle-flags byte."""
    pha
    phx
    lda #0
    xba
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
