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
; The pool sits in the $7E:990E..$9DA7 hole the magic-direct-render
; rewrite freed (see the arena notes above), below the rolling state
; instances at $9C00. The extended SRAM in bank $70 would be the better
; home - it is ours alone and the boot path clears it - but a816's
; low_rom bus only knows $7E/$7F as writable, so a bss pool there fails
; the map check.
.pool rolling_state {
    bss
    range 0x7E9A00 0x7E9BFF
    strategy order
}

; Engine scratch for the refresh loop's scroll_pos / buffer_slots. Was
; $00:1F88, i.e. WRAM the field engine is free to use.
.reserve rolling_engine_scratch 2 in rolling_state


; --- Key-item picker ---------------------------------------------------
; Snapshot of the caller's direct page while the picker renders: the menu
; VWF renderer scratches bytes the field engine owns.
.reserve key_item_dp_save 0x0100 in rolling_state

; Vanilla's window-slide counter ($DA) as last seen by the per-frame
; hook, its scroll position ($BA) as last rendered, the engine-side
; scroll position, and the window-scroll animation's frame counter.
.reserve key_item_open_slide_seen 1 in rolling_state
.reserve key_item_last_scroll 1 in rolling_state
.reserve key_item_scroll_pos 1 in rolling_state
.reserve key_item_scroll_frames 1 in rolling_state
