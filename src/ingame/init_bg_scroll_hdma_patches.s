"""
Caller-side patches retargeting `JSL $01EBD2` (original `InitBGScrollHDMA`) to the relocated copy in bank $20,
so the original's ROM space can be reclaimed.
"""
.import "ingame/init_bg_scroll_hdma"

;; Original `JSL $01EBD2` at $02:818A becomes `JSL init_bg_scroll_hdma`
;; (bank20_reloc).

.alloc at 0x02818A {
    jsr.l init_bg_scroll_hdma
}
