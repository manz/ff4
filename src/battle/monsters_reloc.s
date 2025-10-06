load_monster_pointer:
    rep #0x20
    ;lda.w #127 - 3
    asl
    tax
    lda.l assets_monsters_long_ptr, x
    tax
    tdc
    sep #0x20
    phy
    jsr.w initialize_monster_slot_near
    ply
    rtl

initialize_monster_slot:
    jsr.w initialize_monster_slot_near
    rtl
tab_escape_code:
    jsr.w draw_spaces
    rtl
initialize_monster_slot_near:

    ; clear monster slot with spaces
    lda #11
    sta 0x00
draw_spaces:
    lda.b #0xff
    sta (0x32), y
    sta (0x34), y
    iny
    lda 0x36
    sta (0x32), y
    sta (0x34), y
    iny
    dec 0x00
    bne draw_spaces

    rts
