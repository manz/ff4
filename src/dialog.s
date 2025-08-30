PointeurBank1de1:
    REP #0x20
    LDA.L assets_bank1_1_ptr,X
    STA.B 0x3D
    LDA.W #0x0000
    SEP #0x20
    LDA.L assets_bank1_1_ptr + 2,X
    STA.B 0x3F
    LDA.B #0x01
    RTL
; the bank 1 of 1 is only 0x100 pointers long and not 0x200 as the text dump suggests.
PointeurBank1de2:
    REP #0x20
    LDA.L assets_bank1_1_ptr + 0x300, X
    STA.B 0x3D
    LDA.W #0x0000
    SEP #0x20
    LDA.L assets_bank1_1_ptr + 0x300 + 2,X
    STA.B 0x3F
    LDA #0x01
    RTL

; genuinely false
PointeurBank3:
    REP #0x20
    LDA.L dialog_bank_ptr_base + 0x600,X
    STA.B 0x3D
    LDA.W #0x0000
    SEP #0x20
    LDA.L dialog_bank_ptr_base + 0x600 + 2,X
    STA.B 0x3F
    LDA #0x02
    RTL

CalculePositionTb:
    LDA.B 0xB2
    STA.B 0x3D
    STZ.B 0x3E
    REP #0x20
    LDA.B 0x3D
    CLC
    ASL
    ADC.B 0x3D
    TAX
    SEP #0x20
    RTL
PointeurBank2:
{
    REP #0x20
    LDA.B 0x3D
    ASL
    CLC
    ADC.B 0x3D
    TAX
    LDA.L assets_bank2_ptr,X
    STA.B 0x3D
    LDA.W #0x0000
    SEP #0x20
    LDA.L assets_bank2_ptr + 2,X
    STA.B 0x3F
    LDX.B 0x3D
    LDA.B 0xB2
    BEQ _FinBk2
    TAY
_LoopBk2:
    JSR.W ChargeLettreIncBk2
    BNE _LoopBk2
    JSR.W ChargeLettreDecBk2
    PHA
    JSR.W ChargeLettreIncBk2
    PLA
    CMP #0x03
    BEQ _LoopBk2
    PHA
    PLA
    CMP #0x04
    BEQ _LoopBk2
    CMP #0xfe
    beq _LoopBk2
    DEY
    BNE _LoopBk2
    INX
_FinBk2:
    STX.W 0x0772
    STZ.B 0xDD
    RTL
    ChargeLettreDecBk2:
    LDX.B 0x3D
    DEX
    BMI _OkBk2
    DEC.B 0x3F
    LDX.W #0xFFFF
    BRA _OkBk2
    ChargeLettreIncBk2:
    LDX.B 0x3D
    INX
    BMI _OkBk2
    INC.B 0x3F
    LDX.W #0x8000
_OkBk2:
    STX.B 0x3D
    ChargeLettreBk2:
    LDX.B 0x3D
    PHB
    LDA.B 0x3F
    PHA
    PLB
    LDA.W 0x0000,X
    PLB
    PHA
    PLA
    RTS
}

incpointer:
{
    PHX
    LDX.W 0x0772
    INX
    BNE no_overflow
    INC.B 0x3F
    LDX.W #0x8000
    no_overflow:
    STX.W 0x0772
    PLX
    RTS
}

;=====================================================================
; Fonction de lecture de caractère
;=====================================================================
ChargeLettreInc:
{
    LDX.W 0x0772
    INX
    CPX.W #0x0000
    BNE no_overflow
    INC.B 0x3F
    LDX.W #0x8000
    no_overflow:
    STX.W 0x0772
}
ChargeLettre:
    LDX.W 0x0772
    PHB
    LDA.B 0x3F
    PHA
    PLB
    LDA.B #0x00
    XBA
    LDA.B #0x00
    LDA.W 0x0000,X
    STA.B CURRENT_C
    PLB
    PHA
    PLA
    RTS
