"""
Cart SRAM map below the VWF state: the game's saves at $70:0000-$70:1FFF, ours at $70:2000-$70:6FFF.

Layout only: every block is a pinned reservation sized from the constants
the code uses, so two blocks that overlap fail the build. Blocks that take
turns (never live in the same screen) share one reservation, which names
every user. Confirmed with kintsuki write probes over the field item list,
treasure, battle (items + magic) and dialog.
"""


.import "core/preamble"
.include "core/vwf_state.i"
.include "battle/sram.i"

; The game's own saves (vanilla's 8 KB): nothing of ours may land there.
.pool sram_saves {
    bss
    range 0x700000 0x701FFF
    strategy order
}
.reserve game_saves 0x2000 at 0x700000 in sram_saves

; Everything of ours, above the saves in bank $70 and all of bank $71. The battery keeps whatever the last power-off
; (or an older build's layout) left there: the boot clears both (core/bank20_helpers.s, clear_ram).
PATCH_SRAM_LOW := 0x702000
PATCH_SRAM_LOW_END := 0x708000
PATCH_SRAM_HIGH := 0x710000
PATCH_SRAM_HIGH_END := 0x718000

; Dialog VWF tiles. The dialog renderer stays below $70:2F00.
DIALOG_TILE_BUFFER := 0x702000
DIALOG_TILE_BUFFER_SIZE := 0xF00
; Small-VWF tile allocator: allocated_tile_id (word) + slot_limit_low.
SMALL_VWF_ALLOCATOR := 0x702F00
SMALL_VWF_ALLOCATOR_SIZE := 3

.pool sram_work {
    bss
    contexts vram_save
    range 0x702000 0x706FFF
    strategy order
}

.reserve sram_dialog_tiles DIALOG_TILE_BUFFER_SIZE at DIALOG_TILE_BUFFER in sram_work
.reserve sram_small_vwf_allocator SMALL_VWF_ALLOCATOR_SIZE at SMALL_VWF_ALLOCATOR in sram_work
; Glyph CHR for tiles $000..$1EF. Renders observed reach tile $1AA; the
; last 16 tiles' worth of buffer is BATTLE_FLAGS' page.
.reserve sram_vwf_chr VWF_CHR_BUFFER_SIZE at VWF_CHR_BUFFER in sram_work
.reserve sram_battle_flags 1 at BATTLE_FLAGS in sram_work
; Vanilla's VRAM save ($14:FF9C) while the treasure popup or a dialog is up, and the menus' (ingame/menu_vram.s)
; for as long as a menu is open: nothing else may write here then.
.reserve sram_vram_save VRAM_SAVE_BYTE_COUNT at VRAM_SAVE_SRAM_BASE in sram_work.vram_save

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
    range PATCH_SRAM_HIGH ( PATCH_SRAM_HIGH_END - 1 )
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
; The item description last drawn (render.last_drawn_text_ptr): once in the VRAM save window, where the menu's own
; save holds the map's tiles, so every reset punched a hole in the field map.
.reserve description_cache 2 in sram_bank71
; Steps taken while the place-name window is up (ingame/places_names.s).
.reserve place_name_steps 1 in sram_bank71
; Pixels before a small-VWF render's first glyph (render.render_with_config), under 8; the map title sets it for its
; render and puts it back to 0.
.reserve render_lead 1 in sram_bank71
; The blank cells before a map title, centring it (ingame/map_title_vwf.s).
.reserve map_title_cells 1 in sram_bank71

; Deferred menu VRAM uploads (small_vwf/vram_queue.s): 16 entries of (VRAM word, source, bytes, source bank).
VRAM_QUEUE_SLOTS := 16
.struct VramQueue {
    word count  ; entries pushed
    word next  ; entries uploaded
    word staging_used  ; staging bytes taken
    word source_bank  ; push_rom's source bank, set by its caller
    byte[VRAM_QUEUE_SLOTS * 8] entries
}
.reserve vram_queue_state as VramQueue in sram_bank71
.reserve vram_queue_staging 0x1000 in sram_bank71

; The dialogue's VRAM uploads, drained by the field NMI (dialog/vblank_upload.s): up to 4 of (VRAM word, source,
; bytes, source bank).
VBLANK_UPLOAD_SLOTS := 4
.struct VblankUploads {
    word count  ; entries waiting for the next vblank
    word bank  ; the next push's source bank, set by its caller
    byte[VBLANK_UPLOAD_SLOTS * 8] entries
}
.reserve vblank_uploads as VblankUploads in sram_bank71
