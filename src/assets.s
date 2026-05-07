"""
Pinned binary blobs (fonts, scripts, tilemaps, intro graphics) included via `.incbin` at fixed ROM addresses,
plus the `font_table` pointer table indexed by font id.
"""
; ----------------------------------------------------------------
; Module: assets
; Pinned binary blobs (fonts, scripts, tilemaps).
; ----------------------------------------------------------------

*=0x0AF000
.incbin "fonts/8x8.bin"

*=0x0FA710
.incbin "assets/characters_names.dat"

*=0x0E9800
.incbin "assets/monsters.dat"

*=0x218000
.incbin "assets/bank1_1.ptr"

.incbin "assets/bank1_2.ptr"

.incbin "assets/bank2.ptr"

*=0x228000
.incbin "assets/bank1_1.dat"

*=0x24A000
.incbin "assets/bank1_2.dat"

*=0x25A000
.incbin "assets/bank2.dat"

*=0x27B000
.incbin "assets/battle_statuses.dat"

*=0x288000
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

*=0x298000
.incbin "assets/battle_messages.ptr"

.incbin "assets/battle_messages.dat"

*=0x299900
.incbin "assets/battle_text.ptr"
.incbin "assets/battle_text.dat"
.if ENABLE_INTRO {
    *=0x318000
    .incbin "assets/intro.map"
    .incbin "assets/intro.col"
    .incbin "assets/intro.set"
}
