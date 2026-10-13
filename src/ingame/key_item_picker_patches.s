

"""
Key-item picker hooks into ShowItemWindow ($00:AF4D, called by EventCmd_f7). Vanilla still opens, scrolls and
closes the window; the hooks put the engine's ring in it.

Bank $00 addresses here are 2 bytes past the ff4decomp notes from $00:89ED on.
"""
.import "core/items"


.import "core/assets"
.import "ingame/key_item_picker"
.import "core/bank20_helpers"
.include "core/libmz.i"


.import "core/vanilla"
; Silence UpdateItemText ($00:B22B): it draws the whole list into the band the ring uses.
.alloc at 0x00B22B {
    rts
}


; ScrollItemListUp / Down over the ring, same 8-frame cadence.
.alloc at 0x00B08E {
    jsr.l key_item_scroll_up_impl
    rts
}


.alloc at 0x00B09E {
    jsr.l key_item_scroll_down_impl
    rts
}


; Restore the map's VRAM at the end of the close animation (`lda #$01 / sta $ec`).
.alloc at 0x00B06E {
    jsr.l key_item_close_impl
}


; Scroll ceiling from the real item count: replaces the 4 bytes `lda $ba / cmp #$11`; `bne $B016` follows.
.alloc at 0x00B00D {
    jsl key_item_scroll_limit_impl
}


; Cursor row as a ring slot: replaces `lda $ba / clc / adc $8c / sta $4b` (7 bytes).
.alloc at 0x00B13D {
    jsr.l key_item_cursor_slot_impl
    pad_nop(3)
}


; Per-frame render hook over `lda #$01 / sta $7D`. The `jsr $912F` frame wait above it must stay.
.alloc at 0x00AF7E {
    jsr.l key_item_after_open_impl
}


; UpdateItemText patches (the routine itself is silenced above).
; List stride: $BA * 2 (single column), not * 4.
.alloc at 0x00B23C {
    nop
}
; Items per page: 8 -> 4.


.alloc at 0x00B245 {
    lda #0x04
}
; Name offset: `item_name_offset` instead of the inline id * 9 ($B253-$B26C), NOP-padded to keep $B26F anchored.


.alloc at 0x00B253 {
    rep #0x10
    jsr.l item_name_offset
    tax
    inx
    pad_nop(18)
}
; Name length: 8 -> ITEM_UNLEASHED_TEXT_SIZE.


.alloc at 0x00B26F {
    lda #ITEM_UNLEASHED_TEXT_SIZE
}
; Name source: `lda.l $0F8000, x` -> items_unleashed.


.alloc at 0x00B273 {
; names are NUL-terminated: past the end, spaces, X held on the $00
    jsr.l item_name_char
}
; Both column-toggle branches advance Y a full row ($18), one item per row.


.alloc at 0x00B2B5 {
    adc #0x18
}


.alloc at 0x00B2BF {
    adc #0x18
}
; Colon, tens, ones past the 16-char name: +$10 / +$11 / +$12 (vanilla +8 / +9 / +10).


.alloc at 0x00B28E {
    sta.w dialog_text_buffer + 0x10, y
}


.alloc at 0x00B2A4 {
    sta.w dialog_text_buffer + 0x11, y
}


.alloc at 0x00B2A9 {
    sta.w dialog_text_buffer + 0x12, y
}
; No second column: the JOY_RIGHT mask becomes $00 so the `beq` always skips the right-button branch.


.alloc at 0x00AFB2 {
    and #0x00
}
; A-select index ($00:AF9C): ($BA + $8C) * 2, dropping the column add ($AFA2) and the second asl ($AFA5).


.alloc at 0x00AFA2 {
    pad_nop(3)
}


.alloc at 0x00AFA5 {
    nop
}
