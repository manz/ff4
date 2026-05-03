; ===========================================================================
; Mult8 Hardware Implementation - Bank 2 version at $8560
; Input: $26, $28 → Output: $2a = $26 * $28
; Called via Mult8_far ($855C) which does JSR Mult8; RTL
; Uses same pattern as existing MultHW at $85D2 (26 bytes, fits in 28)
; ===========================================================================

*=0x028560
    phx  ; Preserve X (original does this)
    lda 0x26
    sta.l 0x004202  ; Multiplicand
    lda 0x28
    sta.l 0x004203  ; Multiplier (triggers multiply)
    ; Wait using bank switch (same as MultHW)
    phb  ; 3 cycles
    lda #0x00  ; 2 cycles
    pha  ; 3 cycles
    plb  ; 4 cycles (DB=0 now, 12 cycles waited)
    ldx 0x4216  ; 16-bit X reads RDMPYL/H (X is 16-bit)
    stx 0x2a  ; Store 16-bit result to $2a/$2b
    plb  ; Restore data bank
    plx
    rts
