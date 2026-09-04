"""
Test stub for menu-font kerning lookups (small_vwf, battle message)  ;
symbols `pair`, `kerning_func`, `prev_char` injected from Python before assembly.
"""
; Test stub for menu-font kerning lookups (small_vwf, battle message).
; Symbols `pair`, `kerning_func`, `prev_char` injected from Python.
;
; Menu-font routines self-manage bank and read the pair from `prev_char`.
; `prev_char` is a full 24-bit address: small_vwf keeps it in SRAM (off
; the field's direct page, which aliases the MOSAIC shadow), while the
; battle renderer still keeps its own on direct page, which a long store
; reaches all the same with D = 0. No setup_font call is needed.

.map identifier=1 bank_range=0x00, 0x6f addr_range=0x8000, 0xffff mask=0x8000 mirror_bank_range=0x80, 0xcf
.map identifier=2 bank_range=0x7e, 0x7f addr_range=0x0000, 0xffff mask=0x10000 writable=1

*=0x7E0000
    rep #0x30
    lda.w #pair
    sta.l prev_char
    jsr.l kerning_func
    stp
