
PointeurBank1de1:
    REP #0x20
    LDA.L assets_bank1_1_ptr,X
    STA.B dialog_ptr
    LDA.W #0x0000
    SEP #0x20
    LDA.L assets_bank1_1_ptr + 2,X
    STA.B dialog_ptr + 2
    LDA.B #0x01
    RTL
; the bank 1 of 1 is only 0x100 pointers long and not 0x200 as the text dump suggests.
PointeurBank1de2:
    REP #0x20
    LDA.L assets_bank1_1_ptr + 0x300, X
    STA.B dialog_ptr
    LDA.W #0x0000
    SEP #0x20
    LDA.L assets_bank1_1_ptr + 0x300 + 2,X
    STA.B dialog_ptr + 2
    LDA #0x01
    RTL

; genuinely false
PointeurBank3:
    REP #0x20
    LDA.L dialog_bank_ptr_base + 0x600,X
    STA.B dialog_ptr
    LDA.W #0x0000
    SEP #0x20
    LDA.L dialog_bank_ptr_base + 0x600 + 2,X
    STA.B dialog_ptr + 2
    LDA #0x02
    RTL

CalculePositionTb:
    LDA.B 0xB2
    STA.B dialog_ptr
    STZ.B dialog_ptr + 1
    REP #0x20
    LDA.B dialog_ptr
    CLC
    ASL
    ADC.B dialog_ptr
    TAX
    SEP #0x20
    RTL
PointeurBank2:
{
    REP #0x20
    LDA.B dialog_ptr
    ASL
    CLC
    ADC.B dialog_ptr
    TAX
    LDA.L assets_bank2_ptr,X
    STA.B dialog_ptr
    LDA.W #0x0000
    SEP #0x20
    LDA.L assets_bank2_ptr + 2,X
    STA.B dialog_ptr + 2
    LDX.B dialog_ptr
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
    LDX.B dialog_ptr
    DEX
    BMI _OkBk2
    DEC.B dialog_ptr + 2
    LDX.W #0xFFFF
    BRA _OkBk2
    ChargeLettreIncBk2:
    LDX.B dialog_ptr
    INX
    BMI _OkBk2
    INC.B dialog_ptr + 2
    LDX.W #0x8000
_OkBk2:
    STX.B dialog_ptr
    ChargeLettreBk2:
    LDX.B dialog_ptr
    PHB
    LDA.B dialog_ptr + 2
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
    INC.B dialog_ptr + 2
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
    INC.B dialog_ptr + 2
    LDX.W #0x8000
    no_overflow:
    STX.W 0x0772
}
ChargeLettre:

    LDX.W 0x0772
    PHB
    LDA.B dialog_ptr + 2
    PHA
    PLB
    LDA.B #0x00
    XBA
    LDA.B #0x00
    rep #0x20

    .if 1 {
        LDA.W 0x0000,X
        STA.B CURRENT_C
    } else {
        STZ.B CURRENT_C
    }

    sep #0x20
    PLB
    PHA
    PLA

    RTS
