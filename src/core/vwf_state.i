"""
Shared VWF engine state addresses: the CHR buffer and the VRAM save window.

Both the battle messages renderer (`battle_render` in
`src/battle/message.s`) and the menu small-VWF renderer
(`render` in `src/small_vwf/render.s`) build glyph CHR into the same
SRAM tile buffer at $70:3000. They cohabit by never running
concurrently: battle owns the buffer during battle scenes, small_vwf
owns it during field menus.

The shared address is a single symbol so every engine (field-menu
items, treasure, drops, ...) points at the same place. Bumping the
size only needs to happen here: `_vram_copy.buffer` sits at $70:5000
past the buffer, so the VRAM-save staging is decoupled from the
CHR-buffer size.

Per-render parameters live in `vwf_cfg` (VwfConfig at $70:7080), the
engine's own state in `vwf_engine` (VwfEngine at $70:70C0): callers fill
the config, then call `render.render_with_config`.
"""


; --- VWF CHR buffer (shared across battle + menu renderers) -----------

VWF_CHR_BUFFER := 0x703000
; Sized to cover tile_ids $000..$1EF. The field menu rolling buffer
; has 11 slots * K=10 tiles from base $100 (FIELD_ITEM_VWF_TILE_BASE),
; so its high slots end at tile_id $16D, and the drops slots past
; them at $1A9.
VWF_CHR_BUFFER_SIZE := 0x1F00  ; tiles $000..$1EF; BATTLE_FLAGS follows

; --- Battle-render gate state (OUTSIDE the CHR buffer) ------------------
; These bytes must not live inside VWF_CHR_BUFFER. The battle inventory
; rolling buffer anchors at tile_id $C0 and hands each of its 6 slots
; ITEM_VWF_TILE_BUDGET (10) tiles, so slot N's CHR slice runs from
; $70:3C00 + N*160; slot 4 alone spans $70:3E80..$70:3F1F. Gate bytes in
; there get glyph pixels over pending_transfer_mask, the region dirty
; bits, render_skipped and dma_dirty_slots (observed:
; pending_transfer_mask = $F3), so the battle names / monsters regions lose
; their dirty + CHR-pending bits and never flush again: black name blocks
; and an empty monster window for the rest of the battle.
; Hence BATTLE_RENDER_STATE at $70:7100, typed and reserved in
; battle/render_state.s.

; The text buffer, vwf_cfg and vwf_engine are reserved in vwf_ram.s.

; CHR-flush source offset for `render.flush_chr_to_vram`. Every VWF
; caller writes glyph CHR at `VWF_CHR_BUFFER + tile_id_base * 16`; the
; field menu items anchor at tile_id base $100 (FIELD_ITEM_VWF_TILE_BASE),
; so the primary flush starts $1000 bytes into the buffer.
VWF_CHR_FLUSH_OFFSET := 0x100 * 0x10

; --- VRAM save / restore range ---
; The dialog VWF saves the VRAM CHR window before dialog opens and
; restores it on close. With field-menu items + item-description
; each carving out their own slice of CHR ($5000..$5FFF), the save
; range must cover that whole 4KB block so menu close puts the
; menu CHR back the way the field renderer expects it.
;
;   Word $2800 .. $37FF  =  byte $5000 .. $6FFF  (8KB)
;
; Generous on the upper end so another region lands inside the save
; window without bumping the SRAM scratch.
VRAM_SAVE_BASE_WORD := 0x2800
VRAM_SAVE_BYTE_COUNT := 0x2000
VRAM_SAVE_SRAM_BASE := 0x705000
