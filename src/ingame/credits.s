"""
Staff credits: points the text loader at `credits_text` and lengthens the cutscene for the extra text.
"""
.import "core/assets"


.alloc at 0x13d7ef {
    ldx.w #credits_text & 0xffff
}
.alloc at 0x13d7f5 {
    lda.b #credits_text >> 16
}
; Longer cutscene for the additional text.
.alloc at 0x13d61d {
    lda.b #0x20
}
.alloc at 0x13d623 {
    lda.b #0x0b
}
.alloc at 0x13f016 {
    .incbin "the_end_gfx.bin"
}
