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

.scope items_menu_vwf {
draw_field_item_name:
"""
Bank-20 stub entry. Mirrors the vanilla fixed-font body byte-for-
byte: writes the items_unleashed symbol + 16 name bytes across the
two tilemap rows. This proves the JSL hook works  ; the actual VWF
swap (top row -> blanks + bottom row -> small_vwf glyphs) lands in
the next phase.

The caller patches at $01:9013 and $01:9060 do `jsl ...  ; rts` so
we own the full DrawItemName / DrawEquipItemName body now. We do
NOT `phy` here because the patched callers no longer push Y -- Y
is preserved across the JSL by convention and consumed inline.
"""


    sta.b 0x43
    php
    rep #0x20
    lda.b 0x29
    clc
    adc.w #0x0040
    sta.b 0x1D
    lda.b 0x43
    and.w #0x00FF
; X = item id * ITEM_UNLEASHED_RECORD_SIZE. Inline `id*17 = id*16 + id`
; so the module does not depend on the top-level multiply helper
; (which is not visible from .import scope).
    pha
    asl
    asl
    asl
    asl  ; * 16
    clc
    adc 0x01, s
    tax
    pla  ; balance stack
    sep #0x20
    lda.l assets_items_unleashed_dat, x
    sta (0x1D), y
    iny
    lda.b 0xDB
    ora.b 0x34
    sta (0x29), y
    sta (0x1D), y
    iny
    inx
    lda.b #ITEM_UNLEASHED_TEXT_SIZE
    sta.b 0x45

_loop:
; Skip GetDakuten ; the French item names live entirely in the
; 1-byte range (no dakuten/kana split), so write the raw byte to
; both tilemap rows. Same visual as `GetDakuten ; sta ; xba ; sta`
; on a no-split input.
    lda.l assets_items_unleashed_dat, x
    sta (0x29), y
    sta (0x1D), y
    inx
    iny
    lda.b 0xDB
    ora.b 0x34
    sta (0x29), y
    sta (0x1D), y
    iny
    dec.b 0x45
    bne _loop
    plp
    rtl
}
