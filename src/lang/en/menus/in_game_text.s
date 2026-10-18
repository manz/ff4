"""English text data for the in-game menus."""
.include "ingame/macros.i"
.include "core/bank20.i"
.table "ff4_menus_small_vwf.tbl"  ; build.py: ff4_menus.tbl, accented capitals folded
.import "core/vanilla"


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
    .text "Items"
    .db 0x01
    .dw 0x00F0
    .text "Magic"
    .db 0x01
    .dw 0x0170
    .text "Equip"
    .db 0x01
    .dw 0x01F0
    .text "Status"
    .db 0x01
    .dw 0x0270
    .text "Form"
    .db 0x01
    .dw 0x02F0
    .text "Change"
    .db 0x01
    .dw 0x0370
    .text "Config"
    .db 0x01
    .dw 0x03F0
    .text "Save"
    .db 0
gils:
    .text "Gil"
    .db 0
time:
    .text "Time"
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
    .dw 0x0046  ; centred in its window, by whole tiles
    .text "Items"
    .db 0
notuse:
    .dw 0x0052
    .text "Can't use that."
    .db 0
nothing_here:
; なにもありません: the same empty slot picked twice ($01:A300)
    move_to(10, 1)
    .text "There's nothing here."
    .db 0
    }
}

.alloc spell_titles_text in bank20_reloc {
    .scope spells {
    """Spell-list headers."""
white:
    move_to(26, 3)  ; the school titles: centred in their window, by whole tiles
    .text "White"
    .db 0
black:
    move_to(26, 5)
    .text "Black"
    .db 0
summon:
    move_to(26, 7)
    .text "Summon"
    .db 0
ninja:
    move_to(26, 5)  ; over Rituel's cells, its trailing space included
    .text "Ninja "
    .db 0
mp_needed:
; copied at the cost row (magic.s)
    .text "MP Cost"
    .db 0
    }
}

.alloc exchange_label_text in bank20_reloc {
    .scope spells {
; the treasure popup's exchange label, drawn at $01:D95E: over the header's Tout prendre while a drop is being
; exchanged, as vanilla's こうかん over 全部とる; its spaces blank the rest of Tout prendre's cells
kokan:
    move_to(10, 1)
    .text "Exchange    "
    .db 0
    }
}

.alloc key_items_warning_text in bank20_reloc {
    .scope treasure {
key_items_left_warning:
"""Drawn over the treasure screen when key items are left behind ($01:DB2E DrawWindowText): window, then text."""
; one line, the window fitted to it (129 px in 17 cells)
    menu_window(6, 11, 17, 1)
    move_to(7, 11)  ; pos text: the glyph row is the one below
    .text "Key items remain."
    .db 0
    }
}

.alloc fat_chocobo_text in bank20_reloc {
    .scope fat_chocobo {
    """
Fat Chocobo's screen (ingame/fat_chocobo.s). Vanilla writes his name at (7, 2) once and each line at (13, 2);
    the name does not fit before column 13 in French, so every line carries it from column 7.
    """
choice_window:
; FatChocoChoiceWindow + FatChocoChoicePosText ($01:CD80 DrawWindowText): window, then あずける / ひきだす
    menu_window(2, 6, 12, 2)
    move_to(4, 7)
    .text "Deposit"
    col(6)
    .text "Withdraw"
    .db 0
greens:
; 「よーお なんかようかーい」
    move_to(7, 2)
    .text "Fat Chocobo: Yo! What'll it be?"
    .db 0
whistle:
; 「こんなとこでフエふくなよ」
    move_to(7, 2)
    .text "Fat Chocobo: No whistling in here!"
    .db 0
give:
; 「なにさくれるんだーい」
    move_to(7, 2)
    .text "Fat Chocobo: What're you leaving?"
    .db 0
take:
; 「なにがほしいんだーい」
    move_to(7, 2)
    .text "Fat Chocobo: What're you taking?"
    .db 0
full:
; 「うーん もうくえない」
    move_to(7, 2)
    .text "Fat Chocobo: I'm stuffed!"
    .db 0
bag_full:
; 「にもつさせいりしなー」
    move_to(7, 2)
    .text "Fat Chocobo: Your bag is full!"
    .db 0
    }
}

