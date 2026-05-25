"""
.include "../bank20.i"

Relocated battle monster-name pointer resolver: indexes `assets_monsters_long_ptr[A*2]` and renders the
resulting string into the active slot.
"""
.extern assets_monsters_long_ptr


.include "../bank20.i"

.alloc battle_monsters_reloc_block in bank20_reloc {
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
        jsr.w _initialize_monster_slot_near
        ply
        rtl

    initialize_monster_slot:
    """Cross-bank (RTL) entry that clears a monster's display slot to spaces."""
        jsr.w _initialize_monster_slot_near
        rtl

    tab_escape_code:
    """Text-stream escape that draws a column of spaces to advance the cursor."""
        jsr.w _draw_spaces
        rtl

    _initialize_monster_slot_near:

    ; clear monster slot with spaces
        lda #11
        sta 0x00

    _draw_spaces:
        lda.b #0xff
        sta (0x32), y
        sta (0x34), y
        iny
        lda 0x36
        sta (0x32), y
        sta (0x34), y
        iny
        dec 0x00
        bne _draw_spaces

        rts
}
