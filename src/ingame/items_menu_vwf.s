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

.extern assets_items_unleashed_dat
.extern render
.extern render.display_char
.extern render.bits_left_on_tile
.extern render.temp
.extern render.counter
.extern render_allocator
.extern render_allocator.init_with_tile_id
.extern render_allocator.slot_limit_low
.extern render_allocator.allocated_tile_id

.scope items_menu_vwf {
draw_field_item_name:
"""
Bank-20 VWF item-name render for the field menu.

Top tilemap row at ($29),y gets $FF blank tiles + the menu palette
byte ($DB | $34) so the 16-pixel-tall slot keeps its full height.
Bottom row gets the items_unleashed symbol byte (fixed font, lands
at the slot's first tile) followed by VWF tiles produced by
`small_vwf.render.display_char`. Slot N owns tile_ids
ITEM_VWF_TILE_BASE + N * ITEM_VWF_TILE_BUDGET .. + K - 1 ; the
allocator's slot_limit_low clamp keeps spill out of the next
slot's range.

The first pass of this helper hit two snags worth recording so
they stay fixed:

1. `small_vwf.render.tilemap_offset` and `small_vwf.render.bits_left_on_tile`
   live in direct page ($1D, $73) which vanilla `DrawItemName`
   also touched as its kana-row pointer. Solution: drive
   tilemap_offset directly as the absolute WRAM byte index for the
   bottom row and never use ($1D),y indirection ourselves ; the
   top-row writes go via ($29),y so the two rows stay decoupled.

2. `small_vwf.render_allocator.allocated_tile_id` was reset to 0
   by an unrelated `render.init` call (item-description redraw)
   between our `init_with_tile_id` and the first `display_char`.
   Solution: re-arm `allocated_tile_id` straight after the JSR so
   any race is contained to a single bytecode window, and stash
   the slot base in $43 so a later check can detect the clobber
   if it comes back.

Y is preserved by the caller and tracks the top-row byte offset.
display_char internally advances `tilemap_offset` by 2 per blit so
we just bump Y by 2 in lockstep for the top-row blank.
"""


    sta.b 0x43
    php
    sep #0x20
    rep #0x10
; --- X = item id * ITEM_UNLEASHED_RECORD_SIZE ---
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
    pla  ; balance stack
    sep #0x20
; --- Tile_id base = ITEM_VWF_TILE_BASE + $5D * ITEM_VWF_TILE_BUDGET ---
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
    adc.w #ITEM_VWF_TILE_BASE
    sta.b 0x43  ; reuse $43 as 16-bit tile_id base scratch
    pla  ; balance stack
    sep #0x20
; --- Init small_vwf allocator with this slot's base ---
    phx
    lda.b 0x43
    jsr.w render_allocator.init_with_tile_id
; Belt + braces: write allocated_tile_id verbatim. init_with_tile_id
; takes A and stashes it; we re-stash so an interleaved render.init
; (item-description redraw etc.) is shadowed back to the slot base
; on this side of the call boundary.
    lda.b 0x43
    sta.l render_allocator.allocated_tile_id
    lda.b #0x00
    sta.l render_allocator.allocated_tile_id + 1
    lda.b 0x43
; Debug breadcrumb: stash the computed base + slot index in SRAM
; scratch so a write-watch from outside can confirm which slot the
; helper was invoked for and what tile_id base it actually used.
    sta.l 0x70F800
    lda.b 0x5D
    sta.l 0x70F801
    clc
    adc.b #( ITEM_VWF_TILE_BUDGET - 1 )
    sta.l render_allocator.slot_limit_low
    plx
; --- Reset per-render render state (mirror of render.init tail) ---
    lda.b #0x08
    sta.b render.bits_left_on_tile
    stz.b render.temp
    stz.b render.counter
; --- Set tilemap_offset = $29 + $40 + Y (absolute bottom-row WRAM byte) ---
    rep #0x20
    tya
    and.w #0x00FF
    clc
    adc.b 0x29
    clc
    adc.w #0x0040
    sta.b 0x1D
    sep #0x20
; --- Symbol byte: write fixed tile to bottom row, blank to top ---
    lda.l assets_items_unleashed_dat, x
    pha
    lda.b #0xFF
    sta (0x29), y  ; top row blank
    pla
    sta (0x1D), y  ; bottom row symbol (direct sta via $1D as 16-bit ptr)
    iny
    lda.b 0xDB
    ora.b 0x34
    sta (0x29), y
    sta (0x1D), y
    iny
    inx
; Advance tilemap_offset past the symbol slot (2 bytes = tile + pal)
    rep #0x20
    lda.b 0x1D
    clc
    adc.w #0x0002
    sta.b 0x1D
    sep #0x20
; --- VWF loop: ITEM_UNLEASHED_TEXT_SIZE chars ---
    lda.b #ITEM_UNLEASHED_TEXT_SIZE
    sta.b 0x45

_loop:
    lda.l assets_items_unleashed_dat, x
    phx
    phy
    jsr.w render.display_char  ; CHR blit + tilemap_write @ $1D, advances both
    ply
    plx
; Top row blank + palette at the position the VWF cell took
    lda.b #0xFF
    sta (0x29), y
    iny
    lda.b 0xDB
    ora.b 0x34
    sta (0x29), y
    iny
    inx
    dec.b 0x45
    bne _loop
    plp
    rtl
}
