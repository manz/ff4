

"""
Key-item picker ROM patches.

Hijack original ShowItemWindow at $00:AF4D (NOT $00:AF4B — the
ff4decomp notes file is off by 2 bytes  ; the real entry verified via
EventCmd_f7's `JSR $AF4D` opcode at $00:ED9B-$ED9D in original bytes).

EventCmd_f7 ($00:ED96) flow:
  $00:ED98: INX  ; advance script PC
  $00:ED99: STX $B3  ; save script PC
  $00:ED9B: JSR $AF4D  ; <-- ShowItemWindow entry
  $00:ED9E: JSR ...

ShowItemWindow itself is left in place: vanilla still opens, scrolls
and closes the window, and the hooks below put the engine's ring in it.
"""
.import "core/items"


.import "core/assets"
.import "ingame/key_item_picker"
.import "core/bank20_helpers"
.include "core/libmz.i"


.import "core/vanilla"
; Silence vanilla's own list draw. UpdateItemText ($00:B22B) lays the
; WHOLE filtered list into the window band and vanilla then scrolls over
; it with $BB ; with the engine drawing its ring into the same band the
; list came out twice over.
.alloc at 0x00B22B {
    rts
}


; Window scrolling, over the engine's ring instead of a fully drawn
; list. Vanilla ScrollItemListUp/Down each animate $BB by 2px a frame
; for 8 frames ; the replacements keep that cadence, then step back onto
; the ring and redraw it.
.alloc at 0x00B08E {
    jsr.l key_item_scroll_up_impl
    rts
}


.alloc at 0x00B09E {
    jsr.l key_item_scroll_down_impl
    rts
}


; Hand the map its VRAM back as the window closes. Vanilla's close
; animation ends with `lda #$01 ; sta $ec` at $00:B06E, the last thing
; before ShowItemWindow returns.
.alloc at 0x00B06E {
    jsr.l key_item_close_impl
}


; Scroll ceiling, from the list actually built. Replaces exactly the
; four bytes of `lda $ba / cmp #$11` at $00:B00D; the `bne $B016` that
; follows still decides whether to scroll.
;   B00D A5 BA     lda $ba
;   B00F C9 11     cmp #$11
.alloc at 0x00B00D {
    jsl key_item_scroll_limit_impl
}


; Cursor address, folded into the rolling ring. In our ROM:
;   B13D A5 BA     lda $ba
;   B13F 18        clc
;   B140 65 8C     adc $8c
;   B142 85 4B     sta $4b
; (the ff4decomp notes place this block at $B13B - bank $00 there runs
; two bytes behind ours from $0089ED on, the same drift
; utils/import_decomp_labels.py re-anchors around.)
.alloc at 0x00B13D {
    jsr.l key_item_cursor_slot_impl
    pad_nop(3)
}


; Render the list through the rolling engine once the window is open.
; Hooks `lda #$01 ; sta $7D` at $00:AF7E and reproduces the store ; the
; `jsr $912F` above it is vanilla's frame wait for this input loop and
; has to stay.
.alloc at 0x00AF7E {
    jsr.l key_item_after_open_impl
}


; UpdateItemText at $00:B22B reads scroll pos $BA and multiplies by 4
; (asl asl, 2 cols x 2 bytes) to index $0712. Single-col needs stride 2
; (1 col x 2 bytes), so NOP the 2nd asl at $00:B23C.
;
; Layout stays 2-col: the +#$0D / +#$0B col-toggle at $00:B2B5 / $00:B2BF
; stays. A single-row stride would need a wider patch (the text buffer is
; 13 chars per half-row x 2 = 26 wide). The single-stride scroll walks the
; filtered $0712 in step with the engine.
.alloc at 0x00B23C {
    nop

; Items per page: original `lda #$08` → 4 (single-col 4 rows).
}


.alloc at 0x00B245 {
    lda #0x04

; Replace the inline id*9 multiplier at $00:B253-B26C with a
; call to item_name_offset. A is item-id on entry (just loaded via
; lda $0712,x at $B24B), returns A = the name's offset in items_unleashed.
; Move into X for the existing inner-loop indexed
; `lda.l items_unleashed, x` read. The original block was
; 26 bytes ($B253..$B26C); replacement uses 8 bytes, padded with NOP
; to keep downstream instruction addresses ($B26F lda#, $B273 lda.l
; ...) anchored.
}


.alloc at 0x00B253 {
    rep #0x10
    jsr.l item_name_offset
    tax
    inx
    pad_nop(18)

; Inner-name-write loop count at $00:B26F: original `lda #$08`
; (8 letters per name). Bump to ITEM_UNLEASHED_TEXT_SIZE.
}


.alloc at 0x00B26F {
    lda #ITEM_UNLEASHED_TEXT_SIZE

; Item-name table source at $00:B273: original `lda.l $0F8000,x`
; (JP layout). Redirect to items_unleashed.
}


.alloc at 0x00B273 {
; names are NUL-terminated: past the end, spaces, X held on the $00
    jsr.l item_name_char

; Make both column-toggle branches advance Y by 24 (full text-buffer
; row, 12 chars). Both → `adc #$18` so every item lands on its own
; row regardless of which column the toggle picks. Widening to fit a
; 16-char name + colon + qty requires the picker's tilemap row stride
; to change too.
}


.alloc at 0x00B2B5 {
    adc #0x18
}


.alloc at 0x00B2BF {
    adc #0x18

; Item-text layout post-name: original writes ":" at +8 ($077C), tens
; at +9 ($077D), ones at +10 ($077E). 12-char names pushed the trio
; to $0780/81/82. 16-char names need another +4 to land past the name
; (items_unleashed = symbol + 16 chars), so trio sits at
; $0784/85/86 with the same 1-tile spacer between name and colon.
}


.alloc at 0x00B28E {
    sta.w dialog_text_buffer + 0x10, y
}


.alloc at 0x00B2A4 {
    sta.w dialog_text_buffer + 0x11, y
}


.alloc at 0x00B2A9 {
    sta.w dialog_text_buffer + 0x12, y

; Single-col picker has no col-1 to move cursor to. NOP the JOY_RIGHT
; check at $00:AFB0 by replacing the AND mask with $00, which leaves the
; beq always taken and skips the right-button branch. Original:
;   AFB0: A5 03      lda $03
;   AFB2: 29 01      and #$01     ← JOY_RIGHT mask
;   AFB4: F0 1A      beq +$1A
}


.alloc at 0x00AFB2 {
    and #0x00

; A-select index calc at $00:AF9C: original
;   lda $ba / clc / adc $8c / asl / clc / adc $8b / asl / tax
;   index = (($ba + $8c) * 2 + $8b) * 2  = ($ba+$8c)*4
; Single col: drop the col mix-in AND the second asl, so
; index = ($ba + $8c) * 2 (one item = 2 bytes id+qty).
;   $00:AFA2 clc / adc $8b (3 bytes) → 3 NOPs
;   $00:AFA5 asl (1 byte) → NOP
}


.alloc at 0x00AFA2 {
    pad_nop(3)
}


.alloc at 0x00AFA5 {
    nop
}
