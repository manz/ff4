"""
In-place patches for the staff credits screen: re-point the credits text loader at our relocated
`assets_credits_text_bin` block.
"""

.alloc at 0x13d7ef {
        ldx.w #assets_credits_text_bin & 0xffff
}
.alloc at 0x13d7f5 {
        lda.b #assets_credits_text_bin >> 16

    ; Augments cutscene duration to show the additional text.
}
.alloc at 0x13d61d {
        lda.b #0x20
}
.alloc at 0x13d623 {
        lda.b #0x0b
}
.alloc at 0x13f016 {
    .incbin "assets/the_end_gfx.bin"
}
