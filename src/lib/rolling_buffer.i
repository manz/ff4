"""
Shared rolling-buffer scroll cadence.

Profile state uses the `RollingBufferState` struct (src/core/items.s); the
shared scroll code is src/lib/rolling_inventory_engine.s.
"""


; Default held-DOWN cadence shared between the field and treasure
; inventory rolling buffers. Single retune knob — bumping these here
; changes the feel for both menus.
;   PIXELS_PER_FRAME = 8 / TOTAL_PIXELS = 16 → 2-frame animation per
;   row, ≈20 rows/sec under held DOWN once the post-anim 1-frame
;   settle is counted.
INVENTORY_SCROLL_PIXELS_PER_FRAME := 8
INVENTORY_SCROLL_TOTAL_PIXELS := 16
