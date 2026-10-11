"""
Patches that re-point the bank-2 hardware multiplier (`Mult8` at $8560) at our reimplementation, plus the JMP
trampoline at $83B9 jumping into `_hw_mult16`.
"""

.import "preamble"
.import "vanilla"
.include "config.i"
.include "../bank20.i"

.if BATTLE_ENABLED {
; ===========================================================================
; Mult8 at $8560 ($2a = $26 * $28) on the hardware multiplier, NMI-safe. Called via mult8_far ($855C) which does
; JSR Mult8; RTL.
; ===========================================================================

    .alloc at 0x028560 {
    jsr.l mult8_nmi_safe
    rts
    }

    .alloc _mult8_nmi_safe in bank20_reloc {
mult8_nmi_safe:
"""
$2a/$2b = $26 * $28 on the hardware multiplier (M = 8, X = 16; X, Y and DB kept, A = 0).

The battle NMI multiplies on the same hardware (vanilla MultHW, every frame). One landing between our WRMPYB
write and the RDMPYL read hands us its product: a text update read its table index as $20 for 0 * 6 and copied a
window's text from $0005 down through the stack page into the NMI vector. Every battle NMI ends with
`inc battle_frame_counter`: redo the multiply when it moved meanwhile.
"""
_mult8_retry:
    lda.l battle_frame_counter
    pha
    lda.b btlgfx_dp.multiplier1
    sta.l cpu_regs.WRMPYA
    lda.b btlgfx_dp.multiplier2
    sta.l cpu_regs.WRMPYB  ; starts the product: 8 cycles
    nop
    nop
    nop
    nop
    lda.l cpu_regs.RDMPYL
    sta.b btlgfx_dp.mult8_result
    lda.l cpu_regs.RDMPYH
    sta.b btlgfx_dp.mult8_result + 1
    pla
    cmp.l battle_frame_counter
    bne _mult8_retry
    lda.b #0x00
    rtl

mult_hw_nmi_safe:
"""
Vanilla MultHW ($02:85D2): hw_product = hw_multiplicand * hw_multiplier (M = 8, X = 16; X kept, A = 0). Same race
as mult8_nmi_safe: the battle NMI's sprite draw ($02:E41C) multiplies too, and so does the main thread's.
"""
_mult_hw_retry:
    lda.l battle_frame_counter
    pha
    lda.b btlgfx_dp.hw_multiplicand
    sta.l cpu_regs.WRMPYA
    lda.b btlgfx_dp.hw_multiplier
    sta.l cpu_regs.WRMPYB  ; starts the product: 8 cycles
    nop
    nop
    nop
    nop
    lda.l cpu_regs.RDMPYL
    sta.b btlgfx_dp.hw_product
    lda.l cpu_regs.RDMPYH
    sta.b btlgfx_dp.hw_product + 1
    pla
    cmp.l battle_frame_counter
    bne _mult_hw_retry
    tdc  ; A = 0 as vanilla leaves it (D = 0 in battle graphics)
    rtl
    }

    .alloc at 0x0285D2 {
    jsr.l mult_hw_nmi_safe
    rts
    }
}
