"""
Hard-coded battle command graphics: tile-id rows used when the row/defend command labels need to be redrawn
from ROM.
"""


.include "../bank20.i"
.include "battle_labels.i"  ; build/gen: utils/battle_labels.py

.alloc battle_graphics_block in bank20_reloc {
    .scope defend_row {
    """Two glyph rows for the Defend / Row battle command labels."""
    defend_row_length = 6
defend_text:
    .db 0xff, 0xff, 0xff, 0xff, 0xff, 0xff
    battle_label_garde()
row_text:
    .db 0xff, 0xff, 0xff, 0xff, 0xff, 0xff
    battle_label_rang()
    }
}
