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

Forward-compat reservation:
  VWF_CONFIG_BASE points at a planned per-context state struct
  (font_ptr, kerning_ptr, tile_id_base, slot_budget, palette,
  tilemap_base, flags). When the engines start reading from this
  block, callers will write the struct once before invoking
  `vwf_render_string` and the engine drops its hardcoded font
  pointer. The struct lives in unused SRAM space ($70:F800+, same
  region we already use for the items_menu_vwf debug breadcrumb)
  so adding it does not perturb battle / menu live state.
"""


; --- VWF CHR buffer (shared across battle + menu renderers) -----------

VWF_CHR_BUFFER := 0x703000
; Sized to cover tile_ids $00..$1FF (512 * 16 bytes). Field menu
; rolling buffer has 11 slots * K=10 tiles starting at base $C0,
; so the high slots end up at tile_id $160+ ; the previous $1000
; sizing capped at $FF and the high-slot CHR landed in
; $704000-$704FFF which was outside any blit / DMA reach.
VWF_CHR_BUFFER_SIZE := 0x2000

; --- Null-terminated text-staging buffer ------------------------------
; Callers copy the source string (from items_unleashed, monster names,
; magic list, ...) into this buffer + write $00 terminator, then call
; `vwf_render_string` with just a pointer. Lets the engine drop the
; explicit char-count argument that battle / item-description / field
; helpers each carry today, and lets us swap the source layout
; (fixed-stride table vs null-terminated table vs RAM-resident string)
; without touching the renderer. Sized for the longest field-menu
; item slot in `assets_items_unleashed_dat` + 1 terminator + headroom.
VWF_TEXT_BUFFER := 0x707000
VWF_TEXT_BUFFER_SIZE := 0x40

; --- VWF config struct (forward-compat ; not consumed yet) ------------
; Field offsets so future readers can `lda.l VWF_CONFIG_BASE + .field`
; without manual byte math. Phase n of the unification will start
; populating + consuming these.
VWF_CONFIG_BASE := 0x707080

; --- Engine scratch in SRAM (no DP collisions) ---------------------------
; Long-addressable scratch for VWF callers that need a counter / pointer
; without stealing direct-page bytes from the menu loop. The field-items
; helper uses VWF_SRC_OFFSET as the 16-bit source index into
; assets_items_unleashed_dat while X holds the destination index in
; VWF_TEXT_BUFFER (only sta.l abs,x is encoded by a816).
VWF_SRC_OFFSET := 0x7070C0

; --- Dirty flag for NMI-side CHR flush ----------------------------------
; Set by `render.display_char` (or `render.render_with_config`) after a
; blit lands in `VWF_CHR_BUFFER`. The NMI flush hook reads this byte,
; fires the DMA from `VWF_CHR_BUFFER + $C00` to VRAM $AC00 ($400 bytes)
; when set, then clears it. Gates the upload exactly the same way the
; battle inventory's `dma_dirty_slots` gates the per-slot DMA.
VWF_CHR_DIRTY := 0x7070C2

; --- Secondary descriptor for two-region simultaneous flush -------------
; Drops + treasure-inventory coexist in the treasure popup and render
; through the same `items_menu_vwf.draw_field_item_name` JSL hook.
; Region 1 = $100..$13B (treasure) flushes via the primary descriptor
; at VWF_CONFIG_BASE ; region 1B = $16E..$1A9 (drops) needs its own
; flush dest + size so each panel's CHR lands in VRAM without the
; other's stale buffer bytes leaking through one combined DMA.
;
; VWF_CALLER_CTX is a one-byte hint set by drops_rolling around the
; vanilla JSR chain ; items_menu_vwf reads it to decide whether to
; write the primary or the secondary descriptor + dirty flag.
;   0 = primary  (treasure / field-items / default)
;   1 = drops    (secondary)
VWF_CALLER_CTX := 0x7070C3
VWF_CHR_DIRTY_B := 0x7070C4
VWF_CHR_VRAM_WORD_B := 0x7070C5
VWF_CHR_BYTE_COUNT_B := 0x7070C7
VWF_CHR_SRC_OFFSET_B := 0x7070C9

.struct VwfConfig {
    word tile_id_base
    byte slot_budget
    word tilemap_base
    byte palette_byte
    byte flags
    word chr_vram_word
    word chr_byte_count
}

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
