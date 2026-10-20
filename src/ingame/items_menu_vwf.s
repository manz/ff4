"""
Field-menu item-name VWF renderer, replacing vanilla `DrawEquipItemName` / `DrawItemName` ($01:9013 / $01:9060).

The slot keeps its two tilemap rows: the top row ($29) is blank $FF tiles, the bottom row ($29+$40) holds the
8px-tall VWF name.

Entry: A = item id, Y = tilemap byte offset (16-bit), $29 = top-row tilemap pointer (bank $7E),
       $5D = slot index, $DB = palette/attr byte.
Exit:  X = `items_unleashed` offset of the last byte consumed.
Each slot owns FIELD_ITEM_VWF_TILE_BUDGET (10) tile ids from FIELD_ITEM_VWF_TILE_BASE + slot * budget.
"""


.import "core/items"
.import "core/bank20_helpers"
.import "small_vwf/baked_names"
.import "core/vwf_ram"
.include "core/bank20.i"
.include "battle/inventory_budget.i"

.include "core/libmz.i"
.include "core/vwf_state.i"

.import "core/assets"
.import "small_vwf/init"
.import "core/libmz"
.import "core/vanilla"


.alloc _items_menu_vwf_block in bank20_reloc {
    .scope items_menu_vwf {
    """
    VWF item-name slots for the field menu, treasure, drops, equip and key-item picker.
    """
draw_field_item_name:
"""
    Fills `vwf_cfg`, blanks the top row, writes the symbol to the bottom row, then copies the baked name tiles.
"""


        sta.b 0x43  ; item id
        php
        sep #0x20
        rep #0x10
; Y must come back unchanged: the caller `DrawItemSlot` positions the colon glyph from it.
        phy
; tile_id_base = FIELD base + slot * 10, stored 16-bit: the base is $100, so bit 8 must survive.
        rep #0x20
        lda.b menu_dp.item_slot
        and.w #0x00FF
        pha
        asl
        asl
        asl  ; * 8
        clc
        adc 0x01, s  ; + slot = * 9
        clc
        adc 0x01, s  ; + slot = * 10
        clc
        adc.w #FIELD_ITEM_VWF_TILE_BASE
        sta.l vwf_cfg.tile_id_base  ; word
        pla  ; balance
        sep #0x20
        lda.b #FIELD_ITEM_VWF_TILE_BUDGET
        sta.l vwf_cfg.slot_budget
; Flush descriptor: primary (treasure / field items) or secondary (drops, equip, key items), picked by
; vwf_engine.caller_ctx. Exact matches only, so a garbage ctx from an old savestate falls back to primary.
        sep #0x20
        lda.l vwf_engine.caller_ctx
        cmp.b #VWF_CTX_DROPS
        beq _write_secondary_desc
        cmp.b #VWF_CTX_EQUIP
        beq _write_secondary_desc
        cmp.b #VWF_CTX_KEY_ITEM
        beq _write_key_item_desc
        rep #0x20
; --- Primary descriptor (treasure / field-items / default) ---
        lda.w #FIELD_VWF_VRAM_DEST_WORD
        sta.l vwf_cfg.chr_vram_word
        lda.w #FIELD_VWF_PRIMARY_BYTE_COUNT
        sta.l vwf_cfg.chr_byte_count
        bra _desc_done

_write_secondary_desc:
; --- Secondary descriptor (drops in treasure popup) ---
        rep #0x20
        lda.w #DROPS_VWF_VRAM_DEST_WORD
        sta.l vwf_engine.flush_b.vram_word
        lda.w #DROPS_VWF_BYTE_COUNT
        sta.l vwf_engine.flush_b.byte_count
        lda.w #DROPS_VWF_CHR_SRC_OFFSET
        sta.l vwf_engine.flush_b.src_offset
        bra _desc_done

_write_key_item_desc:
; --- Key-item picker (BG3 CHR $6800, the dialogue VWF window) ---
; Shares the secondary slot: the picker never coexists with the treasure popup.
        rep #0x20
        lda.w #KEY_ITEM_VWF_VRAM_DEST_WORD
        sta.l vwf_engine.flush_b.vram_word
        lda.w #KEY_ITEM_VWF_BYTE_COUNT
        sta.l vwf_engine.flush_b.byte_count
        lda.w #KEY_ITEM_VWF_CHR_SRC_OFFSET
        sta.l vwf_engine.flush_b.src_offset

_desc_done:
        sep #0x20
; Attr OR mask: $01 = tile_id bit 8 (ids are $100..$169). The picker over the field map also needs
; priority ($20) or the glyphs fall behind the map.
        lda.l vwf_engine.caller_ctx
        cmp.b #VWF_CTX_KEY_ITEM
        beq _flags_key_item
        lda.b #0x01
        bra _flags_store

_flags_key_item:
        lda.b #0x21

_flags_store:
        sta.l vwf_cfg.flags
; vwf_cfg.tilemap_base = $29 + $40 + Y + 2 (past the symbol cell). Y is 16-bit: slot 2's Y is $0144.
        rep #0x20
        tya
        clc
        adc.b menu_dp.tilemap_offset
        clc
        adc.w #0x0042  ; + $40 (next row) + $02 (past symbol)
        sta.l vwf_cfg.tilemap_base
        sep #0x20
; Top row: $FF tile + palette across the slot width.
        phy
        jsr.w _top_row_cells

_top_loop:
        lda.b #0xFF
        sta.b (menu_dp.tilemap_offset), y
        iny
        lda.b menu_dp.item_usable
        ora.b menu_dp.window_attr
        sta.b (menu_dp.tilemap_offset), y
        iny
        dex
        bne _top_loop
; Bottom row: blank first so cells past a shorter name don't show the previous name's tiles.
        rep #0x20
        pla
        clc
        adc.w #0x0040
        tay
        sep #0x20
        phy  ; bottom-row start, so the restore below ignores the run length
; Blank only symbol + tile budget cells (widest name is 75px = 10 tiles). The shop draws the price to the
; right BEFORE the name, so blanking all 17 cells would eat a 4-digit price.
        ldx.w #( 1 + FIELD_ITEM_VWF_TILE_BUDGET )

_bottom_blank_loop:
        lda.b #0xFF
        sta.b (menu_dp.tilemap_offset), y
        iny
        lda.b menu_dp.item_usable
        ora.b menu_dp.window_attr
        sta.b (menu_dp.tilemap_offset), y
        iny
        dex
        bne _bottom_blank_loop
        ply
; Back to Y_orig (bottom-row start - $40), then symbol + palette into the bottom row's first cell.
        rep #0x20
        tya
        sec
        sbc.w #0x0040
        tay
        lda.b menu_dp.tilemap_offset
        clc
        adc.w #0x0040
        sta.b 0x1D
        sep #0x20
; the name's symbol byte, first in its items_unleashed string
        lda.b 0x43
        jsr.l item_name_offset
        tax
        lda.l items_unleashed, x
        sta (0x1D), y  ; bottom-row symbol tile
        iny
        lda.b menu_dp.item_usable
        ora.b menu_dp.window_attr
        sta (0x1D), y  ; bottom-row symbol palette
        iny
        jsr.w _baked_item_name
; Drops also raise the secondary dirty flag. The primary flag stays set: treasure drew its slots earlier
; this frame and clearing it would skip that flush.
        sep #0x20
        lda.l vwf_engine.caller_ctx
        beq _dirty_done
        cmp.b #VWF_CTX_KEY_ITEM
        beq _dirty_key_item
        cmp.b #VWF_CTX_EQUIP
        beq _dirty_key_item
        cmp.b #VWF_CTX_DROPS
        bne _dirty_done
        lda.b #0x01
        sta.l vwf_engine.flush_b.dirty
        bra _dirty_done

_dirty_key_item:
; Picker and equip use the secondary flush only; the primary dirty flag must be cleared. Its target ($2800)
; is the BG3 tilemap on the field map, and equip keeps other data at $5000.
        lda.b #0x01
        sta.l vwf_engine.flush_b.dirty
        lda.b #0x00
        sta.l vwf_engine.chr_dirty

_dirty_done:
        ply
        plp
        rtl

_top_row_cells:
; X = top-row cells: the full slot, or EQUIP_NAME_CELLS (equip names start too far right for 17).
        ldx.w #( 1 + ITEM_UNLEASHED_TEXT_SIZE )
        lda.l vwf_engine.caller_ctx
        cmp.b #VWF_CTX_EQUIP
        bne _row_cells_done
        ldx.w #EQUIP_NAME_CELLS

_row_cells_done:
        rts

draw_equip_item_name:
"""
    `DrawEquipItemName` ($01:9013) replacement.

    Entry: Y = equipment offset in the record at ($60) ($30..$35), X = slot tilemap offset, $29 = BG2 buffer.
    Uses the drops tile region (slots 11..16) so it coexists with the inventory list.
    Preserves Y, $5D and vwf_engine.caller_ctx.
"""


        php
        sep #0x20
        rep #0x10
        phy
        lda.b menu_dp.item_slot
        pha
        lda.l vwf_engine.caller_ctx
        pha
        tya
        sec
        sbc.b #0x30
        clc
        adc.b #DROPS_VWF_TILE_SLOT_OFFSET
        sta.b menu_dp.item_slot
        lda.b #VWF_CTX_EQUIP
        sta.l vwf_engine.caller_ctx
        lda (0x60), y
        txy
        jsr.l draw_field_item_name
        pla
        sta.l vwf_engine.caller_ctx
        pla
        sta.b menu_dp.item_slot
        ply
        plp
        rtl

_baked_item_name:
"""
Copies item $43's baked tiles to the CHR buffer at vwf_cfg.tile_id_base, pads the budget with paper, writes the
tile ids from vwf_cfg.tilemap_base (attr ORed with vwf_cfg.flags) and raises chr_dirty.
"""
        php
        rep #0x30
        phy
        lda.b 0x43
        and.w #0x00FF
        asl
        asl
        tax
        lda.l item_names_vwf_tbl + 2, x
        and.w #0x00FF
        pha  ; 3,s tiles
        lda.l item_names_vwf_tbl, x
        pha  ; 1,s offset in the blob
        lda.l vwf_cfg.tile_id_base
        asl
        asl
        asl
        asl
        tay  ; CHR buffer offset
        lda 3, s
        asl
        asl
        asl  ; words to copy
        beq _paper
        plx
        pha
_copy_tiles:
        lda.l item_names_vwf, x
        phx
        tyx
        sta.l VWF_CHR_BUFFER, x
        plx
        inx
        inx
        iny
        iny
        lda 1, s
        dec
        sta 1, s
        bne _copy_tiles
        pla
        pha  ; keep the frame: 1,s spare, 3,s tiles
_paper:
        sep #0x20
        lda.l vwf_cfg.slot_budget
        sec
        sbc 3, s
        beq _cells
        rep #0x20
        and.w #0x00FF
        asl
        asl
        asl  ; words of paper
        tax
_paper_word:
        lda.w #0x00FF  ; plane 0 set, plane 1 clear: colour 1
        phx
        tyx
        sta.l VWF_CHR_BUFFER, x
        plx
        iny
        iny
        dex
        bne _paper_word
_cells:
        rep #0x30
        lda.l vwf_cfg.tilemap_base
        tax
        lda 3, s
        tay  ; cells to write
        beq _cells_done
        sep #0x20
        lda.l vwf_cfg.tile_id_base
_cell:
        sta.l 0x7E0000, x
        xba
        lda.l 0x7E0001, x
        ora.l vwf_cfg.flags
        sta.l 0x7E0001, x
        xba
        inc
        inx
        inx
        dey
        bne _cell
_cells_done:
        sep #0x20
        lda.b #0x01
        sta.l vwf_engine.chr_dirty
        rep #0x30
        pla
        pla
        ply
        plp
        rts

render_with_config_trampoline:
"""
    Long-call entry to `render.render_with_config`.
"""


        jsr.w render.render_with_config
        rtl
    }
}
