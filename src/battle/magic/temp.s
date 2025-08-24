
; [ draw spell list directly to transfer buffer ]
DrawMagicListDirect:
{
magic_length = 8
    lda     0x00         ; character slot
    asl
    tax
    rep #0x20
    lda.l     MagicListPtrs,x   ; pointers to spell lists
    clc
    adc     0x06         ; add magic type offset
    sta     0x00
    tdc
    sep #0x20
    ldy.w     #0          ; transfer buffer offset
    lda     #0x0C        ; 8 rows
    sta     0x06
loop:
    lda     (0x00)
    beq     next       ; skip empty slots
    bmi     disabled
    lda     #0x00        ; palette 0, white text
    bra     set_color
disabled:
    lda     #0x04        ; palette 1, gray text
set_color:
    sta     0xc536,y     ; write color to transfer buffer
    iny
    lda     #0x0e        ; text control character
    sta     0xc536,y
    iny
    lda     (0x00)       ; spell ID
    and     #0x7f        ; clear disabled bit
    asl                  ; spell ID * 8 (8 bytes per name)
    asl
    asl
    tax
    lda.b     #magic_length          ; 5 characters per spell name
    sta     0x02
name_loop:
    lda.l    assets_magic_dat+1,x
    lda.b   #0x42
    sta     0xc536,y
    lda     #0x20
    sta     0xc537,y
    iny
    iny
    inx
    dec     0x02
    bne     name_loop
next:
    inc     0x00         ; next spell slot
    dec     0x06
    bne     loop
    tdc
    sta     0xc536,y     ; null terminator
    rtl
}