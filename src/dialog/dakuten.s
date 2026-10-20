"""
Dakuten composite-glyph table + `lookup_dakuten` helper that maps a character code to its
dakuten/handakuten composite tile pair.
"""


.include "core/bank20.i"
.import "core/assets"
.alloc lookup_dakuten in bank20_reloc {
"""A = current char (8 bits) -> A = the resolved char (16 bits)."""


    {
        php
        sep #0x20
        cmp.l dakuten_pairs
        bmi _char_out_of_range
        cmp.l dakuten_pairs + 2
        bpl _char_out_of_range

        phx
        rep #0x20
        and.w #0x00ff
        sec
        sbc.l dakuten_pairs
        asl
        tax

        lda.l dakuten_pairs + 4, x

        sep #0x20
        plx
        bra _exit
_char_out_of_range:
        xba
        lda #0xff

_exit:
        plp
        rtl
    }

_store_char_with_dakuten:
    {
        jsr.l lookup_dakuten
        cmp #0xff
        beq _skip
        sta.l 0x7E0000, x
_skip:

        sta.l 0x7E0040, x

        rtl
    }
}
