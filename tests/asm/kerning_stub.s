; Test stub run from kintsuki Python tests.
; Symbols `pair`, `kerning_func`, `font_index`, `setup_font` are injected
; into a816's resolver from Python before assembly.
;
; STP halts the CPU; Python detects cpu_state.stp == 1 and reads A.

.map identifier=1 bank_range=0x00, 0x6f addr_range=0x8000, 0xffff mask=0x8000 mirror_bank_range=0x80, 0xcf
.map identifier=2 bank_range=0x7e, 0x7f addr_range=0x0000, 0xffff mask=0x10000 writable=1

*=0x7E0000

; 8-bit A and X/Y; setup_font and the kerning helpers were written
; against this convention.
    sep #0x30

    lda.b #font_index
    jsr.l setup_font

; Match the in-game caller: 16-bit A and X/Y. Pair lives in
; CURRENT_C; the routine indexes [font_addr],y with 16-bit Y.
    rep #0x30
    lda.w #pair
    sta.b CURRENT_C
    jsr.l kerning_func
    stp
