"""
Cart SRAM map below the VWF state: $70:2000-$70:6FFF.

Layout only: every block is a pinned reservation sized from the constants
the code uses, so two blocks that overlap fail the build. Blocks that take
turns (never live in the same screen) share one reservation, which names
every user. Confirmed with kintsuki write probes over the field item list,
treasure, battle (items + magic) and dialog.
"""


.import "preamble"
.include "src/vwf_state.i"
.include "src/battle/sram.i"

; Dialog VWF tiles. The dialog renderer stays below $70:2F00.
DIALOG_TILE_BUFFER := 0x702000
DIALOG_TILE_BUFFER_SIZE := 0xF00
; Small-VWF tile allocator: allocated_tile_id (word) + slot_limit_low.
SMALL_VWF_ALLOCATOR := 0x702F00
SMALL_VWF_ALLOCATOR_SIZE := 3

.pool sram_work {
    bss
    range 0x702000 0x706FFF
    strategy order
}

.reserve sram_dialog_tiles DIALOG_TILE_BUFFER_SIZE at DIALOG_TILE_BUFFER in sram_work
.reserve sram_small_vwf_allocator SMALL_VWF_ALLOCATOR_SIZE at SMALL_VWF_ALLOCATOR in sram_work
; Glyph CHR for tiles $000..$1EF. Renders observed reach tile $1AA; the
; last 16 tiles' worth of buffer is BATTLE_FLAGS' page.
.reserve sram_vwf_chr VWF_CHR_BUFFER_SIZE at VWF_CHR_BUFFER in sram_work
.reserve sram_battle_flags 1 at BATTLE_FLAGS in sram_work
; Taken in turns: vanilla's VRAM save ($14:FF9C) fills the whole window
; while the treasure popup or a dialog is up; the field item menu keeps
; the item-description cache (render.last_drawn_text_ptr) at +2. A cache
; overwritten by a save only costs one description redraw.
.reserve sram_vram_save VRAM_SAVE_BYTE_COUNT at VRAM_SAVE_SRAM_BASE in sram_work
