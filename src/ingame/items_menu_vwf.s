"""
Field-menu item-name VWF renderer.

Replaces vanilla `DrawItemName` / `DrawEquipItemName` at $01:9013 /
$01:9060. The vanilla routine wrote 16-pixel-tall fixed-font tile
ids across two tilemap rows ($29) (dakuten / top half) and
($1D = $29 + $40) (kana / bottom half). We keep the 16-pixel-tall
slot layout but render the name as 8-pixel-tall variable-width
glyphs in the BOTTOM tile row only  ; the TOP row is filled with
blank ($FF) tiles + the menu palette byte ($DB) so the slot still
takes two tilemap rows of vertical space.

Inputs (caller convention preserved):
  A   = item id (8-bit), set by either entry point.
  Y   = tilemap byte offset within the row (set by the rolling
        engine before each row render).
  $29 = top-row tilemap pointer (16-bit, in WRAM bank $7E).
  $5D = slot index 0..N-1 (set by `_menu_render_item_to_slot` in
        `src/ingame/inventory_rolling.s` before each per-row call).
  $DB = palette / attribute byte for fixed cells.

Outputs:
  Top row at ($29),y..($29),y+31     filled with $FF + ($DB|$34).
  Bottom row at ($29+$40),y..        filled with VWF glyphs +
                                     palette via small_vwf.
  X   = `items_unleashed` offset for the last byte consumed.

Tile-id allocation:
  Each visible slot owns ITEM_VWF_TILE_BUDGET (=10) tile ids
  starting at ITEM_VWF_TILE_BASE + slot * budget, same scheme the
  battle inventory uses. The render_allocator clamp at
  slot_limit_low keeps overflow contained to the slot.

Status:
  Wiring scaffold. The bank-20 entry point is in place and the
  $01:9013 / $01:9060 hooks JSL into it, but the body still falls
  back to the fixed-font path so the visible output matches what
  vanilla DrawItemName produced before the switch. Subsequent
  phases will swap the loop body to `small_vwf.render.display_char`
  + per-slot CHR clear + top-row blanking.
"""


.import "items"
.import "small_vwf/baked_names"
.import "vwf_ram"
.include "../bank20.i"
.include "src/battle/inventory_budget.i"

.include "src/libmz.i"
.include "src/vwf_state.i"

.import "assets"
.import "small_vwf/init"
.import "libmz"
.import "vanilla"


