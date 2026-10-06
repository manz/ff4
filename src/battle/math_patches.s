"""
Patches that re-point the bank-2 hardware multiplier (`Mult8` at $8560) at our reimplementation, plus the JMP
trampoline at $83B9 jumping into `_hw_mult16`.
"""

.import "preamble"
.import "vanilla"

; ===========================================================================
; Mult8 Hardware Implementation - Bank 2 version at $8560
; Input: $26, $28 → Output: $2a = $26 * $28
; Called via mult8_far ($855C) which does JSR Mult8; RTL
; Uses same pattern as existing MultHW at $85D2 (26 bytes, fits in 28)
; ===========================================================================

.alloc at 0x028560 {
    phx  ; Preserve X (original does this)
    lda.b btlgfx_dp.multiplier1
    sta.l cpu_regs.WRMPYA  ; Multiplicand
    lda.b btlgfx_dp.multiplier2
    sta.l cpu_regs.WRMPYB  ; Multiplier (triggers multiply)
; Wait using bank switch (same as MultHW)
    phb  ; 3 cycles
    lda #0x00  ; 2 cycles
    pha  ; 3 cycles
    plb  ; 4 cycles (DB=0 now, 12 cycles waited)
    ldx cpu_regs.RDMPYL  ; 16-bit X reads RDMPYL/H (X is 16-bit)
    stx.b btlgfx_dp.mult8_result  ; Store 16-bit result to $2a/$2b
    plb  ; Restore data bank
    plx
    rts
}
