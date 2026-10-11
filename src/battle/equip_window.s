"""
Relocated battle equipped-items window transfer routine.

Pivots the per-character equip popup from `R-label  L-label / R-item  L-item` (two columns of stacked
label-over-item) to `R-label  R-item / L-label  L-item` (label and item on the same row, per hand).

Layout in the 32x7 window:
    Row 0: slot-1 label (8 tiles, cols 3-10)   | slot-1 item top (15 tiles, cols 11-25)
    Row 1: <blank>                             | slot-1 item bot
    Row 2: slot-2 label                        | slot-2 item top
    Row 3: <blank>                             | slot-2 item bot

Driven by:
    RLHand buf (40 bytes/char) : tile entries 0..9 = slot-1 label, 10..19 = slot-2 label
    EquipBuf   (120 bytes/char): bytes 0..$3B = slot-1 item (top 0..$1D, bot $1E..$3B)
                                 bytes $3C..$77 = slot-2 item ($3C..$59 top, $5A..$77 bot)

Tilemap dest bases (set by hooks in items_patches.s):
    $00 = $D1EE (label column: the inventory's name column, right of the cursor)
    $02 = $D1FE (item column, $00 + $10, the cursor left of it; its ":" column follows the inventory row format)

The labels and item names are VWF glyphs, rendered when the popup opens into the command list's tiles: the inventory
under the popup holds the item tiles, and the command window is hidden while it shows. The command list re-renders
once the popup closes (CMD_DIRTY_BIT, and `equip_popup_closed`'s signal).
"""


.import "battle/inventory_rolling_patches"
.import "battle/inventory_rolling"
.import "battle/redraw_gates"
.import "wram_layout"


.include "../bank20.i"
.import "vanilla"
.include "src/battle/bank02_trampolines.i"
; root-scope extern: battle/tasks_patches imports this module's importers
.extern signal_commands

