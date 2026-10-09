"""
Small bank-$20 helpers the vanilla code reaches by JSL: the HDMA-aware BG1VOFS write, the cold-boot SRAM
clear and the 17-byte item-record multiplies.
"""
.import "preamble"
.import "items"
.include "config.i"
.include "bank20.i"
.import "vanilla"
.import "assets"

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


    jsr.l field_clear_ram
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


item_name_offset:
"""A = item id (low byte) -> A = 16-bit offset of its string in `items_unleashed` (symbol byte, name, $00). X kept."""
    php
    rep #0x30
    phx
    and.w #0x00FF
    asl
    tax
    lda.l items_unleashed_ptrs, x
    plx
    plp
    rtl


item_name_char:
"""
The key-item picker's name copy ($00:B273, X = 16-bit offset): the byte at items_unleashed + X, or a space once the
name has ended, with X held on its $00 so the caller's `inx` keeps it there.
"""
    lda.l items_unleashed, x
    bne _char
    lda.b #0xFF
    dex
_char:
    rtl


battle_item_offset:
"""A = item id (low byte) -> A = 16-bit offset of its string in `item_names` (symbol byte, name, $00). X kept."""
    php
    rep #0x30
    phx
    and.w #0x00FF
    asl
    tax
    lda.l item_names_ptrs, x
    plx
    plp
    rtl


battle_item_mult8:
"""
Vanilla btlgfx's `lda #9 / sta $28 / jsr Mult8` for an item name: id in $26 -> its `item_names` offset in $2A,
as Mult8 leaves the product. X, Y kept.
"""
    php
    rep #0x30
    phx
    lda.b 0x26
    and.w #0x00FF
    asl
    tax
    lda.l item_names_ptrs, x
    sta.b 0x2A
    plx
    plp
    rtl


battle_item_char:
"""The byte at item_names + X, or a space once the name has ended (X held on its $00 for the caller's inx)."""
    lda.l item_names, x
    bne _battle_char
    lda.b #0xFF
    dex
_battle_char:
    rtl


battle_item_char_after_symbol:
"""As battle_item_char, one byte on: X on the symbol, the name after it."""
    lda.l item_names + 1, x
    bne _battle_char_after
    lda.b #0xFF
    dex
_battle_char_after:
    rtl


battle_magic_mult8:
"""
Vanilla btlgfx's `lda #6 / sta $28 / jsr Mult8` for a spell name: id in $26 -> its `magic_names` offset in $2A, as
Mult8 leaves the product. X, Y kept.
"""
    php
    rep #0x30
    phx
    lda.b 0x26
    and.w #0x00FF
    asl
    tax
    lda.l magic_names_ptrs, x
    sta.b 0x2A
    plx
    plp
    rtl


battle_magic_char:
"""The byte at magic_names + X, or a space once the name has ended (X held on its $00 for the caller's inx)."""
    lda.l magic_names, x
    bne _magic_char
    lda.b #0xFF
    dex
_magic_char:
    rtl


battle_magic_char_after_first:
"""As battle_magic_char, one byte on (TextVar_04 draws the first letter on its own)."""
    lda.l magic_names + 1, x
    bne _magic_char_after
    lda.b #0xFF
    dex
_magic_char_after:
    rtl
}
