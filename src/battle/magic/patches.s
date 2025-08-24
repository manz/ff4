; do not initalize the magic text buffers
*=0x029A69
; 029A69  20 70 A0   JSR $A070
    nop
    nop
    nop

; Black magic
*=0x029834
    ldx.w #24 * 4

; summon
*=0x02982F
    ldx.w #24 * 4 * 2

; patches the transfer size
*=0x16fe1c
    .dw 0x600 ; 0x400

*=0x029839
transfer_white_magic:
    ldx.w #0x0000  ; white magic
    phx
    stx 0x06
    lda 0x1822
    sta 0x00
    jsr.l DrawMagicListDirect
    lda #0x02    ; spell list
    ldy.w #0x0002
    jsr.w 0x9738; LoadMenuTfrData
    lda #0x01
    sta 0x1825   ; 1 transfer
    sta 0x1824   ; enable menu tilemap vram transfer
    plx
    rts

*=0x029ead
DrawMagicList:
    lda 0x00         ; character slot
    asl
    tax
    rep #0x20
    lda.l MagicListPtrs,x   ; pointers to spell lists
    clc
    adc 0x06         ; add magic type offset
    sta  0x00
    tdc
    sep #0x20
    rts
draw_letter_far:
    pha
    tdc
    sta.l 0x7FFFFF
    pla
    jsr.w 0xa497 ; Original DrawLetter
    rtl

; attack name window
; patches for display attack name
*=0x02cbcc
    lda.b #battle_magic_length

*=0x02cbdd
    lda.l assets_magic_dat, x

*=0x02cbe6
    cpy.w #battle_magic_length + 1

; cursor and scrolling

; patches the spell menu vram transfer
;destination_buffer
*=0x16fe1c
    .dw 0x600 ; 0x400

;@fe0c:  .word   $bea6,$7020,$0280       ; 0: main window (10 rows)
;       .word   $c1e6,$71c0,$0280       ; 1: battle command window (10 rows)
;       .word   $c526,$7420,$0400       ; 2: spell list (16 rows)

; number of lines to scroll ?
*=0x02B72B
    cmp #11

; items per line for cursor dpad right
*=0x02B781
    cmp #1


; dpad up
*=0x02B712
    nop
    nop

*=0x02B71C
    nop
    nop

; dpad down
*=0x02B751
;    INC     D,$63
    nop
    nop

*=0x02B742
    nop
    nop

; magic list cursor x position
*=0x16FC56
    .db 2
    .db 0x3C + 14
    .db 0x74

; up and down should only inc /dec once ?
*=0x02B764
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