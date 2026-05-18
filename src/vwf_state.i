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
}
