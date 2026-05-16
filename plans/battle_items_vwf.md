# Battle items VWF

## What

Replace the fixed-width 12-character item-name rendering in the battle
inventory with the existing 8x8 VWF blitter (`battle_render.display_char`).
Lets proportionally-spaced French names fit the 15-tile slot budget that
the rolling inventory already reserves, removes hard truncation, frees
the per-glyph padding wasted on narrow characters.

## Why

Vanilla `DrawInventoryItemText` packs item names as 12 fixed tile IDs
into a 48-byte buffer. Our rolling inventory expanded to 60 bytes (15
tiles per row × 2 bytes), but the renderer still emits one tile-id per
character, so a 12-character French name like `Médaille d'Or` either
overflows or truncates. VWF rendering pulls the same name through
`battle_render.display_char`, allocating CHR dynamically and packing
proportional glyphs into 15 tiles of horizontal pixels (~120 px).

## Boundaries

- In scope: battle inventory (the in-battle item menu).
- In scope: the rolling-buffer slot refresh hook (re-render on
  scroll edge).
- Out of scope: equipped-items buffer ($9A00). Equip menu rendering
  stays fixed-width for this PR; can follow up.
- Out of scope: item descriptions (already VWF via small_vwf).
- Out of scope: field inventory VWF. Same approach, different surface.

## Approach

1. **Reserve a battle_render region for inventory**. Current regions
   (`src/battle/message.s:143-150`):
   ```
   0x00-0x3F messages
   0x40-0x7F monster names
   0x80-0xAF char names
   0xB0-0xEF commands
   ```
   Add `0xF0-0xFF` (16 tiles = 512B CHR) for inventory item name. With
   6 ring slots and 15 tiles per name, the ring needs ~90 tiles. Either
   extend the CHR window past $BDE0 (free runway up to roughly
   $BFE0-ish per the audit) or reuse the commands region during the
   item-menu mode (commands hide when inventory is open).
2. **Patch `DrawInventoryItemText`** at `$02:9FA4`. Replace the
   per-character tile-id copy with a `battle_render.init_inventory`
   + per-byte `display_char` loop, then write the resulting tile IDs
   into the existing 60-byte slot at `$97A6 + slot * 60`.
3. **Quantity digits**. Stay fixed-width for now (the rightmost 2
   tiles per row in the slot layout). Avoids a special-case digit
   path in display_char.
4. **Trash icon**. Existing 2x2 fixed glyph stays. Item id $FF skips
   the VWF render path.
5. **Tilemap layout unchanged**. The slot still consumes 30 tiles
   (15 × 2 rows), still gets DMA'd to VRAM tilemap by the existing
   rolling-buffer transfer. Only the CHR pointed at by the tile IDs
   changes.

## Files

- `src/battle/items_patches.s` — hook `DrawInventoryItemText` text
  copy loop.
- `src/battle/message.s` — add inventory region constants +
  `init_inventory` entry.
- `src/battle/inventory_rolling.s` — slot-refresh callsite. Already
  pre-renders on swap / scroll; VWF render lands at the same site.
- `tests/test_battle_init.py` — extend with an "open battle
  inventory" frame that captures the VWF rendered names.

## Tests

- Battle init smoke unchanged (no item menu open).
- New `tests/test_battle_inventory_vwf.py`: load a battle-with-items
  kss, open the item menu, capture screen golden showing
  VWF-rendered names.
- `tests/_profile/profile_battle_vwf.py` exercised with the inventory
  open; confirm `_display_char` calls fit within budget on edge
  frames (re-render is one slot, ~15 chars × 4.4k cy = 66k cy ≈ 18%
  of frame).

## Risks

- **CHR overflow**: 90 tiles for the ring needs $A000-base allocation
  past current region. Audit the $BDE0-? runway carefully before
  expanding.
- **Tile-id collision with commands**: if commands region 0xB0-0xEF
  is the chosen reuse target, items render must wait for cmd window
  to be hidden. The existing battle inventory open path already
  hides the cmd window via the slice-2 gates, but verify.
- **Edge-slot render time**: VWF blit of one item name on scroll
  edge must fit in ~1 vblank. Item names are ~12-15 chars × 4.4k cy
  = 53-66k cy ≈ 15-18% of frame budget. Headroom OK.
- **dakuten/special chars**: item names with accents flow through
  `battle_display_dakuten_char`. Already handled by the existing VWF
  path. Verify on `Médaille` etc.

## Phasing

| phase | scope | size |
|---|---|---|
| 1 | Region reservation + region-init helper | ~50 lines asm |
| 2 | `DrawInventoryItemText` VWF hook + slot write | ~150 lines asm |
| 3 | Rolling-buffer slot-refresh wiring | ~80 lines asm |
| 4 | Goldens + smoke test for battle inventory | tests |
| 5 | Polish: quantity-digit alignment, trash icon | small |

Each phase commits independently. PR can land as either one chunk or
phase-by-phase depending on review cadence.

## Crack

The 90-tile CHR budget is the load-bearing assumption. If the
$A000-$BFFF window proves too tight, fall back to reusing commands
region 0xB0-0xEF during item-menu mode and round-trip the cmd window
on close. Adds a tilemap clear on transition but keeps the CHR
footprint where it is.
