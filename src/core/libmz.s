"""Shared low-level helpers: vblank spinner + DMA transfer routines for VRAM / palette + small bank-trampolines."""

.import "core/preamble"
.include "core/libmz.i"
.include "core/bank20.i"


.alloc _libmz_block in bank20_reloc {
wait_for_vblank:
"""Spin until the next vblank edge: wait for $4212 to go low, then high."""
    {
    pha

_negative:
    lda.l cpu_regs.HVBJOY
    bmi _negative

_positive:
    lda.l cpu_regs.HVBJOY
    bpl _positive
    pla
    rts
    }

wait_for_vblank_long:
"""RTL trampoline around `wait_for_vblank` for cross-bank callers."""
    jsr.w wait_for_vblank
    rtl

dma_transfer_to_vram:
"""
DMA a block into VRAM on channel 7. Stack args, pushed in order: source_offset, source_bank, vram_pointer, count,
dma_mode. All five are pulled before RTS.
"""


    {
    arg_count = 5
    stack_ptr = arg_count * 2 - 1
    source_offset = stack_ptr
    source_bank = stack_ptr - 2
    vram_pointer = stack_ptr - 4
    count = stack_ptr - 6
    dma_mode = stack_ptr - 8
    channel = 7
    rep #0x20
    sep #0x10
    ldx #0x80
    stx ppu.VMAIN
    lda.b source_offset, s
    sta.w DMA_BASE + channel * sizeof(DMAChannel) + DMAChannel.A1TL
    sep #0x10
    lda.b source_bank, s
    sta.w DMA_BASE + channel * sizeof(DMAChannel) + DMAChannel.A1B
    rep #0x20
    lda.b vram_pointer, s
    sta.w ppu.VMADDL
    lda.b count, s
    sta.w DMA_BASE + channel * sizeof(DMAChannel) + DMAChannel.DASL
    lda.b dma_mode, s
    sta.w DMA_BASE + channel * sizeof(DMAChannel) + DMAChannel.DMAP
    ldx.b #1 << channel
    stx cpu_regs.MDMAEN
    nop
    nop
    pla
    pla
    pla
    pla
    pla
    rts
    }


dma_transfer_to_palette:
"""DMA a block into CGRAM on channel 7. Stack args, pushed in order: source_offset, source_bank, count; pulled."""


    {
    arg_count = 3
    stack_ptr = arg_count * 2 - 1
    source_offset = stack_ptr
    source_bank = stack_ptr - 2
    count = stack_ptr - 4
    rep #0x20
    sep #0x10
    ldx #0x80
    stx ppu.VMAIN
    lda.b source_offset, s
    sta dma_ch7.A1TL
    lda.b source_bank, s
    sta dma_ch7.A1B
    lda.b count, s
    sta dma_ch7.DASL
    lda #0x2200
    sta dma_ch7.DMAP
    ldx #1 << 7
    stx cpu_regs.MDMAEN
    nop
    nop
    pla
    pla
    pla
    rts
    }


_enable_display:
    pha
    lda #0x00  ; enable screen, full brightness
    sta ppu.INIDISP
    pla
    rts

enable_gamepad:
"""Enable auto-joypad-read (NMI stays off) by writing 1 to $4200."""
    pha
    lda #0x01
    sta cpu_regs.NMITIMEN
    pla
    rts


disable_gamepad:
"""Disable auto-joypad-read and all NMI/IRQ sources ($4200 := 0)."""
    stz cpu_regs.NMITIMEN
    rts


initialize_snes:
"""Reset PPU, DMA and CPU registers to idle at boot (mode-7 matrix identity, NMI/HDMA/joypad off, forced blank)."""


    sep #0x30  ; make X, Y, A all 8-bits
    lda #0x80  ; screen off, no brightness
    sta ppu.INIDISP
    lda #0x00
    sta ppu.OBSEL
    sta ppu.OAMADDL
    sta ppu.OAMADDH
    sta ppu.BGMODE
    sta ppu.MOSAIC
    sta ppu.BG1SC
    sta ppu.BG2SC
    sta ppu.BG3SC
    sta ppu.BG4SC
    sta ppu.BG12NBA
    sta ppu.BG34NBA
    sta ppu.BG1HOFS
    sta ppu.BG1HOFS
    sta ppu.BG1VOFS
    sta ppu.BG1VOFS
    sta ppu.BG2HOFS
    sta ppu.BG2HOFS
    sta ppu.BG2VOFS
    sta ppu.BG2VOFS
    sta ppu.BG3HOFS
    sta ppu.BG3HOFS
    sta ppu.BG3VOFS
    sta ppu.BG3VOFS
    sta ppu.BG4HOFS
    sta ppu.BG4HOFS
    sta ppu.BG4VOFS
    sta ppu.BG4VOFS
    lda #0x80  ; increase VRAM address after writing to 0x2119
    sta ppu.VMAIN
    lda #0x00
    sta ppu.VMADDL
    sta ppu.VMADDH
    sta ppu.M7SEL
    sta ppu.M7A
    lda #0x01
    sta ppu.M7A
    lda #0x00
    sta ppu.M7B
    sta ppu.M7B
    sta ppu.M7C
    sta ppu.M7C
    sta ppu.M7D
    lda #0x01
    sta ppu.M7D
    lda #0x00
    sta ppu.M7X
    sta ppu.M7X
    sta ppu.M7Y
    sta ppu.M7Y
    sta ppu.CGADD
    sta ppu.W12SEL
    sta ppu.W34SEL
    sta ppu.WOBJSEL
    sta ppu.WH0
    sta ppu.WH1
    sta ppu.WH2
    sta ppu.WH3
    sta ppu.WBGLOG
    sta ppu.WOBJLOG
    lda #0x01
    sta ppu.TM
    lda #0x00
    sta ppu.TS
    sta ppu.TMW
    sta ppu.TSW
    lda #0x30
    sta ppu.CGWSEL
    lda #0x00
    sta ppu.CGADSUB
    lda #0xE0
    sta ppu.COLDATA
    stz ppu.SETINI
    stz cpu_regs.NMITIMEN
    lda #0xFF
    sta cpu_regs.WRIO
    lda #0x00
    sta cpu_regs.WRMPYA
    sta cpu_regs.WRMPYB
    sta cpu_regs.WRDIVL
    sta cpu_regs.WRDIVH
    sta cpu_regs.WRDIVB
    sta cpu_regs.HTIMEL
    sta cpu_regs.HTIMEH
    sta cpu_regs.VTIMEL
    sta cpu_regs.VTIMEH
    sta cpu_regs.MDMAEN
    sta cpu_regs.HDMAEN
    sta cpu_regs.MEMSEL
    rts
}
