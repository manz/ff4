.include 'src/ingame/macros.i'

.scope newgame {
new_game:
    move_to(1, 1)
    .text 'Nouvelle partie'
    .db 0

time_load_save:
    .dw 0x046E + 2
    .text 'Temps'
    .db 0

gils_load_game:
    .text 'Gils'
    .db 0

save:
    .text 'Partie'
    .db 0

load_this_save:
    .dw 0x006E + 2
    .text 'Cette'
    .db 1
    .dw 0x00EE + 2
    .text 'partie?'
    .db 0

yes_no:
    .dw 0x0172
    .text 'Oui'
    .db 1
    .dw 0x01F2
    .text 'Non'
    .db 0

empty_save:
    .dw 0x0090 + 2
    .text 'VIDE'
    .db 0

saves:
    move_to(1, 1)
    .text 'Sauvegardes'
    .db 0

did_not_save:
    move_to(1, 1)
    .text 'Annulation ' ; extra space at the end to clear the previous title.
    .db 0
}
