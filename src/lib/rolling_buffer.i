"""Rolling-buffer scroll cadence (state: RollingBufferState in core/items.s; code: lib/rolling_inventory_engine.s)."""


; Held-DOWN cadence for the field and treasure lists: 8 px/frame over 16 px = 2 frames a row (~20 rows/s).
INVENTORY_SCROLL_PIXELS_PER_FRAME := 8
INVENTORY_SCROLL_TOTAL_PIXELS := 16
