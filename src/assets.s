"""
Pinned binary blobs (fonts, scripts, tilemaps, intro graphics) included via `.incbin` at fixed ROM addresses,
plus the `font_table` pointer table indexed by font id.
"""
; ----------------------------------------------------------------
; Module: assets
; Pinned binary blobs (fonts, scripts, tilemaps).
; ----------------------------------------------------------------

.include "config.i"
.alloc at 0x0AF000 {
    .incbin "fonts/8x8.bin"
}
.alloc at 0x0FA710 {
    .incbin "assets/characters_names.dat"
}
.alloc at 0x0E9800 {
    .incbin "assets/monsters.dat"
}
.alloc at 0x218000 {
    .incbin "assets/bank1_1.ptr"
    .incbin "assets/bank1_2.ptr"
    .incbin "assets/bank2.ptr"
}
.alloc at 0x228000 {
    .incbin "assets/bank1_1.dat"
}
.alloc at 0x24A000 {
    .incbin "assets/bank1_2.dat"
}
.alloc at 0x25A000 {
    .incbin "assets/bank2.dat"
}
.alloc at 0x27B000 {
    .incbin "assets/battle_statuses.dat"
}
.alloc at 0x288000 {
    .incbin "assets/menu_font.dat"
    .incbin "assets/font.dat"
    .incbin "assets/wicked_font.dat"
    .incbin "assets/book_font.dat"
    .incbin "assets/bold_font.dat"
    .incbin "assets/battle_commands.dat"
font_table:
"""24-bit pointer table indexed by font id (0=dialog, 1=wicked, 2=book, 3=bold)."""
    .pointer assets_font_dat
    .pointer assets_wicked_font_dat
    .pointer assets_book_font_dat
    .pointer assets_bold_font_dat


    .incbin "assets/credits_text.bin"
}
.alloc at 0x298000 {
    .incbin "assets/battle_messages.ptr"
    .incbin "assets/battle_messages.dat"
}
.alloc at 0x299900 {
    .incbin "assets/battle_text.ptr"
    .incbin "assets/battle_text.dat"
}

.pool assets {
    range 0x2e8000 0x2effff
    range 0x318000 0x31ffff
    strategy pack
}

.alloc __assets_stupid_mandatory_symbol in assets {
    .incbin "assets/attack_names.ptr"
    .incbin "assets/attack_names.dat"
    .incbin "assets/monsters_long.ptr"
    .incbin "assets/monsters_long.dat"
    .incbin "assets/battle_commands_nul.ptr"
    .incbin "assets/battle_commands_nul.dat"
    .incbin "assets/magic.dat"
    .incbin "assets/places_names.dat"
    .incbin "assets/classes.ptr"
    .incbin "assets/classes.dat"
    .incbin "assets/items.dat"
    .incbin "assets/item_descriptions.dat"
    .incbin "assets/dakuten.bin"
}

.if ENABLE_INTRO {
    .alloc _intro_assets in assets {
    .incbin "assets/intro.map"
    .incbin "assets/intro.col"
    .incbin "assets/intro.set"
    }
}