.alloc _battle_equip_window_block in bank20_reloc {
    _HAND_ITEMS := 0x16FECB  ; per character: each hand's item entry (flags, id, quantity), 4 bytes a hand
    _EQUIP_TEXT := 0x16FEC1  ; per character: EquipBuf, 60 bytes a hand
    _HAND_LABEL_TEXT := 0x16FF25  ; per character: the label cells, 10 a hand
    _HAND_LABELS := 0x16FED5  ; battle/graphics_patches.s: 2 labels of 10 characters per handedness
    _PARTY_RECORDS := 0x7E2000  ; $80 a character, +0 bits 6-7: handedness
    _FORMAT := 0x9E66  ; battle/inventory_rolling.s inv_format_buffer: build_item_format writes there
    _ITEM_STRIDE := 0x3C  ; one hand's EquipBuf rows: two rows of 15 cells
    _ITEM_TILES := 0x90  ; the command list's tiles: 12 for each item name, then 8 for each label
    _ITEM_TILE_COUNT := 12
    _LABEL_TILES := _ITEM_TILES + 2 * _ITEM_TILE_COUNT
    _LABEL_TILE_COUNT := 8
    _LABEL_CELLS := 10
    _LABELS_PER_HANDEDNESS := 2 * _LABEL_CELLS
    _TEXT_CELLS := 15  ; DrawText's row length for both: an item's EquipBuf rows, the label scratch rows
    _SPACE := 0xFF
    _VWF_ON := 0xFE  ; draw_inventory_text: fixed tiles <-> VWF

_render_popup_text:
"""
Render the selected character's hand labels and item names in the VWF while the popup shows, unless its glyphs
already show them. Keeps the caller's DrawText parameters and direct page $00-$07.
"""
    php
    phb
    sep #0x20
    rep #0x10
    lda.b #0x7E
    pha
    plb
    rep #0x20
    lda.w 0xEF54
    pha
    lda.w 0xEF52
    pha
    lda.w 0xEF50
    pha
    lda.b 0x00
    pha
    lda.b 0x02
    pha
    lda.b 0x04
    pha
    lda.b 0x06
    pha
    sep #0x20
    lda.l btlgfx_dp.menu_windows_open
    and.b #0x08  ; only while the popup shows: the command window has the tiles otherwise
    beq _rpt_done
    jsr.w _popup_key_changed
    bcc _rpt_done
    lda.b #0x00
    jsr.w _render_hand
    lda.b #0x01
    jsr.w _render_hand
    jsr.l battle_flags.clear_vwf_render
    lda.l battle_render_state.pending_transfer_mask
    ora.b #battle_render.CHR_REGION_COMMANDS | battle_render.CHR_PENDING
    sta.l battle_render_state.pending_transfer_mask
    lda.l battle_menu_dirty  ; the command list re-renders its tiles once the popup closes
    ora.b #CMD_DIRTY_BIT
    sta.l battle_menu_dirty
_rpt_done:
    rep #0x20
    pla
    sta.b 0x06
    pla
    sta.b 0x04
    pla
    sta.b 0x02
    pla
    sta.b 0x00
    pla
    sta.w 0xEF50
    pla
    sta.w 0xEF52
    pla
    sta.w 0xEF54
    plb
    plp
    rts

_popup_key_changed:
"""Carry set when the character or a hand's item differs from `equip_popup_key`, which takes the new values."""
    jsr.w _char_x2
    rep #0x20
    lda.l _HAND_ITEMS, x
    tax
    sep #0x20
    clc
    lda.l battle_selected_char
    cmp.w equip_popup_key
    beq _pkc_char
    sec
_pkc_char:
    sta.w equip_popup_key
    ldy.w #0x0000
_pkc_byte:
    lda.w 0x0000, x  ; flags, id, quantity
    cmp.w equip_popup_key + 1, y
    beq _pkc_same
    sec
_pkc_same:
    sta.w equip_popup_key + 1, y
    inx
    iny
    cpy.w #0x0003
    bne _pkc_next
    inx  ; past the entry's 4th byte
_pkc_next:
    cpy.w #EQUIP_POPUP_KEY_SIZE - 1
    bne _pkc_byte
    rts

_char_x2:
"""X = the selected character * 2 (A8 X16)."""
    rep #0x20
    lda.l battle_selected_char
    and.w #0x00FF
    asl
    tax
    sep #0x20
    rts

_render_hand:
"""Hand A8 (0, 1): its item name into its EquipBuf rows, then its label (`_render_label`)."""
    pha
    jsr.w _char_x2
    rep #0x20
    lda.l _EQUIP_TEXT, x
    sta.w 0xEF52
    lda.l _HAND_ITEMS, x
    tax
    sep #0x20
    lda 1, s
    beq _rh_entry
    inx
    inx
    inx
    inx
    rep #0x20
    lda.w 0xEF52
    clc
    adc.w #_ITEM_STRIDE
    sta.w 0xEF52
    sep #0x20
_rh_entry:
    stz.w 0xEF55  ; white
    lda.w 0x0001, x
    beq _rh_empty
    sta.b 0x02
    lda.w 0x0002, x
    sta.b 0x03
    lda.w 0x0000, x
    and.b #0x80  ; unusable: grey
    beq _rh_palette
    lda.b #0x04
_rh_palette:
    sta.b 0x00
    sta.b 0x01
    ldx.w #_FORMAT
    stx.w 0xEF50
    lda.b #_TEXT_CELLS
    sta.w 0xEF54
    jsr.l build_item_format_far
    lda 1, s
    beq _rh_item_tiles
    lda.b #_ITEM_TILE_COUNT
_rh_item_tiles:
    clc
    adc.b #_ITEM_TILES
    ldy.w #_ITEM_TILE_COUNT
    jsr.l messages_vwf.draw_inventory_text_at
    bra _rh_label
_rh_empty:
    rep #0x20
    ldx.w 0xEF52
    ldy.w #_ITEM_STRIDE / 2
    lda.w #0x00FF  ; a blank cell
_rh_blank:
    sta.w 0x0000, x
    inx
    inx
    dey
    bne _rh_blank
    sep #0x20
_rh_label:
    pla
    jmp.w _render_label

_render_label:
"""
Hand A8's label ("Droite", "Principale", ...: the character's handedness picks the pair) in the VWF, its glyph row
copied into the hand's label cells.
"""
    pha
    jsr.w _char_x2
    rep #0x20
    txa
    asl
    asl
    asl
    asl
    asl
    asl  ; character * $80
    tax
    sep #0x20
    lda.l _PARTY_RECORDS, x
    rep #0x20
    and.w #0x00C0
    lsr
    lsr
    lsr
    lsr
    lsr
    lsr  ; handedness 0-3
    sta.b 0x00
    asl
    asl
    sta.b 0x02  ; * 4
    asl
    asl
    clc
    adc.b 0x02  ; * 20
    sta.b 0x02
    sep #0x20
    lda 1, s
    beq _rl_first
    rep #0x20
    lda.b 0x02
    clc
    adc.w #_LABEL_CELLS
    sta.b 0x02
    sep #0x20
_rl_first:
    ldx.b 0x02
    ldy.w #0x0000
    lda.b #_VWF_ON
    sta.w _FORMAT, y
    iny
_rl_char:
    lda.l _HAND_LABELS, x
    cmp.b #_SPACE  ; the labels are space-padded
    beq _rl_end
    sta.w _FORMAT, y
    inx
    iny
    cpy.w #_LABEL_CELLS + 1
    bne _rl_char
_rl_end:
    lda.b #0x00
    sta.w _FORMAT, y
    ldx.w #_FORMAT
    stx.w 0xEF50
    ldx.w #equip_label_text
    stx.w 0xEF52
    lda.b #_TEXT_CELLS
    sta.w 0xEF54
    stz.w 0xEF55
    lda 1, s
    beq _rl_tiles
    lda.b #_LABEL_TILE_COUNT
_rl_tiles:
    clc
    adc.b #_LABEL_TILES
    ldy.w #_LABEL_TILE_COUNT
    jsr.l messages_vwf.draw_inventory_text_at
; the glyph row (the second) into the hand's label cells
    jsr.w _char_x2
    rep #0x20
    lda.l _HAND_LABEL_TEXT, x
    sta.b 0x00
    sep #0x20
    lda 1, s
    beq _rl_dest
    rep #0x20
    lda.b 0x00
    clc
    adc.w #_LABEL_CELLS * 2
    sta.b 0x00
    sep #0x20
_rl_dest:
    rep #0x20
    ldx.w #_TEXT_CELLS * 2  ; the second row
    ldy.w #0x0000
_rl_copy:
    lda.w equip_label_text, x
    sta (0x00), y
    inx
    inx
    iny
    iny
    cpy.w #_LABEL_CELLS * 2
    bne _rl_copy
    sep #0x20
    pla
    rts

equip_popup_opened:
"""
The equip popup opens ($4A bit 3 just set): render its glyphs (the command list had the tiles) and transfer its
window again. Callable with JSL; keeps direct page $00-$03.
"""
    php
    rep #0x20
    lda.b 0x00
    pha
    lda.b 0x02
    pha
    sep #0x20
    lda.b #0xFF
    sta.l equip_popup_key  ; no character: render
    jsr.l tfr_equip_window_new
    rep #0x20
    pla
    sta.b 0x02
    pla
    sta.b 0x00
    plp
    rtl

equip_popup_closed:
"""The equip popup closed: the command list takes its tiles back (CMD_DIRTY_BIT is set). Callable with JSL."""
    jsr.l signal_commands
    rtl

tfr_equip_window_new:
"""
    Relocated replacement for vanilla `TfrEquipWindow` at $02:97A6.

    Walks 6 per-block transfer passes: slot-1 / slot-2 labels into the
    left column (rows 1 and 3), slot-1 / slot-2 item top+bot halves into
    the right column (rows 0-1 and 2-3 respectively). Caller is the
    bank-02 trampoline that JSLs here  ; return via RTL.
"""


    {
    rep #0x10  ; X/Y 16-bit at runtime (caller may have X=1)
    jsr.w _render_popup_text
    ldx.w #0xD1EE
    stx 0x00
    ldx.w #0xD1FE
    stx 0x02
    lda.w battle_selected_char
    asl
    tax
    rep #0x20
    lda.l 0x16FEC1, x  ; EquipTextBufPtrs
    pha
    lda.l 0x16FF25, x  ; RLHandTextBufPtrs
    tax
    sep #0x20

; --- Pass A: slot-1 label -> LEFT col row 1 (buf[0..$0F]: its 8 glyph cells of 10) ---
    ldy.w #0x0040
loop_a:
    lda.w 0x0000, x
    sta (0x00), y
    inx
    iny
    cpy.w #0x0050
    bne loop_a

; --- Pass B: slot-2 label -> LEFT col row 3 (buf[$14..$23]) ---
    inx
    inx
    inx
    inx
    ldy.w #0x00C0
loop_b:
    lda.w 0x0000, x
    sta (0x00), y
    inx
    iny
    cpy.w #0x00D0
    bne loop_b

; --- Switch to EquipBuf ---
    plx

; --- Pass C: slot-1 item top -> RIGHT col row 0 (buf[0..$1D]) ---
    ldy.w #0x0000
loop_c:
    lda.w 0x0000, x
    sta (0x02), y
    inx
    iny
    cpy.w #0x001E
    bne loop_c

; --- Pass D: slot-1 item bot -> RIGHT col row 1 (buf[$1E..$3B]) ---
    ldy.w #0x0040
loop_d:
    lda.w 0x0000, x
    sta (0x02), y
    inx
    iny
    cpy.w #0x005E
    bne loop_d

; --- Pass E: slot-2 item top -> RIGHT col row 2 (buf[$3C..$59]) ---
    ldy.w #0x0080
loop_e:
    lda.w 0x0000, x
    sta (0x02), y
    inx
    iny
    cpy.w #0x009E
    bne loop_e

; --- Pass F: slot-2 item bot -> RIGHT col row 3 (buf[$5A..$77]) ---
    ldy.w #0x00C0
loop_f:
    lda.w 0x0000, x
    sta (0x02), y
    inx
    iny
    cpy.w #0x00DE
    bne loop_f

; --- Trigger tilemap upload (window 7, 2 transfers) ---
    lda #0x07
    ldy.w #0x0002
    jsr.l load_menu_tfr_data_trampoline
    lda #0x01
    sta.w menu_tilemap_tfr_count
    sta.w menu_tilemap_tfr_enable
    rtl
    }
}

