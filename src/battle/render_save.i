"""
Save and restore the battle glyph renderer's shared state around a render that runs from the NMI.
"""

RENDER_STATE_BYTES = 14  ; what save_render_state pushes

.macro save_render_state() {
    """
Push the battle glyph renderer's state (direct page `bits_left_on_tile` .. `current_char`) and the tile
allocator. For the renderers that run from the NMI (the rolling inventory's item rows, the spell list's scroll
rows): they run in the middle of a main-thread draw. The blitter reloads `bits_left_on_tile` after its aligned
check (left at 8, its shift dispatch jumped past its table into a BRK), and a half-started name would land in
the tiles the NMI's own render pointed the allocator at.
    """
    rep #0x20
    lda.b battle_render.bits_left_on_tile
    pha
    lda.b battle_render.tilemap_offset
    pha
    lda.b battle_render.temp
    pha
    lda.b battle_render.counter
    pha
    lda.b battle_render.prev_char  ; and current_char
    pha
    lda.l render_allocator.allocated_tile_id
    pha
    lda.l render_allocator.slot_limit_low
    pha
    sep #0x20
}

.macro restore_render_state() {
    """Pull what `save_render_state` pushed."""
    rep #0x20
    pla
    sta.l render_allocator.slot_limit_low
    pla
    sta.l render_allocator.allocated_tile_id
    pla
    sta.b battle_render.prev_char
    pla
    sta.b battle_render.counter
    pla
    sta.b battle_render.temp
    pla
    sta.b battle_render.tilemap_offset
    pla
    sta.b battle_render.bits_left_on_tile
    sep #0x20
}
