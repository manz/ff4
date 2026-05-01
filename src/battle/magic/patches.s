.extern DrawMagicListDirect
.extern MagicListPtrs

*=0x029A69                              ; do not initalize the magic text buffers
    ; 029A69  20 70 A0   JSR $A070
    nop
    nop
    nop

*=0x029834                              ; Black magic
    ldx.w #24 * 4

*=0x02982F                              ; summon
    ldx.w #24 * 4 * 2

*=0x16fe1c                              ; patches the transfer size
    .dw 0x600                           ; 0x400

*=0x029839

transfer_white_magic:
    ldx.w #0x0000                       ; white magic
    phx
    stx 0x06
    lda 0x1822
    sta 0x00
    jsr.l DrawMagicListDirect
    lda #0x02                           ; spell list
    ldy.w #0x0002
    jsr.w 0x9738                        ; LoadMenuTfrData
    lda #0x01
    sta 0x1825                          ; 1 transfer
    sta 0x1824                          ; enable menu tilemap vram transfer
    plx
    rts

*=0x029ead

DrawMagicList:
    lda 0x00                            ; character slot
    asl
    tax
    rep #0x20
    lda.l MagicListPtrs, x              ; pointers to spell lists
    clc
    adc 0x06                            ; add magic type offset
    sta 0x00
    tdc
    sep #0x20
    rts

draw_letter_far:
    pha
    tdc
    sta.l 0x7FFFFF
    pla
    jsr.w 0xa497                        ; Original DrawLetter
    rtl

    ; attack name window

*=0x02cbcc                              ; patches for display attack name
    lda.b #battle_magic_length

*=0x02cbdd
    lda.l assets_magic_dat, x

*=0x02cbe6
    cpy.w #battle_magic_length + 1

*=0x02cba2
    sec
    sbc #0x48

    rep #0x20
    and.w #0x00ff
    asl
    tax
    ; force the longest one.
    ; ldx.w #51* 2
    lda.l assets_attack_names_ptr, x
    tax
    sep #0x20

    tdc
    tay

loop:
    lda.l assets_attack_names_dat, x
    sta 0x74fd, y
    beq exit
    iny
    inx
    bra loop

exit:
    jmp.w 0xbca2                        ; display monster? attack name window

    ; attack window position

*=0x029369
    ldx.w #0x0009

    ; attack window size

*=0x02936f
    ldx.w #0x040e

*=0x029382
    ldx.w #0xdb50 - 4 - 2 - 16


    ; cursor and scrolling

*=0x16fe1c                              ; patches the spell menu vram transfer
    ;destination_buffer
    .dw 0x600                           ; 0x400

*=0x02B72B                              ; number of lines to scroll ?
    cmp #11

*=0x02B781                              ; items per line for cursor dpad right
    cmp #1


*=0x02B712                              ; dpad up
    nop
    nop

*=0x02B71C
    nop
    nop

*=0x02B751                              ; dpad down
    ;    INC     D,$63
    nop
    nop

*=0x02B742
    nop
    nop

*=0x16FC56                              ; magic list cursor x position
    .db 8 - 8
    .db 0x3C + 8 * 3 + 4 - 8

*=0x02B764                              ; up and down should only inc /dec once ?
    inc 0x5F
    ;inc 0x5F
    nop
    nop
    inc 0x63
    ;inc 0x63
    nop
    nop

*=0x02B785
    dec 0x5F
    ;dec 0x5F
    nop
    nop
    dec 0x63
    ;dec 0x63
    nop
    nop

*=0x02A567                              ; display magic name in battle messages.
    lda #9

*=0x02A573
    lda.l assets_magic_dat, x

*=0x02A57E
    lda.l assets_magic_dat + 1, x

*=0x02A57A
    lda #9 - 1
