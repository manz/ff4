"""Small (8x8) menu VWF renderer."""
.include "src/vwf_state.i"

VARS_BUFFER = 0x710000

.macro initialize(var) {
    """Mirror a direct-page byte to the global save area."""
    lda.b var
    sta.l VARS_BUFFER + var
}

.macro _initialize_long(var) {
    initialize(var)
    initialize(var + 1)
    initialize(var + 2)
}

.macro restore(var) {
    """Pull the previously-saved value back into direct page."""
    lda.b VARS_BUFFER + var
    sta.b var
}

.macro _restore_long(var) {
    restore(var)
    restore(var + 1)
    restore(var + 2)
}

.macro _set_var_value(var, value) {
    lda.b #value
    sta.b var
}

.scope _vram_copy {
; Moved from $704000 to $705000 so the CHR buffer at $703000 can
; grow to $1000 bytes (cover tile_ids $00..$FF) without trampling
; the vram-save staging.
    buffer = 0x705000
save_dialog_vram_far:
    jsr.l 0x14fd0f
; original save
    jsr.l wait_for_vblank_long
    phb
    tdc
    pha
    plb
    lda #0x80
    sta 0x2115
    ldx #0x2800
    stx 0x2116
    ldx 0x2139
    lda #0x81
    sta 0x4300
    lda #0x39
    sta 0x4301
    ldx.w #buffer & 0xffff
    stx 0x4302
    lda.b #buffer >> 16
    sta 0x4304
    ldx.w #render.buffer_size
    stx 0x4305
    lda #0x01
    sta 0x420b
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
    ldx.w #render.buffer_size
    stx 0x0122
    jsr.w _transfer_to_vram
    jsr.l wait_for_vblank_long
    jsr.l 0x14ffd6
; original restore
    rtl
_transfer_to_vram:
"""clone of the original copy to be able to call it from the 0x20 bank."""
    phb
    tdc
    pha
    plb
    lda #0x80
    sta 0x2115
    tdc
    sta 0x420c
    ldy 0x011d
    sty 0x2116
    lda #0x01
    sta 0x4300
    rep #0x20
    lda #0x2118
    sta 0x4301
    lda 0x011f
    sta 0x4302
    lda 0x0121
    sta 0x4304
    sep #0x20
    lda 0x0123
    sta 0x4306
    lda #0x01
    sta 0x420b
    plb
    rts
}

