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
    contexts vram_save, item_menu
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
.reserve sram_vram_save VRAM_SAVE_BYTE_COUNT at VRAM_SAVE_SRAM_BASE in sram_work.vram_save
.reserve sram_description_cache 2 at VRAM_SAVE_SRAM_BASE + 2 in sram_work.item_menu

; Bank $71: menu small-VWF state and the second half of the menu's VRAM save.
.struct MenuTextState {
    byte resident  ; the string being drawn is resident (small_vwf/menu_text.s)
    word region_owner  ; the block whose strings hold tiles $200-$2FF
    word line_start  ; the dakuten-row cell of the line being drawn, for `col`
    byte[64] vram_bits  ; a bit per tile $200-$3FF: a string starting there is in VRAM
    byte[84] name_cache  ; 6 bytes per name index: the name last uploaded
}

.pool sram_bank71 {
    bss
    range 0x710000 0x717FFF
    strategy order
}
; The small VWF renderer saves its direct-page variables at $71:0000 + their DP offset (small_vwf/render.s).
.reserve sram_render_dp 0x100 at 0x710000 in sram_bank71
.reserve menu_text_state as MenuTextState in sram_bank71
; VRAM $6000-$7FFF while a menu is up (ingame/menu_vram.s), and its "saved" marker.
.reserve menu_vram_high VRAM_SAVE_BYTE_COUNT in sram_bank71
.reserve menu_vram_saved 2 in sram_bank71
; Non-zero while a menu window change has faded the screen out (ingame/menu_fade.s).
.reserve menu_faded_out 1 in sram_bank71
