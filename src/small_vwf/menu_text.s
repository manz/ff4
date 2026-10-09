"""
Small-VWF menu text: whole string blocks drawn in the 8-pixel VWF instead of the 8x8 font.

The menu text thunks (menus/system_menus_text.s) offer every string here first. A string inside one of `_blocks`
gets the tiles at its byte offset in its block: a glyph is at most 8 pixels wide, so no two strings of a block
share a tile and nothing is allocated. Blocks on screen together need disjoint tiles.
  - `newgame` (load and save screens): tiles $180-$1FF, the item-description region, unused there.
  - `in_game_menu` (commands, Gils, Temps, KO): $370-$3FF, its own for good. It stays on screen under the
    sub-menus, and Gils / Temps are drawn every frame, so it is *resident*: a string whose first cell already
    shows its first tile is not drawn again.
Only this module draws tiles $200-$3FF, so a bit per tile says which strings are already in VRAM this menu
session: drawing one again only rewrites the tilemap. A block taking over $200-$2FF forgets that range's bits; a
name whose text changed (renamed) uploads again. Tiles $100-$1FF are shared with the item renderers: always uploaded.
  - One sub-menu at a time in $200-$2FF: `status` $200-$2B7, `equip` $200-$2B7, `dextrality` (handedness, on
    status and equip) $2B8-$2DF, `items_menu` $200-$23F, `spells` $200-$23F with `use_spell` $240-$25F,
    `options` $200-$2FF with its controls window (opened over it) in $180-$1FF, the item-description region.
  - The treasure popup is a field screen: nothing saves $6000-$7FFF there, so its header (Butin, Quitter,
    Tout prendre) takes $1AA-$1CF and its exchange label (`spells.kokan`, drawn at $01:D95E) $1D0-$1D9, after the
    drops' item names ($16E-$1A9).
Tiles $200-$3FF are VRAM $6000-$7FFF, free in every menu (ingame/menu_vram.s saves the field's copy). Two strings
come from elsewhere: the class name (DrawClassName, tiles $2E0-$2FF) and the character names (DrawCharName, read
from RAM), whose tiles are keyed by name index ($300 + index * 8), so names never collide on any screen.
"""
.import "vanilla"
.import "vwf_ram"
.import "libmz"
.import "menus/start_screen_text"
.import "menus/in_game_text"
.import "assets"
.import "sram_layout"
.import "small_vwf/render"
.include "config.i"
.include "src/vwf.i"
.include "../bank20.i"
.include "src/libmz.i"

_GLYPH_ROW := 0x40  ; menu text puts the dakuten at +0 and the glyph one row down
_BLANK_TILE := 0xFF

.assert newgame.strings_end - newgame.new_game <= 0x80, "the newgame strings outgrow tiles $180-$1FF"
.assert in_game_menu.strings_end - in_game_menu.cant_fight <= 0x90, "the main-menu strings outgrow tiles $370-$3FF"
.assert status.strings_end - status.status <= 0xB8, "the status strings outgrow tiles $200-$2B7"
.assert equip.strings_end - equip.menu <= 0xB8, "the equip strings outgrow tiles $200-$2B7"
.assert items_menu.strings_end - items_menu.items_menu_right <= 0x40, "the items strings outgrow tiles $200-$23F"
.assert spells.kokan - spells.white <= 0x40, "the spell titles outgrow tiles $200-$23F"
.assert treasure.exchange - treasure.header_window <= 0x26, "the treasure header outgrows tiles $1AA-$1CF"
.assert spells.mp_needed - spells.kokan <= 0x30, "the treasure exchange label outgrows tiles $1D0-$1FF"
.assert use_spell.strings_end - use_spell.mp_cost <= 0x20, "the spell prompt outgrows tiles $240-$25F"
.assert options.controls - options.title <= 0xFF, "the options strings outgrow tiles $200-$2FE"
.assert options.strings_end - options.controls <= 0x80, "the controls strings outgrow tiles $180-$1FF"
.assert dextrality.strings_end - dextrality.hands <= 0x28, "the handedness strings outgrow tiles $2B8-$2DF"

