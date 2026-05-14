"""
Relocated battle equipped-items window transfer routine.

Pivots the per-character equip popup from `R-label  L-label / R-item  L-item` (two columns of stacked
label-over-item) to `R-label  R-item / L-label  L-item` (label and item on the same row, per hand).

Layout in the 32x7 window:
    Row 0: slot-1 label (10 tiles, cols 0-9)  | slot-1 item top (15 tiles, cols 14-28)
    Row 1: <blank>                             | slot-1 item bot
    Row 2: slot-2 label                        | slot-2 item top
    Row 3: <blank>                             | slot-2 item bot

Driven by:
    RLHand buf (40 bytes/char) : tile entries 0..9 = slot-1 label, 10..19 = slot-2 label
    EquipBuf   (120 bytes/char): bytes 0..$3B = slot-1 item (top 0..$1D, bot $1E..$3B)
                                 bytes $3C..$77 = slot-2 item ($3C..$59 top, $5A..$77 bot)

Tilemap dest bases (set by hooks in items_patches.s):
    $00 = $D1E8 (label column)
    $02 = $D204 (item column, $00 + $1C)
"""


.extern load_menu_tfr_data_trampoline

tfr_equip_window_new:
"""
Relocated replacement for vanilla `TfrEquipWindow` at $02:97A6.

Walks 6 per-block transfer passes: slot-1 / slot-2 labels into the
left column (rows 1 and 3), slot-1 / slot-2 item top+bot halves into
the right column (rows 0-1 and 2-3 respectively). Caller is the
bank-02 trampoline that JSLs here  ; return via RTL.
"""


{
    rep #0x10  ; X/Y 16-bit at runtime (caller may have X=1)
    ldx.w #0xD1E8
    stx 0x00
    ldx.w #0xD204
    stx 0x02
    lda 0x1822
    asl
    tax
    rep #0x20
    lda.l 0x16FEC1, x  ; EquipTextBufPtrs
    pha
    lda.l 0x16FF25, x  ; RLHandTextBufPtrs
    tax
    sep #0x20

; --- Pass A: slot-1 label -> LEFT col row 1 (buf[0..$13]) ---
    ldy.w #0x0040
loop_a:
    lda.w 0x0000, x
    sta (0x00), y
    inx
    iny
    cpy.w #0x0054
    bne loop_a

; --- Pass B: slot-2 label -> LEFT col row 3 (buf[$14..$27]) ---
    ldy.w #0x00C0
loop_b:
    lda.w 0x0000, x
    sta (0x00), y
    inx
    iny
    cpy.w #0x00D4
    bne loop_b

; --- Switch to EquipBuf ---
    plx

; --- Pass C: slot-1 item top -> RIGHT col row 0 (buf[0..$1D]) ---
    ldy.w #0x0000
loop_c:
    lda.w 0x0000, x
    sta (0x02), y
    inx
    iny
    cpy.w #0x001E
    bne loop_c

; --- Pass D: slot-1 item bot -> RIGHT col row 1 (buf[$1E..$3B]) ---
    ldy.w #0x0040
loop_d:
    lda.w 0x0000, x
    sta (0x02), y
    inx
    iny
    cpy.w #0x005E
    bne loop_d

; --- Pass E: slot-2 item top -> RIGHT col row 2 (buf[$3C..$59]) ---
    ldy.w #0x0080
loop_e:
    lda.w 0x0000, x
    sta (0x02), y
    inx
    iny
    cpy.w #0x009E
    bne loop_e

; --- Pass F: slot-2 item bot -> RIGHT col row 3 (buf[$5A..$77]) ---
    ldy.w #0x00C0
loop_f:
    lda.w 0x0000, x
    sta (0x02), y
    inx
    iny
    cpy.w #0x00DE
    bne loop_f

; --- Trigger tilemap upload (window 7, 2 transfers) ---
    lda #0x07
    ldy.w #0x0002
    jsr.l load_menu_tfr_data_trampoline
    lda #0x01
    sta 0x1825
    sta 0x1824
    rtl
}
