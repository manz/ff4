sram_size_2kb_blocks:
    .dw 0  ; 0x00 = 0KB (no SRAM) = 0 blocks
    .dw 1  ; 0x01 = 2KB = 1 block
    .dw 2  ; 0x02 = 4KB = 2 blocks
    .dw 4  ; 0x03 = 8KB = 4 blocks
    .dw 8  ; 0x04 = 16KB = 8 blocks
    .dw 16  ; 0x05 = 32KB = 16 blocks
    .dw 32  ; 0x06 = 64KB = 32 blocks
    .dw 64  ; 0x07 = 128KB = 64 blocks (maximum)

clear_ram:
    jsr.l 0x15C9AA
    lda.b #1
    jsr.w _clear_ram

    rtl

_clear_ram:
{
; Get RAM size from ROM header
    lda.l 0x00FFD8  ; Load RAM size from ROM header (8-bit)
    cmp.b #0x07  ; Check if value > 7
    bcc _size_ok  ; Branch if value <= 7
    lda.b #0x07  ; Clamp to maximum supported value (7)
_size_ok:
    rep #0x20  ; Switch to 16-bit mode
    and.w #0x00FF  ; Clear high byte (ensure 8-bit value)
    asl  ; Convert to word offset (multiply by 2)
    tax  ; X = offset into lookup table

    lda.w sram_size_2kb_blocks, x  ; Load number of 2KB blocks
    beq _done  ; If 0 blocks, nothing to clear
    pha  ; Push block count to stack

; Set data bank to SRAM bank $70
    sep #0x20  ; Switch to 8-bit for bank operations
    phb  ; Save current data bank
    lda.b #0x70  ; Load SRAM bank $70
    pha  ; Push bank
    plb  ; Set data bank to $70

    rep #0x20  ; Back to 16-bit mode
    lda.w #0x0000  ; A = 16-bit zero value
    ldx.w #0x0000  ; X = offset within current bank

_block_loop:
; Clear one 2KB block (1024 words = $400 words)
    ldy.w #0x0000  ; Y = word count within current 2KB block

_clear_2kb:
    sta.w 0x0000, x  ; Store 16-bit word at current address
    inx  ; Increment offset by 2 bytes
    inx
    iny  ; Increment word count
    cpy.w #0x0400  ; 2KB = 1024 words = $400 words
    bne _clear_2kb

; Check if we need to switch banks (X >= $8000)
    cpx.w #0x8000
    bcc _same_bank  ; Stay in same bank if X < $8000

; Switch to next SRAM bank
    sep #0x20  ; Switch to 8-bit for bank operations
    lda.b 0x01, s  ; Peek at stack to get current bank
    inc  ; Next bank
    cmp.b #0x7E  ; Check if we've gone past SRAM banks
    bcs _done_with_bank  ; If >= $7E, we're done
    pha  ; Push new bank
    plb  ; Set new data bank
    rep #0x20  ; Back to 16-bit
    ldx.w #0x0000  ; Reset offset to start of new bank
    lda.w #0x0000  ; Reload zero value
    bra _check_more_blocks

_same_bank:
    rep #0x20  ; Ensure 16-bit mode
    lda.w #0x0000  ; Reload zero value

_check_more_blocks:
; Decrement block counter on stack
    sep #0x20  ; Switch to 8-bit for stack operations
    pla  ; Pull block count
    dec  ; Decrement count
    pha  ; Push back to stack
    rep #0x20  ; Back to 16-bit for next iteration
    lda.w #0x0000  ; Reload zero value
    bne _block_loop  ; If not zero, clear next block

_done_with_bank:
    sep #0x20  ; Switch to 8-bit
    pla  ; Clean up stack (remove the 0)
    plb  ; Restore original data bank

_done:
}
