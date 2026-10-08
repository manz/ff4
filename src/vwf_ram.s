"""
The VWF engines' state in cart SRAM: the text-staging buffer, the
per-render config (`vwf_cfg`) and the engine's own state (`vwf_engine`).

Each block sits in a pool bounded to its span, so growing one past it
fails the build. vwf_state.i keeps the CHR buffer and VRAM save layout.
"""


.import "preamble"

; --- Null-terminated text-staging buffer ------------------------------
; Callers copy the source string (from items_unleashed, monster names,
; magic list, ...) into this buffer + write $00 terminator, then call
; `vwf_render_string` with just a pointer. Lets the engine drop the
; explicit char-count argument that battle / item-description / field
; helpers each carry today, and lets us swap the source layout
; (fixed-stride table vs null-terminated table vs RAM-resident string)
; without touching the renderer. Sized for the longest field-menu
; item slot in `items_unleashed` + 1 terminator + headroom.
.pool vwf_text_ram {
    bss
    range 0x707000 0x70703F
    strategy order
}
.reserve vwf_text_buffer 0x40 in vwf_text_ram

; Where one panel's CHR goes: the drops panel's flush (see caller_ctx).
.struct VwfFlushDesc {
    byte dirty
    word vram_word
    word byte_count
    word src_offset
}

; VwfEngine fields:
;
; src_offset - Long-addressable scratch for VWF callers that need a counter / pointer
; without stealing direct-page bytes from the menu loop. The field-items
; helper uses src_offset as the 16-bit source index into
; items_unleashed while X holds the destination index in
; vwf_text_buffer (only sta.l abs,x is encoded by a816).
;
; chr_dirty - Set by `render.display_char` (or `render.render_with_config`) after a
; blit lands in `VWF_CHR_BUFFER`. The NMI flush hook reads this byte,
; fires the DMA from `VWF_CHR_BUFFER + $C00` to VRAM $AC00 ($400 bytes)
; when set, then clears it. Gates the upload exactly the same way the
; battle inventory's `dma_dirty_slots` gates the per-slot DMA.
;
; caller_ctx, flush_b - Drops + treasure-inventory coexist in the treasure popup and render
; through the same `items_menu_vwf.draw_field_item_name` JSL hook.
; Region 1 = $100..$13B (treasure) flushes via the primary descriptor
; at vwf_cfg ; region 1B = $16E..$1A9 (drops) needs its own
; flush dest + size so each panel's CHR lands in VRAM without the
; other's stale buffer bytes leaking through one combined DMA.
;
; caller_ctx is a one-byte hint set by drops_rolling around the
; vanilla JSR chain ; items_menu_vwf reads it to decide whether to
; write the primary or the secondary descriptor + dirty flag.
;   VWF_CTX_* in items.s: primary, drops (secondary), key item, equip.
;
; tilemap_offset - Tilemap write cursor for `render.draw_text_buffer`.
;
; This lived on direct page ($1D) until the key-item picker: that menu
; overlays the field map, where NMI stays enabled, and vanilla's
; UpdateCtrl ($14:FD12) uses $1D as scratch. An NMI landing mid-render
; zeroed the cursor and the rest of the name's tilemap cells went to
; $7E:0000 instead of the staging buffer. The other menus never saw it
; because they run with NMI off. Long-addressed, so no interrupt can
; alias it.
;
; prev_char, current_char - Kerning state for `render.draw_text_buffer`: the previous and current
; character codes.
;
; These lived on direct page at $77 / $79, which is free in the menus
; but is the field engine's MOSAIC shadow: the picker renders over a
; live map, so glyph codes landed in $77 and the window IRQ pushed them
; straight to $2106 - the map pixelated for as long as a render took.
; The renderer's other scratch ($73-$75) is saved and restored around a
; render; these two never were, and even saving them would not help
; while an interrupt reads the byte mid-render.
.struct VwfEngine {
    word src_offset
    byte chr_dirty
    byte caller_ctx
    VwfFlushDesc flush_b
    word tilemap_offset
    byte prev_char
    byte current_char
}

.struct VwfConfig {
    word tile_id_base
    byte slot_budget
    word tilemap_base
    byte palette_byte
    byte flags
    word chr_vram_word
    word chr_byte_count
}

; --- Per-render parameters: callers fill them, then call
; `render.render_with_config` ---------------------------------------------
.pool vwf_cfg_ram {
    bss
    range 0x707080 ( 0x707080 + sizeof(VwfConfig) - 1 )
    strategy order
}
.reserve vwf_cfg as VwfConfig in vwf_cfg_ram

; --- Engine state, long-addressed so no direct-page user can alias it ----
.pool vwf_engine_ram {
    bss
    range 0x7070C0 ( 0x7070C0 + sizeof(VwfEngine) - 1 )
    strategy order
}
.reserve vwf_engine as VwfEngine in vwf_engine_ram
