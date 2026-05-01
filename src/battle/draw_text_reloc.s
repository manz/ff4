.if 1 {
HexToDecVar := 0x2f29c
Mult8_far := 0x2855c
Div16_far := 0x28527

DakutenTbl = 0
StatusNamePtrs = 0
AttackName = 0
MagicName = 0
ItemName = 0
CharNameTbl = 0
MonsterName = 0

CmdDataPtrs = 0x16feb7
BattleCmdName = 0

.macro longa() {
    rep #0x20
}

.macro shorta() {
    sep #0x20
}

.macro shorta0() {
    tdc
    shorta()
}

.macro asl3() {
    asl
    asl
    asl
}

.macro asl7() {
    asl
    asl
    asl
    asl
    asl
    asl
    asl
}

.macro inx5() {
    inx
    inx
    inx
    inx
    inx
}
.macro clr_ax() {
    tdc
    tax
}
.macro clr_ay() {
    tdc
    tay
}

; [ draw text ]

DrawText:
_a455:  lda     0xef55
        sta     0x36
        asl     0xef54
        ldx.w    0xef50
        stx     0x30
        ldx.w    0xef52
        stx     0x32
        lda     0x32
        clc
        adc     0xef54
        sta     0x34
        lda     0x33
        adc     #0x00
        sta     0x35
        ldy.w    #0
_a478:  lda     (0x30) ; for kerning to work great we need to load the next char as well
        beq     _a490       ; branch if terminator
        cmp     #0x0f
        bcc     _a488
        jsr.w DrawLetter
        jsr.w IncTextPtr
        bra     _a478
; escape codes 0x01-0x0e
_a488:  jsr.w ExecTextCmd
        jsr.w IncTextPtr
        bra     _a478
_a490:  rts

; ------------------------------------------------------------------------------

; [ increment text pointer ]

IncTextPtr:
_a491:  ldx.w    0x30
        inx
        stx     0x30
        rts

; ------------------------------------------------------------------------------

; [ draw text character ]

DrawLetter:
_a497:  cmp     #0x42
        bcc     DrawLetterWithDakuten

DrawLetterNoDakuten:
_a49b:  phx
        sta     (0x34),y
        lda     #0xff
        sta     (0x32),y
        iny
        lda     0x36         ; tile flags
        sta     (0x32),y
        sta     (0x34),y
        iny
        plx
        rts

DrawLetterWithDakuten:
_a4ac:  phx
        sec
        sbc     #0x0f
        asl
        tax
        lda.l DakutenTbl,x   ; dakuten
        sta     (0x32),y
        lda.l DakutenTbl+1,x   ; kana
        sta     (0x34),y
        iny
        lda     0x36         ; tile flags
        sta     (0x32),y
        sta     (0x34),y
        iny
        plx
        rts

; ------------------------------------------------------------------------------

; text escape code jump table
TextCmdTbl:
_a4c8:  .dw   TextCmd_00
        .dw   TextCmd_01
        .dw   TextCmd_02
        .dw   TextCmd_03
        .dw   TextCmd_04
        .dw   TextCmd_05
        .dw   TextCmd_06
        .dw   TextCmd_07
        .dw   TextCmd_08
        .dw   TextCmd_09
        .dw   TextCmd_0a
        .dw   TextCmd_0b
        .dw   TextCmd_0c
        .dw   TextCmd_0d
        .dw   TextCmd_0e

; ------------------------------------------------------------------------------

; [ escape code 0x06: variable ]

TextCmd_06:
_a4e6:  jsr.w IncTextPtr
        lda     (0x30)
        bmi     _a4ee
        rts
_a4ee:  and     #0x7f
        bne     _a4f8
        ldx.w    #0x0000
        jmp.w TextVar_00
_a4f8:  cmp     #0x01
        bne     _a502
        ldx.w    #0x0003
        jmp.w TextVar_01
_a502:  cmp     #0x02
        bne     _a509
        jmp.w TextVar_02
_a509:  cmp     #0x03
        bne     _a510
        jmp.w TextVar_03
_a510:  cmp     #0x04
        bne     TextVar_05
        jmp.w TextVar_04

; ------------------------------------------------------------------------------

; [ variable type 5: status name ]

TextVar_05:
_a517:  lda     0x359a
        asl
        tax
        lda.l StatusNamePtrs,x
        sta     0x00
        lda.l StatusNamePtrs+1,x
        sta     0x01
        lda.b     #StatusNamePtrs >> 16
        sta     0x02
_a52c:  lda     [0x00]
        beq     _a53a
        jsr.w DrawLetter
        ldx.w    0x00
        inx
        stx     0x00
        bra     _a52c
_a53a:  rts

; ------------------------------------------------------------------------------

; [ variable type 4: magic name ]

TextVar_04:
_a53b:  lda     0x359a
        cmp     #0x48
        bcc     _a565
        sec
        sbc     #0x48
        sta     0x26
        lda     #0x08
        sta     0x28
        jsr.l Mult8_far
        ldx.w    0x2a
        lda     #0x08
        sta     0x00
_a554:  lda.l AttackName,x
        cmp     #0xff
        beq     _a564
        jsr.w DrawLetter
        inx
        dec     0x00
        bne     _a554
_a564:  rts
_a565:  sta     0x26
        lda     #0x06
        sta     0x28
        jsr.l Mult8_far
        ldy.w    #0
        ldx.w    0x2a
        lda.l MagicName,x
        jsr.w DrawLetterNoDakuten
        lda     #0x05
        sta     0x00
_a57e:  lda.l MagicName+1,x
        cmp     #0xff
        beq     _a58e
        jsr.w DrawLetter
        inx
        dec     0x00
        bne     _a57e
_a58e:  rts

; ------------------------------------------------------------------------------

; [ variable type 3: item name ]

TextVar_03:
_a58f:  lda     0x359a
        sta     0x26
        lda     #0x09
        sta     0x28
        jsr.l Mult8_far
        ldy.w    #0
        ldx.w    0x2a
        inx
        lda     #0x08
        sta     0x00
_a5a5:  lda.l ItemName,x
        cmp     #0xff
        beq     _a5b5
        jsr.w DrawLetter
        inx
        dec     0x00
        bne     _a5a5
_a5b5:  rts

; ------------------------------------------------------------------------------

; [ variable type 2: character name ]

TextVar_02:
_a5b6:  lda     0x359a
        longa()
        asl7()
      
        tax
        shorta0()
        lda     0x2000,x
        dec
        and     #0x3f
        tax
        lda.l CharNameTbl,x   ; name for each character

DrawCharName:
_a5d1:  sta     0x26
        lda     #0x06
        sta     0x28
        jsr.l Mult8_far
        lda     #0x06
        sta     0x00
        ldx.w    0x2a
        inx5()
_a5e5:  lda     0x1500,x
        cmp     #0xff
        bne     _a5f5
        dex
        dec     0x00
        lda     0x00
        cmp     #0x01
        bne     _a5e5
_a5f5:  ldx.w    0x2a
_a5f7:  lda     0x1500,x
        jsr.w DrawLetter
        inx
        dec     0x00
        bne     _a5f7
        rts

; ------------------------------------------------------------------------------

; [ variable type 0/1: battle variable ]

TextVar_00:
TextVar_01:
_a603:  lda     0x359a,x
        sta     0x00
        lda     0x359b,x
        sta     0x01
        lda     0x359c,x
        sta     0x02
        jsr.l HexToDecVar
        jsr.w NormalizeVar
_a619:  lda     0xf4ad,x
        jsr.w DrawLetterNoDakuten
        inx
        cpx.w    #8
        bne     _a619
        rts

; ------------------------------------------------------------------------------

; [ text escape code ]

ExecTextCmd:
_a626:  asl
        tax
        lda.l TextCmdTbl,x
        sta     0x00
        lda.l TextCmdTbl+1,x
        sta     0x01
        jmp.w     (0x0000)

; ------------------------------------------------------------------------------

; [ escape code 0x01: newline ]

TextCmd_01:
    jsr.l messages_vwf.new_line_escape_code_handler
    rts
;_a637:  lda     0xef54
;        longa()
;        pha
;        asl
;        clc
;        adc     0x32
;        sta     0x32
;        pla
;        clc
;        adc     0x32
;        sta     0x34
;        clr_ay()
;        shorta()
;        rts

; ------------------------------------------------------------------------------

; [ escape code 0x00: string terminator (unused) ]

TextCmd_00:
_a64e:  rts

; ------------------------------------------------------------------------------

; [ escape code 0x04: character name (by character id) ]

TextCmd_04:
_a64f:  jsr.w IncTextPtr
        lda     (0x30)
        jmp.w DrawCharName

; ------------------------------------------------------------------------------

; [ escape code 0x02: character name (by slot) ]

TextCmd_02:
_a657:  jsr.w IncTextPtr
        lda     (0x30)

DrawCharSlotName:
_a65c:  pha
        tax
        lda     0x29c5,x
        cmp     #0xff
        bne     _a672
        ldx.w    #0x0006
_a668:  lda     #0xff
        jsr.w DrawLetter
        dex
        bne     _a668
        pla
        rts
_a672:  pla
        longa()
        asl7()
        tax
        shorta0()
        lda     0x2000,x
        dec
        and     #0x3f
        tax
        lda.l CharNameTbl,x   ; name for each character
        sta     0x26
        lda     #0x06
        sta     0x00
        sta     0x28
        jsr.l Mult8_far
        ldx.w    0x2a
_a698:  lda     0x1500,x
        jsr.w DrawLetter
        inx
        dec     0x00
        bne     _a698
        rts

; ------------------------------------------------------------------------------

; [ escape code 0x03: borders and symbols ]

TextCmd_03:
_a6a4:  jsr.w IncTextPtr
        lda     (0x30)
        jmp.w DrawLetterNoDakuten

; ------------------------------------------------------------------------------

; [ escape code 0x05: tab ]

TextCmd_05:
_a6ac:  jsr.w IncTextPtr
        lda     (0x30)
        sta     0x00
_a6b3:  lda     #0xff
        jsr.w DrawLetter
        dec     0x00
        bne     _a6b3
        rts

; ------------------------------------------------------------------------------

; [ escape code 0x07: character 1 variable ]

TextCmd_07:
_a6bd:  ldx.w    #0x0000
        ;clr_a
        tdc
        bra     DrawCharVar

; ------------------------------------------------------------------------------

; [ escape code 0x08: character 2 variable ]

TextCmd_08:
_a6c3:  ldx.w    #0x0080
        lda     #1
        bra     DrawCharVar

; ------------------------------------------------------------------------------

; [ escape code 0x09: character 3 variable ]

TextCmd_09:
_a6ca:  ldx.w    #0x0100
        lda     #2
        bra     DrawCharVar

; ------------------------------------------------------------------------------

; [ escape code 0x0a: character 4 variable ]

TextCmd_0a:
_a6d1:  ldx.w    #0x0180
        lda     #3
        bra     DrawCharVar

; ------------------------------------------------------------------------------

; [ escape code 0x0b: character 5 variable ]

TextCmd_0b:
_a6d8:  ldx.w    #0x0200
        lda     #4
; fallthrough

; ------------------------------------------------------------------------------

; [ draw character variable ]

DrawCharVar:
_a6dd:  stx     0x0a
        pha
        jsr.w IncTextPtr
        lda     (0x30)
        bne     _a6eb
; 0: character name
        pla
        jmp.w DrawCharSlotName
_a6eb:  tax
        pla
        sta     0x03
        txa
        ldx.w    0x0a
; 1: current hp
        cmp     #0x01
        bne     _a6fd
        stz     0x02
        lda     #0x07
        jmp.w DrawHPNum
; 2: max hp
_a6fd:  cmp     #0x02
        bne     _a708
        stz     0x02
        lda     #0x09
        jmp.w DrawHPNum
; 3: current mp
_a708:  cmp     #0x03
        bne     _a715
        lda     #1
        sta     0x02
        lda     #0x0b
        jmp.w DrawMPNum
; 4: max mp
_a715:  cmp     #0x04
        bne     _a722
        lda     #1
        sta     0x02
        lda     #0x0d
        jmp.w DrawMPNum
; 5: invalid (infinite loop)
_a722:  jmp.w _a722

; ------------------------------------------------------------------------------

; [ clear hex to decimal conversion buffer ]

; unused

ClearHexToDecBuf:
_a725:  lda     #0xff
        sta     0x180c
        sta     0x180d
        sta     0x180e
        sta     0x180f
        rts

; ------------------------------------------------------------------------------

; [ draw mp value ]

; 0x02: number of digits to skip (0 for hp, 1 for mp)

DrawMPNum:
_a734:  ldx.w    0x0a
        jsr.w GetStatNumText
        lda     0x02
        tax
_a73c:  lda     0x180c,x
        cmp     #0xff
        beq     _a746
        clc
        adc     #0x6d                    ; 0x6d is "0" on bg2
_a746:  jsr.w DrawLetterNoDakuten
        inx
        cpx.w    #4
        bne     _a73c
        rts

; ------------------------------------------------------------------------------

; [ draw hp value ]

DrawHPNum:
_a750:  ldx.w    0x0a
        jsr.w GetStatNumText
        lda     0x02
        tax
_a758:  lda     0x180c,x
        jsr.w DrawLetterNoDakuten
        inx
        cpx.w    #4
        bne     _a758
        rts

; ------------------------------------------------------------------------------

; [ convert hp or mp value to text ]

GetStatNumText:
_a765:  longa()
        stx     0x00
        clc
        adc     0x00
        tax
        lda     0x2000,x     ; get hp/mp value
        tax
        shorta0()
        jsr.w HexToDec
        jmp.w NormalizeNum

; ------------------------------------------------------------------------------

; [ escape code 0x0e: change tile flags ]

TextCmd_0e:
_a77a:  jsr.w IncTextPtr
        lda     (0x30)
        sta     0x36
        rts

; ------------------------------------------------------------------------------

; [ escape code 0x0d: monster count ]

TextCmd_0d:
_a782:  jsr.w IncTextPtr
        lda     (0x30)
        tax
        lda     0x29ca,x
        beq     _a7a9
        lda     0x29b1,x
        cmp     #0xff
        beq     _a7a6
        lda     0x29ca,x
        tax
        cmp     #0x01
        bne     _a7a0
        lda     #0xff        ; blank if only 1 monster
        bra     _a7a6
_a7a0:  jsr.w HexToDec
        lda     0x1810
_a7a6:  jmp.w DrawLetterNoDakuten
_a7a9:  dec
        jmp.w DrawLetterNoDakuten

; ------------------------------------------------------------------------------

; [ escape code 0x0c: monster name ]

TextCmd_0c:
_a7ad:  jsr.w IncTextPtr
        lda     (0x30)
        tax
        lda     0x29ca,x
        beq     _a7bf
        lda     0x29b1,x
        cmp     #0xff
        bne     _a7cb
_a7bf:  ldx.w    #8

        jsr.l initialize_monster_slot
        rts

;_a7c2:  lda     #0xff
;        jsr.w DrawLetterNoDakuten
;        dex
;        bne     _a7c2
;        rts
_a7cb:  pha
        lda     0x38d0,x
        beq     _a7d6
        pla
        lda     #0xdf
        bra     _a7d7
_a7d6:  pla
_a7d7:
{
jsr.l load_monster_pointer
_loop:
    lda.l assets_monsters_long_dat, x
    beq _exit
    jsr.w 0xA497  ; draw text
    ;jsr.w msg_monster_window_trampoline
    inx
    bra _loop
_exit:
    rts
_end:
    .debug '{_end} < 0x02A7F0 ?'
}
;_a7d7:  longa()
;        asl3()
;        tax
;        shorta0()
;        lda     #8
;        sta     0x00
;_a7e4:  lda.l MonsterName,x
;        jsr.w DrawLetter
;        inx
;        dec     0x00
;        bne     _a7e4
;        rts

; ------------------------------------------------------------------------------

NormalizeVar:
_873b:  ldx.w    #0
_873e:  lda     0xf4ad,x
        cmp     #0x80
        bne     _8750
        lda     #0xff
        sta     0xf4ad,x
        inx
        cpx.w    #7
        bne     _873e
_8750:  rts

HexToDec:
_86bf:  stx     0x26
        ldx.w    #10000
        stx     0x28
        jsr.l Div16_far
        lda     0x2a
        clc
        adc     #0x80
        sta     0x180c
        ldx.w    0x2c
        stx     0x26
        ldx.w    #1000
        stx     0x28
        jsr.l Div16_far
        lda     0x2a
        clc
        adc     #0x80
        sta     0x180d
        ldx.w    0x2c
        stx     0x26
        ldx.w    #100
        stx     0x28
        jsr.l Div16_far
        lda     0x2a
        clc
        adc     #0x80
        sta     0x180e
        ldx.w    0x2c
        stx     0x26
        ldx.w    #10
        stx     0x28
        jsr.l Div16_far
        lda     0x2a
        clc
        adc     #0x80
        sta     0x180f
        lda     0x2c
        clc
        adc     #0x80
        sta     0x1810
        rts
        
NormalizeNum:
_8716:  ldx.w    #0
_8719:  lda     0x180d,x                 ; shift out the top digit
        sta     0x180c,x
        inx
        cpx.w     #5
        bne     _8719
        ldx.w     #0
_8728:  lda     0x180c,x
        cmp     #0x80
        bne     _873a                   ; return if digit is not zero
        lda     #0xff
        sta     0x180c,x                 ; hide digit
        inx
        cpx.w     #3                      ; don't hide ones digit
        bne     _8728
_873a:  rts
}