.alloc item_refusal_text in bank20_reloc {
    .scope items_menu {
no_effect:
; うまくいかないようです ($01:A5D6, $01:A6F2): an item on a target it cannot help
    move_to(6, 11)
    .text "It has no effect..."
    .db 0
not_needed:
; そのひつようはありません ($01:A6BF, $01:A7BF): a cure the target does not need
    move_to(6, 11)
    .text "That's not needed."
    .db 0
    }
}

.alloc summon_learned_text in bank20_reloc {
    .scope items_menu {
summon_learned:
; SummonMsgWindow ($01:A8E4 DrawWindowText): "Rydia / a appris Gobelin". The game writes the name at (13, 10) and
; the summon after "a appris" (items.s moves it to (18, 12)); Flagelleur, the widest, ends in column 22.
    menu_window(12, 9, 11, 5)
    move_to(13, 12)
    .text "learned"
    .db 0
    }
}

.alloc namingway_text in bank20_reloc {
    .scope namingway {
    """Namingway's name-change screen (ingame/namingway.s)."""
question:
; ネミングウェイ 「おなまえの ごへんこうで?」
    move_to(7, 1)
    .text "Namingway: Change a name?"
    .db 0
choice:
; かえる / かえない, copied at (4, 6); the second cursor stops at column 10
    .text "Yes"
    col(6)
    .text "No"
    .db 0
whose:
; どなたさまがごへんこうなさいますか?
    move_to(7, 1)
    .text "Who wants a new name?"
    .db 0
wiser:
; そのほうがよろしゅうございますな (B: no change)
    move_to(7, 1)
    .text "A wise choice indeed!"
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
    .text "End"
    .db 0
    }
}

.alloc status_text in bank20_reloc {
    .scope status {
    """Status screen labels."""
status:
    .dw 0x01F0
    .text "Status"
    .db 0
exp_for_next_level:
    .dw 0x0260
    .text "Next level"
    .db 0
char_stats:
    .dw 0x0114 - 0x80
    .text "Level"
    .db 1
    .dw 0x01A0
    .text "Experience"
    .db 1
    .dw 0x0206
    .text "HP"
    .db 1
    .dw 0x0286
    .text "MP"
    .db 1
    .dw 0x0344
    .text "Stats"
    .db 1
    .dw 0x03C2
    .text "Strength"
    .db 1
    .dw 0x0442
    .text "Agility"
    .db 1
    .dw 0x04C2
    .text "Vitality"
    .db 1
    .dw 0x0542
    .text "Intellect"
    .db 1
    .dw 0x05C2
    .text "Spirit"
    .db 1
;att/def/mag:
    .dw 0x035A
    .text "Attack"
    .db 1
    .dw 0x03DA
    .text "Attack%"
    .db 1
    .dw 0x045A
    .text "Defense"
    .db 1
    .dw 0x04DA
    .text "Defense%"
    .db 1
    .dw 0x055A
    .text "M.Def"
    .db 1
    .dw 0x05DA
    .text "M.Def%"
    .db 0
    }
}

.alloc options_text in bank20_reloc {
    .scope options {
    """Options screen text."""
title:
    .dw 0x009A  ; centred in its window, by whole tiles
    .text "Config"
    .db 0
config:
    .dw 0x0102, 0x161C  ; two rows taller than vanilla's: the ATB gauge row
    .dw 0x0144
    .text "Battle Mode"
    .db 0x01
    .dw 0x015E
    .text "Active"
    col(7)
    .text "Wait"
    .db 0x01
    .dw 0x01C4
    .text "Battle Speed"
    .db 0x01
    .dw 0x021E
    .text "Fast"
    col(7)
    .text "Slow"
    .db 0x01
    .dw 0x0244
    .text "Message Speed"
    .db 0x01
    .dw 0x02C4
    .text "Sound"
    .db 0x01
    .dw 0x02DE
    .text "Stereo"
    col(7)
    .text "Mono"
    .db 0x01
    .dw 0x0344
    .text "Controller"
    .db 0x01
    .dw 0x035E
    .text "Normal"
    col(7)
    .text "Custom"
    .db 0x01
    .dw 0x03DE
    .text "Single"
    col(7)
    .text "Multiple"
    .db 0x01
    .dw 0x0444
    .text "Cursor"
    .db 0x01
    .dw 0x045E
    .text "Reset"
    col(7)
    .text "Memory"
    .db 0x01
    .dw 0x04C4
    .text "Color"
    .db 0
pad_select_title_window:
; replaces ConfigLabelWindow ($01:D659): fits "Choix des manettes" (83 px), centred like the controls title
    menu_window(9, 0, 12, 2)
pad_select:
; パッドセレクタ ($01:D65F DrawWindowText): window, then title
    menu_window(5, 7, 20, 11)
    move_to(11, 1)  ; centred in its window, by whole tiles
    .text "Controller Setup"
    .db 0
pad:
; コントローラー, after each name ($01:D685 DrawMenuText)
    .text "Controller"
    .db 0
    }
}

