"""
Battle put-char primitives: the `battle_flags` render-mode toggles and the WRAM-mode put-char routines.

The message renderer and the `battle/sram` dispatch tables both call these, so they live below both.
"""
.import "preamble"
.import "dakuten"
.include "src/battle/sram.i"
.include "../bank20.i"

_BATTLE_DAKUTEN_TABLE = 0x16FA40

.alloc _battle_put_char_block in bank20_reloc {
    .scope battle_flags {
    """Battle-flags toggles for switching the message renderer between WRAM tiles and VWF."""
set_vwf_render:
"""NOTE: set_sram_copy and clear_sram_copy removed - SRAM mode no longer used"""
    battle_flags_set(0x02)
    rtl
clear_vwf_render:
    battle_flags_clear(0x02)
    rtl
    }

_copy_battle_char:
"""Copy a glyph + its dakuten companion from the SRAM staging area to the destination pair."""
    lda.l sram_base + 0x2E00, x
    sta (0x00), y
    lda.l sram_base + 0x2E00 + 0x30, x
    sta (0x02), y
    rtl

    .scope wram {
    """WRAM-mode put-char primitives used by the original battle text renderer."""
put_char:
    phx
    sta (0x34), y
    lda #0xFF
    sta (0x32), y
    iny
    lda 0x36
    sta (0x32), y
    sta (0x34), y
    iny
    plx
    rtl
put_char_with_dakuten:
    phx
    .if 0 {
    sec
    sbc #0xF
    asl
    tax
    lda.l _BATTLE_DAKUTEN_TABLE, x
    sta (0x32), y
    lda.l _BATTLE_DAKUTEN_TABLE + 1, x
    sta (0x34), y
    } else {
    jsr.l lookup_dakuten
    sta (0x32), y
    xba
    sta (0x34), y
    lda #0x00
    xba
    }
    iny
    lda 0x36
    sta (0x32), y
    sta (0x34), y
    iny
    plx
    rtl
    }

; NOTE: sram scope removed - SRAM mode no longer used
; .scope sram { put_char, put_char_with_dakuten }
}
