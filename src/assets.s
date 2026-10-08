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
    .incbin "characters_names.dat"
}
.alloc at 0x0E9800 {
    .incbin "monsters.dat"
}
.alloc at 0x218000 {
    .incbin "bank1_1.ptr"
    .incbin "bank1_2.ptr"
    .incbin "bank2.ptr"
}
; Dialog bank 1-1 spans $22 onwards (the reader follows the 24-bit pointer across banks).
.pool dialog_bank1_1 {
    range 0x228000 0x25ffff
    strategy pack
}
.alloc at 0x228000 in dialog_bank1_1 cross_bank {
    .incbin "bank1_1.dat"
}
; Dialog text grows with French typography (spaces before ! ? : ;): each bank has room in its own pool.
.pool dialog_bank1_2 {
    range 0x2a8000 0x2affff
    strategy pack
}
.alloc at 0x2A8000 in dialog_bank1_2 {
    .incbin "bank1_2.dat"
}
.pool dialog_bank2 {
    range 0x2b8000 0x2dffff
    strategy pack
}
.alloc at 0x2B8000 in dialog_bank2 cross_bank {
    .incbin "bank2.dat"
}
.alloc at 0x27B000 {
    .incbin "battle_statuses.dat"
}
.alloc at 0x288000 {
    .incbin "menu_font.dat"
    .incbin "font.dat"
    .incbin "wicked_font.dat"
    .incbin "book_font.dat"
    .incbin "bold_font.dat"
    .incbin "battle_commands.dat"
font_table:
"""24-bit pointer table indexed by font id (0=dialog, 1=wicked, 2=book, 3=bold)."""
    .pointer font_dat
    .pointer wicked_font_dat
    .pointer book_font_dat
    .pointer bold_font_dat


    .incbin "credits_text.bin"
}
.alloc at 0x298000 size 0x2000 {
    .incbin "battle_messages.ptr"
    .incbin "battle_messages.dat"
}
.alloc at 0x29A000 size 0x2000 {
    .incbin "battle_text.ptr"
    .incbin "battle_text.dat"
}

.pool assets {
    range 0x2e8000 0x2effff
    range 0x318000 0x31ffff
    strategy pack
}

.alloc __assets_stupid_mandatory_symbol in assets {
    .incbin "attack_names.ptr"
    .incbin "attack_names.dat"
    .incbin "monsters_long.ptr"
    .incbin "monsters_long.dat"
    .incbin "battle_commands_nul.ptr"
    .incbin "battle_commands_nul.dat"
    .incbin "magic.dat"
    .incbin "places_names.dat"
    .incbin "classes.ptr"
    .incbin "classes.dat"
    .incbin "items.dat"
    .incbin "item_descriptions.dat"
    .incbin "dakuten.bin"
}

; 17-byte records indexed by item id; the pool keeps the table inside one bank.
.alloc _items_unleashed in assets {
    .incbin "items_unleashed.dat"
}

.if ENABLE_INTRO {
    .alloc _intro_assets in assets {
    .incbin "intro.map"
    .incbin "intro.col"
    .incbin "intro.set"
    }
}