_CLASS_TILE := 0xE0  ; with attribute bits 2: tiles $2E0-$2FF
_CLASS_TILES := 0x20
_NAME_TILES := 8  ; a name has 6 characters
_NAME_ATTRIBUTE := 0x03  ; tiles $300-$3FF
_NAME_LENGTH := 6
_RESIDENT_BIT := 0x80  ; in a block's attribute word: tiles nobody else uses for the whole menu session
_NAME_INDEXES := 14
.assert sizeof(MenuTextState.name_cache) == _NAME_INDEXES * _NAME_LENGTH, "one cached name per name index"
_SHARED_REGION := 0x02  ; attribute bits of tiles $200-$2FF, taken in turns by the sub-menu blocks
.label _char_name_tbl = 0x018457  ; CharNameTbl: character id - 1 to name index
.label _char_names = 0x7E1500  ; 6 bytes per name index

.alloc at 0x0183B0 {
; DrawCharName after its zero-id check
    jsl menu_text_vwf.draw_name
    rts
}

_SPELL_LENGTH := 9  ; magic_names: 9 characters per spell id
_SPELL_TILES := 5  ; the widest name, Léviathan, is 40 pixels
_SCHOOL_SPELLS := 24  ; a school's spells span at most 24 ids: (id - 1) mod 24 is unique within a list
.assert _SCHOOL_SPELLS * _SPELL_TILES <= 0x80, "spell names outgrow tiles $100-$17F"

.alloc at 0x01B305 {
; DrawMagicName once it picked the palette ($db): A and X are still on the stack
    plx
    pla
    jsl menu_text_vwf.draw_spell
    rts
}

.alloc at 0x01B418 {
; The magic type highlight: A = attribute, X = cell offset in BG4's buffer
    jsl menu_text_vwf.tint_cells
    rts
}

.alloc at 0x018FE3 {
; DrawClassName's copy loop (X = offset in class_names, from load_classes_pointer)
    jsl menu_text_vwf.draw_class
    rts
}

