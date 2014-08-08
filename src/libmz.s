wait_for_vblank:
{
    pha
negative:
	lda $4212
	bmi negative
positive:
	lda $4212
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

    rep #$20
    sep #$10
    ldx #$80
    stx $2115
    channel_shifted = channel<<4
    lda.b source_offset, s
    sta.w $4302 + channel_shifted

    sep #$10
    lda.b source_bank, s
    sta.w $4304 + channel_shifted
    rep #$20

    lda.b vram_pointer, s
    sta.w $2116

    lda.b count, s
    sta.w $4305 + channel_shifted

    lda.b dma_mode, s
    sta.w $4300 + channel_shifted

    ldx.b #1 << channel
    stx $420B
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
    rep #$20
    sep #$10
    ldx #$80
    stx $2115

    lda.b source_offset, s
    sta $4372

    lda.b source_bank, s
    sta $4374

    lda.b count, s
    sta $4375

    lda #0x2200
    sta $4370

    ldx #1 << 7
    stx $420B
    nop
    nop
    pla
    pla
    pla
    rts
}

enable_display:
    pha
	lda #$00        ; enable screen, full brightness
	sta $2100
	pla
	rts

enable_gamepad:
    pha
    lda #$01
    sta $4200
    pla
    rts


disable_gamepad:
    stz $4200
    rts


initialize_snes:
	sep #$30        ; make X, Y, A all 8-bits
	lda #$80        ; screen off, no brightness
	sta $2100       ; brightness & screen enable register
	lda #$00
	sta $2101       ; sprite register (size & address in VRAM)
	sta $2102       ; sprite registers (address of sprite memory [OAM])
	sta $2103       ; sprite registers (address of sprite memory [OAM])
	sta $2105       ; graphic mode register
	sta $2106       ; mosaic register
	sta $2107       ; plane 0 map VRAM location
	sta $2108       ; plane 1 map VRAM location
	sta $2109       ; plane 2 map VRAM location
	sta $210A       ; plane 3 map VRAM location
	sta $210B       ; plane 0 & 1 Tile data location
	sta $210C       ; plane 2 & 3 Tile data location
	sta $210D       ; plane 0 scroll x (first 8 bits)
	sta $210D       ; plane 0 scroll x (last 3 bits)
	sta $210E       ; plane 0 scroll y (first 8 bits)
	sta $210E       ; plane 0 scroll y (last 3 bits)
	sta $210F       ; plane 1 scroll x (first 8 bits)
	sta $210F       ; plane 1 scroll x (last 3 bits)
	sta $2110       ; plane 1 scroll y (first 8 bits)
	sta $2110       ; plane 1 scroll y (last 3 bits)
	sta $2111       ; plane 2 scroll x (first 8 bits)
	sta $2111       ; plane 2 scroll x (last 3 bits)
	sta $2112       ; plane 2 scroll y (first 8 bits)
	sta $2112       ; plane 2 scroll y (last 3 bits)
	sta $2113       ; plane 3 scroll x (first 8 bits)
	sta $2113       ; plane 3 scroll x (last 3 bits)
	sta $2114       ; plane 3 scroll y (first 8 bits)
	sta $2114       ; plane 3 scroll y (last 3 bits)
	lda #$80        ; increase VRAM address after writing to $2119
	sta $2115       ; VRAM address increment register
	lda #$00
	sta $2116       ; VRAM address low
	sta $2117       ; VRAM address high
	sta $211A       ; initial mode 7 setting register
	sta $211B       ; mode 7 matrix parameter A register (low)
	lda #$01
	sta $211B       ; mode 7 matrix parameter A register (high)
	lda #$00
	sta $211C       ; mode 7 matrix parameter B register (low)
	sta $211C       ; mode 7 matrix parameter B register (high)
	sta $211D       ; mode 7 matrix parameter C register (low)
	sta $211D       ; mode 7 matrix parameter C register (high)
	sta $211E       ; mode 7 matrix parameter D register (low)
	lda #$01
	sta $211E       ; mode 7 matrix parameter D register (high)
	lda #$00
	sta $211F       ; mode 7 center position X register (low)
	sta $211F       ; mode 7 center position X register (high)
	sta $2120       ; mode 7 center position Y register (low)
	sta $2120       ; mode 7 center position Y register (high)
	sta $2121       ; color number register ($00-$ff)
	sta $2123       ; bg1 & bg2 window mask setting register
	sta $2124       ; bg3 & bg4 window mask setting register
	sta $2125       ; obj & color window mask setting register
	sta $2126       ; window 1 left position register
	sta $2127       ; window 2 left position register
	sta $2128       ; window 3 left position register
	sta $2129       ; window 4 left position register
	sta $212A       ; bg1, bg2, bg3, bg4 window logic register
	sta $212B       ; obj, color window logic register (or, and, xor, xnor)
	lda #$01
	sta $212C       ; main screen designation (planes, sprites enable)
	lda #$00
	sta $212D       ; sub screen designation
	sta $212E       ; window mask for main screen
	sta $212F       ; window mask for sub screen
	lda #$30
	sta $2130       ; color addition & screen addition init setting
	lda #$00
	sta $2131       ; add/sub sub designation for screen, sprite, color
	lda #$E0
	sta $2132       ; color data for addition/subtraction
	stz $2133       ; screen setting (interlace x,y/enable SFX data)
	stz $4200       ; disable v-blank, interrupt, joypad register
	lda #$FF
	sta $4201       ; programmable I/O port
	lda #$00
	sta $4202       ; multiplicand A
	sta $4203       ; multiplier B
	sta $4204       ; multiplier C
	sta $4205       ; multiplicand C
	sta $4206       ; divisor B
	sta $4207       ; horizontal count timer
	sta $4208       ; horizontal count timer MSB
	sta $4209       ; vertical count timer
	sta $420A       ; vertical count timer MSB
	sta $420B       ; general DMA enable (bits 0-7)
	sta $420C       ; horizontal DMA (HDMA) enable (bits 0-7)
	sta $420D       ; access cycle designation (slow/fast rom)
    rts
