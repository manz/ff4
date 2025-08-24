; MISS sprite graphics
*=0x0cfc60
    .incbin 'fonts/miss.bin'

*=0x16fb87
{
    ; chars to copy from the font to the 4bpp tileset in battle
    .table 'text/ff4_menus.tbl'

    .db 0x76,0x78
    .text '/'
    .text 'GRadeginqrsu'
    .db 0x8c, 0x90, 0x7f
    .db 0x80, 0x81, 0x82
    .db 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x16, 0x17, 0x18, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff
}

*=0x02975d
; PM Needed
.db 223, 226, 230, 233, 228, 232, 0xff

; Defend / Row window content
; moves the row destination back a few bytes
*=0x29a90
    ldx.w #0xd618

*=0x29a8b
    ldx.w #0xd5e8

*=0x029a98
    lda.l defend_row.defend_text, x

*=0x029a9e
    lda.l defend_row.row_text, x

*=0x029aa7
    cpx.w #defend_row.defend_row_length * 2

*=0x029aac
    cpx.w #defend_row.defend_row_length

; moves row pointer back 8 pixels.
*=0x02b96a
    lda.b #0x0c

; defend window
*=0x16fe5a + 6 * 8
    .db 0x00, 0x09, 0x08, 0x04


*=0x16fe5a + 6 * 9
; row window
.db 0x18,0x09,0x08,0x04

; switches around small mp to pm in the MP Needed battle window.
*=0x02a1e3
    lda #0xdc
    sta 0xba94,y
    dec
    sta 0xba96,y
