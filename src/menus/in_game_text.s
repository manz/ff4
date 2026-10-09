"""French translated text data for the in-game menus."""
.include "src/ingame/macros.i"
.include "../bank20.i"
.table "text/ff4_menus.tbl"
.import "dakuten"
.import "vanilla"


.alloc in_game_menu_text in bank20_reloc {
    .scope in_game_menu {
    """Main pause-menu strings."""
cant_fight:
    .text "KO"
    .db 0
menu:
; window
    menu_window(23, 0, 7, 17)
; position
    .dw 0x0070
    .text "Objets"
    .db 0x01
    .dw 0x00F0
    .text "Magie"
    .db 0x01
    .dw 0x0170
    .text "Equiper"
    .db 0x01
    .dw 0x01F0
    .text "Statut"
    .db 0x01
    .dw 0x0270
    .text "Placer"
    .db 0x01
    .dw 0x02F0
    .text "Changer"
    .db 0x01
    .dw 0x0370
    .text "Options"
    .db 0x01
    .dw 0x03F0
    .text "Sauver"
    .db 0
gils:
    .text "Gils"
    .db 0
time:
    .text "Temps"
    .db 0
    }
}

.alloc items_menu_text in bank20_reloc {
    .scope items_menu {
    """Items submenu strings."""
items_menu_right:
    menu_window(22, 0, 7, 3)
item:
    menu_window(0, 0, 7, 3)
    .dw 0x0044
    .text "Objets"
    .db 0
notuse:
    .dw 0x0052
    .text "Impossible à utiliser."
    .db 0
    }
}

.alloc spell_titles_text in bank20_reloc {
    .scope spells {
    """Spell-list headers."""
white:
    move_to(24, 3)
    .text "Magie"
    .db 0
black:
    move_to(24, 5)
    .text "Rituel"
    .db 0
summon:
    move_to(24, 7)
    .text "Chimere"
    .db 0
ninja:
    move_to(24, 5)
    .text "Ninja "
    .db 0
    }
}

.alloc exchange_label_text in bank20_reloc {
    .scope spells {
; the treasure popup's exchange label, drawn at $01:D95E
kokan:
    move_to(24, 3)
    .text "Echange"
    .db 0
    }
}

.alloc namingway_text in bank20_reloc {
    .scope namingway {
    """Namingway's name-change screen (ingame/namingway.s)."""
question:
; ネミングウェイ 「おなまえの ごへんこうで?」
    move_to(7, 1)
    .text "Namingway : Changer de nom ?"
    .db 0
choice:
; かえる / かえない, copied at (4, 6); the second cursor stops at column 10
    .text "Oui"
    col(6)
    .text "Non"
    .db 0
whose:
; どなたさまがごへんこうなさいますか?
    move_to(7, 1)
    .text "Qui veut changer de nom ?"
    .db 0
wiser:
; そのほうがよろしゅうございますな (B: no change)
    move_to(7, 1)
    .text "Sage décision, en effet !"
    .db 0
alphabets:
; ひらがな / カタカナ / ABC / おわり beside the letters window
    move_to(3, 9)
    .text "ABC"
    .db 0x01
    move_to(3, 11)
    .text "éèà"
    .db 0x01
    move_to(3, 13)
    .text "123"
    .db 0x01
    move_to(3, 23)
    .text "Fin"
    .db 0
    }
}

.alloc status_text in bank20_reloc {
    .scope status {
    """Status screen labels."""
status:
    .dw 0x01F0
    .text "Statut"
    .db 0
exp_for_next_level:
    .dw 0x0260
    .text "Niveau suivant"
    .db 0
char_stats:
    .dw 0x0114 - 0x80
    .text "Niveau"
    .db 1
    .dw 0x01A0
    .text "Expérience"
    .db 1
    .dw 0x0206
    .text "PV"
    .db 1
    .dw 0x0286
    .text "PM"
    .db 1
    .dw 0x0344
    .text "Talents"
    .db 1
    .dw 0x03C2
    .text "Vigueur"
    .db 1
    .dw 0x0442
    .text "Agilité"
    .db 1
    .dw 0x04C2
    .text "Vitesse"
    .db 1
    .dw 0x0542
    .text "Esprit"
    .db 1
    .dw 0x05C2
    .text "Volonté"
    .db 1
;att/def/mag:
    .dw 0x035A
    .text "Attaque"
    .db 1
    .dw 0x03DA
    .text "Attaque%"
    .db 1
    .dw 0x045A
    .text "Défense"
    .db 1
    .dw 0x04DA
    .text "Défense%"
    .db 1
    .dw 0x055A
    .text "Déf Mag"
    .db 1
    .dw 0x05DA
    .text "Déf Mag%"
    .db 0
    }
}