.alloc _small_vwf_menu_text in bank20_reloc {
    .include "src/vwf_state.i"

    .scope menu_text_vwf {
    """Entry points called by the menu text thunks, D = $0100, the vanilla routine's frame on the stack."""
draw_pos:
"""
DrawPosText ($01:8301): Y = string - $8000, the position word first. Carry clear: not a VWF string, nothing
touched.
"""
    jsr.w _claim
    bcs _draw_pos
    rts
_draw_pos:
    phk
    plb
    rep #0x20
    tya
    ora.w #0x8000
    tay
    lda.w 0x0000, y
    clc
    adc.b menu_dp.tilemap_offset
    tax
    iny
    iny
    sep #0x20
    bra _draw
draw_at:
"""
DrawMenuText ($01:82CD): X = tilemap offset ($29 added), Y = string - $8000. Carry clear: not a VWF string,
nothing touched.
"""
    jsr.w _claim
    bcs _draw_at
    rts
_draw_at:
    phk
    plb
    rep #0x20
    tya
    ora.w #0x8000
    tay
    sep #0x20
    bra _draw
copy_at:
"""CopyText ($01:8798): X = tilemap offset of the glyph row, Y = string - $8000. Carry clear: not a VWF string."""
    jsr.w _claim
    bcs _copy_at
    rts
_copy_at:
    phk
    plb
    rep #0x20
    tya
    ora.w #0x8000
    tay
    txa
    clc
    adc.b menu_dp.tilemap_offset
    sec
    sbc.w #_GLYPH_ROW
    tax
    sep #0x20
_draw:
    jsr.w _on_screen
    bcc _render
    sec
    rts
_render:
    phx
    phy
    jsr.w render.init
    rep #0x20
    lda.l vwf_cfg.tile_id_base
    jsr.w render_allocator.init_with_tile_id_wide
    sep #0x20
    ply
    plx
    jsr.w _start_line
_char_loop:
    lda.w 0x0000, y
    beq _done
    iny
    cmp #0x01
    beq _move_to
    cmp #0x03
    beq _column
    phx
    phy
    jsr.w render.display_char
    ply
    plx
    bra _char_loop
_move_to:
    jsr.w _pad
    rep #0x20
    lda.w 0x0000, y
    clc
    adc.b menu_dp.tilemap_offset
    tax
    iny
    iny
    sep #0x20
    jsr.w _fresh_tile
    jsr.w _start_line
    bra _char_loop
_column:
    jsr.w _pad
    lda.w 0x0000, y
    iny
    rep #0x20
    and.w #0x00FF
    asl
    clc
    adc.l menu_text_state.line_start
    tax
    sep #0x20
    jsr.w _fresh_tile
    jsr.w _begin_line
    bra _char_loop
_done:
    jsr.w _pad
    jsr.w _upload_once
    jsr.w render.deinit
    sec
    rts

draw_name:
"""
DrawCharName ($01:83B0): A = character id (non-zero), Y = tilemap offset. The name is copied out of RAM and drawn
in the tiles of its name index.
"""
    phb
    pha
    rep #0x20
    tya
    clc
    adc.b menu_dp.tilemap_offset
    tax
    sep #0x20
    pla
    phx
    dec
    rep #0x30
    and.w #0x003F
    tax
    lda.l _char_name_tbl, x
    and.w #0x00FF
    pha
    asl
    asl
    asl
    sta.l vwf_cfg.tile_id_base
    pla
    asl
    pha
    asl
    clc
    adc 1, s
    tax  ; name index * 6
    pla
    sep #0x20
    ldy.w #0x0000
_copy_name:
    lda.l _char_names, x
    phx
    tyx
    sta.l vwf_text_buffer, x
    plx
    inx
    iny
    cpy.w #_NAME_LENGTH
    bne _copy_name
    tyx
    lda.b #0x00
    sta.l vwf_text_buffer, x
    lda.b #_NAME_TILES
    sta.l vwf_cfg.slot_budget
    lda.b #_NAME_ATTRIBUTE
    sta.l vwf_cfg.flags
    jsr.w _check_name_cache
    lda.b #0x00
    sta.l menu_text_state.resident  ; a renamed character redraws in the same cell
    lda.b #vwf_text_buffer >> 16
    pha
    plb
    ldy.w #vwf_text_buffer & 0xFFFF
    plx
    jsr.w _draw
    plb
    rtl

tint_cells:
"""
The magic type highlight ($01:B418): A = palette attribute, X = cell offset in BG4's buffer ($7E:C600). Tints the
title's 7 cells (vanilla 5) but keeps their tile bits 8-9, or a small-VWF title would fall back onto the 8x8 font's
tiles. Returns like vanilla: X past the cells, Y = 0, A kept.
"""
    pha
    ldy.w #7
_tint_cell:
    lda.l 0x7EC601, x
    and.b #0x03
    ora 1, s
    sta.l 0x7EC601, x
    inx
    inx
    dey
    bne _tint_cell
    pla
    rtl

draw_spell:
"""
DrawMagicName ($01:B305): A = spell id, X = tilemap offset, $db = the cells' attribute (grey when the spell can't
be cast). The name takes tiles $100 + ((id - 1) mod 24) * 5, below the messages' $180-$1FF.
"""
    phb
    phy  ; the caller walks its spell list with Y
    pha
    rep #0x20
    txa
    clc
    adc.b menu_dp.tilemap_offset
    tax
    sep #0x20
    phx
    ldy.w #_SPELL_LENGTH
_paint_cells:
    lda.b #0xFF
    sta.l 0x7E0000, x
    sta.l 0x7E0040, x
    lda.b 0xDB
    sta.l 0x7E0001, x
    sta.l 0x7E0041, x
    inx
    inx
    dey
    bne _paint_cells
    lda 3, s  ; spell id, under the cell offset
    rep #0x20
    and.w #0x00FF
    pha
    asl
    asl
    asl
    adc 1, s  ; id * 9
    tax
    pla
    sep #0x20
    ldy.w #0x0000
_copy_spell:
    lda.l magic_names, x
    phx
    tyx
    sta.l vwf_text_buffer, x
    plx
    inx
    iny
    cpy.w #_SPELL_LENGTH
    bne _copy_spell
_trim_spell:
    dey
    bmi _trimmed
    tyx
    lda.l vwf_text_buffer, x
    cmp.b #0xFF
    bne _trimmed
    lda.b #0x00
    sta.l vwf_text_buffer, x
    bra _trim_spell
_trimmed:
    lda.b #0x00
    sta.l vwf_text_buffer + _SPELL_LENGTH
    lda 3, s
    dec
_school_index:
    cmp.b #_SCHOOL_SPELLS
    bcc _school_indexed
    sbc.b #_SCHOOL_SPELLS
    bra _school_index
_school_indexed:
    sta.b 0x45
    asl
    asl
    clc
    adc.b 0x45
    rep #0x20
    and.w #0x00FF
    sta.l vwf_cfg.tile_id_base
    sep #0x20
    lda.b #_SPELL_TILES
    sta.l vwf_cfg.slot_budget
    lda.b #0x01
    sta.l vwf_cfg.flags
    lda.b #0x00
    sta.l menu_text_state.resident
    lda.b #vwf_text_buffer >> 16
    pha
    plb
    ldy.w #vwf_text_buffer & 0xFFFF
    plx
    phx
    jsr.w _draw
    plx  ; X = the cell offset, as vanilla returns it
    pla
    ply
    plb
    rtl

draw_class:
"""DrawClassName's copy loop ($01:8FE3): X = offset in class_names, Y = tilemap address ($29 added)."""
    phb
    rep #0x20
    txa
    clc
    adc.w #class_names & 0xFFFF
    phy
    tay
    plx
    lda.w #_CLASS_TILE
    sta.l vwf_cfg.tile_id_base
    sep #0x20
    lda.b #_CLASS_TILES
    sta.l vwf_cfg.slot_budget
    lda.b #0x02
    sta.l vwf_cfg.flags
    lda.b #0x00
    sta.l menu_text_state.resident
    rep #0x20
    lda.w #class_names & 0xFFFF
    jsr.w _own_region
    sep #0x20
    lda.b #class_names >> 16
    pha
    plb
    jsr.w _draw
    plb
    rtl

_claim:
"""
Carry set when Y (string - $8000) lies in a block of `_blocks`: vwf_cfg then holds the string's first tile, its
attribute bits and the rest of the region to clear. Keeps A, X, Y.
"""
    php
    rep #0x30
    pha
    phx
    ldx.w #0x0000
_next_block:
    lda.l _blocks, x
    beq _unclaimed
    tya
    ora.w #0x8000
    cmp.l _blocks, x
    bcc _skip_block
    cmp.l _blocks + 2, x
    bcs _skip_block
    sec
    sbc.l _blocks, x
    clc
    adc.l _blocks + 4, x
    sta.l vwf_cfg.tile_id_base
    eor.w #0x00FF
    sep #0x20
    sta.l vwf_cfg.slot_budget
    lda.l _blocks + 6, x
    and.b #0x03
    sta.l vwf_cfg.flags
    lda.l _blocks + 6, x
    and.b #_RESIDENT_BIT
    sta.l menu_text_state.resident
    rep #0x20
    lda.l _blocks, x
    jsr.w _own_region
; The item description must not trust its cache: its tiles may be ours now.
    lda.w #0x0000
    sta.l render.last_drawn_text_ptr
    plx
    pla
    plp
    sec
    rts
_skip_block:
    txa
    clc
    adc.w #8
    tax
    bra _next_block
_unclaimed:
    plx
    pla
    plp
    clc
    rts

_blocks:
; first string, end, allocator id of the first tile, attribute bits (tile id bits 8-9)
    .dw newgame.new_game & 0xFFFF, newgame.strings_end & 0xFFFF, 0x80, 0x01
    .dw in_game_menu.cant_fight & 0xFFFF, in_game_menu.strings_end & 0xFFFF, 0x70, 0x03 | _RESIDENT_BIT
    .dw status.status & 0xFFFF, status.strings_end & 0xFFFF, 0x00, 0x02
    .dw equip.menu & 0xFFFF, equip.strings_end & 0xFFFF, 0x00, 0x02
    .dw items_menu.items_menu_right & 0xFFFF, items_menu.strings_end & 0xFFFF, 0x00, 0x02
    .dw spells.white & 0xFFFF, spells.kokan & 0xFFFF, 0x00, 0x02
    .dw treasure.header_window & 0xFFFF, treasure.exchange & 0xFFFF, 0xAA, 0x01
    .dw spells.kokan & 0xFFFF, spells.mp_needed & 0xFFFF, 0xD0, 0x01
    .dw use_spell.mp_cost & 0xFFFF, use_spell.strings_end & 0xFFFF, 0x40, 0x02
    .dw options.title & 0xFFFF, options.controls & 0xFFFF, 0x00, 0x02
    .dw options.controls & 0xFFFF, options.strings_end & 0xFFFF, 0x80, 0x01
    .dw dextrality.hands & 0xFFFF, dextrality.strings_end & 0xFFFF, 0xB8, 0x02
    .dw 0x0000

forget_uploads:
"""A new menu session (ingame/menu_vram.s save): VRAM $6000-$7FFF holds whatever the field left there."""
    php
    rep #0x30
    phx
    ldx.w #62
_forget:
    lda.w #0x0000
    sta.l menu_text_state.vram_bits, x
    dex
    dex
    bpl _forget
    sta.l menu_text_state.region_owner
    plx
    plp
    rts

_own_region:
"""A = the drawing block's key (16 bits, M = 16). A new owner of tiles $200-$2FF forgets their bits."""
    pha
    sep #0x20
    lda.l vwf_cfg.flags
    cmp.b #_SHARED_REGION
    rep #0x20
    bne _owned
    pla
    cmp.l menu_text_state.region_owner
    beq _owner_kept
    sta.l menu_text_state.region_owner
    phx
    ldx.w #30
_forget_region:
    lda.w #0x0000
    sta.l menu_text_state.vram_bits, x
    dex
    dex
    bpl _forget_region
    plx
_owner_kept:
    rts
_owned:
    pla
    rts

_check_name_cache:
"""The name in vwf_text_buffer against the one last uploaded for its tiles; a change clears its bit."""
    php
    rep #0x30
    phx
    phy
    lda.l vwf_cfg.tile_id_base
    lsr
    lsr
    lsr  ; name index
    pha
    asl
    clc
    adc 1, s
    asl  ; name index * 6
    tax
    pla
    ldy.w #0x0000
    sep #0x20
_compare_name:
    phx
    tyx
    lda.l vwf_text_buffer, x
    plx
    cmp.l menu_text_state.name_cache, x
    beq _same_char
    sta.l menu_text_state.name_cache, x
    jsr.w _clear_vram_bit
_same_char:
    inx
    iny
    cpy.w #_NAME_LENGTH
    bne _compare_name
    ply
    plx
    plp
    rts

_upload_once:
"""Upload the string's tiles unless it is already in VRAM (tiles $200-$3FF only)."""
    lda.l vwf_cfg.flags
    cmp.b #0x02
    bcs _tracked
    jmp.w _upload
_tracked:
    jsr.w _vram_bit
    and.l menu_text_state.vram_bits, x
    bne _in_vram
    jsr.w _upload
    jsr.w _vram_bit
    ora.l menu_text_state.vram_bits, x
    sta.l menu_text_state.vram_bits, x
_in_vram:
    rts

_clear_vram_bit:
"""Forget that the current string is in VRAM. Keeps X."""
    phx
    jsr.w _vram_bit
    eor.b #0xFF
    and.l menu_text_state.vram_bits, x
    sta.l menu_text_state.vram_bits, x
    plx
    rts

_vram_bit:
"""X = the byte of the current string's bit in menu_text_state.vram_bits, A = its mask (8 bits)."""
    php
    rep #0x20
    lda.l vwf_cfg.flags
    and.w #0x0003
    xba
    ora.l vwf_cfg.tile_id_base
    sec
    sbc.w #0x0200
    pha
    lsr
    lsr
    lsr
    tax
    pla
    and.w #0x0007
    plp
    phx
    tax
    lda.l _bit_masks, x
    plx
    rts
_bit_masks:
    .db 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80

_on_screen:
"""Carry set when the string is resident and the cell at X + _GLYPH_ROW already shows its first tile."""
    lda.l menu_text_state.resident
    beq _not_on_screen
    phx
    rep #0x20
    txa
    clc
    adc.w #_GLYPH_ROW
    tax
    sep #0x20
    lda.l 0x7E0000, x
    cmp.l vwf_cfg.tile_id_base
    bne _not_drawn
    lda.l 0x7E0001, x
    and.b #0x03
    cmp.l vwf_cfg.flags
    bne _not_drawn
    plx
    sec
    rts
_not_drawn:
    plx
_not_on_screen:
    clc
    rts

_fresh_tile:
"""The next glyph starts a tile of its own."""
    lda.b #0x08
    sta.b render.bits_left_on_tile
    jmp.w render_allocator.increment

_start_line:
"""A line from a position word: `col` counts from its cell X."""
    rep #0x20
    txa
    sta.l menu_text_state.line_start
    sep #0x20
_begin_line:
"""
Start a segment at tilemap offset X (its dakuten row); it ends where the 8x8 font would have ended it, at the
string's end, its next position word or its next `col`.
"""
    rep #0x20
    txa
    clc
    adc.w #_GLYPH_ROW
    sta.l render.tilemap_offset
    tax
    sep #0x20
    phy
_count:
    lda.w 0x0000, y
    beq _counted
    cmp #0x01
    beq _counted
    cmp #0x03
    beq _counted
    iny
    inx
    inx
    bra _count
_counted:
    rep #0x20
    txa
    sta.l vwf_cfg.tilemap_base
    sep #0x20
    ply
    rts

_pad:
"""
Blank the VWF cells between the text and the line's 8x8 end: a shorter text hides the longer one drawn
before. Cells without a VWF tile (attribute bits 0-1 clear) stay as they are, a narrowed window's outside too.
"""
    php
    phx
    rep #0x30
    lda.l render.tilemap_offset
    tax
    sep #0x20
    lda.b render.bits_left_on_tile
    cmp #0x08
    beq _pad_check  ; the current cell holds no pixel yet
    inx
    inx
_pad_check:
    rep #0x20
    txa
    cmp.l vwf_cfg.tilemap_base
    sep #0x20
    bcs _padded
    lda.l 0x7E0001, x
    bit.b #0x03
    beq _pad_next
    and.b #0xFC
    sta.l 0x7E0001, x
    lda.b #_BLANK_TILE
    sta.l 0x7E0000, x
_pad_next:
    inx
    inx
    bra _pad_check
_padded:
    plx
    plp
    rts

_upload:
"""DMA the string's tiles at the next vblank: buffer tile N goes to VRAM tile (attribute bits << 8) + N."""
    php
    phb
    sep #0x20
    lda.b #0x00
    pha
    plb
    rep #0x20
    pea.w _uploaded - 1
    lda.l vwf_cfg.tile_id_base
    asl
    asl
    asl
    asl
    clc
    adc.w #VWF_CHR_BUFFER & 0xFFFF
    pha
    pea.w VWF_CHR_BUFFER >> 16
    lda.l vwf_cfg.flags
    and.w #0x0003
    xba
    ora.l vwf_cfg.tile_id_base
    asl
    asl
    asl
    clc
    adc.w #0x4000 >> 1
    pha
    lda.l render_allocator.allocated_tile_id
    sec
    sbc.l vwf_cfg.tile_id_base
    inc
    asl
    asl
    asl
    asl
    pha
    pea.w 0x1801
    sep #0x20  ; wait_for_vblank reads $4212 alone
    jsr.w wait_for_vblank
    jmp.w dma_transfer_to_vram
_uploaded:
    plb
    plp
    rts
    }
}
