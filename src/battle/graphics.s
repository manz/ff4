"""
.include "../bank20.i"

Hard-coded battle command graphics: tile-id rows used when the row/defend command labels need to be redrawn
from ROM.
"""

.include "../bank20.i"

.alloc battle_graphics_block in bank20_reloc {
    .scope defend_row {
        """Two glyph rows for the Defend / Row battle command labels."""
        defend_row_length = 6
    defend_text:
        .db 0xff, 0xff, 0xff, 0xff, 0xff, 0xff
        .db 222, 224, 231, 225, 226, 255
    row_text:
        .db 0xff, 0xff, 0xff, 0xff, 0xff, 0xff
        .db 223, 224, 229, 227, 255, 255
    }
}
