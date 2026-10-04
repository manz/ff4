"""
Shared VWF engine state addresses + future-config-struct slots.

Both the battle messages renderer (`battle_render` in
`src/battle/message.s`) and the menu small-VWF renderer
(`render` in `src/small_vwf/render.s`) build glyph CHR into the same
SRAM tile buffer at $70:3000. They cohabit by never running
concurrently: battle owns the buffer during battle scenes, small_vwf
owns it during field menus.

Define the shared address as a single symbol so future engines
(field-menu items, treasure-list VWF, drops-list VWF, ...) all
point at the same place automatically. Bumping the size only
needs to happen here  ; `_vram_copy.buffer` already sits at $70:5000
past the buffer so the VRAM-save staging is decoupled from the
CHR-buffer size.

Per-render parameters live in `vwf_cfg` (VwfConfig at $70:7080), the
engine's own state in `vwf_engine` (VwfEngine at $70:70C0): callers fill
the config, then call `render.render_with_config`.
"""


; --- VWF CHR buffer (shared across battle + menu renderers) -----------

VWF_CHR_BUFFER := 0x703000
; Sized to cover tile_ids $00..$1FF (512 * 16 bytes). Field menu
; rolling buffer has 11 slots * K=10 tiles starting at base $C0,
; so the high slots end up at tile_id $160+ ; the previous $1000
; sizing capped at $FF and the high-slot CHR landed in
; $704000-$704FFF which was outside any blit / DMA reach.
VWF_CHR_BUFFER_SIZE := 0x1F00  ; tiles $000..$1EF; BATTLE_FLAGS follows

; --- Battle-render gate state (OUTSIDE the CHR buffer) ------------------
; These bytes must not live inside VWF_CHR_BUFFER. The inventory rolling
; buffer anchors at tile_id $C0 and hands each of its 11 slots
; ITEM_VWF_TILE_BUDGET (10) tiles, so slot N's CHR slice runs from
; $70:3C00 + N*160 and the last slot ends at $70:4240. Slot 4 alone spans
; $70:3E80..$70:3F1F, which is exactly where the gate bytes used to sit --
; a rendered item name wrote glyph pixels over pending_transfer_mask, the

; region dirty bits, render_skipped and dma_dirty_slots (observed:
; pending_transfer_mask = $F3), so the battle names / monsters regions lost
; their dirty + CHR-pending bits and never flushed again: black name blocks
; and an empty monster window for the rest of the battle.
; Hence BATTLE_RENDER_STATE at $70:7100: reserved in battle/render_state.s.

; Typed and reserved in battle/render_state.s.

; The text buffer, vwf_cfg and vwf_engine are reserved in vwf_ram.s.

; Engine-shared CHR-flush source offset. Every VWF caller writes
; glyph CHR at `VWF_CHR_BUFFER + tile_id_base * 16` ; both battle
; inventory and field menu items happen to anchor at tile_id base
; $C0, so the flush always starts $C00 bytes into the buffer.
; (If a future client uses a different base, this constant moves to
; the engine and we still avoid forking the DMA source per caller.)
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
; Generous on the upper end so a future region 3 / region 4 (status,
; equipment, ...) lands inside the save window without bumping the
; SRAM scratch.
VRAM_SAVE_BASE_WORD := 0x2800
VRAM_SAVE_BYTE_COUNT := 0x2000
VRAM_SAVE_SRAM_BASE := 0x705000
