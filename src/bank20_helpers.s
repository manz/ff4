"""
Small bank-$20 helpers the vanilla code reaches by JSL: the HDMA-aware BG1VOFS write, the cold-boot SRAM
clear and the 17-byte item-record multiplies.
"""
.import "preamble"
.import "items"
.include "config.i"
.include "bank20.i"

.alloc bank20_helpers in bank20_reloc {
; --- Inline reloc helpers ------------------------------------------------

; Conditional BG1VOFS write for HDMA inventory scrolling.
; Called from UpdateScrollRegs at $14FF2D via JSL.
; Skips BG1VOFS write when menu HDMA is active.
    .if INVENTORY_ROLLING_BUFFER {
conditional_bg1_vofs:
    lda.l field_menu_rolling.hdma_enable
    bne _cond_skip_bg1vofs
; HDMA not active - do original BG1VOFS writes
; Menu context: D=$0100, so $93 reads from $0193
    lda.b 0x93
    sta.w ppu.BG1VOFS
    lda.b 0x94
    sta.w ppu.BG1VOFS

_cond_skip_bg1vofs:
    rtl
    }


clear_ram:
"""
Clear the dialog VWF tile buffer + engine scratch at $702000-$7070FF
(includes VWF_CONFIG_BASE, VWF_CHR_DIRTY / DIRTY_B, VWF_CALLER_CTX, and
the secondary descriptor fields) after letting the boot ROM init at
$15C9AA. Range was $5000 bytes pre-secondary-descriptor  ; bumped to
$5100 so the new dirty / vram_word / byte_count / src_offset bytes
land zero on cold boot instead of inheriting random SRAM and
triggering a bogus secondary flush on the very first NMI (which trashed
the save-selection sprite CHR).
"""


    jsr.l 0x15C9AA
    {
    lda.b #0x00
    ldx.w #0x0000

_loop:
    sta.l 0x702000, x
    inx
    cpx.w #0x5100
    bne _loop
    }
    rtl


multiply_item_index_17:
"""
Relocated multiply-by-ITEM_UNLEASHED_RECORD_SIZE for the items_unleashed
name offset. Called from $019023 via JSL when the field menu is
wired to the 17-byte assets_items_unleashed_dat table.
Input: $43 = item ID (16-bit mode active).
Output: X = offset into ItemName table.
"""


; ITEM_UNLEASHED_RECORD_SIZE = 17 = (id << 4) + id.
    lda 0x43
    pha
    asl
    asl
    asl
    asl  ; * 16
    clc
    adc 0x01, s  ; * 16 + id = * 17
    tax
    pla  ; balance stack
    rtl


multiply_by_17:
"""
A: value to multiply  ; returns A*17 in A. Sized for the 17-byte assets_items_unleashed_dat stride.
"""


    php
    rep #0x20
    and.w #0x00FF
    pha
    asl
    asl
    asl
    asl
    clc
    adc 0x01, s  ; * 16 + value = * 17
    sta 0x01, s
    pla
    plp
    rtl
}
