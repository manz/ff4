.extern assets_monsters_long_ptr

load_monster_pointer:
"""Resolve a long-form monster name pointer from `assets_monsters_long_ptr[A*2]` and render it into the current slot."""
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
"""Cross-bank (RTL) entry that clears a monster's display slot to spaces."""
    jsr.w initialize_monster_slot_near
    rtl

tab_escape_code:
"""Text-stream escape that draws a column of spaces to advance the cursor."""
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
