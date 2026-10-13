"""
Reserved state for the rolling-inventory menus. Not in `items.i`: that file is included inside `.alloc` bodies,
and placement directives cannot nest.
"""


; Rolling-menu state pool in cart SRAM bank $70 (ours alone, cleared at boot). Below $7200: VWF CHR buffer ($3000),
; VRAM save window ($5000), VWF text/config/engine ($7000..$70CC), battle render state ($7100).
.pool rolling_state {
    bss
    range 0x707200 0x707FFF
    strategy order
}

; Refresh loop scratch (scroll_pos / buffer_slots). Not $00:1F88: the field engine uses it.
.reserve rolling_engine_scratch 2 in rolling_state


; --- Key-item picker ---------------------------------------------------
; Caller's DP register, held while the picker renders on its own page (the renderer scratches field-owned DP).
.reserve key_item_dp_prev 2 in rolling_state

; Key items the filter accepted: the scroll ceiling comes from it (vanilla hardcoded 17).
.reserve key_item_count 1 in rolling_state

; Vanilla's window-slide counter ($DA) last seen, its scroll position ($BA) last rendered, the engine scroll
; position, and the window-scroll animation's frame counter.
.reserve key_item_open_slide_seen 1 in rolling_state
.reserve key_item_last_scroll 1 in rolling_state
.reserve key_item_scroll_pos 1 in rolling_state
.reserve key_item_scroll_frames 1 in rolling_state

; VRAM the picker overwrites (glyph CHR window, BG3 tilemap window band), restored on close: maps with high
; BG3 tile ids use both.
.reserve key_item_chr_save 0x0460 in rolling_state
.reserve key_item_map_save 0x0200 in rolling_state

; DMA channel 3 registers ($4330-$433A), saved across the picker's transfers so a map HDMA on it gets them back.
.reserve key_item_dma_save 0x000B in rolling_state
