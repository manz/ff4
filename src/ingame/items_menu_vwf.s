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


.include "src/items.i"
.include "src/battle/inventory_budget.i"

.include "src/libmz.i"
.include "src/vwf_state.i"

.extern assets_items_unleashed_dat
.extern render
.extern render.render_with_config
.extern wait_for_vblank_long
.extern dma_transfer_to_vram

.scope items_menu_vwf {
draw_field_item_name:
"""
Bank-20 field-menu item-name render driven by VwfConfig.

Stages the item name in `VWF_TEXT_BUFFER` with a $00 terminator,
fills `VWF_CONFIG_BASE` with per-slot tile budget + tilemap dest,
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
; --- Copy items_unleashed name bytes into VWF_TEXT_BUFFER, terminate $00 ---
; Byte 0 of the record is the symbol (rendered separately as fixed
; tile below) ; bytes 1..ITEM_UNLEASHED_TEXT_SIZE go into the buffer.
; X is the destination index (only abs,x works with sta.l) ; the
; source offset rides in long SRAM scratch `VWF_SRC_OFFSET` so we
; do not steal a direct-page byte from vanilla's menu loop (the
; original placement on DP $45 clashed with the items code's row
; counter and broke the per-slot copy).
    rep #0x20
    txa
    inc       ; skip symbol byte
    sta.l VWF_SRC_OFFSET
    sep #0x20
    ldx.w #0x0000

_copy_loop:
    phx
    rep #0x20
    lda.l VWF_SRC_OFFSET
    tax
    sep #0x20
    lda.l assets_items_unleashed_dat, x
    pha  ; save the byte so the 16-bit src-pointer update does not clobber it
    inx
    rep #0x20
    txa
    sta.l VWF_SRC_OFFSET
    sep #0x20
    pla
    plx
    sta.l VWF_TEXT_BUFFER, x
    inx
    cpx.w #ITEM_UNLEASHED_TEXT_SIZE
    bne _copy_loop
    lda.b #0x00
    sta.l VWF_TEXT_BUFFER, x  ; null terminator
; --- Populate VwfConfig.tile_id_base = FIELD base + $5D * K ---
; K = FIELD_ITEM_VWF_TILE_BUDGET (=10). slot * 10 = slot*8 + slot*2.
; Store the full 16-bit value: slots 6..10 produce tile_id_base
; $C0 + 10*K = $C0 + 100 = $124 which the 8-bit allocator wrapped
; back into the menu font CHR range. The wide init keeps tile_id
; bit 8 (which `tilemap_write_no_inc` ORs in via $01 on the high
; tilemap byte) intact.
    rep #0x20
    lda.b 0x5D
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
    sta.l VWF_CONFIG_BASE + VwfConfig.tile_id_base  ; word
    pla  ; balance
    sep #0x20
    lda.b #FIELD_ITEM_VWF_TILE_BUDGET
    sta.l VWF_CONFIG_BASE + VwfConfig.slot_budget
; CHR -> VRAM flush descriptor. Menu PPU runs in Mode 0
; (BGMODE = $00 at `ff4decomp/menu/menu.asm:3878`) with BG34NBA = $22
; -> BG3 CHR at VRAM word $2000 (byte $4000). Tile_ids $C0..$FF
; in 2bpp BG3 live at $4000 + $C0 * 16 = $4C00 (word $2600), $400
; bytes. NMI flush reads these once the engine sets VWF_CHR_DIRTY.
    rep #0x20
    lda.w #FIELD_VWF_VRAM_DEST_WORD
    sta.l VWF_CONFIG_BASE + VwfConfig.chr_vram_word
    lda.w #0x0400
    sta.l VWF_CONFIG_BASE + VwfConfig.chr_byte_count
    sep #0x20
; Tilemap attr OR mask. Field VWF tile_ids live in the 9-bit
; window ($100..$169) so bit 0 of the attr byte (= tile_id bit 8)
; must be set ; the allocator stores $0100+, the tilemap entry
; writes the low byte to the tile_id slot and ORs `$01` into the
; attr byte to give the PPU the full 9-bit tile_id.
    lda.b #0x01
    sta.l VWF_CONFIG_BASE + VwfConfig.flags
; --- VwfConfig.tilemap_base = $29 + $40 + Y + 2 (skip symbol slot) ---
; Caller's Y is the 16-bit byte offset of the top row tile we are
; about to write the symbol into ; VWF chars start two bytes later.
; X-flag is 16-bit (we did rep #$10 at entry) so `tya` returns the
; full Y. An earlier version of this helper masked Y to its low
; byte with `and #$00FF`, which made every slot past slot 1
; collapse onto slot 0's tilemap base (slot 2's Y = $0144 -> $44).
    rep #0x20
    tya
    clc
    adc.b 0x29
    clc
    adc.w #0x0042  ; + $40 (next row) + $02 (past symbol)
    sta.l VWF_CONFIG_BASE + VwfConfig.tilemap_base
    sep #0x20
; --- Top row: $FF tile + palette across the full slot width
; (1 symbol + ITEM_UNLEASHED_TEXT_SIZE name + trailing blanks fit
; into the same Y window the vanilla loop walked) ---
    ldx.w #0x0000

_top_loop:
    lda.b #0xFF
    sta (0x29), y
    iny
    lda.b 0xDB
    ora.b 0x34
    sta (0x29), y
    iny
    inx
    cpx.w #( 1 + ITEM_UNLEASHED_TEXT_SIZE )
    bne _top_loop
; --- Restore caller's Y to point at the symbol slot, write symbol +
; palette to the bottom row first tile ---
    rep #0x20
    tya
    sec
    sbc.w #( ( 1 + ITEM_UNLEASHED_TEXT_SIZE ) * 2 )
    tay
    lda.b 0x29
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
    lda.l assets_items_unleashed_dat, x
    sta (0x1D), y  ; bottom-row symbol tile
    iny
    lda.b 0xDB
    ora.b 0x34
    sta (0x1D), y  ; bottom-row symbol palette
    iny
; --- Run the unified renderer over VWF_TEXT_BUFFER ---
    jsr.l render_with_config_trampoline
    plp
    rtl

render_with_config_trampoline:
"""Trampoline that pops the bank then jsr's the bank-local entry
in small_vwf, paired RTL so callers stay long-jmp clean."""
    jsr.w render.render_with_config
    rtl
}
