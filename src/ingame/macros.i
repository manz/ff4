"""Tilemap-cursor + window helper macros used by the in-game menu text scripts."""
.macro move_to(left, top) {
    """Emit a tilemap cursor word at column `left`, row `top`."""
    .dw left * 2 + top * 64
}

.macro col(column) {
    """Small-VWF strings only: move the pen to `column` cells from where the line started (its position word)."""
    .db 0x03, column
}

.macro menu_window(left, top, width, height) {
    """Emit a window descriptor: cursor + width/height byte pair."""
    move_to(left, top)
    .db width, height
}

.macro menu_window_move_text(left, top, width, height) {
    """Emit a window descriptor immediately followed by a text-cursor positioned inside."""
    move_to(left, top)
    .db width, height
    move_to(left + 1, top + 1)
}

.macro transform_window(from, to) {
    """Kick the window-transform animation: pass source/target window addresses."""
    ldy.w #from & 0xffff
    ldx.w #to & 0xffff
    jmp.w transform_window_trampoline
}
