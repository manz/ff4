wait_for_vblank:
{
    pha
negative:
	lda 0x4212
	bmi negative
positive:
	lda 0x4212
	bpl positive
	pla
	rts
}


dma_transfer_to_vram:
{
    ; on the stack:
    ; return address
    ; source offset
    ; source bank
    ; vram pointer
    ; count
    ; mode
    arg_count = 5
    stack_ptr       = arg_count * 2 - 1

    source_offset   = stack_ptr
    source_bank     = stack_ptr - 2
    vram_pointer    = stack_ptr - 4
    count           = stack_ptr - 6
    dma_mode        = stack_ptr - 8
    channel         = 4

    rep #0x20
    sep #0x10
    ldx #0x80
    stx 0x2115
    lda.b source_offset, s
    sta.w 0x4302 + (channel<<4)

    sep #0x10
    lda.b source_bank, s
    sta.w 0x4304 + (channel<<4)
    rep #0x20

    lda.b vram_pointer, s
    sta.w 0x2116

    lda.b count, s
    sta.w 0x4305 + (channel<<4)

    lda.b dma_mode, s
    sta.w 0x4300 + (channel<<4)

    ldx.b #1 << channel
    stx 0x420B
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
{
    ; on the stack:
    ; return address
    ; source offset
    ; source bank
    ; count
    arg_count = 3
    stack_ptr       = arg_count * 2 - 1

    source_offset   = stack_ptr
    source_bank     = stack_ptr - 2
    count           = stack_ptr - 4
    rep #0x20
    sep #0x10
    ldx #0x80
    stx 0x2115

    lda.b source_offset, s
    sta 0x4372

    lda.b source_bank, s
    sta 0x4374

    lda.b count, s
    sta 0x4375

    lda #0x2200
    sta 0x4370

    ldx #1 << 7
    stx 0x420B
    nop
    nop
    pla
    pla
    pla
    rts
}

enable_display:
    pha
	lda #0x00        ; enable screen, full brightness
	sta 0x2100
	pla
	rts

enable_gamepad:
    pha
    lda #0x01
    sta 0x4200
    pla
    rts


disable_gamepad:
    stz 0x4200
    rts


initialize_snes:
	sep #0x30        ; make X, Y, A all 8-bits
	lda #0x80        ; screen off, no brightness
	sta 0x2100       ; brightness & screen enable register
	lda #0x00
	sta 0x2101       ; sprite register (size & address in VRAM)
	sta 0x2102       ; sprite registers (address of sprite memory [OAM])
	sta 0x2103       ; sprite registers (address of sprite memory [OAM])
	sta 0x2105       ; graphic mode register
	sta 0x2106       ; mosaic register
	sta 0x2107       ; plane 0 map VRAM location
	sta 0x2108       ; plane 1 map VRAM location
	sta 0x2109       ; plane 2 map VRAM location
	sta 0x210A       ; plane 3 map VRAM location
	sta 0x210B       ; plane 0 & 1 Tile data location
	sta 0x210C       ; plane 2 & 3 Tile data location
	sta 0x210D       ; plane 0 scroll x (first 8 bits)
	sta 0x210D       ; plane 0 scroll x (last 3 bits)
	sta 0x210E       ; plane 0 scroll y (first 8 bits)
	sta 0x210E       ; plane 0 scroll y (last 3 bits)
	sta 0x210F       ; plane 1 scroll x (first 8 bits)
	sta 0x210F       ; plane 1 scroll x (last 3 bits)
	sta 0x2110       ; plane 1 scroll y (first 8 bits)
	sta 0x2110       ; plane 1 scroll y (last 3 bits)
	sta 0x2111       ; plane 2 scroll x (first 8 bits)
	sta 0x2111       ; plane 2 scroll x (last 3 bits)
	sta 0x2112       ; plane 2 scroll y (first 8 bits)
	sta 0x2112       ; plane 2 scroll y (last 3 bits)
	sta 0x2113       ; plane 3 scroll x (first 8 bits)
	sta 0x2113       ; plane 3 scroll x (last 3 bits)
	sta 0x2114       ; plane 3 scroll y (first 8 bits)
	sta 0x2114       ; plane 3 scroll y (last 3 bits)
	lda #0x80        ; increase VRAM address after writing to 0x2119
	sta 0x2115       ; VRAM address increment register
	lda #0x00
	sta 0x2116       ; VRAM address low
	sta 0x2117       ; VRAM address high
	sta 0x211A       ; initial mode 7 setting register
	sta 0x211B       ; mode 7 matrix parameter A register (low)
	lda #0x01
	sta 0x211B       ; mode 7 matrix parameter A register (high)
	lda #0x00
	sta 0x211C       ; mode 7 matrix parameter B register (low)
	sta 0x211C       ; mode 7 matrix parameter B register (high)
	sta 0x211D       ; mode 7 matrix parameter C register (low)
	sta 0x211D       ; mode 7 matrix parameter C register (high)
	sta 0x211E       ; mode 7 matrix parameter D register (low)
	lda #0x01
	sta 0x211E       ; mode 7 matrix parameter D register (high)
	lda #0x00
	sta 0x211F       ; mode 7 center position X register (low)
	sta 0x211F       ; mode 7 center position X register (high)
	sta 0x2120       ; mode 7 center position Y register (low)
	sta 0x2120       ; mode 7 center position Y register (high)
	sta 0x2121       ; color number register (0x00-0xff)
	sta 0x2123       ; bg1 & bg2 window mask setting register
	sta 0x2124       ; bg3 & bg4 window mask setting register
	sta 0x2125       ; obj & color window mask setting register
	sta 0x2126       ; window 1 left position register
	sta 0x2127       ; window 2 left position register
	sta 0x2128       ; window 3 left position register
	sta 0x2129       ; window 4 left position register
	sta 0x212A       ; bg1, bg2, bg3, bg4 window logic register
	sta 0x212B       ; obj, color window logic register (or, and, xor, xnor)
	lda #0x01
	sta 0x212C       ; main screen designation (planes, sprites enable)
	lda #0x00
	sta 0x212D       ; sub screen designation
	sta 0x212E       ; window mask for main screen
	sta 0x212F       ; window mask for sub screen
	lda #0x30
	sta 0x2130       ; color addition & screen addition init setting
	lda #0x00
	sta 0x2131       ; add/sub sub designation for screen, sprite, color
	lda #0xE0
	sta 0x2132       ; color data for addition/subtraction
	stz 0x2133       ; screen setting (interlace x,y/enable SFX data)
	stz 0x4200       ; disable v-blank, interrupt, joypad register
	lda #0xFF
	sta 0x4201       ; programmable I/O port
	lda #0x00
	sta 0x4202       ; multiplicand A
	sta 0x4203       ; multiplier B
	sta 0x4204       ; multiplier C
	sta 0x4205       ; multiplicand C
	sta 0x4206       ; divisor B
	sta 0x4207       ; horizontal count timer
	sta 0x4208       ; horizontal count timer MSB
	sta 0x4209       ; vertical count timer
	sta 0x420A       ; vertical count timer MSB
	sta 0x420B       ; general DMA enable (bits 0-7)
	sta 0x420C       ; horizontal DMA (HDMA) enable (bits 0-7)
	sta 0x420D       ; access cycle designation (slow/fast rom)
    rts
