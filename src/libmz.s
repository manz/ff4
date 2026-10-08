"""Shared low-level helpers: vblank spinner + DMA transfer routines for VRAM / palette + small bank-trampolines."""

.import "preamble"
.include "libmz.i"
.include "bank20.i"


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
    DMA-transfer a block from ROM/RAM into VRAM via channel 7.
    Stack args (caller pushes in order): source_offset, source_bank,
    vram_pointer, count, dma_mode. All five args are pulled before RTS.
"""


    {
; on the stack:
; return address
; source offset
; source bank
; vram pointer
; count
; mode
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
"""
    DMA-transfer a block into CGRAM (palette) via channel 7.
    Stack args (caller-pushed): source_offset, source_bank, count.
    All three pulled before RTS.
"""


    {
; on the stack:
; return address
; source offset
; source bank
; count
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
"""Enable auto-joypad-read + vblank NMI by writing 1 to $4200."""
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
"""
    Reset PPU, DMA, and CPU registers to a known idle state at boot.
    8-bit M/X  ; clears OBJ/BG registers, neutralises mode-7 matrix to identity,
    disables NMI/HDMA/joypad, leaves screen forced-blank.
"""


    sep #0x30  ; make X, Y, A all 8-bits
    lda #0x80  ; screen off, no brightness
    sta ppu.INIDISP  ; brightness & screen enable register
    lda #0x00
    sta ppu.OBSEL  ; sprite register (size & address in VRAM)
    sta ppu.OAMADDL  ; sprite registers (address of sprite memory [OAM])
    sta ppu.OAMADDH  ; sprite registers (address of sprite memory [OAM])
    sta ppu.BGMODE  ; graphic mode register
    sta ppu.MOSAIC  ; mosaic register
    sta ppu.BG1SC  ; plane 0 map VRAM location
    sta ppu.BG2SC  ; plane 1 map VRAM location
    sta ppu.BG3SC  ; plane 2 map VRAM location
    sta ppu.BG4SC  ; plane 3 map VRAM location
    sta ppu.BG12NBA  ; plane 0 & 1 Tile data location
    sta ppu.BG34NBA  ; plane 2 & 3 Tile data location
    sta ppu.BG1HOFS  ; plane 0 scroll x (first 8 bits)
    sta ppu.BG1HOFS  ; plane 0 scroll x (last 3 bits)
    sta ppu.BG1VOFS  ; plane 0 scroll y (first 8 bits)
    sta ppu.BG1VOFS  ; plane 0 scroll y (last 3 bits)
    sta ppu.BG2HOFS  ; plane 1 scroll x (first 8 bits)
    sta ppu.BG2HOFS  ; plane 1 scroll x (last 3 bits)
    sta ppu.BG2VOFS  ; plane 1 scroll y (first 8 bits)
    sta ppu.BG2VOFS  ; plane 1 scroll y (last 3 bits)
    sta ppu.BG3HOFS  ; plane 2 scroll x (first 8 bits)
    sta ppu.BG3HOFS  ; plane 2 scroll x (last 3 bits)
    sta ppu.BG3VOFS  ; plane 2 scroll y (first 8 bits)
    sta ppu.BG3VOFS  ; plane 2 scroll y (last 3 bits)
    sta ppu.BG4HOFS  ; plane 3 scroll x (first 8 bits)
    sta ppu.BG4HOFS  ; plane 3 scroll x (last 3 bits)
    sta ppu.BG4VOFS  ; plane 3 scroll y (first 8 bits)
    sta ppu.BG4VOFS  ; plane 3 scroll y (last 3 bits)
    lda #0x80  ; increase VRAM address after writing to 0x2119
    sta ppu.VMAIN  ; VRAM address increment register
    lda #0x00
    sta ppu.VMADDL  ; VRAM address low
    sta ppu.VMADDH  ; VRAM address high
    sta ppu.M7SEL  ; initial mode 7 setting register
    sta ppu.M7A  ; mode 7 matrix parameter A register (low)
    lda #0x01
    sta ppu.M7A  ; mode 7 matrix parameter A register (high)
    lda #0x00
    sta ppu.M7B  ; mode 7 matrix parameter B register (low)
    sta ppu.M7B  ; mode 7 matrix parameter B register (high)
    sta ppu.M7C  ; mode 7 matrix parameter C register (low)
    sta ppu.M7C  ; mode 7 matrix parameter C register (high)
    sta ppu.M7D  ; mode 7 matrix parameter D register (low)
    lda #0x01
    sta ppu.M7D  ; mode 7 matrix parameter D register (high)
    lda #0x00
    sta ppu.M7X  ; mode 7 center position X register (low)
    sta ppu.M7X  ; mode 7 center position X register (high)
    sta ppu.M7Y  ; mode 7 center position Y register (low)
    sta ppu.M7Y  ; mode 7 center position Y register (high)
    sta ppu.CGADD  ; color number register (0x00-0xff)
    sta ppu.W12SEL  ; bg1 & bg2 window mask setting register
    sta ppu.W34SEL  ; bg3 & bg4 window mask setting register
    sta ppu.WOBJSEL  ; obj & color window mask setting register
    sta ppu.WH0  ; window 1 left position register
    sta ppu.WH1  ; window 2 left position register
    sta ppu.WH2  ; window 3 left position register
    sta ppu.WH3  ; window 4 left position register
    sta ppu.WBGLOG  ; bg1, bg2, bg3, bg4 window logic register
    sta ppu.WOBJLOG  ; obj, color window logic register (or, and, xor, xnor)
    lda #0x01
    sta ppu.TM  ; main screen designation (planes, sprites enable)
    lda #0x00
    sta ppu.TS  ; sub screen designation
    sta ppu.TMW  ; window mask for main screen
    sta ppu.TSW  ; window mask for sub screen
    lda #0x30
    sta ppu.CGWSEL  ; color addition & screen addition init setting
    lda #0x00
    sta ppu.CGADSUB  ; add/sub sub designation for screen, sprite, color
    lda #0xE0
    sta ppu.COLDATA  ; color data for addition/subtraction
    stz ppu.SETINI  ; screen setting (interlace x,y/enable SFX data)
    stz cpu_regs.NMITIMEN  ; disable v-blank, interrupt, joypad register
    lda #0xFF
    sta cpu_regs.WRIO  ; programmable I/O port
    lda #0x00
    sta cpu_regs.WRMPYA  ; multiplicand A
    sta cpu_regs.WRMPYB  ; multiplier B
    sta cpu_regs.WRDIVL  ; multiplier C
    sta cpu_regs.WRDIVH  ; multiplicand C
    sta cpu_regs.WRDIVB  ; divisor B
    sta cpu_regs.HTIMEL  ; horizontal count timer
    sta cpu_regs.HTIMEH  ; horizontal count timer MSB
    sta cpu_regs.VTIMEL  ; vertical count timer
    sta cpu_regs.VTIMEH  ; vertical count timer MSB
    sta cpu_regs.MDMAEN  ; general DMA enable (bits 0-7)
    sta cpu_regs.HDMAEN  ; horizontal DMA (HDMA) enable (bits 0-7)
    sta cpu_regs.MEMSEL  ; access cycle designation (slow/fast rom)
    rts
}
