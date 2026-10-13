"""
Inventory VWF tile budget, shared by inventory_rolling.s and message.s. tests/test_vwf_asset_widths.py checks it
against the items XML; slots must stay disjoint if ITEM_VWF_TILE_BUDGET changes.
"""


; CHR tile_ids reserved per inventory slot (each tile_id = 16 CHR bytes).
ITEM_VWF_TILE_BUDGET := 10

; First slot's tile; slot N owns ITEM_VWF_TILE_BASE + N * ITEM_VWF_TILE_BUDGET onward.
ITEM_VWF_TILE_BASE := 0xC0

ITEM_VWF_CHR_BYTES := ITEM_VWF_TILE_BUDGET * 16  ; CHR slice per slot
ITEM_VWF_CHR_WORDS := ITEM_VWF_TILE_BUDGET * 8  ; word-stride clear-loop count
