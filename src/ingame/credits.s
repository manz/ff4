"""
In-place patches for the staff credits screen: re-point the credits text loader at our relocated
`credits_text` block.
"""
.import "assets"


.alloc at 0x13d7ef {
    ldx.w #credits_text & 0xffff
}
.alloc at 0x13d7f5 {
    lda.b #credits_text >> 16

; Augments cutscene duration to show the additional text.
}
.alloc at 0x13d61d {
    lda.b #0x20
}
.alloc at 0x13d623 {
    lda.b #0x0b
}
.alloc at 0x13f016 {
    .incbin "the_end_gfx.bin"
}