.alloc options_text in bank20_reloc {
    .scope options {
    """Options screen text."""
title:
    .dw 0x0096
    .text "Options"
    .db 0
config:
    .dw 0x0102, 0x141C
    .dw 0x0144
    .text "Mode de combat"
    .db 0x01
    .dw 0x015E
    .text "Actif"
    col(7)
    .text "Pause"
    .db 0x01
    .dw 0x01C4
    .text "Vitesse du combat"
    .db 0x01
    .dw 0x021E
    .text "Vite"
    col(7)
    .text "Lent"
    .db 0x01
    .dw 0x0244
    .text "Vitesse du texte"
    .db 0x01
    .dw 0x02C4
    .text "Audio"
    .db 0x01
    .dw 0x02DE
    .text "Stéréo"
    col(7)
    .text "Mono"
    .db 0x01
    .dw 0x0344
    .text "Contrôle"
    .db 0x01
    .dw 0x035E
    .text "Normal"
    col(7)
    .text "Personnalisé"
    .db 0x01
    .dw 0x03DE
    .text "Seul"
    col(7)
    .text "Multiple"
    .db 0x01
    .dw 0x0444
    .text "Curseur"
    .db 0x01
    .dw 0x045E
    .text "Reset"
    col(7)
    .text "Mémoire"
    .db 0x01
    .dw 0x04C4
    .text "Couleur"
    .db 0
    }
}

.alloc controls_text in bank20_reloc {
    .scope options {
controls:
    move_to(9, 1)
    .text "Contrôles personnalisés"
    .db 0x01
    .dw 0x0204
    .text "Action"
    .db 0x01
    .dw 0x0284
    .text "Annuler"
    .db 0x01
    .dw 0x0304
    .text "Menu"
    .db 0x01
    .dw 0x0384
    .text "Bouton L"
    .db 0x01
    .dw 0x0404
    .text "Start"
    .db 1
    .dw 0x0484
    .text "Fin"
    .db 0
button_actions:
"""What L and Start can do (vanilla's None / Yes / No / Menu): the cursor stops at columns 0, 5, 10 and 15."""
    .text "Aucun"
    col(5)
    .text "Action"
    col(10)
    .text "Annuler"
    col(15)
    .text "Menu"
    .db 0
pad_buttons:
"""The buttons an action can take: the cursor stops at columns 0, 3, 6, 9 and 12."""
    .text "A"
    col(3)
    .text "B"
    col(6)
    .text "X"
    col(9)
    .text "Y"
    col(12)
    .text "SELECT"
    .db 0
    }
}

.alloc equip_text in bank20_reloc {
    .scope equip {
    """Equipment menu slot labels."""
menu:
    _text_y = 1
    menu_window(0, 0, 30, 11)
    move_to(14, 0 + _text_y)
    .text "Droite"
    .db 0x01
    move_to(14, 2 + _text_y)
    .text "Gauche"
    .db 0x01
    move_to(14, 4 + _text_y)
    .text "Tête"
    .db 0x01
    move_to(14, 6 + _text_y)
    .text "Corps"
    .db 0x01
    move_to(14, 8 + _text_y)
    .text "Mains"
    .db 0
    }
}

.alloc dextrality_text in bank20_reloc {
    .scope dextrality {
    """Handedness labels."""
hands:
string_0:
; ぶきよう
    .text "String 0"
    .db 0
string_1:
; ひだりきき
    .text "Gaucher"
    .db 0
string_2:
; みぎきき
    .text "Droitier"
    .db 0
string_3:
; りょうきき
    .text "Ambidextre"
    .db 0
    }
}

.alloc use_spell_text in bank20_reloc {
    .scope use_spell {
    """Spell-cast prompt strings."""
mp_cost:
    move_to(1, 4)
    .text "Requis"
    .db 0
; use_on_whom:
; move_to(1, 10)
; .text 'Sur qui ?'
; .db 0
    }
}

.alloc treasure_header_text in bank20_reloc {
    .scope treasure {
header_window:
    menu_window(0, 0, 6, 2)
    move_to(1, 1)
    .text "Butin"
    .db 1
exit:
    move_to(24, 1)
    .text "Quitter"
    .db 1
take_all:
    move_to(10, 1)
    .text "Tout prendre"
    .db 0
    }
}

.alloc _in_game_text_block in bank20_reloc {
    .scope spells {
mp_needed:
    .text "Coût PM"
    .db 0
    }

    .scope messages {
    """Generic prompt strings."""
use_on_whom:
    move_to(10, 1)
    .text "Utiliser sur qui ?"
    .db 0
cantuse:
    move_to(10, 1)
    .text "Cet objet ne peut être utilisé ici."
    .db 0
cant_use_magic:
    menu_window_move_text(7, 12, 14, 1)
    .text "Ne peut utiliser la magie"
    .db 0
    }

    .scope treasure {
    """Treasure-chest UI text + windows."""
choice_window:
"""patch them in place"""
    menu_window(8, 0, 22, 2)
items_window:
    menu_window(0, 3, 30, 10)
exchange:
    move_to(10, 1)
    .text "Échanger    "
    .db 0
key_items_left_warning:
    menu_window(5, 10, 19, 4)
    move_to(6, 11)
    .text "  Il reste des    "
    .db 1
    move_to(6, 13)
    .text "objets importants."
    .db 0
    }


copy_text_with_dakuten_far:
"""Far-callable text copier with dakuten composite lookup."""
    {
    phb
    phk
    plb
    rep #0x20
    txa
    clc
    adc.b menu_dp.tilemap_offset
    tax
    sep #0x20
_loop:
    lda.w 0x0000, y
    beq _exit
    jsr.l lookup_dakuten
    sta 0x7e0000, x
    xba
    sta 0x7e0040, x
    inx
    inx
    iny
    bra _loop
_exit:
    plb
    rtl
    }
}
