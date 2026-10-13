"""
Hard-coded battle command graphics: tile-id rows used when the row/defend command labels need to be redrawn
from ROM.
"""


.include "core/bank20.i"
.include "battle_labels.i"  ; build/gen: utils/battle_labels.py

.alloc battle_graphics_block in bank20_reloc {
    .scope defend_row {
    """Two rows each (the blank one above, the label's) for the Defend / Row windows: their inside width."""
    defend_row_length = 3
defend_text:
    .db 0xff, 0xff, 0xff
    battle_label_garde()
row_text:
    .db 0xff, 0xff, 0xff
    battle_label_rang()
    }
}
