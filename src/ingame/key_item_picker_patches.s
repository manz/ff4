

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

Replace 4 bytes at $00:AF4D-$00:AF50 with `JSL key_item_init_impl`.
init_impl ends with RTL (from engine_init_rolling_buffer macro), pops
24-bit return = $00:AF51, where we stash an RTS to bail back to
EventCmd_f7's $00:ED9E continuation.

Original bytes at $00:AF4D-$00:AF52:
  A5 CC      LDA $CC  ; wait-loop: $CC = player gfx flag
  D0 FC      BNE $AF4D
  A9 01      LDA #$01

Patched:
  22 LL MM HH JSL key_item_init_impl
  60          RTS
  A9 01       (original LDA #$01 stays — never reached after RTS)
"""


.if TREASURE_INVENTORY_ROLLING {
; TODO : wire `jsr.l key_item_render_all` at $00:AF4D once the picker
; has a VRAM strategy that doesn't garble the room/map underneath. The
; picker triggers from event scripts mid-map (EventCmd_f7), so unlike
; the field menu we cannot blow away the BG3 CHR slice the room is
; using. Two viable paths : (a) save/restore around picker entry/exit,
; (b) reserve picker-only VRAM that the map provably never touches.
; Engine code at `key_item_render_all` + `key_item_init_impl` is in
; place but currently unreachable.
; UpdateItemText at $00:B22B reads scroll pos $BA, multiplies by 4
; (asl asl) for 2-col x 2-byte stride into $0712. Single-col layout
; needs stride = 2, so replace the 2nd `asl` at $00:B232 with NOP.
;
; Items per page: $07 init at $00:B23C = 8 (4 rows x 2 cols).
; For single-col we render N rows (visible items in the picker
; window). Original window is 4 rows; replace #$08 with #$04.
;
; Both patches surgical 1-byte: keep original layout, change scroll
; stride + per-page count so it walks $0712 as single-col.
; UpdateItemText scroll stride: original `lda $ba / asl asl / tax`
; means scroll-step indexes 4 bytes (2 cols × 2 bytes). Single-col
; needs stride 2 (1 col × 2 bytes). NOP the 2nd asl at $00:B23C.
;
; Layout still 2-col due to the +#$0D / +#$0B col-toggle at $00:B2B5
; / $00:B2BF — those would need a wider single-row stride patch
; (text buffer is 13 chars/half-row × 2 = 26 wide) which is more
; invasive. Keep 2-col layout for now, single-stride scroll lets
; us walk the filtered $0712 in step with the engine's worldview.
    *=0x00B23C
    nop

; Items per page: original `lda #$08` → 4 (single-col 4 rows).
    *=0x00B245
    lda #0x04

; Replace the inline id*9 multiplier at $00:B253-B26C with a
; jsl multiply_by_17 chain. A is item-id on entry (just loaded via
; lda $0712,x at $B24B), returns A = id * ITEM_UNLEASHED_RECORD_SIZE.
; Move into X for the existing inner-loop indexed
; `lda.l assets_items_unleashed_dat, x` read. The original block was
; 26 bytes ($B253..$B26C); replacement uses 9 bytes, padded with NOP
; to keep downstream instruction addresses ($B26F lda#, $B273 lda.l
; ...) anchored.
    *=0x00B253
    rep #0x10
    jsr.l multiply_by_17
    tax
    inx
    pad_nop(18)

; Inner-name-write loop count at $00:B26F: original `lda #$08`
; (8 letters per name). Bump to ITEM_UNLEASHED_TEXT_SIZE.
    *=0x00B26F
    lda #ITEM_UNLEASHED_TEXT_SIZE

; Item-name table source at $00:B273: original `lda.l $0F8000,x`
; (JP layout). Redirect to assets_items_unleashed_dat.
    *=0x00B273
    lda.l assets_items_unleashed_dat, x

; Make both column-toggle branches advance Y by 24 (full text-buffer
; row, 12 chars). Both → `adc #$18` so every item lands on its own
; row regardless of which column the toggle picks. Keep at 24
; for now ; widening to fit a 16-char name + colon + qty requires
; revisiting the picker's tilemap row stride too.
    *=0x00B2B5
    adc #0x18
    *=0x00B2BF
    adc #0x18

; Item-text layout post-name: original writes ":" at +8 ($077C), tens
; at +9 ($077D), ones at +10 ($077E). 12-char names pushed the trio
; to $0780/81/82. 16-char names need another +4 to land past the name
; (assets_items_unleashed_dat = symbol + 16 chars), so trio sits at
; $0784/85/86 with the same 1-tile spacer between name and colon.
    *=0x00B28E
    sta 0x0784, y
    *=0x00B2A4
    sta 0x0785, y
    *=0x00B2A9
    sta 0x0786, y

; Single-col picker has no col-1 to move cursor to. NOP the JOY_RIGHT
; check at $00:AFB0 by replacing the AND mask with $00 — beq always
; taken, right-button branch skipped. Original:
;   AFB0: A5 03      lda $03
;   AFB2: 29 01      and #$01     ← JOY_RIGHT mask
;   AFB4: F0 1A      beq +$1A
    *=0x00AFB2
    and #0x00

; A-select index calc at $00:AF9C: original
;   lda $ba / clc / adc $8c / asl / clc / adc $8b / asl / tax
;   index = (($ba + $8c) * 2 + $8b) * 2  = ($ba+$8c)*4
; Single col: drop the col mix-in AND the second asl, so
; index = ($ba + $8c) * 2 (one item = 2 bytes id+qty).
;   $00:AFA2 clc / adc $8b (3 bytes) → 3 NOPs
;   $00:AFA5 asl (1 byte) → NOP
    *=0x00AFA2
    pad_nop(3)
    *=0x00AFA5
    nop
}
