.scope message_patches {
 ; pointers to battle dialog
*=0x02c909
    lda.l assets_battle_messages_ptr,x
    sta 0x00
    lda.l assets_battle_messages_ptr+1,x
    sta 0x01
    lda.w #assets_battle_messages_ptr >> 16
    sta 0x02


 ; pointers to battle messages
*=0x02cc07
    lda.l assets_battle_text_ptr,x
    sta 0x00
    tdc
    sep #0x20
    lda.b #assets_battle_text_ptr >> 16
    sta 0x02

; |tileset 0xb000 -> 0xbfff bg3 tiles
; |-------------------
; |tilemap bg2 64*32
; |0xb000, 0x1000
; |-------------------
; |tile map bg1 64*64
; |0xc0000, 0x2000
; |-------------------
; |tilemap bg3 64*64
; |0xe0000, 0x2000
; |-------------------


; resize bg1 to 32x64 and moves it to v:0xd000
*=0x0382f5
    ; bg 1
    lda.b #(0xd000 >> 9 | 0b01)
    sta 0x2107
    lda.b #(0xc000 >> 9 | 0b01)
    sta 0x2108

; bg1 move
*=0x028B3B
    ldy.w #0x6000 + 0x800
*=0x02bcad
    ldy.w #0x6000 + 0x800
*=0x02BCB2
    ldy.w #0x6400 + 0x800

; bg1 move
;02/91FE: A0 00 58     LDY #$5800
*=0x0291FE
    ldy.w #0x6000

;02/921F: A0 00 5C     LDY #$5C00
*=0x02921F
    ldy.w#0x6400

; Menu defend row mp cost init
*=0x16fdd6 + 6 * 6
    ;   wram    vram    size
    .dw 0xd366, 0x6400 + 0x260, 0x0340

*=0x16fe0c + 6 * 6
    .dw 0xd366, 0x6400 + 0x260, 0x0140




*=0x0292F8
    ; move the text buffer pointer back 3 entries
    ldx.w #0xDB2E - 3 * 2
    stx 0xEF52
    jsr.w msg_window_draw_text_trampoline

}

; patch the battle nmi routine to transfer the battle render buffer.
*=0x02836e
    jsr.l messages_vwf.DMA_TRANSFER

; make the message window bigger
*=0x0292DF
    ; (0, 3) (26, 4)
    ldx.w #0x0000
    stx.w 0xEF56
    ldx.w #0x041A + 6
    stx.w 0xEF58