.alloc options_gauge_text in bank20_reloc {
    .scope options_gauge {
    """The options screen's ATB gauge row (ingame/options.s), its own block: options_text fills its tiles."""
row:
    .dw 0x0644  ; row 10, under the colour sliders
    .text "ATB Gauge"
    .db 0x01
    .dw 0x065E
    .text "On"
    col(7)
    .text "Off"
    .db 0
    }
}

.alloc controls_text in bank20_reloc {
    .scope options {
controls:
    move_to(9, 1)
    .text "Custom Controls"
    .db 0x01
    .dw 0x0204
    .text "Confirm"
    .db 0x01
    .dw 0x0284
    .text "Cancel"
    .db 0x01
    .dw 0x0304
    .text "Menu"
    .db 0x01
    .dw 0x0384
    .text "L Button"
    .db 0x01
    .dw 0x0404
    .text "Start"
    .db 1
    .dw 0x0484
    .text "End"
    .db 0
button_actions:
"""What L and Start can do (vanilla's None / Yes / No / Menu): the cursor stops at columns 0, 5, 10 and 15."""
    .text "None"
    col(5)
    .text "Confirm"
    col(10)
    .text "Cancel"
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
    .text "Right"
    .db 0x01
    move_to(14, 2 + _text_y)
    .text "Left"
    .db 0x01
    move_to(14, 4 + _text_y)
    .text "Head"
    .db 0x01
    move_to(14, 6 + _text_y)
    .text "Body"
    .db 0x01
    move_to(14, 8 + _text_y)
    .text "Arms"
    .db 0
two_hands:
; りょうてで つかう アイテムです / ほかはそうびできません ($01:BF81 DrawWindowText): window, then text
    menu_window(9, 14, 11, 6)
    move_to(10, 15)
    .text "Two-handed weapon."
    .db 1
    move_to(10, 17)
    .text "No other item"
    .db 1
    move_to(10, 19)
    .text "can be equipped."
    .db 0
    }
}

.alloc dextrality_text in bank20_reloc {
    .scope dextrality {
    """Handedness labels."""
hands:
string_0:
; ぶきよう
    .text "Clumsy"
    .db 0
string_1:
; ひだりきき
    .text "Left hand"
    .db 0
string_2:
; みぎきき
    .text "Right hand"
    .db 0
string_3:
; りょうきき
    .text "Both hands"
    .db 0
    }
}

.alloc use_spell_text in bank20_reloc {
    .scope use_spell {
    """Spell-cast prompt strings."""
mp_cost:
    move_to(2, 4)
    .text "MP Cost"  ; as on the spell list screen
    .db 0
    }
}

.alloc treasure_header_text in bank20_reloc {
    .scope treasure {
header_window:
    menu_window(0, 0, 6, 2)
    move_to(3, 1)  ; centred in its window, by whole tiles
    .text "Spoils"
    .db 1
exit:
    move_to(24, 1)
    .text "Exit"
    .db 1
take_all:
    move_to(10, 1)
    .text "Take All"
    .db 0
    }
}

.alloc _in_game_text_block in bank20_reloc {
    .scope messages {
    """Generic prompt strings."""
use_on_whom:
    move_to(10, 1)
    .text "Use on whom?"
    .db 0
cantuse:
    move_to(10, 1)
    .text "This item can't be used here."
    .db 0
cant_use_magic:
    menu_window_move_text(7, 12, 14, 1)
    .text "Can't use magic"
    .db 0
    }

    .scope treasure {
    """Treasure-chest UI text + windows."""
choice_window:
    menu_window(8, 0, 22, 2)
items_window:
    menu_window(0, 3, 30, 10)
exchange:
    move_to(10, 1)
    .text "Exchange    "
    .db 0
    }
}
