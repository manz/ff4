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


; The key-item picker's state.
.struct KeyItemPicker {
    word dp_prev  ; caller's D, held while the picker renders on its own page
    byte count  ; key items the filter accepted: the scroll ceiling (vanilla hardcoded 17)
    byte open_slide_seen  ; vanilla's window-slide counter ($DA) last seen
    byte last_scroll  ; vanilla's scroll position ($BA) last rendered
    byte scroll_pos  ; engine scroll position
    byte scroll_frames  ; window-scroll animation frame counter
    byte[0x0460] chr_save  ; glyph CHR window the picker overwrites, restored on close
    byte[0x0200] map_save  ; BG3 tilemap window band, same
    byte[0x000B] dma_save  ; DMA channel 3 ($4330-$433A), saved across the picker's transfers
}
.reserve key_item_picker as KeyItemPicker in rolling_state
