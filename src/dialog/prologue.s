"""
The prologue (event special $09) scrolls up line by line, as vanilla's auto-scrolling dialogue did, instead of typing
pages: the special sets the dialogue's mode to SCROLL_LINES where vanilla set 1 (dialog/vwf.s).
"""
.import "core/preamble"
.include "dialog/vwf.i"

.alloc at 0x00D4C0 {
; Special_09 after its FadeIn: `lda #1 / sta $cb`
    lda.b #SCROLL_LINES
}
