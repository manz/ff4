"""
Retargets the `JSL $01EBD2` (InitBGScrollHDMA) at $02:818A to the bank-$20 copy, freeing the original's space.
"""
.import "ingame/init_bg_scroll_hdma"

.alloc at 0x02818A {
    jsr.l init_bg_scroll_hdma
}
