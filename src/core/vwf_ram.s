"""
The VWF engines' state in cart SRAM: the text-staging buffer, the
per-render config (`vwf_cfg`) and the engine's own state (`vwf_engine`).

Each block sits in a pool bounded to its span, so growing one past it
fails the build. vwf_state.i keeps the CHR buffer and VRAM save layout.
"""


.import "core/preamble"

; Null-terminated text-staging buffer: callers copy the string here so the renderer
; is independent of the source layout. Longest field-menu item + terminator + headroom.
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

; src_offset: long-addressed scratch for VWF callers (unused).
; chr_dirty: set after a blit into VWF_CHR_BUFFER; the NMI hook DMAs vwf_cfg.chr_byte_count bytes
;   from VWF_CHR_BUFFER + VWF_CHR_FLUSH_OFFSET to vwf_cfg.chr_vram_word, then clears it.
; caller_ctx (VWF_CTX_* in items.s): picks the primary (vwf_cfg) or secondary (flush_b) flush.
;   The treasure popup renders treasure ($100..$13B) and drops ($16E..$1A9) through the same hook;
;   separate flushes keep one panel's stale CHR out of the other's DMA.
; tilemap_offset, prev_char, current_char: draw_text_buffer cursor and kerning state.
;   Not on DP: the key-item picker runs over the field map with NMI on, where UpdateCtrl ($14:FD12)
;   uses $1D as scratch and $77 is the MOSAIC shadow ($2106), so DP copies get clobbered or leak.
; chr_dirty_from, chr_dirty_to: the primary flush's dirty bytes, from VWF_CHR_FLUSH_OFFSET. A scroll step redraws
;   one slot, and the whole block would not fit in vblank next to the menu's own transfers. A span past
;   chr_byte_count ($FFFF: a render that does not track it) flushes the whole block.
.struct VwfEngine {
    word src_offset
    byte chr_dirty
    byte caller_ctx
    VwfFlushDesc flush_b
    word tilemap_offset
    byte prev_char
    byte current_char
    word chr_dirty_from
    word chr_dirty_to
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

; Per-render parameters: callers fill them, then call render.render_with_config.
.pool vwf_cfg_ram {
    bss
    range 0x707080 ( 0x707080 + sizeof(VwfConfig) - 1 )
    strategy order
}
.reserve vwf_cfg as VwfConfig in vwf_cfg_ram

; Engine state, long-addressed so no direct-page user can alias it.
.pool vwf_engine_ram {
    bss
    range 0x7070C0 ( 0x7070C0 + sizeof(VwfEngine) - 1 )
    strategy order
}
.reserve vwf_engine as VwfEngine in vwf_engine_ram
