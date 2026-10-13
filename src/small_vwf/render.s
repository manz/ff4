"""
Small (8x8) menu VWF renderer.

Packs glyphs into a CHR staging buffer by measured width plus kerning, then DMAs the dirty tiles to VRAM.
Tile ids start at $100, so tilemap entries carry bit 8 in the attribute byte. Scratch lives in SRAM: on the
field the direct-page bytes are live engine state (see vwf_engine in vwf_ram.s).
"""
.import "core/preamble"
.import "core/vwf_ram"
.import "core/assets"
.import "core/items"
.import "battle/render_state"
.import "core/libmz"
.include "dialog/vwf.i"
.include "core/bank20.i"
.include "core/libmz.i"
.import "core/vanilla"
.import "core/sram_layout"

; Root-scope externs: one declared inside an `.alloc` body never resolves at the use site.
.extern battle_render
.extern battle_render.clear_buffer

.alloc _small_vwf_render in bank20_reloc {
    .include "core/vwf_state.i"

    .macro initialize(var) {
    """Save a borrowed direct-page byte (sram_layout's `sram_render_dp`, one byte per direct-page address)."""
    lda.b var
    sta.l sram_render_dp + var
    }

    .macro restore(var) {
    """Give a borrowed direct-page byte its saved value back."""
    lda.l sram_render_dp + var
    sta.b var
    }

    .macro _set_var_value(var, value) {
    lda.b #value
    sta.b var
    }

    .scope _vram_copy {
; $705000, past the CHR buffer at $703000.
    buffer = VRAM_SAVE_SRAM_BASE
save_dialog_vram_far:
    jsr.l save_dlg_gfx_ext
; original save
    jsr.l wait_for_vblank_long
    phb
    tdc
    pha
    plb
    lda #0x80
    sta ppu.VMAIN
    ldx #0x2800
    stx ppu.VMADDL
    ldx ppu.VMDATALREAD
    lda #0x81
    sta dma_ch0.DMAP
    lda #PPU.VMDATALREAD
    sta dma_ch0.BBAD
    ldx.w #buffer & 0xffff
    stx dma_ch0.A1TL
    lda.b #buffer >> 16
    sta dma_ch0.A1B
    ldx.w #VRAM_SAVE_BYTE_COUNT
    stx dma_ch0.DASL
    lda #0x01
    sta cpu_regs.MDMAEN
    plb
    rtl
restore_dialog_gfx_far:
    lda #0x00
    pha
    plb
    ldx #0x2800
    stx 0x011d
    ldx.w #buffer & 0xffff
    stx 0x011f
    lda.b #buffer >> 16
    sta 0x0121
    ldx.w #VRAM_SAVE_BYTE_COUNT
    stx 0x0122
    jsr.w _transfer_to_vram
    jsr.l wait_for_vblank_long
    jsr.l restore_dlg_gfx_ext
; original restore
    rtl
_transfer_to_vram:
"""Copy of vanilla's VRAM transfer, callable from bank $20."""
    phb
    tdc
    pha
    plb
    lda #0x80
    sta ppu.VMAIN
    tdc
    sta cpu_regs.HDMAEN
    ldy 0x011d
    sty ppu.VMADDL
    lda #0x01
    sta dma_ch0.DMAP
    rep #0x20
    lda #PPU_BASE + PPU.VMDATAL  ; BBAD (A1TL rewritten below)
    sta dma_ch0.BBAD
    lda 0x011f
    sta dma_ch0.A1TL
    lda 0x0121
    sta dma_ch0.A1B
    sep #0x20
    lda 0x0123
    sta dma_ch0.DASH
    lda #0x01
    sta cpu_regs.MDMAEN
    plb
    rts
    }

    .scope render_allocator {
    """
    Tile-id allocator: a 16-bit word at $702F00 covering the full 10-bit tile id range (8-bit callers can read the
    low byte). All accessors run with M = 16.
    """
    allocated_tile_id = 0x702F00
    slot_limit_low = 0x702F02
"""
Inventory clamp: `increment` stops when the allocator's low byte reaches it, so an overflowing name overwrites its
slot's last tile. Inventory init writes slot_base + K-1; every other init writes $FF (no clamp).
"""


init_with_tile_id:
"""
A = tile id (0..$FF), M = 8. Zero-extends to 16 bits and resets slot_limit_low to $FF. Bit 8 comes from
vwf_cfg.flags at tilemap write time; use init_with_tile_id_wide for larger ids.
"""


    sta.l allocated_tile_id
    pha
    lda.b #0xFF
    sta.l slot_limit_low
    pla
    php
    rep #0x20
    pha
    lda.l allocated_tile_id
    and.w #0x00ff
    sta.l allocated_tile_id
    pla
    plp
    rts
init_with_tile_id_wide:
"""A = tile id (0..$3FF), M = 16. Resets slot_limit_low to $FF."""


    sta.l allocated_tile_id
    pha
    sep #0x20
    lda.b #0xFF
    sta.l slot_limit_low
    rep #0x20
    pla
    rts
init:
    pha
    rep #0x20
    lda.w #0x0000
    sta.l allocated_tile_id
    sep #0x20
    lda.b #0xFF
    sta.l slot_limit_low
    pla
    rts
init_battle_far:
    jsr.l play_battle_song
    jsr.w init
    jsr.w battle_render.clear_buffer
    rtl
increment:
"""Advance the allocator by 1, clamped at slot_limit_low. Keeps M and A."""


    php
    sep #0x20
    pha
    lda.l allocated_tile_id
    cmp.l slot_limit_low
    bcs _inc_clamped
    rep #0x20
    lda.l allocated_tile_id
    inc
    sta.l allocated_tile_id
    sep #0x20
_inc_clamped:
    pla
    plp
    rts
get:
"""Return current 16-bit allocator value in A (caller sets M)."""
    lda.l allocated_tile_id
    rts
    }

    .scope render {
    """Core 8x8 menu-VWF render scope."""
; variables
    _var_base = 0x63
    bits_left_on_tile = _var_base + 0x10
    temp = bits_left_on_tile + 1
    counter = temp + 1
    prev_char = vwf_engine.prev_char  ; long, off the field's MOSAIC shadow
    current_char = vwf_engine.current_char  ; (see src/core/vwf_ram.s)
    tilemap_offset = vwf_engine.tilemap_offset  ; long, NMI-safe (see src/core/vwf_ram.s)
    buffer_ptr = VWF_CHR_BUFFER
    buffer_size = VWF_CHR_BUFFER_SIZE
; Item-description cache, in the VRAM save window (see sram_layout.s).
    last_drawn_text_ptr = VRAM_SAVE_SRAM_BASE + 2
init:
"""
Reset the per-render scratch and the allocator, and clear only this region's CHR slice
(vwf_cfg.slot_budget tiles from vwf_cfg.tile_id_base): other regions' CHR may be mid-flush.
"""


    lda.b #0x00
    sta.l prev_char
    initialize(bits_left_on_tile)
    jsr.w render_allocator.init
    pha
    _set_var_value(bits_left_on_tile, 0x08)
    lda.b bits_left_on_tile
_brk_init_bits:
    pla
    initialize(temp)
    stz.b temp
    pha
; --- Per-region CHR clear from VwfConfig ---
    php
    rep #0x30
    lda.l vwf_cfg.tile_id_base
    and #0x01FF  ; 9-bit tile_id_base
    asl
    asl
    asl
    asl  ; * 16
    clc
    adc.w #VWF_CHR_BUFFER & 0xFFFF
    tax
    lda.l vwf_cfg.slot_budget
    and.w #0x00FF
    asl
    asl
    asl  ; budget * 8 word-pairs
    tay
    beq _init_skip_clear
    sep #0x20

_init_clear_loop:
    lda.b #0xFF
    sta.l VWF_CHR_BUFFER & 0xFF0000, x
    inx
    lda.b #0x00
    sta.l VWF_CHR_BUFFER & 0xFF0000, x
    inx
    dey
    bne _init_clear_loop

_init_skip_clear:
    plp
    pla  ; balances the `pha` after `stz.b temp`, or the rts returns into a BRK
    initialize(counter)
    rts
flush_chr_to_vram:
"""
NMI-side VWF CHR flush. When vwf_engine.chr_dirty is set, DMA vwf_cfg.chr_byte_count bytes from
VWF_CHR_BUFFER + VWF_CHR_FLUSH_OFFSET to VRAM word vwf_cfg.chr_vram_word, then the flush_b descriptor; clears
the dirty flags.
"""


    {
    php
    sep #0x20
    rep #0x10
    lda.l vwf_engine.chr_dirty
    beq _flush_skip_a
    lda.b #0x00
    sta.l vwf_engine.chr_dirty
; Only the one known descriptor (FIELD_VWF_VRAM_DEST_WORD, at most $B00 bytes): stale cart RAM ($FF from a
; savestate) would otherwise DMA 64K over all of VRAM.
    rep #0x20
    lda.l vwf_cfg.chr_vram_word
    cmp.w #FIELD_VWF_VRAM_DEST_WORD
    bne _flush_bad_a
    lda.l vwf_cfg.chr_byte_count
    beq _flush_bad_a
    cmp #0x0B01
    bcs _flush_bad_a
    sep #0x20
; Channel 3: no context runs HDMA on it (field $20, treasure $50 = ch6 + ch4, battle $87). A one-shot DMA leaves
; its descriptor in the channel registers, and on ch6 the treasure rolling buffer's BG3VOFS HDMA would re-arm over
; it and lose its scroll table.
    lda.b #0x01  ; DMAP: word transfer (2 byte regs, alt low/high)
    sta.l dma_ch3.DMAP
    lda.b #PPU.VMDATAL
    sta.l dma_ch3.BBAD
    rep #0x20
    lda.w #( VWF_CHR_BUFFER + VWF_CHR_FLUSH_OFFSET ) & 0xFFFF
    sta.l dma_ch3.A1TL  ; A1T low+mid
    sep #0x20
    lda.b #( VWF_CHR_BUFFER + VWF_CHR_FLUSH_OFFSET ) >> 16
    sta.l dma_ch3.A1B  ; A1B source bank
    rep #0x20
    lda.l vwf_cfg.chr_vram_word
    sta.l ppu.VMADDL  ; VMADD
    lda.l vwf_cfg.chr_byte_count
    sta.l dma_ch3.DASL  ; DAS
    sep #0x20
    lda.b #0x80
    sta.l ppu.VMAIN  ; VMAIN: increment on $2119, +1 word
    lda.b #0x08
    sta.l cpu_regs.MDMAEN  ; MDMAEN ch3

    bra _flush_skip_a

_flush_bad_a:
    sep #0x20

_flush_skip_a:
; Secondary descriptor (flush_b: drops, description, key-item picker), same channel 3 after the primary DMA.
; flush_b.vram_word is whitelisted ($2B70, $2C00, $6800) so stale SRAM never fires a DMA.
    sep #0x20
    lda.l vwf_engine.flush_b.dirty
    beq _flush_skip_b
; A frame whose vanilla transfers ran long (equip screen) gets here after vblank, where a VRAM DMA is dropped.
; Keep the flag for the next NMI.
    lda.l cpu_regs.HVBJOY  ; HVBJOY: bit 7 = in vblank
    bpl _flush_skip_b
    lda.b #0x00
    sta.l vwf_engine.flush_b.dirty
    rep #0x20
    lda.l vwf_engine.flush_b.vram_word
    cmp #0x2B70
    beq _vram_word_b_ok
    cmp #0x2C00
    beq _vram_word_b_ok
    cmp.w #KEY_ITEM_VWF_VRAM_DEST_WORD  ; $6800, picker on BG3 CHR
    bne _flush_skip_b_late

_vram_word_b_ok:
    sep #0x20
    lda.b #0x01
    sta.l dma_ch3.DMAP
    lda.b #PPU.VMDATAL
    sta.l dma_ch3.BBAD
    rep #0x20
    lda.l vwf_engine.flush_b.src_offset
    clc
    adc.w #VWF_CHR_BUFFER & 0xFFFF
    sta.l dma_ch3.A1TL
    sep #0x20
    lda.b #VWF_CHR_BUFFER >> 16
    sta.l dma_ch3.A1B
    rep #0x20
    lda.l vwf_engine.flush_b.vram_word
    sta.l ppu.VMADDL
    lda.l vwf_engine.flush_b.byte_count
    sta.l dma_ch3.DASL
    sep #0x20
    lda.b #0x80
    sta.l ppu.VMAIN
    lda.b #0x08
    sta.l cpu_regs.MDMAEN

_flush_skip_b_late:
    sep #0x20

_flush_skip_b:
    plp
    rts
    }
render_with_config:
"""
Render vwf_text_buffer with the settings in vwf_cfg (tile_id_base, slot_budget, tilemap_base; see
core/vwf_ram.s), then mark the CHR dirty for the NMI flush. M = 8, X = 16 on entry.
"""


    {
    php
    sep #0x20
    rep #0x10
; Reset kerning and tile room: a previous slot's last char or a clamped bits_left would shift this slot's first
; glyph (treasure slot 0 rendered as "le d'or" after the drops).
    lda.b #0x00
    sta.l prev_char
    lda.b #0x08
    sta.b bits_left_on_tile
; 16-bit init: tile_id_base is 9 bits, the 8-bit init would wrap slots past $FF into the font CHR.
    rep #0x20
    lda.l vwf_cfg.tile_id_base
    jsr.w render_allocator.init_with_tile_id_wide
; Re-stash the base so an interleaved render.init cannot zero it.
    lda.l vwf_cfg.tile_id_base
    sta.l render_allocator.allocated_tile_id
    sep #0x20
    lda.l vwf_cfg.tile_id_base
    clc
    adc.l vwf_cfg.slot_budget
    sec
    sbc.b #0x01
    sta.l render_allocator.slot_limit_low
; Clear this slot's CHR to $FF $00 (blank tile): slot_budget * 16 bytes at VWF_CHR_BUFFER + tile_id_base * 16.
    php
    rep #0x30
    lda.l vwf_cfg.tile_id_base
    and #0x01FF  ; 9-bit tile_id_base
    asl
    asl
    asl
    asl  ; * 16
    clc
    adc.w #VWF_CHR_BUFFER & 0xFFFF
    tax
    lda.l vwf_cfg.slot_budget
    and.w #0x00FF
    asl
    asl
    asl  ; words to clear = budget * 8 (16 bytes/tile, written as words)
    tay
    sep #0x20

_chr_clear_loop:
    lda.b #0xFF
    sta.l VWF_CHR_BUFFER & 0xFF0000, x
    inx
    lda.b #0x00
    sta.l VWF_CHR_BUFFER & 0xFF0000, x
    inx
    dey
    bne _chr_clear_loop
    plp
    lda.b #0x08
    sta.b bits_left_on_tile
    stz.b temp
    stz.b counter
    rep #0x20
    lda.l vwf_cfg.tilemap_base
    sta.l tilemap_offset
    sep #0x20
    jsr.w draw_text_buffer
; Ask the NMI flush hook for a VRAM upload.
    lda.b #0x01
    sta.l vwf_engine.chr_dirty
    plp
    rts
    }

draw_text_buffer:
"""
Blit the null-terminated vwf_text_buffer through display_char. The caller (render_with_config) sets the
allocator, slot_limit_low, bits_left_on_tile = 8, temp = counter = 0 and tilemap_offset (bottom tilemap row,
+2 per blit). Keeps X.
"""


    {
    phx
    ldx.w #0x0000

_dtb_loop:
    lda.l vwf_text_buffer, x
    beq _dtb_done
    inx
    phx
    jsr.w display_char
    plx
    bra _dtb_loop

_dtb_done:
    plx
    rts
    }
deinit:
    {
    restore(bits_left_on_tile)
    restore(temp)
    restore(counter)
    rts
    }
make_pointers:
    {
    pha

    ldx.w #0x0000
    ldy.w #0x0000
    lda.l current_char
    xba
    lda.b #0x00
    xba
    rep #0x20
    pha
    asl
    asl
    asl
    clc
    adc 1, s
    tax
    pla
    lda.w #0x0000
    sep #0x20

; 16-bit read: an 8-bit one drops tile id bit 8 and $100+ blits land on the font at offset 0.
    rep #0x20
    lda.l render_allocator.allocated_tile_id
    asl
    asl
    asl
    asl  ; tile_id * 16, 16-bit result
    sta.b dialog_vwf.old_tile_pos
    tay
    sep #0x20
    pla
    rts
    }
display_char:
    {
    sta.l current_char

    jsr.w make_pointers

    rep #0x20
    lda.w #0x0008
    sta.b counter
    sep #0x20

char_line_loop:
    rep #0x20
    lda.w #0x0000
    sep #0x20
    jsr.w _adjust_bits_left_for_kerning
    lda.b bits_left_on_tile

    cmp #0x08
    bne _shift

_read_8x8_char:
    lda.l menu_font, x

    inx
    xba
    bra _store

_shift:
; PPU multiplication is shared with the NMI, which corrupts char lines, so shift by hand
    phx
    lda.l menu_font, x
_really_shift:

    xba
    lda #0x00
    xba

    pha
    lda.b bits_left_on_tile
    asl
    tax
    pla

    rep #0x20
    jmp.w (_mul_table, x)
_mul_table:
    .dw _mul_0
    .dw _mul_1
    .dw _mul_2
    .dw _mul_3
    .dw _mul_4
    .dw _mul_5
    .dw _mul_6
    .dw _mul_7
    .dw _mul_8

_mul_8:
_mul_7:
    asl  ; 1
_mul_6:
    asl  ; 2
_mul_5:
    asl  ; 3
_mul_4:
    asl  ; 4
_mul_3:
    asl  ; 5
_mul_2:
    asl  ; 6
_mul_1:
    asl  ; 7
_mul_0:
    sep #0x20
    plx
    inx
_store:

    xba
    phx
    tyx
    ora.l buffer_ptr + 1, x
    sta.l buffer_ptr + 1, x
    xba
    ora.l buffer_ptr + 0x10 + 1, x
    sta.l buffer_ptr + 0x10 + 1, x
    txy
    plx
_skip_empty_pixel_line:
    iny
    iny
    dec.b counter
    bne char_line_loop

    rep #0x20
    stz.b temp
    lda.w #0x0000
    sep #0x20


brk_bits_left:
    lda.l menu_font, x

    sta.b temp

    rep #0x20
    clc

    lda.w #0x0000
    sep #0x20

    lda.b bits_left_on_tile

    clc
    sbc.b temp

loopdec:
    cmp #0x00
    bmi coupe
    beq coupe

    sta.b bits_left_on_tile
    jsr.w tilemap_write_no_inc
    rts

coupe:
    clc
    adc.b #0x08
    jsr.w tilemap_write
    bra loopdec
    }
    .macro save_a(code) {
    pha
    {{ code }}
    pla
    }
    .macro with_long_a(code) {
    rep #0x20
    {{ code }}
    sep #0x20
    }
_adjust_bits_left_for_kerning:
    {
; A kern that pushes the room past 8 pixels starts the glyph in the previous tile: step back one tile
; (allocator, tilemap cursor, Y and dialog_vwf.old_tile_pos) and keep the remainder.
    lda.b counter
    cmp.b #0x08
    bne _later_row  ; once per glyph, on its first row (counter counts the rows down from 8)
    lda.b bits_left_on_tile
    sta.b temp
    jsr.w get_kerning_adjustment
    bcs _room
    clc
    adc.b temp
    sta.b temp
_room:
    lda.b temp
    cmp.b #0x09
    bcc _set_room
    sec
    sbc.b #0x08
    sta.b temp
    rep #0x20
    lda.l render_allocator.allocated_tile_id
    dec
    sta.l render_allocator.allocated_tile_id
    lda.l tilemap_offset
    dec
    dec
    sta.l tilemap_offset
    tya
    sec
    sbc.w #0x0010
    tay
    lda.b dialog_vwf.old_tile_pos
    sec
    sbc.w #0x0010
    sta.b dialog_vwf.old_tile_pos
    sep #0x20
    lda.b temp
_set_room:
    sta.b bits_left_on_tile
    pha
    lda.l current_char
    sta.l prev_char
    pla
_later_row:
    rts
    }

_get_kerning_adjustment_binary_search:
    {
; Space ($FF) is never in a kerning pair.
    sep #0x20
    lda.l prev_char
    cmp #0xff
    beq _space_skip
    lda.l current_char
    cmp #0xff
    beq _space_skip
    rep #0x20

    phb
    pea.w font_table >> 16
    plb

    kerning_table_offset = 256 * 9
    ldy.w #kerning_table_offset
    lda.w menu_font, y
    beq not_found

    sec
    sbc.w #0x0001
    pha
    lda.w #0x0000
    pha
    pea.w 0x0000

_loop:
    lda 0x0005, s
    cmp 0x0003, s
    bcc _not_found_cleanup

    lda 0x0005, s
    sec
    sbc 0x0003, s
    lsr
    clc
    adc 0x0003, s
    sta 0x0001, s

    lda 0x0001, s
    asl
    clc
    adc 0x0001, s
    clc
    adc.w #kerning_table_offset + 2
    tay

    lda.w menu_font, y
    cmp.l prev_char
    beq _found
    bcc _search_upper

_search_lower:
    lda 0x0001, s
    sec
    sbc.w #0x0001
    bcc _not_found_cleanup  ; mid was 0, underflow → not found
    sta 0x0005, s
    bra _loop

_search_upper:
    lda 0x0001, s
    clc
    adc.w #0x0001
    sta 0x0003, s
    bra _loop

_not_found_cleanup:
    pla
    pla
    pla
not_found:
    lda.w #0x0000
    sec
    plb
    plb
    rts

_space_skip:
    rep #0x20
    lda.w #0x0000
    sec
    rts

_found:
    iny
    iny
    lda.w menu_font, y
    and.w #0x00FF
    ply
    ply
    ply
    clc
    plb
    plb
    rts
    }

get_kerning_adjustment:
    {
    phx
    phy
    rep #0x20
    jsr.w _get_kerning_adjustment_binary_search
    sep #0x20
    ply
    plx
    rts
    }

small_vwf_kerning_binary_ext:
    jsr.w get_kerning_adjustment
    rtl
tilemap_write_no_inc:
"""
Write the allocator's low byte at tilemap_offset and OR vwf_cfg.flags into the attribute byte. Bit 0 there is
tile id bit 8: only callers owning the 512-tile window set flags = $01.
"""


    _base_addr = 0x7e0000
    php
    rep #0x30
    lda.l tilemap_offset
    tax
    sep #0x20
    lda.l render_allocator.allocated_tile_id
    sta.l _base_addr, x
    lda.l _base_addr + 1, x
    ora.l vwf_cfg.flags
    sta.l _base_addr + 1, x
    plp
    rts
tilemap_write:
    pha
    jsr.w tilemap_write_no_inc
    jsr.w render_allocator.increment
    with_long_a({
lda.l tilemap_offset
inc
inc
sta.l tilemap_offset}
)


    pla
    rts
    }
}
