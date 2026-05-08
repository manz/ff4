"""
Relocated battle text-draw helpers and constants (HexToDec / Mult8 / Div16 trampolines, dakuten + name pointer
table aliases) consumed by the messages-VWF path.
"""
.if 1 {
    hex_to_dec_var := 0x2f29c
    mult8_far := 0x2855c
    div16_far := 0x28527

    dakuten_tbl = 0
    status_name_ptrs = 0
    attack_name = 0
    magic_name = 0
    item_name = 0
    char_name_tbl = 0
    monster_name = 0

    cmd_data_ptrs = 0x16feb7
    battle_cmd_name = 0

    .macro longa() {
    """Switch A to 16-bit (`REP #$20`)."""
    rep #0x20
    }

    .macro shorta() {
    """Switch A to 8-bit (`SEP #$20`)."""
    sep #0x20
    }

    .macro shorta0() {
    """Clear A and switch to 8-bit (TDC then `SEP #$20`)."""
    tdc
    shorta()
    }

    .macro _asl3() {
    asl
    asl
    asl
    }

    .macro _asl7() {
    asl
    asl
    asl
    asl
    asl
    asl
    asl
    }

    .macro _inx5() {
    inx
    inx
    inx
    inx
    inx
    }
    .macro _clr_ax() {
    tdc
    tax
    }
    .macro _clr_ay() {
    tdc
    tay
    }

; [ draw text ]

draw_text:


"""
Relocated `draw_text` ($02A455): consume the dialog stream and dispatch through the text command + variable
tables.
"""


_a455:
    lda 0xef55
    sta 0x36
    asl 0xef54
    ldx.w 0xef50
    stx 0x30
    ldx.w 0xef52
    stx 0x32
    lda 0x32
    clc
    adc 0xef54
    sta 0x34
    lda 0x33
    adc #0x00
    sta 0x35
    ldy.w #0
_a478:
    lda (0x30)  ; for kerning to work great we need to load the next char as well
    beq _a490  ; branch if terminator
    cmp #0x0f
    bcc _a488
    jsr.w draw_letter
    jsr.w _inc_text_ptr
    bra _a478
_a488:
"""escape codes 0x01-0x0e"""
    jsr.w _exec_text_cmd
    jsr.w _inc_text_ptr
    bra _a478
_a490:
    rts

; ------------------------------------------------------------------------------

; [ increment text pointer ]

_inc_text_ptr:
_a491:
    ldx.w 0x30
    inx
    stx 0x30
    rts

; ------------------------------------------------------------------------------

; [ draw text character ]

draw_letter:
"""Render the letter currently in A through the text-stream blit path."""
_a497:
    cmp #0x42
    bcc _draw_letter_with_dakuten

_draw_letter_no_dakuten:
_a49b:
    phx
    sta (0x34), y
    lda #0xff
    sta (0x32), y
    iny
    lda 0x36  ; tile flags
    sta (0x32), y
    sta (0x34), y
    iny
    plx
    rts

_draw_letter_with_dakuten:
_a4ac:
    phx
    sec
    sbc #0x0f
    asl
    tax
    lda.l dakuten_tbl, x  ; dakuten
    sta (0x32), y
    lda.l dakuten_tbl + 1, x  ; kana
    sta (0x34), y
    iny
    lda 0x36  ; tile flags
    sta (0x32), y
    sta (0x34), y
    iny
    plx
    rts

; ------------------------------------------------------------------------------

text_cmd_tbl:
"""text escape code jump table"""
_a4c8:
    .dw _text_cmd_00
    .dw _text_cmd_01
    .dw _text_cmd_02
    .dw _text_cmd_03
    .dw _text_cmd_04
    .dw _text_cmd_05
    .dw _text_cmd_06
    .dw _text_cmd_07
    .dw _text_cmd_08
    .dw _text_cmd_09
    .dw _text_cmd_0a
    .dw _text_cmd_0b
    .dw _text_cmd_0c
    .dw _text_cmd_0d
    .dw _text_cmd_0e

; ------------------------------------------------------------------------------

; [ escape code 0x06: variable ]

_text_cmd_06:
_a4e6:
    jsr.w _inc_text_ptr
    lda (0x30)
    bmi _a4ee
    rts
_a4ee:
    and #0x7f
    bne _a4f8
    ldx.w #0x0000
    jmp.w _text_var_00
_a4f8:
    cmp #0x01
    bne _a502
    ldx.w #0x0003
    jmp.w _text_var_01
_a502:
    cmp #0x02
    bne _a509
    jmp.w _text_var_02
_a509:
    cmp #0x03
    bne _a510
    jmp.w _text_var_03
_a510:
    cmp #0x04
    bne _text_var_05
    jmp.w _text_var_04

; ------------------------------------------------------------------------------

; [ variable type 5: status name ]

_text_var_05:
_a517:
    lda 0x359a
    asl
    tax
    lda.l status_name_ptrs, x
    sta 0x00
    lda.l status_name_ptrs + 1, x
    sta 0x01
    lda.b #status_name_ptrs >> 16
    sta 0x02
_a52c:
    lda [0x00]
    beq _a53a
    jsr.w draw_letter
    ldx.w 0x00
    inx
    stx 0x00
    bra _a52c
_a53a:
    rts

; ------------------------------------------------------------------------------

; [ variable type 4: magic name ]

_text_var_04:
_a53b:
    lda 0x359a
    cmp #0x48
    bcc _a565
    sec
    sbc #0x48
    sta 0x26
    lda #0x08
    sta 0x28
    jsr.l mult8_far
    ldx.w 0x2a
    lda #0x08
    sta 0x00
_a554:
    lda.l attack_name, x
    cmp #0xff
    beq _a564
    jsr.w draw_letter
    inx
    dec 0x00
    bne _a554
_a564:
    rts
_a565:
    sta 0x26
    lda #0x06
    sta 0x28
    jsr.l mult8_far
    ldy.w #0
    ldx.w 0x2a
    lda.l magic_name, x
    jsr.w _draw_letter_no_dakuten
    lda #0x05
    sta 0x00
_a57e:
    lda.l magic_name + 1, x
    cmp #0xff
    beq _a58e
    jsr.w draw_letter
    inx
    dec 0x00
    bne _a57e
_a58e:
    rts

; ------------------------------------------------------------------------------

; [ variable type 3: item name ]

_text_var_03:
_a58f:
    lda 0x359a
    sta 0x26
    lda #0x09
    sta 0x28
    jsr.l mult8_far
    ldy.w #0
    ldx.w 0x2a
    inx
    lda #0x08
    sta 0x00
_a5a5:
    lda.l item_name, x
    cmp #0xff
    beq _a5b5
    jsr.w draw_letter
    inx
    dec 0x00
    bne _a5a5
_a5b5:
    rts

; ------------------------------------------------------------------------------

; [ variable type 2: character name ]

_text_var_02:
_a5b6:
    lda 0x359a
    longa()
    _asl7()

    tax
    shorta0()
    lda 0x2000, x
    dec
    and #0x3f
    tax
    lda.l char_name_tbl, x  ; name for each character

_draw_char_name:
_a5d1:
    sta 0x26
    lda #0x06
    sta 0x28
    jsr.l mult8_far
    lda #0x06
    sta 0x00
    ldx.w 0x2a
    _inx5()
_a5e5:
    lda 0x1500, x
    cmp #0xff
    bne _a5f5
    dex
    dec 0x00
    lda 0x00
    cmp #0x01
    bne _a5e5
_a5f5:
    ldx.w 0x2a
_a5f7:
    lda 0x1500, x
    jsr.w draw_letter
    inx
    dec 0x00
    bne _a5f7
    rts

; ------------------------------------------------------------------------------

; [ variable type 0/1: battle variable ]

_text_var_00:
_text_var_01:
_a603:
    lda 0x359a, x
    sta 0x00
    lda 0x359b, x
    sta 0x01
    lda 0x359c, x
    sta 0x02
    jsr.l hex_to_dec_var
    jsr.w _normalize_var
_a619:
    lda 0xf4ad, x
    jsr.w _draw_letter_no_dakuten
    inx
    cpx.w #8
    bne _a619
    rts

; ------------------------------------------------------------------------------

; [ text escape code ]

_exec_text_cmd:
_a626:
    asl
    tax
    lda.l text_cmd_tbl, x
    sta 0x00
    lda.l text_cmd_tbl + 1, x
    sta 0x01
    jmp.w (0x0000)

; ------------------------------------------------------------------------------

; [ escape code 0x01: newline ]

_text_cmd_01:
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
;        _clr_ay()
;        shorta()
;        rts

; ------------------------------------------------------------------------------

; [ escape code 0x00: string terminator (unused) ]

_text_cmd_00:
_a64e:
    rts

; ------------------------------------------------------------------------------

; [ escape code 0x04: character name (by character id) ]

_text_cmd_04:
_a64f:
    jsr.w _inc_text_ptr
    lda (0x30)
    jmp.w _draw_char_name

; ------------------------------------------------------------------------------

; [ escape code 0x02: character name (by slot) ]

_text_cmd_02:
_a657:
    jsr.w _inc_text_ptr
    lda (0x30)

_draw_char_slot_name:
_a65c:
    pha
    tax
    lda 0x29c5, x
    cmp #0xff
    bne _a672
    ldx.w #0x0006
_a668:
    lda #0xff
    jsr.w draw_letter
    dex
    bne _a668
    pla
    rts
_a672:
    pla
    longa()
    _asl7()
    tax
    shorta0()
    lda 0x2000, x
    dec
    and #0x3f
    tax
    lda.l char_name_tbl, x  ; name for each character
    sta 0x26
    lda #0x06
    sta 0x00
    sta 0x28
    jsr.l mult8_far
    ldx.w 0x2a
_a698:
    lda 0x1500, x
    jsr.w draw_letter
    inx
    dec 0x00
    bne _a698
    rts

; ------------------------------------------------------------------------------

; [ escape code 0x03: borders and symbols ]

_text_cmd_03:
_a6a4:
    jsr.w _inc_text_ptr
    lda (0x30)
    jmp.w _draw_letter_no_dakuten

; ------------------------------------------------------------------------------

; [ escape code 0x05: tab ]

_text_cmd_05:
_a6ac:
    jsr.w _inc_text_ptr
    lda (0x30)
    sta 0x00
_a6b3:
    lda #0xff
    jsr.w draw_letter
    dec 0x00
    bne _a6b3
    rts

; ------------------------------------------------------------------------------

; [ escape code 0x07: character 1 variable ]

_text_cmd_07:
_a6bd:
    ldx.w #0x0000
;clr_a
    tdc
    bra _draw_char_var

; ------------------------------------------------------------------------------

; [ escape code 0x08: character 2 variable ]

_text_cmd_08:
_a6c3:
    ldx.w #0x0080
    lda #1
    bra _draw_char_var

; ------------------------------------------------------------------------------

; [ escape code 0x09: character 3 variable ]

_text_cmd_09:
_a6ca:
    ldx.w #0x0100
    lda #2
    bra _draw_char_var

; ------------------------------------------------------------------------------

; [ escape code 0x0a: character 4 variable ]

_text_cmd_0a:
_a6d1:
    ldx.w #0x0180
    lda #3
    bra _draw_char_var

; ------------------------------------------------------------------------------

; [ escape code 0x0b: character 5 variable ]

_text_cmd_0b:
_a6d8:
    ldx.w #0x0200
    lda #4
; fallthrough

; ------------------------------------------------------------------------------

; [ draw character variable ]

_draw_char_var:
_a6dd:
    stx 0x0a
    pha
    jsr.w _inc_text_ptr
    lda (0x30)
    bne _a6eb
; 0: character name
    pla
    jmp.w _draw_char_slot_name
_a6eb:
    tax
    pla
    sta 0x03
    txa
    ldx.w 0x0a
; 1: current hp
    cmp #0x01
    bne _a6fd
    stz 0x02
    lda #0x07
    jmp.w _draw_hp_num
; 2: max hp
_a6fd:
    cmp #0x02
    bne _a708
    stz 0x02
    lda #0x09
    jmp.w _draw_hp_num
; 3: current mp
_a708:
    cmp #0x03
    bne _a715
    lda #1
    sta 0x02
    lda #0x0b
    jmp.w _draw_mp_num
; 4: max mp
_a715:
    cmp #0x04
    bne _a722
    lda #1
    sta 0x02
    lda #0x0d
    jmp.w _draw_mp_num
_a722:
"""5: invalid (infinite loop)"""
    jmp.w _a722

; ------------------------------------------------------------------------------

; [ clear hex to decimal conversion buffer ]

; unused

_clear_hex_to_dec_buf:
_a725:
    lda #0xff
    sta 0x180c
    sta 0x180d
    sta 0x180e
    sta 0x180f
    rts

; ------------------------------------------------------------------------------

; [ draw mp value ]

; 0x02: number of digits to skip (0 for hp, 1 for mp)

_draw_mp_num:
_a734:
    ldx.w 0x0a
    jsr.w _get_stat_num_text
    lda 0x02
    tax
_a73c:
    lda 0x180c, x
    cmp #0xff
    beq _a746
    clc
    adc #0x6d  ; 0x6d is "0" on bg2
_a746:
    jsr.w _draw_letter_no_dakuten
    inx
    cpx.w #4
    bne _a73c
    rts

; ------------------------------------------------------------------------------

; [ draw hp value ]

_draw_hp_num:
_a750:
    ldx.w 0x0a
    jsr.w _get_stat_num_text
    lda 0x02
    tax
_a758:
    lda 0x180c, x
    jsr.w _draw_letter_no_dakuten
    inx
    cpx.w #4
    bne _a758
    rts

; ------------------------------------------------------------------------------

; [ convert hp or mp value to text ]

_get_stat_num_text:
_a765:
    longa()
    stx 0x00
    clc
    adc 0x00
    tax
    lda 0x2000, x  ; get hp/mp value
    tax
    shorta0()
    jsr.w hex_to_dec
    jmp.w normalize_num

; ------------------------------------------------------------------------------

; [ escape code 0x0e: change tile flags ]

_text_cmd_0e:
_a77a:
    jsr.w _inc_text_ptr
    lda (0x30)
    sta 0x36
    rts

; ------------------------------------------------------------------------------

; [ escape code 0x0d: monster count ]

_text_cmd_0d:
_a782:
    jsr.w _inc_text_ptr
    lda (0x30)
    tax
    lda 0x29ca, x
    beq _a7a9
    lda 0x29b1, x
    cmp #0xff
    beq _a7a6
    lda 0x29ca, x
    tax
    cmp #0x01
    bne _a7a0
    lda #0xff  ; blank if only 1 monster
    bra _a7a6
_a7a0:
    jsr.w hex_to_dec
    lda 0x1810
_a7a6:
    jmp.w _draw_letter_no_dakuten
_a7a9:
    dec
    jmp.w _draw_letter_no_dakuten

; ------------------------------------------------------------------------------

; [ escape code 0x0c: monster name ]

_text_cmd_0c:
_a7ad:
    jsr.w _inc_text_ptr
    lda (0x30)
    tax
    lda 0x29ca, x
    beq _a7bf
    lda 0x29b1, x
    cmp #0xff
    bne _a7cb
_a7bf:
    ldx.w #8

    jsr.l initialize_monster_slot
    rts

_a7cb:


"""
_a7c2:  lda     #0xff
jsr.w _draw_letter_no_dakuten
dex
bne     _a7c2
rts
"""


    pha
    lda 0x38d0, x
    beq _a7d6
    pla
    lda #0xdf
    bra _a7d7
_a7d6:
    pla
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
;        _asl3()
;        tax
;        shorta0()
;        lda     #8
;        sta     0x00
;_a7e4:  lda.l monster_name,x
;        jsr.w draw_letter
;        inx
;        dec     0x00
;        bne     _a7e4
;        rts

; ------------------------------------------------------------------------------

_normalize_var:
_at_873b:
    ldx.w #0
_at_873e:
    lda 0xf4ad, x
    cmp #0x80
    bne _at_8750
    lda #0xff
    sta 0xf4ad, x
    inx
    cpx.w #7
    bne _at_873e
_at_8750:
    rts

hex_to_dec:
"""Convert the hex value in A/X to decimal digits in the format buffer."""
_at_86bf:
    stx 0x26
    ldx.w #10000
    stx 0x28
    jsr.l div16_far
    lda 0x2a
    clc
    adc #0x80
    sta 0x180c
    ldx.w 0x2c
    stx 0x26
    ldx.w #1000
    stx 0x28
    jsr.l div16_far
    lda 0x2a
    clc
    adc #0x80
    sta 0x180d
    ldx.w 0x2c
    stx 0x26
    ldx.w #100
    stx 0x28
    jsr.l div16_far
    lda 0x2a
    clc
    adc #0x80
    sta 0x180e
    ldx.w 0x2c
    stx 0x26
    ldx.w #10
    stx 0x28
    jsr.l div16_far
    lda 0x2a
    clc
    adc #0x80
    sta 0x180f
    lda 0x2c
    clc
    adc #0x80
    sta 0x1810
    rts

normalize_num:
"""Normalise a number for display (strip leading zeros, etc.)."""
_at_8716:
    ldx.w #0
_at_8719:
    lda 0x180d, x  ; shift out the top digit
    sta 0x180c, x
    inx
    cpx.w #5
    bne _at_8719
    ldx.w #0
_at_8728:
    lda 0x180c, x
    cmp #0x80
    bne _at_873a  ; return if digit is not zero
    lda #0xff
    sta 0x180c, x  ; hide digit
    inx
    cpx.w #3  ; don't hide ones digit
    bne _at_8728
_at_873a:
    rts
}
