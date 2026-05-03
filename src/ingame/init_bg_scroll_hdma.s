init_bg_scroll_hdma:
"""Init BG Scroll HDMA — relocated from $01:EBD2."""
    tdc
    tax

_ebd4:
    lda 0x0DFF29, x  ; load bg scroll hdma tables
    sta 0x75FD, x
    inx
    cpx.w #0x0015
    bne _ebd4
    tdc
    tax

_EBE3:
    sta 0x7612, x  ; clear hdma data
    inx
    cpx #0x1620
    bne _EBE3
    tdc
    tax
    lda #0xFE

_EBF0:
    sta 0x7D14, x  ; bg3 v-scroll
    dec
    inx
    inx
    inx
    inx
    cpx #0x0380
    bne _EBF0
    ldx #0x0230

_EC00:
    lda 0x7D14, x
    dec
    sta 0x7994, x  ; bg2 v-scroll
    inx
    inx
    inx
    inx
    cpx #0x0280
    bne _EC00
    rep #0x20
    tdc
    tax
    lda #0x0173
    ldy.w #0x0008

_EC1A:
    sta 0x8094, x
    pha
    clc
    adc.w #0x0068
    sta 0x8314, x
    clc
    adc.w #0x00F0
    sta 0x8AF4, x
    pla
    dey
    bne _EC37
    clc
    adc.w #0x0004
    ldy.w #0x000C

_EC37:
    cpx #0x0110
    bne _EC40
    clc
    adc.w #0x0004

_EC40:
    inx
    inx
    inx
    inx
    cpx #0x0130
    bne _EC1A
    tdc
    tax
    lda #0x016F
    ldy.w #0x0008

_EC51:
    inc 0x81D3, x
    sta 0x81D4, x
    dey
    bne _EC61
    clc
    adc.w #0x0004
    ldy.w #0x000C

_EC61:
    cpx #0x0110
    bne _EC6A
    clc
    adc #0x0134

_EC6A:
    inx
    inx
    inx
    inx
    cpx #0x0130
    bne _EC51
    tdc
    tax
    lda.w #0x006B
    ldy.w #0x0008

_EC7B:
    sta 0x8454, x
    dey
    bne _EC88
    clc
    adc.w #0x0004
    ldy.w #0x000C

_EC88:
    cpx.w #0x0088
    bne _EC91
    clc
    adc.w #0x0004

_EC91:
    inx
    inx
    inx
    inx
    cpx.w #0x00A0
    bne _EC7B
    tdc
    tax

_EC9C:
    lda 0x8072, x
    sta 0x81C2, x
    sta 0x8442, x
    inx
    inx
    cpx.w #0x0010
    bne _EC9C
    tdc
    tax

_ECAE:
    lda #0x0101
    sta 0x84F2, x
    inx
    inx
    inx
    inx
    cpx #0x0100
    bne _ECAE
    tdc
    tax
    lda.w #0x0053
    ldy.w #0x0008

_ECC5:
    sta 0x85F4, x
    sta 0x8874, x
    pha
    sec
    sbc.w #0x000C
    sta 0x8674, x
    sta 0x88F4, x
    sec
    sbc.w #0x000C
    sta 0x86F4, x
    sta 0x8974, x
    sec
    sbc.w #0x000C
    sta 0x8774, x
    sta 0x89F4, x
    sec
    sbc.w #0x000C
    sta 0x87F4, x
    sta 0x8A74, x
    pla
    dey
    bne _ECFC
    clc
    adc.w #0x0004

_ECFC:
    pha
    lda.w #0x00AC
    sta 0x8872, x
    sta 0x88F2, x
    sta 0x8972, x
    sta 0x89F2, x
    sta 0x8A72, x
    lda #0x01BC
    sta 0x85F2, x
    sta 0x8672, x
    sta 0x86F2, x
    sta 0x8772, x
    sta 0x87F2, x
    pla
    inx
    inx
    inx
    inx
    cpx.w #0x0070
    bne _ECC5
    ldx.w #0x001C
    ldy.w #0x0004
    lda #0x0134

_ED34:
    sta 0x7D14, x
    dey
    bne _ED3E
    clc
    adc.w #0x0004

_ED3E:
    inx
    inx
    inx
    inx
    cpx.w #0x0080
    bne _ED34
    tdc
    tax

_ED49:
    lda #0x0100
    sta 0x8C32, x
    lda #0x0160
    sta 0x8C34, x
    inx
    inx
    inx
    inx
    cpx.w #0x0080
    bne _ED49
    tdc
    sep #0x20
    rtl
