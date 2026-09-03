"""
Shared inventory VWF tile-budget constants. Included by both
`src/battle/inventory_rolling.s` (slot init / clear loops / allocator
clamp) and `src/battle/message.s` (NMI partial-DMA path tables).

The runtime budget is validated against the items XML assets by
`tests/test_vwf_asset_widths.py`  ; bumping ITEM_VWF_TILE_BUDGET also
requires updating the per-slot tile_id tables to stay disjoint.
"""


; CHR tile_ids reserved per inventory slot (each tile_id = 16 CHR bytes).
ITEM_VWF_TILE_BUDGET := 10

; First slot's tile_id low byte. Slot N occupies
; ITEM_VWF_TILE_BASE + N * ITEM_VWF_TILE_BUDGET .. + budget-1.
ITEM_VWF_TILE_BASE := 0xC0

; Derived sizes.
ITEM_VWF_CHR_BYTES := ITEM_VWF_TILE_BUDGET * 16  ; CHR slice per slot
ITEM_VWF_CHR_WORDS := ITEM_VWF_TILE_BUDGET * 8  ; word-stride clear-loop count
