

"""
Shared rolling-buffer engine (single-column profile).

Each profile (field-menu items, treasure inventory, treasure drops,
key-item picker) instantiates the macros below with its own state RAM
base, HDMA shadow buffer, slot/visible counts, and per-profile hooks
for the bits that legitimately differ (HDMA header band layout,
copy-pending shadow signalling, etc.).

Conventions:
  - Macro-internal labels start with `_` so a816 keeps them scope-local
    (a816 1.1.0a13 promotes plain labels through `.scope` and macro
    invocations  ; underscores stay private).
  - State RAM access goes through the `RollingBufferState` struct
    (defined in src/items.i) so profile state blocks share layout.
  - Hooks are passed as label symbols and invoked via `jsr.w` so the
    65816 indirection cost is one extra jsr/rts pair per call site.
"""


; Default held-DOWN cadence shared between the field and treasure
; inventory rolling buffers. Single retune knob — bumping these here
; changes the feel for both menus.
;   PIXELS_PER_FRAME = 8 / TOTAL_PIXELS = 16 → 2-frame animation per
;   row, ≈20 rows/sec under held DOWN once the post-anim 1-frame
;   settle is counted.
INVENTORY_SCROLL_PIXELS_PER_FRAME := 8
INVENTORY_SCROLL_TOTAL_PIXELS := 16
