"""English text for the start screen and save selection, in bank $20."""


.include "ingame/macros.i"
.include "core/bank20.i"

.table "ff4_menus_small_vwf.tbl"  ; build.py: ff4_menus.tbl, accented capitals folded

.alloc newgame_text in bank20_reloc {
    .scope newgame {
    """Title-screen + save-slot strings."""
new_game:
        move_to(1, 1)
        .text "New Game"
        .db 0
time_load_save:
        .dw 0x046E + 2
        .text "Time"
        .db 0
gils_load_game:
        .text "Gil"
        .db 0
save:
        .text "Game"
        .db 0
load_this_save:
        .dw 0x006E + 2
        .text "This"
        .db 1
        .dw 0x00EE + 2
        .text "game?"
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
        move_to(3, 1)  ; centred in its window, by whole tiles
        .text "Saves"
        .db 0
save_completed:
        move_to(8, 11)
        .text "Save complete"
        .db 0
did_not_save:
        move_to(3, 1)  ; over Sauvegardes, from its first cell
        .text "Cancelled  "
; trailing space clears the previous title
        .db 0
    }
}

.alloc save_cancelled_text in bank20_reloc {
    .scope newgame {
save_cancelled:
; ちゅうし ($01:CC33): "Non" on the chosen slot, in the save-completed window
        move_to(8, 11)
        .text "Save cancelled"
        .db 0
    }
}

.alloc _build_number_text in bank20_reloc {
    .scope newgame {
build_number:
        .if DEBUG {
            .text "${BUILD_DATE} ${VERSION}"
        } else {
            .text "${VERSION}"
        }
        .db 0
    }
}
