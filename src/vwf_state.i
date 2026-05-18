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
needs to happen here ; `_vram_copy.buffer` already sits at $70:5000
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
VWF_CHR_BUFFER_SIZE := 0x1000  ; covers tile_ids $00..$FF (256 * 16 bytes)

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

.struct VwfConfig {
    word font_ptr        ; .l-addr 16-bit low (bank stored separately if needed)
    byte font_bank
    word kerning_ptr     ; null = kerning off
    byte kerning_bank
    byte tile_id_base    ; first tile_id this renderer owns
    byte slot_budget     ; ITEM_VWF_TILE_BUDGET-style clamp ; $FF = none
    word tilemap_base    ; WRAM dest base (16-bit, bank-$7E implied)
    byte palette_byte    ; default palette / attr
    byte flags           ; bit 0 = kerning, bit 1 = priority OR ; rest reserved
    ; CHR -> VRAM flush descriptor. The NMI flush routine reads these
    ; (gated on `VWF_CHR_DIRTY`) so each caller decides where its CHR
    ; lands ; battle messages, item descriptions, field items, drops,
    ; treasure all share the same engine without forking the upload.
    ; The source ALWAYS starts at `VWF_CHR_BUFFER + VWF_CHR_FLUSH_OFFSET`
    ; (the engine-side constant below) ; only the VRAM dest + size
    ; vary per caller.
    word chr_vram_word   ; VRAM word address for DMA dest
    word chr_byte_count  ; DMA byte count
}

; Engine-shared CHR-flush source offset. Every VWF caller writes
; glyph CHR at `VWF_CHR_BUFFER + tile_id_base * 16` ; both battle
; inventory and field menu items happen to anchor at tile_id base
; $C0, so the flush always starts $C00 bytes into the buffer.
; (If a future client uses a different base, this constant moves to
; the engine and we still avoid forking the DMA source per caller.)
VWF_CHR_FLUSH_OFFSET := 0xC0 * 0x10
