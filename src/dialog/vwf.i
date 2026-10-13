"""Dialog VWF direct page: the script pointer and the glyph state at $20-$2F, and the skip-wait flag."""

.struct DialogVwf {
    long text_ptr  ; 24-bit pointer into the script
    word counter  ; shift loop counter
    word current_char
    word bits_left  ; bits left in the current tile
    long font_addr  ; 24-bit pointer to the glyph
    word old_tile_pos
    word tile_pos
}
dialog_vwf := (0x20 as DialogVwf)

no_wait_for_action = 0xcb  ; non-zero: don't wait for the action button
