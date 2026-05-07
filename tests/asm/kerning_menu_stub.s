"""
Test stub for menu-font kerning lookups (small_vwf, battle message)  ;
symbols `pair`, `kerning_func`, `prev_char` injected from Python before assembly.
"""
; Test stub for menu-font kerning lookups (small_vwf, battle message).
; Symbols `pair`, `kerning_func`, `prev_char` injected from Python.
;
; Menu-font routines self-manage bank and read the pair from `prev_char`
; on the direct page. No setup_font call is needed (no font_addr indirect).

.map identifier=1 bank_range=0x00, 0x6f addr_range=0x8000, 0xffff mask=0x8000 mirror_bank_range=0x80, 0xcf
.map identifier=2 bank_range=0x7e, 0x7f addr_range=0x0000, 0xffff mask=0x10000 writable=1

*=0x7E0000
    rep #0x30
    lda.w #pair
    sta.b prev_char
    jsr.l kerning_func
    stp