.alloc _battle_equip_popup_bank02 in bank02_trampolines {
equip_popup_open_edge:
"""Vanilla's popup open (B3E): set the window bit, then drop the popup's cached glyph key."""
    lda.b #0x08
    tsb.b 0x4A
    jsr.l equip_popup_opened
    rts

equip_popup_close_edge:
"""Vanilla's popup close (B4D): its first instruction, then the command list's redraw signal."""
    stz.w 0xEF74
    jsr.l equip_popup_closed
    rts
}

.alloc at 0x02AB3E {
    jsr.w equip_popup_open_edge
    nop
}

.alloc at 0x02AB4D {
    jsr.w equip_popup_close_edge
}

; The popup stacks the hands, one row each (layout above), where vanilla put them side by side: its cursor handler
; ($0B, $02:B302) moved between them with LEFT/RIGHT. Now UP/DOWN do, DOWN from the lower hand goes back to the item
; list (vanilla's DOWN), and LEFT/RIGHT do nothing.
_POPUP_CURSOR_X := 12 * 8 - 16  ; on the item: left of its symbol (screen column 12)
.label _popup_close = 0x02B32F  ; back to the item list
.label _popup_none = 0x02B33E
.label _popup_cursor = 0x02B341

.alloc at 0x02B305 size 0x2A {
    lda.b 0x38
    and.b #0x0F
    cmp.b #0x04  ; DOWN
    bne _popup_up
    lda.b 0x5F  ; the hand
    bne _popup_leave
    inc.b 0x5F
    inc.b 0x63
    bra _popup_cursor
_popup_up:
    cmp.b #0x08  ; UP
    bne _popup_none
    lda.b 0x5F
    beq _popup_none
    dec.b 0x5F
    dec.b 0x63
    bra _popup_cursor
_popup_leave:
    dec.b 0x5F  ; the item list's cursor reads it too: back to the first hand, as vanilla's RIGHT-out does
    dec.b 0x63
    .for pad := 0, 6 {
    nop
    }
}

.alloc at 0x02B341 size 17 {
    ldx.w #_POPUP_CURSOR_X
    stx.w 0xEF6B  ; menu cursor 1 x
    lda.b 0x5F
    tax
    lda.l equip_popup_cursor_y, x
    tax
    stx.w 0xEF6D  ; menu cursor 1 y
}

.alloc _equip_popup_cursor in bank20_reloc {
equip_popup_cursor_y:
"""The popup cursor's y per hand: the label rows."""
    .db 0x9E, 0x9E + 12  ; 12 px apart, as the item list's rows
}
