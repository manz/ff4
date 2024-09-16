.macro move_to(left, top) {
    .dw left * 2 + top * 64
}

.macro menu_window(left, top, width, height) {
    move_to(left, top)
    .db width, height
}

.macro menu_window_move_text(left, top, width, height) {
    move_to(left, top)
    .db width, height
    move_to(left + 1, top + 1)
}


