"""
Build context every module can import: the typed hardware register binds
over the a816 standard library. The bus map lives in a816.toml.

Address registers by name: `sta ppu.VMAIN`, `lda.l cpu_regs.HVBJOY`,
`sta dma_ch7.BBAD`. Typed operands pick their addressing mode from the
register's address (absolute for $21xx / $42xx / $43xx). An explicit
`.b` / `.w` / `.l` on the opcode still wins.

Every stdlib field is one byte: a 16-bit store to a register pair
(`stx ppu.VMADDL` with 16-bit X) writes the named byte and the next one.
"""


.import "@std/snes/ppu"
.import "@std/snes/cpu"
.import "@std/snes/dma"

ppu := (PPU_BASE as PPU)
cpu_regs := (CPU_REGS_BASE as CPU_REGS)

dma_ch0 := (DMA_BASE + 0 * sizeof(DMAChannel) as DMAChannel)
dma_ch1 := (DMA_BASE + 1 * sizeof(DMAChannel) as DMAChannel)
dma_ch2 := (DMA_BASE + 2 * sizeof(DMAChannel) as DMAChannel)
dma_ch3 := (DMA_BASE + 3 * sizeof(DMAChannel) as DMAChannel)
dma_ch4 := (DMA_BASE + 4 * sizeof(DMAChannel) as DMAChannel)
dma_ch5 := (DMA_BASE + 5 * sizeof(DMAChannel) as DMAChannel)
dma_ch6 := (DMA_BASE + 6 * sizeof(DMAChannel) as DMAChannel)
dma_ch7 := (DMA_BASE + 7 * sizeof(DMAChannel) as DMAChannel)