.alloc _items_menu_vwf_block in bank20_reloc {
    .scope items_menu_vwf {
    """
    VWF render path for field-menu / treasure / drops item-name slots.
    Hijacks vanilla `DrawItemName` ($01:9060) to populate `vwf_cfg`
    and dispatch through `render.render_with_config`, so
    the patched menu chrome keeps the slot layout while the glyphs go
    through the variable-width font engine.
    """
draw_field_item_name:
"""
    Bank-20 field-menu item-name render driven by `vwf_cfg`.

    Stages the item name in `vwf_text_buffer` with a $00 terminator,
    fills `vwf_cfg` with per-slot tile budget + tilemap dest,
    fills the top tilemap row with $FF blanks (so the 16-pixel-tall
    slot keeps its height), writes the items_unleashed symbol byte
    + palette to the bottom row's first tile, then calls the unified
    `render.render_with_config` to blit the rest. Field uses K=5
    tiles/slot (FIELD_ITEM_VWF_TILE_BUDGET) so 11 slots fit inside the
    $C0..$F6 tile-id window.
"""


    sta.b 0x43  ; item id
    php
    sep #0x20
    rep #0x10
; Preserve caller's Y. Vanilla `DrawEquipItemName` (`$01:9013`) and
; `DrawItemName` (`$01:9060`) each phy at entry and ply before rts ;
; the caller `DrawItemSlot` continues with `tya ; adc #$60 ; tay`
; to position the colon glyph, so Y must come back unchanged.
    phy
; --- X = item id * ITEM_UNLEASHED_RECORD_SIZE (inline mul-by-17) ---
    rep #0x20
    lda.b 0x43
    and.w #0x00FF
    pha
    asl
    asl
    asl
    asl  ; * 16
    clc
    adc 0x01, s  ; + id = * 17
    tax
    pla
    sep #0x20
; --- Copy items_unleashed name bytes into vwf_text_buffer, terminate $00 ---
; Byte 0 of the record is the symbol (rendered separately as fixed
; tile below) ; bytes 1..ITEM_UNLEASHED_TEXT_SIZE go into the buffer.
; X is the destination index (only abs,x works with sta.l) ; the
; source offset rides in long SRAM scratch `vwf_engine.src_offset` so we
; do not steal a direct-page byte from vanilla's menu loop (the
; original placement on DP $45 clashed with the items code's row
; counter and broke the per-slot copy).
    rep #0x20
    txa
    inc  ; skip symbol byte
    sta.l vwf_engine.src_offset
    sep #0x20
    ldx.w #0x0000

_copy_loop:
    phx
    rep #0x20
    lda.l vwf_engine.src_offset
    tax
    sep #0x20
    lda.l items_unleashed, x
    pha  ; save the byte so the 16-bit src-pointer update does not clobber it
    inx
    rep #0x20
    txa
    sta.l vwf_engine.src_offset
    sep #0x20
    pla
    plx
    sta.l vwf_text_buffer, x
    inx
    cpx.w #ITEM_UNLEASHED_TEXT_SIZE
    bne _copy_loop
    lda.b #0x00
    sta.l vwf_text_buffer, x  ; null terminator
; --- Populate vwf_cfg.tile_id_base = FIELD base + $5D * K ---
; K = FIELD_ITEM_VWF_TILE_BUDGET (=10). slot * 10 = slot*8 + slot*2.
; Store the full 16-bit value: slots 6..10 produce tile_id_base
; $C0 + 10*K = $C0 + 100 = $124 which the 8-bit allocator wrapped
; back into the menu font CHR range. The wide init keeps tile_id
; bit 8 (which `tilemap_write_no_inc` ORs in via $01 on the high
; tilemap byte) intact.
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
; CHR -> VRAM flush descriptor. Menu PPU runs in Mode 0
; (BGMODE = $00 at `ff4decomp/menu/menu.asm:3878`) with BG34NBA = $22
; -> BG3 CHR at VRAM word $2000 (byte $4000). Two descriptors live in
; SRAM so the NMI flush can DMA treasure (primary) and drops (secondary)
; in disjoint slices without one panel's range trampling the other's
; through a single combined DMA. vwf_engine.caller_ctx (set by drops_rolling
; around its vanilla JSR chain) picks which descriptor this call's
; flush targets ; tile_id_base / slot_budget / tilemap_base / flags
; stay primary regardless since they are per-call render inputs, not
; per-region flush params.
; Tight `== 1` check so stale SRAM from old savestates (or any future
; CTX value not yet defined) falls back to the primary path instead
; of misrouting to drops. Without this, savestates captured before
; the secondary descriptor existed carried random bytes at
; vwf_engine.caller_ctx and any non-zero value sent the very first render
; into the drops branch on the wrong inventory.
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
; Shares the secondary slot: the picker is an event-script overlay
; on the field map and never coexists with the treasure popup.
    rep #0x20
    lda.w #KEY_ITEM_VWF_VRAM_DEST_WORD
    sta.l vwf_engine.flush_b.vram_word
    lda.w #KEY_ITEM_VWF_BYTE_COUNT
    sta.l vwf_engine.flush_b.byte_count
    lda.w #KEY_ITEM_VWF_CHR_SRC_OFFSET
    sta.l vwf_engine.flush_b.src_offset

_desc_done:
    sep #0x20
; Tilemap attr OR mask. Field VWF tile_ids live in the 9-bit
; window ($100..$169) so bit 0 of the attr byte (= tile_id bit 8)
; must be set ; the allocator stores $0100+, the tilemap entry
; writes the low byte to the tile_id slot and ORs `$01` into the
; attr byte to give the PPU the full 9-bit tile_id.
; The picker overlays the field map, where the window body carries
; the priority bit ($20) ; without it the glyph cells fall behind
; the map tiles the window is drawn over.
    lda.l vwf_engine.caller_ctx
    cmp.b #VWF_CTX_KEY_ITEM
    beq _flags_key_item
    lda.b #0x01
    bra _flags_store

_flags_key_item:
    lda.b #0x21

_flags_store:
    sta.l vwf_cfg.flags
; --- vwf_cfg.tilemap_base = $29 + $40 + Y + 2 (skip symbol slot) ---
; Caller's Y is the 16-bit byte offset of the top row tile we are
; about to write the symbol into ; VWF chars start two bytes later.
; X-flag is 16-bit (we did rep #$10 at entry) so `tya` returns the
; full Y. An earlier version of this helper masked Y to its low
; byte with `and #$00FF`, which made every slot past slot 1
; collapse onto slot 0's tilemap base (slot 2's Y = $0144 -> $44).
    rep #0x20
    tya
    clc
    adc.b menu_dp.tilemap_offset
    clc
    adc.w #0x0042  ; + $40 (next row) + $02 (past symbol)
    sta.l vwf_cfg.tilemap_base
    sep #0x20
; --- Top row: $FF tile + palette across the full slot width
; (1 symbol + ITEM_UNLEASHED_TEXT_SIZE name + trailing blanks fit
; into the same Y window the vanilla loop walked) ---
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
; --- Bottom row: $FF blank pre-fill across the slot width so any
; tilemap entries past the new glyph count stop showing PREVIOUS
; frame's tile_ids. display_char rewrites the front-of-row entries
; as it allocates new tile_ids per glyph ; the leftover positions
; stay $FF blank instead of pointing at stale CHR (e.g. before this
; pre-fill, drops slot 1's bottom row kept references to slot 0's
; tile range whenever the previous frame had a longer name, which
; rendered the start of "Aiguille d'or" inside the next slot's row
; as soon as drops + treasure stopped sharing a single tile region).
;
; Y enters this block at Y_orig + (1+ITEM_UNLEASHED_TEXT_SIZE)*2,
; pointing past the top-row run ; advance to the bottom-row start
; (next BG row = +$40 from top-row base = +$40 - run_size from
; current Y), blank 17 cells, then restore Y back to Y_orig for the
; symbol-write block below.
    rep #0x20
    pla
    clc
    adc.w #0x0040
    tay
    sep #0x20
    phy  ; bottom-row start, so the restore below ignores the run length
; Blank only what a VWF name can actually occupy: the symbol cell
; plus FIELD_ITEM_VWF_TILE_BUDGET glyph cells. This used to clear
; 1 + ITEM_UNLEASHED_TEXT_SIZE (17) cells, the width of the old
; fixed-width 16-char field, but no name is wider than the tile
; budget it is given: the widest item name measures 75px = 10 tiles.
; Those 6 surplus cells belonged to whatever the caller drew to the
; right of the name, and the shop draws each row's price there
; BEFORE the name, so a 4-digit price came back as 000.
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
; --- Restore caller's Y to point at the symbol slot, write symbol +
; palette to the bottom row first tile. Y came back off the stack as
; the bottom-row start (Y_orig + $40), so one subtraction lands on
; Y_orig whatever the blank run length was.
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
; X currently 0 from the top-row loop ; re-fetch items_unleashed offset.
    rep #0x20
    lda.b 0x43
    and.w #0x00FF
    pha
    asl
    asl
    asl
    asl
    clc
    adc 0x01, s
    tax
    pla
    sep #0x20
    lda.l items_unleashed, x
    sta (0x1D), y  ; bottom-row symbol tile
    iny
    lda.b menu_dp.item_usable
    ora.b menu_dp.window_attr
    sta (0x1D), y  ; bottom-row symbol palette
    iny
; --- The name's baked tiles into the slot (small_vwf/baked_names.s) ---
    jsr.w _baked_item_name
; render_with_config sets vwf_engine.chr_dirty=1 unconditionally. For drops
; (CTX=1) ADDITIONALLY raise DIRTY_B so the NMI's secondary flush
; covers drops's region this frame. Treasure's primary DIRTY must
; stay set untouched : treasure rendered its own slots earlier in the
; same frame and clearing here would skip its flush, leaking last-
; frame's CHR back into the treasure inventory band. Leaving DIRTY=1
; is harmless on drops-only frames: the primary DMA covers treasure
; VRAM range only ($5000..$5400) which drops never writes into.
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
; Equip shares this path: its names only touch the secondary region, and
; the primary flush would push the item list's region over whatever the
; equip screen keeps at $5000 while no list is open.
; The picker owns the secondary descriptor ONLY. Its primary dirty
; bit must be cleared, not left set: the primary flush targets
; FIELD_VWF_VRAM_DEST_WORD ($2800), which is spare CHR in the menu's
; mode 0 but the BG3 TILEMAP once the field map is up - flushing it
; would spray glyph bytes over the map's BG3 tilemap.
    lda.b #0x01
    sta.l vwf_engine.flush_b.dirty
    lda.b #0x00
    sta.l vwf_engine.chr_dirty

_dirty_done:
    ply
    plp
    rtl

_top_row_cells:
; X = cells the top (blank) row covers: the full fixed-width slot, or
; just the equip name cells (its names start too far right for 17).
    ldx.w #( 1 + ITEM_UNLEASHED_TEXT_SIZE )
    lda.l vwf_engine.caller_ctx
    cmp.b #VWF_CTX_EQUIP
    bne _row_cells_done
    ldx.w #EQUIP_NAME_CELLS

_row_cells_done:
    rts

draw_equip_item_name:
"""
    `DrawEquipItemName` ($01:9013) replacement: equipped item names in
    the VWF.

    Vanilla convention: Y = equipment byte offset in the character
    record at ($60) ($30..$35), X = tilemap byte offset of the slot,
    $29 = BG2 buffer. The equip screen runs alongside the inventory
    list, so the names take the drops tile region (slots 11..16 via
    $5D) and its flush descriptor instead of the list's slots.
    Preserves Y (the caller INYs to the next slot), $5D and
    vwf_engine.caller_ctx.
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
Item $43's baked tiles into its slot: copied from ROM to the CHR buffer at vwf_cfg.tile_id_base, the rest of the
slot's budget filled with paper, their ids written from vwf_cfg.tilemap_base on (attribute ORed with
vwf_cfg.flags), then chr_dirty raised: the slot ends as render_with_config left it, without rendering.
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
    Trampoline that pops the bank then jsr's the bank-local entry
    in small_vwf, paired RTL so callers stay long-jmp clean.
"""


    jsr.w render.render_with_config
    rtl
    }
}
