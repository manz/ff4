"""
Menu VRAM save and restore ($14:FF62 SaveDlgGfx_ext / $14:FFD6 RestoreDlgGfx_ext).

The menus read their BG tiles from VRAM $4000-$7FFF. $4000-$5FFF holds the 8x8 font and the small VWF's
tiles $100-$1FF; $6000-$7FFF (tiles $200-$3FF) is never drawn by vanilla menus and is free for the small VWF.
A town or dungeon keeps map tiles in both, so the menu saves them to SRAM on entry and puts them back on exit.
"""
.import "preamble"
.import "vanilla"
.import "small_vwf/menu_text"
.import "sram_layout"
.include "config.i"
.include "src/vwf_state.i"
.include "../bank20.i"

_DMA_VRAM_READ := 0x81  ; VRAM to A-bus, one register (VMDATALREAD), A-bus incrementing
_DMA_VRAM_WRITE := 0x01  ; A-bus to VRAM, two registers (VMDATAL/H)
_FONT_VRAM_WORD := 0x2000  ; $4000: 8x8 font + small-VWF tiles $100-$1FF
_HIGH_VRAM_WORD := 0x3000  ; $6000: small-VWF tiles $200-$3FF
_SAVE_BYTES := VRAM_SAVE_BYTE_COUNT
_SAVED_MARK := 0x5356  ; "VS": blank SRAM ($00 / $FF) never reads as a save

.alloc at 0x14FF62 {
    jml menu_vram.save
}

.alloc at 0x14FFD6 {
    jml menu_vram.restore
}

.alloc _menu_vram in bank20_reloc {
    .scope menu_vram {
    """VRAM $4000-$7FFF to SRAM and back around a menu."""
save:
"""Screen off, then VRAM $4000-$5FFF to the VRAM save window and $6000-$7FFF to bank $71. A = 8 bits."""
    phb
    lda.b #0x00
    pha
    plb
    lda.b #0x80
    sta ppu.INIDISP
    sta.b menu_dp.brightness
    ldx.w #_FONT_VRAM_WORD
    ldy.w #VRAM_SAVE_SRAM_BASE & 0xFFFF
    lda.b #VRAM_SAVE_SRAM_BASE >> 16
    jsr.w _read_vram
    ldx.w #_HIGH_VRAM_WORD
    ldy.w #menu_vram_high & 0xFFFF
    lda.b #menu_vram_high >> 16
    jsr.w _read_vram
    jsr.w menu_text_vwf.forget_uploads
    rep #0x20
    lda.w #_SAVED_MARK
    sta.l menu_vram_saved
    sep #0x20
    plb
    rtl

restore:
"""
The font half goes back through the field NMI's one-shot transfer, as vanilla does; $6000-$7FFF is written here,
screen off (the field fades back in), and only when `save` filled the buffer: a menu opened by an older build
(a savestate) has nothing there. Leaves DB = 0 like vanilla's RestoreDlgGfx_ext.
"""
    lda.b #0x00
    pha
    plb
    ldx.w #_FONT_VRAM_WORD
    stx 0x011D
    ldx.w #VRAM_SAVE_SRAM_BASE & 0xFFFF
    stx 0x011F
    lda.b #VRAM_SAVE_SRAM_BASE >> 16
    sta 0x0121
    ldx.w #_SAVE_BYTES
    stx 0x0122
    rep #0x20
    lda.l menu_vram_saved
    cmp.w #_SAVED_MARK
    bne _not_saved
    lda.w #0x0000
    sta.l menu_vram_saved
    sep #0x20
    lda.b #0x80
    sta ppu.INIDISP
    sta ppu.VMAIN
    ldx.w #_HIGH_VRAM_WORD
    stx ppu.VMADDL
    lda.b #_DMA_VRAM_WRITE
    sta dma_ch0.DMAP
    lda.b #PPU.VMDATAL
    sta dma_ch0.BBAD
    ldx.w #menu_vram_high & 0xFFFF
    stx dma_ch0.A1TL
    lda.b #menu_vram_high >> 16
    sta dma_ch0.A1B
    ldx.w #_SAVE_BYTES
    stx dma_ch0.DASL
    lda.b #0x01
    sta cpu_regs.MDMAEN
    rtl
_not_saved:
    sep #0x20
    rtl

_read_vram:
"""DMA _SAVE_BYTES of VRAM from word X to A:Y. DB = 0, screen off."""
    pha
    lda.b #0x80
    sta ppu.VMAIN
    stx ppu.VMADDL
    ldx ppu.VMDATALREAD  ; the first read after VMADD returns the prefetch
    lda.b #_DMA_VRAM_READ
    sta dma_ch0.DMAP
    lda.b #PPU.VMDATALREAD
    sta dma_ch0.BBAD
    sty dma_ch0.A1TL
    pla
    sta dma_ch0.A1B
    ldx.w #_SAVE_BYTES
    stx dma_ch0.DASL
    lda.b #0x01
    sta cpu_regs.MDMAEN
    rts
    }
}
