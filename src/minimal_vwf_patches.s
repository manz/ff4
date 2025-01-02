;=====================================================================
; Les Fonctions de chargement de pointeur de dialogue
;=====================================================================

*=0x00B404
     jsr.l CalculePositionTb
     jsr.l PointeurBank1de1
     sta 0xDD
     ldx 0x3D
     stx 0x0772
     rts

 *=0x00B41D
     jsr.l CalculePositionTb
     jsr.l PointeurBank1de2
     sta 0xDD
     ldx 0x3D
     stx 0x0772
     rts

 *=0x00B436
     jsr.l CalculePositionTb
     jsr.l PointeurBank3
     sta 0xDD
     ldx 0x3D
     stx 0x0772
     rts

 *=0x00B3BB
     lda 0x1702
     sta 0x3D
     lda 0x1701
     sta 0x3E
     jsr.l PointeurBank2
     rts

; nukes the first call of display_script because the text
; has to be rendered before animating the window display
*=0x00B32C
    jsr.w first_window

; Replace the display_script function by the vwfed one.
*=0x00B463
    jsr.l vwfstart
    rts

first_window:
    lda 0x01
    sta 0xDE
    sta 0xED
    jsr.l vwfinit
    rts

animation_wait_route:
    wait_for_nmi_end=0x912F
    jsr.w wait_for_nmi_end

wait_for_open_animation:
    lda 0x7F
    cmp #0x02
    bne wait_for_open_animation
    inc 0xDF
    lda 0xDF
    cmp #0x08
    bne animation_wait_route

    ; restore tileset position
    lda 0x210C
    and #0xF0
    clc
    adc #0x02
    sta 0x210C

    jmp.w end_of_animation

; do not scroll between text blocks
*=0x00B370
    lda #0x00
    sta 0x07
    jmp.w 0xB398

*=0x00B335
    jmp.w animation_wait_route
end_of_animation:
    jmp.w 0xB369 ; skip_wait_for_action_button


{
; Oui
*=0x14F66C
    .table 'text/ff4_menus.tbl'
    .text ' '
    .db 0x20
    .text ' '
    .db 0x20
    .text ' '
    .db 0x20

*=0x14F67C
    .text 'O'
    .db 0x20
    .text 'u'
    .db 0x20
    .text 'i'
    .db 0x20

; Non
*=0x14F68C
    .text ' '
    .db 0x20
    .text ' '
    .db 0x20
    .text ' '
    .db 0x20


*=0x14F69C
    .text 'N'
    .db 0x20
    .text 'o'
    .db 0x20
    .text 'n'
    .db 0x20
}
