"""English strings set inside shared layouts; each language's strings.i defines the same macros."""


.macro hand_texts() {
    """The battle equip window's hand labels, 10 cells each."""
    .text "Right     "
    .text "Left      "
    .text "Right     "
    .text "Main      "
    .text "Main      "
    .text "Left      "
    .text "Main      "
    .text "Main      "
}

.macro yes_cells() {
    """The dialog's Yes/No window: Yes, 3 cells."""
    .text "Y"
    .db 0x20
    .text "e"
    .db 0x20
    .text "s"
    .db 0x20
}

.macro no_cells() {
    """The dialog's Yes/No window: No, 3 cells."""
    .text "N"
    .db 0x20
    .text "o"
    .db 0x20
    .dw 0x20ff
}

.macro gil_caption(width) {
    """The gil window's caption, right-aligned in `width` cells."""
    fill_value(0x20ff, width - 3)
    .text "G"
    .db 0x20
    .text "i"
    .db 0x20
    .text "l"
    .db 0x20
}
