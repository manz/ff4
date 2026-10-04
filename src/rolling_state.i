"""
Reserved state for the rolling-inventory menus.

Kept out of `items.i` because that file is included from inside `.alloc`
bodies, and placement directives cannot nest.
"""


; --- Rolling-menu state pool -------------------------------------------
;
; Hand-picking scratch addresses has cost us repeatedly: bank-$00
; aliases that wrote to ROM, a 256-byte buffer running past the free
; gap, engine scratch landing on live field state. Reserve out of a pool
; instead and let the assembler place things and check for overlap.
;
; The pool lives in the cart's SRAM, past the VWF buffers. The header is
; patched to 128KB and the boot path clears it, so bank $70 is ours
; alone - no vanilla code, no menu/field context switch, nothing to
; collide with. ff4.s declares the bank in the memory map so a bss pool
; can be placed here.
;
; In use below $7200: VWF CHR buffer ($3000), VRAM save window ($5000),
; VWF text buffer + config + flags ($7000..$70CC), battle render state
; ($7100).
.pool rolling_state {
    range 0x707200 0x707FFF
    strategy order
}

; Engine scratch for the refresh loop's scroll_pos / buffer_slots. Was
; $00:1F88, i.e. WRAM the field engine is free to use.
.alloc rolling_engine_scratch in rolling_state {
    .res 2
}


; --- Key-item picker ---------------------------------------------------
; Snapshot of the caller's direct page while the picker renders: the menu
; VWF renderer scratches bytes the field engine owns.
; Caller's direct-page register, held while the picker renders on its
; own page.
.alloc key_item_dp_prev in rolling_state {
    .res 2
}

; How many key items the filter actually accepted. Vanilla hardcoded a
; 17-position scroll ceiling for a list it drew in full; the picker's
; list is built per save, so the ceiling has to come from the count.
.alloc key_item_count in rolling_state {
    .res 1
}

; Vanilla's window-slide counter ($DA) as last seen by the per-frame
; hook, its scroll position ($BA) as last rendered, the engine-side
; scroll position, and the window-scroll animation's frame counter.
.alloc key_item_open_slide_seen in rolling_state {
    .res 1
}
.alloc key_item_last_scroll in rolling_state {
    .res 1
}
.alloc key_item_scroll_pos in rolling_state {
    .res 1
}
.alloc key_item_scroll_frames in rolling_state {
    .res 1
}

; VRAM the picker overwrites while it is open, saved so the map gets it
; back on close: its glyph CHR window and the window band of BG3's
; tilemap. Both are live map data on maps that use high BG3 tile ids -
; nothing else saves them, and the leftovers showed as scrambled map.
.alloc key_item_chr_save in rolling_state {
    .res 0x0460
}
.alloc key_item_map_save in rolling_state {
    .res 0x0200
}

; DMA channel registers ($4330-$433A) saved across the picker's own
; transfers. Reprogramming a channel steals it from whatever HDMA the
; map has armed on it - a pixelate/mosaic effect mid-animation, say -
; and the effect never gets its registers back.
.alloc key_item_dma_save in rolling_state {
    .res 0x000B
}
