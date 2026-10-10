"""Tilemap rows for the top + bottom edges of the location-name window."""


.include "../bank20.i"

PLACE_NAME_LENGTH := 18  ; cells for the title: the widest one takes 17 small-VWF tiles
PLACE_WINDOW_WIDTH := PLACE_NAME_LENGTH + 4  ; the borders and a blank cell inside each
; each row: a corner, PLACE_WINDOW_WIDTH - 2 edges (.for stops before its upper bound), a corner

.alloc places_names_window_block in bank20_reloc {
places_top_window:
"""Tilemap row for the top edge of the location-name window (tile/attr pairs)."""
    .db 0x16, 0x20
    .for i := 0, PLACE_WINDOW_WIDTH - 2 {
    .db 0x17, 0x20
    }
    .db 0x18, 0x20

places_bottom_window:
"""Tilemap row for the bottom edge of the location-name window (tile/attr pairs)."""
    .db 0x1B, 0x20
    .for i := 0, PLACE_WINDOW_WIDTH - 2 {
    .db 0x1C, 0x20
    }
    .db 0x1D, 0x20
}