.scope render_allocator {
    """
    Tile-id allocator for the small-VWF. Stored as a 16-bit word at
    $702F00..$702F01 so callers can reach the full 10-bit BG3
    tile_id range (0..0x3FF) instead of being capped at 8 bits.
    All accessors operate in 16-bit M and write both bytes  ; callers
    that only need the low byte can still do an 8-bit lda.l at the
    same address.
    """
    allocated_tile_id = 0x702F00
    slot_limit_low = 0x702F02
"""
Inventory clamp. When the allocator's low byte reaches this value,
`increment` freezes it  ; the blitter happily keeps reading the same
tile_id and overwrites the slot's last tile instead of bleeding into
the next slot's CHR. Set to 0xFF (no clamp) by every non-inventory
init. Inventory slot init writes slot_base + K-1 here.
"""


init_with_tile_id:
"""
8-bit caller convention: A.lo = tile_id (0..0xFF), M = 8.
Zero-extends to 16-bit so the high byte at $702F01 is clean.
tilemap_write_no_inc adds the hardcoded +0x100 bit shift. 16-bit
callers needing tile_ids outside the 0x100-0x1FF window should use
init_with_tile_id_wide. Also resets slot_limit_low to 0xFF so the
clamp is a no-op for non-inventory regions.
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
"""
16-bit caller convention: A = full tile_id (0..0x3FF), M = 16.
Stores both bytes verbatim. Use this for inventory / future regions
that go past tile_id 0xFF. Also resets slot_limit_low to 0xFF so the
clamp is a no-op until the inventory slot init opts in.
"""


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
    .if BATTLE_ENABLED {
init_battle_far:
    jsr.l 0x13ff12  ; play song
    jsr.w init
    jsr.w battle_render.clear_buffer
    rtl
    }
increment:
"""
Advance the 16-bit allocator by 1. Preserves M / A state.
Clamps the low byte at `slot_limit_low` so an inventory slot whose
name overflows K tiles keeps overwriting its last tile instead of
bleeding into the next slot's tile_id range. Non-inventory regions
set slot_limit_low = 0xFF so the clamp never fires.
"""


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
    prev_char = counter + 2
    current_char = prev_char + 1
    tilemap_offset = 0x1d
    buffer_ptr = VWF_CHR_BUFFER
    buffer_size = VWF_CHR_BUFFER_SIZE
    last_drawn_text_ptr = buffer_ptr + buffer_size + 2
init:
"""
font_ptr = assets_menu_font_dat  ; moved to direct use of assets_menu_font_dat.

Resets the per-render scratch (bits_left_on_tile / temp / counter)
and zeros the allocator. Clears ONLY the CHR slice owned by the
current region (`VwfConfig.tile_id_base * 16` for
`VwfConfig.slot_budget * 16` bytes), mirror of the per-slot clear
in battle's `init_inventory_for_current_slot`. Wiping the whole
buffer here clobbered other regions' CHR mid-frame, so callers
populate config first and `init` confines its $FF/$00 fill to
their slot.
"""


    .if ENABLE_KERNING_MENU {
    stz.b prev_char
    }
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
    lda.l VWF_CONFIG_BASE + VwfConfig.tile_id_base
    and.w #0x01FF  ; 9-bit tile_id_base
    asl
    asl
    asl
    asl  ; * 16
    clc
    adc.w #VWF_CHR_BUFFER & 0xFFFF
    tax
    lda.l VWF_CONFIG_BASE + VwfConfig.slot_budget
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
    pla  ; balances the `pha` after `stz.b temp` ; without this the
; `rts` popped the saved A byte as the high byte of the
; return address and item_description.draw_trampoline ran
; off into a BRK opcode on every menu open.
    initialize(counter)
    rts
flush_chr_to_vram:
"""
NMI-callable VWF CHR flush. Gates on `VWF_CHR_DIRTY`  ; if set,
reads `VwfConfig.chr_src_offset` / `chr_vram_word` / `chr_byte_count`
from the config struct and DMAs the slice from `VWF_CHR_BUFFER +
chr_src_offset` to VRAM word `chr_vram_word`. Clears the dirty
byte on the way out.

Designed to hang off the field NMI hook  ; running in vblank means
the DMA does not tear visible scanlines and we drop the explicit
`wait_for_vblank` the synchronous tail-of-render flush needed.
Battle-side equivalent of the partial CHR DMA in
`messages_vwf.dma_transfer`.
"""


    {
    php
    sep #0x20
    rep #0x10
    lda.l VWF_CHR_DIRTY
    beq _flush_skip_a
    lda.b #0x00
    sta.l VWF_CHR_DIRTY
; CRITICAL: clear HDMAEN bit 6 before retargeting ch6 for a one-shot
; DMA. The treasure-popup rolling buffer also arms ch6 (BG3VOFS HDMA)
; via $1BAE ; if we rewrite $4360-$4365 with the VWF flush descriptor
; without disabling HDMA bit 6 first, the per-scanline HDMA keeps
; running off the rewritten registers and writes VWF_CHR_BUFFER bytes
; to VMDATAL on every visible scanline for the rest of the frame.
; That trashes VRAM, kills BG3 scroll modulation, and made the
; treasure-popup band display garbage stride after the first frame.
; Push HDMAEN on the stack so we restore the prior mask exactly
; (treasure ch6 + drops ch4 + anything else vanilla armed).
    lda.l 0x00420C
    pha
    and.b #0xBF
    sta.l 0x00420C
; Channel 6: free per the FF4 DMA audit (vanilla btlgfx + menu
; never touch $4360..$436F ; ch7 already carries battle's
; `_sram_dma_transfer_7`, small_vwf's libmz transfers and the
; field NMI's tilemap upload). Source = VWF_CHR_BUFFER +
; VWF_CHR_FLUSH_OFFSET (engine constant, identical for battle +
; field). Dest VRAM word + size come from VwfConfig so each caller
; targets its own CHR slot without forking the upload path.
    lda.b #0x01  ; DMAP: word transfer (2 byte regs, alt low/high)
    sta.l 0x004360
    lda.b #0x18  ; BBAD: $2118 VMDATAL
    sta.l 0x004361
    rep #0x20
    lda.w #( VWF_CHR_BUFFER + VWF_CHR_FLUSH_OFFSET ) & 0xFFFF
    sta.l 0x004362  ; A1T low+mid
    sep #0x20
    lda.b #( VWF_CHR_BUFFER + VWF_CHR_FLUSH_OFFSET ) >> 16
    sta.l 0x004364  ; A1B source bank
    rep #0x20
    lda.l VWF_CONFIG_BASE + VwfConfig.chr_vram_word
    sta.l 0x002116  ; VMADD
    lda.l VWF_CONFIG_BASE + VwfConfig.chr_byte_count
    sta.l 0x004365  ; DAS
    sep #0x20
    lda.b #0x80
    sta.l 0x002115  ; VMAIN: increment on $2119, +1 word
    lda.b #0x40
    sta.l 0x00420B  ; MDMAEN ch6
; Restore prior HDMAEN bits (treasure ch6, drops ch4, etc) ; one-shot
; DMA on ch6 has completed by now and HDMA can resume reading the
; treasure HDMA table for per-scanline BG3VOFS on the next frame.
    pla
    sta.l 0x00420C

_flush_skip_a:
; --- Secondary descriptor flush (region 1B, drops in the treasure
; popup). Shares DMA channel 6 with the primary flush ; runs after
; the primary descriptor's DMA finishes so we never re-arm a busy
; channel. Each descriptor covers a disjoint slice of VRAM so two
; sequential DMAs land at distinct dest addresses without conflict.
; Secondary source offset is its OWN word so drops can DMA only its
; CHR slice ; primary keeps starting at VWF_CHR_FLUSH_OFFSET.
;
; Guard against savestates captured before the secondary descriptor
; existed : their SRAM at $7070C4..$7070CA carries random bytes, so
; before firing the DMA we whitelist VWF_CHR_VRAM_WORD_B against the
; two known arming targets ($2B70 drops, $2C00 description) and
; reject anything else as uninitialised. Stale SRAM almost certainly
; will not match either constant, so the secondary DMA stays dormant
; until items_menu_vwf or item_description explicitly arms it. Stops
; the save-selection sprite CHR from being trashed by random garbage
; on the very first NMI after a stale load.
    sep #0x20
    lda.l VWF_CHR_DIRTY_B
    beq _flush_skip_b
    lda.b #0x00
    sta.l VWF_CHR_DIRTY_B
    rep #0x20
    lda.l VWF_CHR_VRAM_WORD_B
    cmp.w #0x2B70
    beq _vram_word_b_ok
    cmp.w #0x2C00
    bne _flush_skip_b_late

_vram_word_b_ok:
    sep #0x20
; Same HDMAEN-bit-6 save/restore dance as the primary flush ; ch6 is
; shared with treasure BG3VOFS HDMA and must not stay armed while
; we hijack its registers for the secondary VRAM blit.
    lda.l 0x00420C
    pha
    and.b #0xBF
    sta.l 0x00420C
    lda.b #0x01
    sta.l 0x004360
    lda.b #0x18
    sta.l 0x004361
    rep #0x20
    lda.l VWF_CHR_SRC_OFFSET_B
    clc
    adc.w #VWF_CHR_BUFFER & 0xFFFF
    sta.l 0x004362
    sep #0x20
    lda.b #VWF_CHR_BUFFER >> 16
    sta.l 0x004364
    rep #0x20
    lda.l VWF_CHR_VRAM_WORD_B
    sta.l 0x002116
    lda.l VWF_CHR_BYTE_COUNT_B
    sta.l 0x004365
    sep #0x20
    lda.b #0x80
    sta.l 0x002115
    lda.b #0x40
    sta.l 0x00420B
    pla
    sta.l 0x00420C

_flush_skip_b_late:
    sep #0x20

_flush_skip_b:
    plp
    rts
    }
render_with_config:
"""
Config-driven VWF entry: reads `VwfConfig` at `VWF_CONFIG_BASE`,
sets up the allocator + render state from it, then walks
VWF_TEXT_BUFFER through `draw_text_buffer`. Single call site
replaces the bespoke init / display_char loops that the field-
items helper and the battle inventory text walker each carry.

VwfConfig fields consumed (matches `src/vwf_state.i`):
  tile_id_base   first tile_id this slot owns
  slot_budget    +K-1 clamp  ; $FF = no clamp
  tilemap_base   absolute WRAM byte index of the destination
                 tilemap row  ; display_char advances tilemap_offset
                 (DP $1D) by 2 per blit

`font_ptr` / `kerning_ptr` are reserved in the struct but
display_char still hardcodes `assets_menu_font_dat` for this
phase  ; swapping the font fetch to indirect-through-config is the
next refactor and lets battle keep its own font without forking
the engine.

M=8, X=16 on entry. Stack-balanced, RTS.
"""


    {
    php
    sep #0x20
    rep #0x10
; Reset per-glyph carry state so each slot's first char starts fresh.
; prev_char carries over from the previous slot's last char ; without
; a reset the new slot's first kerning lookup pairs against an
; unrelated glyph and shifts the allocator several tiles. Same goes
; for bits_left_on_tile : if a prior render ended with the value
; pinned by the $09 clamp at _end (kerning overshoot path), the new
; slot would start with bits_left=0 and burn its first tile.
; Symptom before this reset : treasure-inventory slot 0 rendered as
; "le d'or" (Aigu chopped) right after drops finished rendering.
    .if ENABLE_KERNING_MENU {
    stz.b prev_char
    }
    lda.b #0x08
    sta.b bits_left_on_tile
; Allocator base + clamp via the 16-bit `init_with_tile_id_wide`
; entry. tile_id_base is a 9-bit value (0..$1FF) so we need the
; full word ; the 8-bit init zero-extends and caps at $FF which
; would have wrapped field-menu slots 6..10 (base $C0 + 10*10 =
; $124) back into the menu font CHR range.
    rep #0x20
    lda.l VWF_CONFIG_BASE + VwfConfig.tile_id_base
    jsr.w render_allocator.init_with_tile_id_wide
; Belt + braces: re-stash allocated_tile_id verbatim so any
; interleaved render.init can not zero it on us before display_char
; reads it back.
    lda.l VWF_CONFIG_BASE + VwfConfig.tile_id_base
    sta.l render_allocator.allocated_tile_id
    sep #0x20
    lda.l VWF_CONFIG_BASE + VwfConfig.tile_id_base
    clc
    adc.l VWF_CONFIG_BASE + VwfConfig.slot_budget
    sec
    sbc.b #0x01
    sta.l render_allocator.slot_limit_low
; --- Clear this slot's CHR slice to $FF $00 (blank 2bpp / 4bpp
; tile) so the new blit does not pile pixels onto the previous
; tenant. Mirror of `messages_vwf.init_inventory_for_current_slot`
; in `src/battle/message.s` ; clear loop spans
; (slot_budget * 16) bytes at VWF_CHR_BUFFER + tile_id_base * 16.
    php
    rep #0x30
    lda.l VWF_CONFIG_BASE + VwfConfig.tile_id_base
    and.w #0x01FF  ; 9-bit tile_id_base
    asl
    asl
    asl
    asl  ; * 16
    clc
    adc.w #VWF_CHR_BUFFER & 0xFFFF
    tax
    lda.l VWF_CONFIG_BASE + VwfConfig.slot_budget
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
; Render scratch state.
    lda.b #0x08
    sta.b bits_left_on_tile
    stz.b temp
    stz.b counter
; tilemap_offset = config.tilemap_base (16-bit).
    rep #0x20
    lda.l VWF_CONFIG_BASE + VwfConfig.tilemap_base
    sta.b tilemap_offset
    sep #0x20
    jsr.w draw_text_buffer
; Tell the NMI flush hook this slot needs a VRAM upload. Mirror of
; `battle_render.dma_dirty_slots` ; engine-side so every consumer
; (field items, item descriptions, treasure list, ...) signals dirty
; without knowing about VRAM addresses.
    lda.b #0x01
    sta.l VWF_CHR_DIRTY
    plp
    rts
    }

draw_text_buffer:
"""
Unified entry: walk a null-terminated string at VWF_TEXT_BUFFER
and blit each byte via display_char.

Caller responsibilities (read from VwfConfig at VWF_CONFIG_BASE in
the next phase  ; for now the field-items helper hand-sets these
directly):
  - render_allocator.allocated_tile_id    set via init_with_tile_id
  - render_allocator.slot_limit_low       set per slot budget
  - render.bits_left_on_tile              set to 8
  - render.temp, render.counter           cleared
  - render.tilemap_offset (= DP $1D)      absolute WRAM byte index
                                          of the bottom tilemap row
                                          start  ; display_char auto-
                                          increments by 2 per blit
  - X, Y                                  free for caller use

Each iteration reads the next byte from `VWF_TEXT_BUFFER + Y` (Y
caller-zeroed on entry), exits on $00. display_char writes both
the CHR slice and the tile_id at tilemap_offset, and increments
the allocator (clamped at slot_limit_low).
"""


    {
    phx
    ldx.w #0x0000

_dtb_loop:
    lda.l VWF_TEXT_BUFFER, x
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
    _restore_long(buffer_ptr)
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
    lda.b current_char
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

; Read full 16-bit allocated_tile_id so 9-bit tile_ids ($100+) keep
; their high bit in oldtilepos. The previous 8-bit read masked bit
; 8 and field-menu VWF blits (tile_id_base $100) landed at SRAM
; offset 0, stomping the static font region.
    rep #0x20
    lda.l render_allocator.allocated_tile_id
    asl
    asl
    asl
    asl  ; tile_id * 16, 16-bit result
    sta.b oldtilepos
    tay
    sep #0x20
    pla
    rts
    }
display_char:
    {
    sta.b current_char

    jsr.w make_pointers

    rep #0x20
    lda.w #0x0008
    sta.b counter
    sep #0x20

char_line_loop:
    rep #0x20
    lda.w #0x0000
    sep #0x20
    .if ENABLE_KERNING_MENU {
    jsr.w _adjust_bits_left_for_kerning
    }
    lda.b bits_left_on_tile

    cmp #0x08
    bne _shift

_read_8x8_char:
    lda.l assets_menu_font_dat, x

    inx
    xba
    bra _store

_shift:
; PPU multiplication is being used by the NMI which wrecks char lines once in a while
    phx
    lda.l assets_menu_font_dat, x
_really_shift:


"""
bne _really_shift
inx
xba
bra _skip_empty_pixel_line
"""


    xba
    lda #0x00
    xba

; make jump_table_pointer
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
    .if 0 {
_shift:
; expects bitsleft in A
    phx
    tax
    lda.l vwf_shift_table, x
    sta.l 0x004202


    plx
    lda.l assets_menu_font_dat, x
    bne _really_shift
    inx
    xba
    bra _skip_empty_pixel_line
_really_shift:
    inx

    sta.l 0x004203  ; MULTIPLICAND

    rep #0x20
    nop
    nop
    nop
    nop
    lda.l 0x004216  ; the result is stored in 0x4216-0x4217
    sep #0x20
    }
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
    lda.l assets_menu_font_dat, x

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
    .if ENABLE_KERNING_MENU {
_adjust_bits_left_for_kerning:
    {
    lda.b bits_left_on_tile
    cmp #8
    beq _overflow
    sta.b temp

    jsr.w get_kerning_adjustment
    bcc _adjustment
    bra _end
_adjustment:
    pha
    lda.b temp
    clc
    adc 1, s
    sta.b temp
    .if 0 {
    bpl _no_adjustment

    and.b #0x80
    sta.b bits_left_on_tile
    sta.b temp
    lda.l render_allocator.allocated_tile_id
    dec
    sta.l render_allocator.allocated_tile_id
    jsr.w _refresh_destination_pointer
    }
_no_adjustment:

    pla
_end:
; Clamp temp to 0..8 before writing bits_left_on_tile : kerning
; adjustments can push the value past 8 (e.g. when a kerning entry
; subtracts more than the current tile has left), and the downstream
; dispatch at $97FC indexes a 9-entry jump table by bits_left * 2.
; Out-of-range values land off the table end and execute random
; bytes (BRK $00 on the held-DOWN field-items scroll). Treat any
; value > 8 as "no bits left in this tile" so the next loop pass
; allocates a fresh tile_id instead of crashing.
    lda.b temp
    cmp.b #0x09
    bcc _bits_left_in_range
    lda.b #0x00

_bits_left_in_range:
    sta.b bits_left_on_tile
_overflow:
    pha
    lda.b current_char
    sta.b prev_char
    pla
    rts
    }

_get_kerning_adjustment_binary_search:
    {
; Space ($FF) never appears in any font's kerning pair table; bail
; before the bank push so callers skip the binary search entirely.
    sep #0x20
    lda.b prev_char
    cmp #0xff
    beq _space_skip
    lda.b current_char
    cmp #0xff
    beq _space_skip
    rep #0x20

    phb
    pea.w font_table >> 16
    plb

    kerning_table_offset = 256 * 9
    ldy.w #kerning_table_offset
    lda.w assets_menu_font_dat, y
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

    lda.w assets_menu_font_dat, y
    cmp.b prev_char
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
    lda.w assets_menu_font_dat, y
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
    }
tilemap_write_no_inc:
"""
Write `allocated_tile_id` low byte to `(tilemap_offset)` and OR
`VwfConfig.flags` into the next (palette/attr) byte. The flag
mask used to be hard-coded `$01` (the 9-bit tile_id bit for the
512-tile dialog window) but the field-menu items live in 2bpp
BG3 where bit 0 of the attr byte is tile_id bit 8  ; an always-on
OR pushed all our tile_ids into the +256 half of CHR and the
high inventory slots wrapped past $FF in unpredictable ways.
Letting the caller pick the OR value via the config struct keeps
dialog (set `flags = $01`) working without forcing the menu items
to honour a bit they do not own.
"""


    _base_addr = 0x7e0000
    lda.l render_allocator.allocated_tile_id
    ldx.b tilemap_offset
    sta.l _base_addr, x
    lda.l _base_addr + 1, x
    ora.l VWF_CONFIG_BASE + VwfConfig.flags
    sta.l _base_addr + 1, x
    rts
tilemap_write:
    pha
    jsr.w tilemap_write_no_inc
    jsr.w render_allocator.increment
    with_long_a({
inc.b tilemap_offset
inc.b tilemap_offset}
)


    pla
    rts
}
