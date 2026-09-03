.include "config.i"
"""English-language counterpart of `start_screen_text.s`."""
.include "src/ingame/macros.i"

.scope newgame {
    """Title-screen + save-slot strings."""
new_game:
    move_to(1, 1)
    .text "New Game"
    .db 0
    .if DEBUG {
build_number:
    VERSION := 'v1.0.0a0'
    .text "${BUILD_DATE} ${VERSION}"
    .db 0
    }
time_load_save:
    .dw 0x046E + 2
    .text "Time"
    .db 0
gils_load_game:
    .text "Gil"
    .db 0
save:
    .text "Save"
    .db 0
load_this_save:
    .dw 0x006E + 2
    .text "Load"
    .db 1
    .dw 0x00EE + 2
    .text "this?"
    .db 0
yes_no:
    .dw 0x0172
    .text "Yes"
    .db 1
    .dw 0x01F2
    .text "No"
    .db 0
empty_save:
    .dw 0x0090 + 2
    .text "EMPTY"
    .db 0
saves:
    move_to(1, 1)
    .text "Save Files"
    .db 0
save_completed:
    move_to(8, 11)
    .text "Save complete"
    .db 0
did_not_save:
    move_to(1, 1)
    .text "Cancelled "
; extra space at the end to clear the previous title.
    .db 0
}
