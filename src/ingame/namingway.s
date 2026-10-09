"""
Namingway's name-change screen ($01:BA2E NamingwayYesNo, $01:9B4F NameMenu) in French.

The prompts, the yes/no choice and the alphabet labels point at menus/in_game_text's `namingway` strings, drawn
in the small VWF. The three letter grids (hiragana, katakana, latin in the Japanese ROM) become capitals and
lowercase, lowercase accents, then digits and punctuation: every one a letter the 8x8 font has (no ç) and the
dialog can draw too (utils/name_codes.py), since a name shows up in both. Accented capitals are not name letters.
"""
.include "src/menus/system_menus_macros.i"
.include "src/ingame/bank01_slack.i"
.import "menus/system_menus_text"
.import "menus/in_game_text"
.import "vanilla"

.table "text/ff4_menus.tbl"

.alloc at 0x01BA4A {
; DrawWindowText: the choice window, then the question stored right after it (never pointed at on its own)
    jsr.w namingway_choice_window
}

.alloc _namingway_question in bank01_slack {
namingway_choice_window:
"""The choice window (Y = $E054), then Namingway's question in the small VWF."""
    jsr.w draw_window
    load_system_menu_text_pointer(namingway.question)
    jmp.w draw_pos_text
}

.alloc at 0x01BA50 {
    load_system_menu_text_pointer(namingway.choice)
}

.alloc at 0x01BACA {
    load_system_menu_text_pointer(namingway.wiser)
}

.alloc at 0x01BB1E {
    load_system_menu_text_pointer(namingway.whose)
}

.alloc at 0x019E68 {
    load_system_menu_text_pointer(namingway.alphabets)
}

.alloc _name_letters at 0x01DBBA size 240 {
"""NameAlphaTbl: 3 grids of 8 rows x 10 letters, 0 = empty cell. Capitals left, lowercase right."""
; ABC
    .text "ABCDEabcde"
    .text "FGHIJfghij"
    .text "KLMNOklmno"
    .text "PQRSTpqrst"
    .text "UVWXYuvwxy"
    .text "Z"
    .db 0, 0, 0, 0
    .text "z"
    .db 0, 0, 0, 0
    .db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
; Éàç
    .text "àâéèêëîïôù"
    .text "û"
    .db 0, 0, 0, 0, 0, 0, 0, 0, 0
    .db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
; 123
    .text "01234!?.-'"
    .text "56789:"
    .db 0, 0, 0, 0
    .db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    .db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
}
