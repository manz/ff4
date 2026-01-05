; ===========================================================================
; FF4 Battle Math - Relocated Mult16 Implementation
; Called from JMP trampoline at $83B9 (in math_patches.s)
;
; 16x16 -> 32-bit multiplication using SNES hardware multiplier
; Input:  $393D (16-bit) * $393F (16-bit)
; Output: $3941 (low 16-bit), $3943 (high 16-bit)
; ===========================================================================

.macro shorta() {
    sep #0x20
}

.macro shorta0() {
    tdc
    shorta()
}

hw_mult16:
    php
    rep #0x30           ; 16-bit A, X, Y
    stz 0x3941          ; Clear result low
    stz 0x3943          ; Clear result high
    sep #0x20           ; 8-bit A for hardware multiply registers

    ; The SNES hardware multiplier only does 8x8->16
    ; For 16x16->32, we need: (AH*256 + AL) * (BH*256 + BL)
    ;   = AH*BH*65536 + AH*BL*256 + AL*BH*256 + AL*BL
    ; We compute 4 partial products and add them with proper alignment.

    ; 1. Low(A) * Low(B) -> result bytes 0-1
    lda 0x393d          ; A low byte
    sta 0x4202          ; WRMPYA - multiplicand
    lda 0x393f          ; B low byte
    sta 0x4203          ; WRMPYB - multiplier (triggers multiply)
    nop
    nop                 ; Wait 8 cycles for result
    rep #0x20
    lda 0x4216          ; RDMPYL/H - 16-bit result
    sta 0x3941          ; Store in result bytes 0-1

    ; 2. Low(A) * High(B) -> add to result bytes 1-2
    sep #0x20
    lda 0x393d          ; A low byte
    sta 0x4202
    lda 0x3940          ; B high byte ($393F + 1)
    sta 0x4203
    nop
    nop
    rep #0x20
    lda 0x4216
    clc
    adc 0x3942          ; Add to result bytes 1-2 (with carry to byte 3)
    sta 0x3942

    ; 3. High(A) * Low(B) -> add to result bytes 1-2
    sep #0x20
    lda 0x393e          ; A high byte ($393D + 1)
    sta 0x4202
    lda 0x393f          ; B low byte
    sta 0x4203
    nop
    nop
    rep #0x20
    lda 0x4216
    clc
    adc 0x3942          ; Add to result bytes 1-2
    sta 0x3942

    ; 4. High(A) * High(B) -> add to result bytes 2-3
    sep #0x20
    lda 0x393e          ; A high byte
    sta 0x4202
    lda 0x3940          ; B high byte
    sta 0x4203
    nop
    nop
    rep #0x20
    lda 0x4216
    clc
    adc 0x3943          ; Add to result bytes 2-3
    sta 0x3943

    shorta0()           ; TDC + SEP #$20 - clear high byte of A, 8-bit mode
    plp
    rtl
