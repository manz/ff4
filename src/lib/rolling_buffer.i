"""Rolling-buffer scroll cadence (state: RollingBufferState in core/items.s; code: lib/rolling_inventory_engine.s)."""


; Held-DOWN cadence for the field, treasure and drops lists: 4 px/frame over 16 px = 4 frames a row (15 rows/s),
; each frame drawn (rolling_engine_hdma_rows slides the bands by the pixel). Sell, equip and the Fat Chocobo keep
; vanilla's 8 frames of 2 px: their loops read the pad themselves, a shorter scroll repeats a held press.
INVENTORY_SCROLL_PIXELS_PER_FRAME := 4
VANILLA_SCROLL_PIXELS_PER_FRAME := 2
INVENTORY_SCROLL_TOTAL_PIXELS := 16
