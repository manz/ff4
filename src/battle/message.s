"""
Battle-message tile renderer + VWF parser scopes (`battle_render` low-level blitter, `messages_vwf` high-level
dialog-stream consumer).
"""
.import "core/preamble"
.import "core/assets"
.import "dialog/dakuten"
.import "small_vwf/init"
.import "battle/render_state"
.import "battle/put_char"
.include "battle/sram.i"
.include "core/bank20.i"
.import "core/vanilla"
.import "small_vwf/baked_names"
.import "battle/status_names"
.import "core/wram_layout"
.import "battle/monsters_reloc"

; Lives in a redraw_writer_patches pool; that module depends on this one.
.extern flying_hdma_trampoline


.macro copy_baked_name(blob, table, resume) {
    """
    A = name id, Y = cell offset (M = 8, X = 16): copy the name's baked tiles into the CHR buffer at the allocator.
    With `resume`, the renderer is left inside the name's last tile (Y on its cell, bits_left_on_tile = columns
    left) so the next glyphs join it; otherwise the next glyph starts a fresh tile past the name.
    """
    {
    sty.b battle_render.tilemap_offset
    pha
    lda.b battle_render.bits_left_on_tile
    cmp.b #0x08
    beq _fresh
    jsr.w render_allocator.increment  ; a glyph left the current tile part-filled: the name starts on the next one
_fresh:
    pla
    rep #0x20
    and.w #0x00FF
    asl
    asl
    tax
    lda.l table + 2, x
    pha  ; tiles, last tile's columns
    and.w #0x00FF
    beq _done
    lda.l table, x
    tax
    lda.l render_allocator.allocated_tile_id
    and.w #0x00FF
    asl
    asl
    asl
    asl
    tay
    lda 1, s
    and.w #0x00FF
    asl
    asl
    asl
    pha  ; words left
_copy:
    lda.l blob, x
    phx
    tyx
    sta.l battle_render.buffer_ptr, x
    plx
    inx
    inx
    iny
    iny
    lda 1, s
    dec
    sta 1, s
    bne _copy
    pla
    lda 1, s
    and.w #0x00FF
    tax
    sep #0x20
_cell:
    jsr.w battle_render.tilemap_write
    dex
    bne _cell
    .if resume {
    lda 2, s
    cmp.b #0x08
    bcs _done
    lda.b #0x08
    sec
    sbc 2, s
    sta.b battle_render.bits_left_on_tile
    stz.b battle_render.prev_char  ; no kerning pair across the baked name
    rep #0x20
    lda.l render_allocator.allocated_tile_id
    dec
    sta.l render_allocator.allocated_tile_id
    dec.b battle_render.tilemap_offset
    dec.b battle_render.tilemap_offset
    sep #0x20
    bra _state
    }
_done:
    sep #0x20
    lda.b #0x08  ; the next VWF glyph starts a fresh tile, past the name
    sta.b battle_render.bits_left_on_tile
_state:
    stz.b battle_render.temp
    stz.b battle_render.counter
    rep #0x20
    pla
    lda.w #0x0000  ; no leftover in B: callers transfer A to a 16-bit index
    sep #0x20
    ldy.b battle_render.tilemap_offset
    }
}

.alloc _battle_message_block in bank20_reloc {
    .include "battle/inventory_budget.i"
    .include "core/vwf_state.i"

    .scope battle_render {
    """
    Battle VWF CHR regions, region_size (48) tile ids each:
    0x00 -> 0x2F messages
    0x30 -> 0x5F monster names (init_monsters)
    0x60 -> 0x8F char names (init_names)
    0x90 -> 0xBF commands (init_commands_list)
    0xC0 -> 0xFB inventory: 6 slots x ITEM_VWF_TILE_BUDGET (init_inventory_region)
    """
    buffer_ptr = VWF_CHR_BUFFER
    buffer_size = 8 * ( 128 + 32 ) * 2
    region_size = 48
; Gate state lives at BATTLE_RENDER_STATE ($70:7100), outside the CHR buffer, which inventory slot CHR overwrites
; ($70:3C00..$70:4240, see vwf_state.i). CHR_PENDING = a CHR transfer is queued (deinit). Region bits = regions
; re-rendered this frame: dma_transfer flushes only their 0x300-byte slices (buffer_ptr + N*0x300 to VRAM
; $B000 + N*0x300) instead of the whole buffer. N=0 messages, 1 monsters, 2 names, 3 commands.
    CHR_PENDING = ChrTransferBits.pending.mask
    CHR_REGION_MESSAGES = ChrTransferBits.messages.mask
    CHR_REGION_MONSTERS = ChrTransferBits.monsters.mask
    CHR_REGION_NAMES = ChrTransferBits.names.mask
    CHR_REGION_COMMANDS = ChrTransferBits.commands.mask
; Inventory slots flush per slot (160-byte slices). render_defs.i: dirty / render-skipped / tilemap-pending
; interface shared with redraw_gates.s and the writer-site shims.
    .include "render_defs.i"
    bits_left_on_tile = 0xA9
    tilemap_offset = bits_left_on_tile + 2
    temp = bits_left_on_tile + 4
    counter = bits_left_on_tile + 6
    prev_char = bits_left_on_tile + 8
    current_char = prev_char + 1
init_monsters:
"""Initialize the renderer targeting the monsters region."""
    jsr.w _clear_monster_text
    lda.l battle_render_state.pending_transfer_mask
    ora.b #CHR_REGION_MONSTERS
    sta.l battle_render_state.pending_transfer_mask
    lda.b #CHR_REGION_MONSTERS
    sta.l battle_render_state.render_region
    lda.b #region_size
    brl _init
_clear_monster_text:
"""
Blank the monster window's text (monster_names_text, wram_layout): it sits in freed RAM no battle init clears, and
DrawMonsterNames only writes the lines of the monster types in play.
"""
    php
    rep #0x30
    pha
    phx
    ldx.w #MONSTER_TEXT_SIZE - 2
    lda.w #0x00FF  ; the window's blank cell
_cmt_loop:
    sta.l monster_names_text, x
    dex
    dex
    bpl _cmt_loop
    plx
    pla
    plp
    rts
init_names:
"""Initialize the renderer targeting the name region."""
    lda.l battle_render_state.pending_transfer_mask
    ora.b #CHR_REGION_NAMES
    sta.l battle_render_state.pending_transfer_mask
    lda.b #CHR_REGION_NAMES
    sta.l battle_render_state.render_region
    lda.b #region_size * 2
    brl _init
init_commands_list:
"""Initialize the renderer targeting the commands list region."""
    lda.l battle_render_state.pending_transfer_mask
    ora.b #CHR_REGION_COMMANDS
    sta.l battle_render_state.pending_transfer_mask
    lda.b #CHR_REGION_COMMANDS
    sta.l battle_render_state.render_region
    lda.b #region_size * 3
    brl _init
init_inventory_region:
"""
Reset the allocator to the inventory tile base (0xC0) once per rolling pass; each item's DrawText then advances
it, so item N owns its own tile range. No clear_buffer: tiles 0xC0+ would overrun the buffer into $703C00+.
"""


; Inventory CHR flushes per slot (dma_dirty_slots): pending_transfer_mask must stay untouched here.
    lda.b #region_size * 4
    jsr.w render_allocator.init_with_tile_id
    stz.b prev_char
    lda.b #0x08
    sta.b bits_left_on_tile
    stz.b temp
    stz.b counter
    rts
render_allocator_init_with_tile_id_thunk:
"""In-scope thunk to `render_allocator.init_with_tile_id` (jsr.w across scopes). A = tile_id base."""


    jmp.w render_allocator.init_with_tile_id
_init:
; Region bit already set by the caller; A = tile_id base for the allocator.
    jsr.w render_allocator.init_with_tile_id
    brl _internal_init
; Hop for the gated inits: _gated_skip is past the 8-bit branch range.
_gated_skip_near:
    jmp.w _gated_skip
; Gated inits: like init_X, but a clean region (dirty bit clear) sets render_skipped = $FF and returns with no
; setup, so the gated trampoline skips DrawText. A dirty region clears its bit and does the full init.
init_monsters_gated:
"""Gated init for the monsters region."""
    lda.l battle_render_state.region_dirty_bits
    bit.b #REGION_DIRTY_MONSTERS
    beq _gated_skip_near
    and.b #( ~REGION_DIRTY_MONSTERS ) & 0xFF
    sta.l battle_render_state.region_dirty_bits
    jsr.w _clear_monster_text
    lda.l battle_render_state.tilemap_pending_mask
    ora.b #TILEMAP_PENDING_MAIN
    sta.l battle_render_state.tilemap_pending_mask
    lda.l battle_render_state.pending_transfer_mask
    ora.b #CHR_REGION_MONSTERS
    sta.l battle_render_state.pending_transfer_mask
    lda.b #CHR_REGION_MONSTERS
    sta.l battle_render_state.render_region
    lda.b #region_size
    brl _init_continue
init_names_gated:
"""Gated init for the names region."""
    lda.l battle_render_state.region_dirty_bits
    bit.b #REGION_DIRTY_NAMES
    beq _gated_skip_near
    and.b #( ~REGION_DIRTY_NAMES ) & 0xFF
    sta.l battle_render_state.region_dirty_bits
    lda.l battle_render_state.tilemap_pending_mask
    ora.b #TILEMAP_PENDING_MAIN
    sta.l battle_render_state.tilemap_pending_mask
    lda.l battle_render_state.pending_transfer_mask
    ora.b #CHR_REGION_NAMES
    sta.l battle_render_state.pending_transfer_mask
    lda.b #CHR_REGION_NAMES
    sta.l battle_render_state.render_region
    lda.b #region_size * 2
    brl _init_continue
init_commands_list_gated:
"""Gated init for the commands region."""
    lda.l battle_render_state.region_dirty_bits
    bit.b #REGION_DIRTY_COMMANDS
    beq _gated_skip_near
    and.b #( ~REGION_DIRTY_COMMANDS ) & 0xFF
    sta.l battle_render_state.region_dirty_bits
    lda.l battle_render_state.tilemap_pending_mask
    ora.b #TILEMAP_PENDING_COMMANDS
    sta.l battle_render_state.tilemap_pending_mask
    lda.l battle_render_state.pending_transfer_mask
    ora.b #CHR_REGION_COMMANDS
    sta.l battle_render_state.pending_transfer_mask
    lda.b #CHR_REGION_COMMANDS
    sta.l battle_render_state.render_region
    lda.b #region_size * 3
_init_continue:
    pha
    lda.b #0x00
    sta.l battle_render_state.render_skipped
    pla
; Region bit already set above; A = tile_id base for the allocator.
    jsr.w render_allocator.init_with_tile_id
    brl _internal_init
_gated_skip:
    lda.b #0xFF
    sta.l battle_render_state.render_skipped
    rts
init:
    pha
    lda.l battle_render_state.pending_transfer_mask
    ora.b #CHR_REGION_MESSAGES
    sta.l battle_render_state.pending_transfer_mask
    lda.b #CHR_REGION_MESSAGES
    sta.l battle_render_state.render_region
    pla
    jsr.w render_allocator.init
_internal_init:
    stz.b prev_char
    jsr.w clear_buffer
    pha
    lda.b #0x08
    sta.b bits_left_on_tile
    pla
    stz.b temp
    stz.b counter
    rts
clear_buffer:
"""
Fill the region_size-tile 4bpp buffer at the current allocator tile with $FF/$00 plane rows.
"""


    pha
    phx
    phy
    lda.l render_allocator.allocated_tile_id
    rep #0x20
    asl
    asl
    asl
    asl
    tax
    tdc
    sep #0x20
    ldy.w #0
_clear_loop:
    lda.b #0xFF
    sta.l buffer_ptr, x
    lda.b #0x00
    sta.l buffer_ptr + 1, x
    inx
    inx
    iny
    iny
    cpy.w #region_size * 16
    bne _clear_loop
    ply
    plx
    pla
    rts
clear_buffer_far:
    jsr.w clear_buffer
    rtl
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
    adc 1, s
    tax
    pla
    sep #0x20
_refresh_destination_pointer:
    lda.l render_allocator.allocated_tile_id

    rep #0x20
    and.w #0x00ff
    asl
    asl
    asl
    asl
    tay
    sep #0x20
    pla
    rts
    }
display_char:
"""Render `A` (char) at tilemap offset `Y` into the VWF buffer; preserves A/X/Y, returns Y = `tilemap_offset`."""


    pha
    phx
    phy
    jsr.w _display_char
    ply
    plx
    pla
    ldy.b tilemap_offset
    rts
_display_char:
    {
    sta.b current_char
    sty.b tilemap_offset

    jsr.w make_pointers

; kerning
    pha
    jsr.w _adjust_bits_left_for_kerning
    pla

; Space ($FF) is blank: skip the 8 glyph rows, X past them so brk_bits_left reads the width byte.
    lda.b current_char
    cmp #0xff
    bne _not_space
    rep #0x20
    txa
    clc
    adc.w #0x0008
    tax
    sep #0x20
    jmp.w brk_bits_left
_not_space:

; One specialised 8-row loop per bits_left_on_tile (aligned + shift_0..7), asl count baked in; all end at
; brk_bits_left. The shift dispatch clobbers X, so the font pointer goes to `temp` (the aligned path keeps X).
    rep #0x20
    lda.w #0x0008
    sta.b counter
    sep #0x20

    lda.b bits_left_on_tile
    cmp #0x08
    beq _aligned_loop

    phx
    rep #0x20
    pla
    sta.b temp
    sep #0x20

    lda.b bits_left_on_tile
    asl
    pha
    lda #0x00
    xba
    pla
    tax
    jmp.w (_shift_dispatch, x)

_shift_dispatch:
    .dw _shift_loop_0
    .dw _shift_loop_1
    .dw _shift_loop_2
    .dw _shift_loop_3
    .dw _shift_loop_4
    .dw _shift_loop_5
    .dw _shift_loop_6
    .dw _shift_loop_7

    .macro vwf_row_body(n) {
    rep #0x20
    lda.w #0x0000
    sep #0x20
    lda.l menu_font, x
    inx
    .if n > 0 {
    rep #0x20
    .for k := 0, n {
    asl
    }
    sep #0x20
    }
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
    iny
    iny
    dec.b counter
    }

_aligned_loop:
    lda.l menu_font, x
    inx
    phx
    tyx
    ora.l buffer_ptr + 1, x
    sta.l buffer_ptr + 1, x
    txy
    plx
    iny
    iny
    dec.b counter
    bne _aligned_loop
    jmp.w brk_bits_left

_shift_loop_0:
    ldx.b temp
_shift_loop_0_body:
    vwf_row_body(0)
    bne _shift_loop_0_body
    jmp.w brk_bits_left

_shift_loop_1:
    ldx.b temp
_shift_loop_1_body:
    vwf_row_body(1)
    bne _shift_loop_1_body
    jmp.w brk_bits_left

_shift_loop_2:
    ldx.b temp
_shift_loop_2_body:
    vwf_row_body(2)
    bne _shift_loop_2_body
    jmp.w brk_bits_left

_shift_loop_3:
    ldx.b temp
_shift_loop_3_body:
    vwf_row_body(3)
    bne _shift_loop_3_body
    jmp.w brk_bits_left

_shift_loop_4:
    ldx.b temp
_shift_loop_4_body:
    vwf_row_body(4)
    bne _shift_loop_4_body
    jmp.w brk_bits_left

_shift_loop_5:
    ldx.b temp
_shift_loop_5_body:
    vwf_row_body(5)
    bne _shift_loop_5_body
    jmp.w brk_bits_left

_shift_loop_6:
    ldx.b temp
_shift_loop_6_body:
    vwf_row_body(6)
    bne _shift_loop_6_body
    jmp.w brk_bits_left

_shift_loop_7:
    ldx.b temp
_shift_loop_7_body:
    vwf_row_body(7)
    bne _shift_loop_7_body
    jmp.w brk_bits_left


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
_adjust_bits_left_for_kerning:
    {
    lda.b bits_left_on_tile
    sta.b temp

    jsr.w get_kerning_adjustment
    bcc _adjustment
    bra _end
_adjustment:
    pha
    lda.b temp
    clc
    adc 1, s
    cmp #0x9
    bcs _overflow
    bra _no_overflow
_overflow:
    pla
    lda #0x08
    sta.b temp
    pha
    bra _no_adjustment
_no_overflow:
    sta.b temp
_no_adjustment:

    pla
_end:
    lda.b temp
    sta.b bits_left_on_tile

_finalize:
    pha
    lda.b current_char
    sta.b prev_char
    pla
    rts
    }

_get_kerning_adjustment_binary_search:
    {
; Space ($FF) is in no kerning table: bail before the bank push (external callers too). Caller in M=16.
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
    lda.w menu_font, y
    beq not_found
    dec

; Search bounds on stack, top down: [high] [low] [target_char]
    pha  ; Push high bound (count-1)
    lda.w #0x0000  ; Low bound = 0
    pha  ; Push low bound
    lda.b prev_char  ; Load target character
    pha  ; Push target for comparison

_binary_loop:
    lda 0x05, s  ; Load high bound
    cmp 0x03, s  ; Compare with low bound
    bcc not_found_cleanup  ; If high < low, not found

    lda 0x03, s  ; Load low
    clc
    adc 0x05, s  ; Add high
    lsr  ; Divide by 2
    tax  ; X = mid index

; entry = mid * 3 + kerning_table_offset + 2 (2-byte char pair, 1-byte adjustment)
    pha  ; Save mid
    asl  ; mid * 2
    clc
    adc 0x01, s  ; Add original mid (now mid * 3)
    clc
    adc.w #kerning_table_offset + 2
    tay  ; Y = address of entry
    pla  ; Restore mid to A

    pha  ; Save mid again
    lda.w menu_font, y  ; Load 16-bit char pair

    cmp 0x03, s  ; Compare with target_char
    beq found_pair_cleanup  ; Found exact match!
    bcc search_upper_half  ; If entry < target, search upper half

; high = mid - 1
    pla  ; Get mid
    sec
    sbc.w #0x0001  ; mid - 1
    bcc not_found_cleanup  ; mid was 0, underflow → not found
    sta 0x05, s  ; Update high bound
    bra _binary_loop

search_upper_half:
; low = mid + 1
    pla  ; Get mid
    inc  ; mid + 1
    sta 0x03, s  ; Update low bound
    bra _binary_loop

found_pair_cleanup:
    pla  ; Remove mid from stack

    iny
    iny
    lda.w menu_font, y  ; Load adjustment value (8-bit) - matches original
    and.w #0x00ff  ; Ensure high byte is clear

; ply keeps A (adjustment)
    ply  ; Remove target_char
    ply  ; Remove low bound
    ply  ; Remove high bound

    clc  ; Clear carry (success)
    plb
    plb
    rts

not_found_cleanup:
    pla  ; Remove target_char
    pla  ; Remove low bound
    pla  ; Remove high bound

not_found:
    lda.w #0x0000
    sec  ; Set carry (not found)
    plb
    plb
    rts

_space_skip:
; M=8 from the entry check and nothing pushed yet: return not found
    rep #0x20
    lda.w #0x0000
    sec
    rts

found_pair:
; Unreferenced: the binary search exits through found_pair_cleanup
    clc
    plb
    plb
    rts
    }

get_kerning_adjustment:
    {
    php
    rep #0x10
    phx
    phy
    rep #0x20
    jsr.w _get_kerning_adjustment_binary_search
    sep #0x20
    ply
    plx
    plp
    rts
    }

battle_msg_kerning_binary_ext:
    jsr.w get_kerning_adjustment
    rtl
tilemap_write_no_inc:
"""
Write the allocator's 10-bit tile_id at tilemap_offset: low 8 bits in the entry's low byte, bits 8-9 OR'd into the
high byte with the palette bits, so inventory tile_ids past 0xFF reach the upper half of BG3 CHR.
"""


    phy
    ldy.b tilemap_offset
    lda.l render_allocator.allocated_tile_id
    sta.b (btlgfx_dp.kana_row_ptr), y
    lda #0xff
    sta.b (btlgfx_dp.dakuten_row_ptr), y
    iny
    lda.b btlgfx_dp.text_tile_flags
    sta.b (btlgfx_dp.dakuten_row_ptr), y
    ora.l render_allocator.allocated_tile_id + 1
    ora.b #0x01
    sta.b (btlgfx_dp.kana_row_ptr), y
    ply
    rts
tilemap_write:
    pha
    jsr.w tilemap_write_no_inc
    jsr.w render_allocator.increment
    rep #0x20
    inc.b tilemap_offset
    inc.b tilemap_offset
    sep #0x20
    tdc
    pla
    rts
    }


    .scope messages_vwf {
    """High-level battle-message VWF parser: consumes the dialog stream and feeds glyphs into battle_render."""
    dakuten_table = 0x16fa40
put_fixed_char:
"""Render a char (A) through `battle_render.display_char`."""


    cmp #0x42
    bcc put_fixed_char_dakuten
put_fixed_char_no_dakuten:
    jmp.w battle_render.display_char
put_fixed_char_dakuten:
    jmp.w battle_render.display_char
put_fixed_char_far:
"""Far (RTL) entries for the put_fixed_char routines."""
    jsr.w put_fixed_char
    rtl
put_fixed_char_dakuten_far:
    jsr.w put_fixed_char_dakuten
    rtl
put_fixed_char_no_dakuten_far:
    jsr.w put_fixed_char_no_dakuten
    rtl
init:
"""Set the VWF render flag and init the renderer for the messages window."""


    jsr.l battle_flags.set_vwf_render
    jsr.w battle_render.init
    rtl
init_commands_list:
    jsr.l battle_flags.set_vwf_render
    jsr.w battle_render.init_commands_list
    rtl
init_monsters:
    jsr.l battle_flags.set_vwf_render
    jsr.w battle_render.init_monsters
    rtl

init_names:
    jsr.l battle_flags.set_vwf_render
    jsr.w battle_render.init_names
    rtl
init_inventory_for_current_slot:
"""
Init the VWF for inventory slot _rolling_slot_index ($EF82, 0..5): tile base 0xC0 + slot * ITEM_VWF_TILE_BUDGET,
slice cleared, allocator clamped to the slot.
"""


    php
    rep #0x10
    rep #0x20
    lda 0x7EEF82
    and.w #0x00FF
    sta.b 0x00

; tile base = slot * ITEM_VWF_TILE_BUDGET + ITEM_VWF_TILE_BASE, 6 x 10 tiles in $C0..$FB.
; The *10 is hardcoded (asl x3 + slot twice): change it with K.
    asl
    asl
    asl
    clc
    adc.b 0x00
    clc
    adc.b 0x00
    clc
    adc.w #ITEM_VWF_TILE_BASE
    sta.b 0x02

; Clear the slot's CHR slice: stale bits would OR into the new render. $FF $00 = empty 4bpp plane pair.
    lda.b 0x02
    asl
    asl
    asl
    asl
    clc
    adc.w #battle_render.buffer_ptr & 0xffff
    tax
    ldy.w #ITEM_VWF_CHR_WORDS
_chr_clear_loop:
    lda.w #0x00ff
    sta 0x700000, x
    inx
    inx
    dey
    bne _chr_clear_loop

    lda.b 0x02
    sep #0x20
    pha
    jsr.l battle_flags.set_vwf_render
    pla
; A = slot tile base. Never store it into pending_transfer_mask (a dirty-region bitmask): $C0, $CA, ... wipe
; CHR_PENDING and every region bit, and the names region (rendered once per battle) stays black all fight.
    jsr.w battle_render.render_allocator_init_with_tile_id_thunk
; Clamp the allocator to the slot's last tile, AFTER init_with_tile_id (which resets slot_limit_low to $FF).
    lda.b 0x02
    clc
    adc.b #( ITEM_VWF_TILE_BUDGET - 1 )
    sta.l render_allocator.slot_limit_low
    stz.b battle_render.prev_char
    lda.b #0x08
    sta.b battle_render.bits_left_on_tile
    stz.b battle_render.temp
    stz.b battle_render.counter
    plp
    rtl
init_inventory:
"""`init_inventory_region` with set_vwf_render, so char dispatch goes through the VWF put_char path."""


    jsr.l battle_flags.set_vwf_render
    jsr.w battle_render.init_inventory_region
    rtl
mirror_main_to_cmd:
"""
Copy the main-view BG3 tilemap $7E:BE65..$C1A4 ($340 bytes) to the cmd window $7E:C1A5..$C4E4 with MVN (~5800
cycles, half vanilla's loop). Not GP-DMA via $2180: a WRAM-to-WRAM DMA writes zeros. M=8 X=16 in, P restored.
"""


    php
    rep #0x30
    ldx #0xBE65
    ldy #0xC1A5
    lda #0x033F
; A = byte count - 1 ($340 bytes)
    .db 0x54
    .db 0x7E
    .db 0x7E
; mvn #$7E, #$7E (dst_bank, src_bank)
    plp
    rtl
spell_name_begin:
"""
Start one spell name in the VWF: A = its first tile id in the spell ring. Blanks its SPELL_NAME_TILES tiles and
points the allocator at them, clamped to the last one so a name can't spill. M=8, X=16.
"""


    php
    sep #0x20
    rep #0x10
    pha
    rep #0x20
    and.w #0x00FF
    asl
    asl
    asl
    asl
    tax
    clc
    adc.w #battle_render.SPELL_NAME_TILES * 0x10
    pha  ; the clear's end, on the stack: an NMI row render starts its own name in between

_snb_clear:
    lda.w #0x00FF
    sta.l battle_render.buffer_ptr, x
    inx
    inx
    txa
    cmp 1, s
    bne _snb_clear
    pla
    sep #0x20
    pla
    pha
    jsr.w battle_render.render_allocator_init_with_tile_id_thunk
    pla
    clc
    adc.b #battle_render.SPELL_NAME_TILES - 1
    sta.l render_allocator.slot_limit_low
    stz.b battle_render.prev_char
    lda.b #0x08
    sta.b battle_render.bits_left_on_tile
    stz.b battle_render.temp
    stz.b battle_render.counter
    plp
    rtl

draw_spell_name:
"""
One spell name from its baked tiles (small_vwf/baked_names.s): X = spell id, Y = cell offset into the ($32)/($34)
row pair, $36 = palette. Tiles go to the CHR buffer at the allocator (set by spell_name_begin), cells written as the
renderer would; the NMI hook transfers the region. M=8, X=16; Y comes back past the name.
"""
    php
    sep #0x20
    rep #0x10
    rep #0x20
    txa
    asl
    asl
    tax
    lda.l spell_names_vwf_tbl + 2, x
    and.w #0x00FF
    beq _dsn_done
    pha  ; 3,s tiles
    lda.l spell_names_vwf_tbl, x
    tax  ; source offset in the blob
    phy  ; 1,s cell offset
    lda.l render_allocator.allocated_tile_id
    and.w #0x00FF
    asl
    asl
    asl
    asl
    tay  ; CHR buffer offset
    lda 3, s
    asl
    asl
    asl  ; words
    pha
_dsn_copy:
    lda.l spell_names_vwf, x
    phx
    tyx
    sta.l battle_render.buffer_ptr, x
    plx
    inx
    inx
    iny
    iny
    lda 1, s
    dec
    sta 1, s
    bne _dsn_copy
    pla
    ply
    sty.b battle_render.tilemap_offset
    pla  ; tiles
    sep #0x20
    tax
_dsn_cell:
    jsr.w battle_render.tilemap_write
    dex
    bne _dsn_cell
    ldy.b battle_render.tilemap_offset
_dsn_done:
    sep #0x20
    lda.b #0x08
    sta.b battle_render.bits_left_on_tile
    stz.b battle_render.prev_char
    plp
    rtl

spell_ring_flush:
"""Queue the spell ring's CHR flush for the next NMI. Preserves P."""


    php
    sep #0x20
    lda.l battle_render_state.pending_transfer_mask
    ora.b #battle_render.CHR_PENDING | battle_render.CHR_REGION_SPELLS
    sta.l battle_render_state.pending_transfer_mask
    plp
    rtl

draw_inventory_text:
"""
Inventory text renderer walking the format buffer itself (no vanilla draw_text dispatch), so VWF name chars mix
with fixed symbol / digit tiles without toggling battle_flags mid-stream.
In (vanilla draw_text contract): $EF50 format ptr, $EF52 destination (bank $7E), $EF54 line length (15),
$EF55 palette, $7EEF82 slot index (0..5) for the allocator base.
Codes: 0x00 end, 0x03 BB fixed tile BB, 0x0E PP attribute byte, 0x0B II item II's baked name, 0xFC NN goto cell
NN, 0xFE fixed <-> VWF toggle; any other byte is a glyph in the current mode.
"""


    php
    rep #0x10
    sep #0x20

; DBR = $7E: abs,X / abs,Y writes target WRAM
    phb
    lda.b #0x7E
    pha
    plb

; allocator at 0xC0 + slot * 10, glyph state reset
    jsr.w init_inventory_for_current_slot_local
    bra _di_body

draw_inventory_text_at:
"""
`draw_inventory_text` into a caller-chosen tile range instead of the current inventory slot's: A8 = first tile id
(the 0x1xx page's low byte), Y16 = tiles it may use. The range's CHR is blanked first; the caller queues its flush.
"""
    php
    rep #0x10
    sep #0x20
    phb
    pha
    lda.b #0x7E
    pha
    plb
    pla
    jsr.w _init_glyphs_at

_di_body:

; Vanilla draw_text prologue: src / row-1 / row-2 / palette into DP $30 / $32 / $34 / $36 (tilemap_write)
    lda 0xef55
    sta.b btlgfx_dp.text_tile_flags
    ldx 0xef50
    stx.b btlgfx_dp.text_ptr
    ldx 0xef52
    stx.b btlgfx_dp.dakuten_row_ptr
; row 2 = row 1 + line_length * 2. Don't asl $ef54 in place: it would double every render.
    lda 0xef54
    asl
    clc
    adc.b btlgfx_dp.dakuten_row_ptr
    sta.b btlgfx_dp.kana_row_ptr
    lda.b btlgfx_dp.dakuten_row_ptr + 1
    adc #0x00
    sta.b btlgfx_dp.kana_row_ptr + 1

; Pre-clear both rows (15 cells each) to space + palette so a 0xFC goto leaves no stale tiles behind.
    ldy.w #0x0000
_di_clear:
    lda #0xff
    sta.b (btlgfx_dp.dakuten_row_ptr), y
    sta.b (btlgfx_dp.kana_row_ptr), y
    iny
    lda.b btlgfx_dp.text_tile_flags
    sta.b (btlgfx_dp.dakuten_row_ptr), y
    sta.b (btlgfx_dp.kana_row_ptr), y
    iny
    cpy.w #30
    bne _di_clear

; X = format ptr, Y = cell offset into ($32)/($34)
    ldx 0xEF50
    ldy.w #0x0000

; Start in fixed mode (the leading symbol byte is a tile_id). Mode flag in DP $1F, not $37: $37-$3A are
; joypad shadows, and $80 there latched as a phantom A press (cursor.asm @b5a6), toggling swap mode every scroll.
    lda.b #0x80
    sta.b 0x1F

_di_loop:
    lda.w 0x0000, x
    beq _di_done
    cmp #0x03
    beq _di_fixed
    cmp #0x0E
    beq _di_pal
    cmp #0x0B
    bne _di_not_baked
    jmp.w _di_baked
_di_not_baked:
    cmp #0xFC
    beq _di_pad
    cmp #0xFE
    beq _di_vwf_toggle
    bit.b 0x1F
    bmi _di_fixed_char
; VWF char: display_char advances Y (tilemap_offset) as it allocates
    inx
    sty.b battle_render.tilemap_offset
    jsr.w battle_render.display_char
    ldy.b battle_render.tilemap_offset
    jmp.w _di_loop

_di_fixed_char:
; Fixed char: tile_id at ($34),y, no +0x100 bit (that is only for VWF tiles in 0x1xx)
    sta.b (btlgfx_dp.kana_row_ptr), y
    lda #0xff
    sta.b (btlgfx_dp.dakuten_row_ptr), y
    iny
    lda.b btlgfx_dp.text_tile_flags
    sta.b (btlgfx_dp.dakuten_row_ptr), y
    sta.b (btlgfx_dp.kana_row_ptr), y
    iny
    inx
    jmp.w _di_loop


_di_fixed:
; 0x03 BB: fixed tile_id BB, as _di_fixed_char
    inx
    lda.w 0x0000, x
    sta.b (btlgfx_dp.kana_row_ptr), y
    lda #0xff
    sta.b (btlgfx_dp.dakuten_row_ptr), y
    iny
    lda.b btlgfx_dp.text_tile_flags
    sta.b (btlgfx_dp.dakuten_row_ptr), y
    sta.b (btlgfx_dp.kana_row_ptr), y
    iny
    inx
    jmp.w _di_loop

_di_pal:
; 0x0E PP: tile flags byte, as vanilla draw_text's $36
    inx
    lda.w 0x0000, x
    sta.b btlgfx_dp.text_tile_flags
    inx
    jmp.w _di_loop

_di_done:
; Clear the VWF flag so later renders (monster HP, status text) use the WRAM put_char path
    jsr.l battle_flags.clear_vwf_render
; Mark the slot's 160-byte CHR slice dirty; the NMI flushes it within vblank
    php
    sep #0x30
    lda 0x7EEF82  ; slot index (low byte only ; M=8)
    and.b #0x07  ; clamp to 0..7 (valid range 0..5)
    tax
    lda.l _dma_slot_bit_lut, x
    ora.l battle_render_state.dma_dirty_slots
    sta.l battle_render_state.dma_dirty_slots
    plp
    plb
    plp
    rtl

_di_skip:
    inx
    jmp.w _di_loop

_di_vwf_toggle:
    inx
    lda.b 0x1F
    eor.b #0x80
    sta.b 0x1F
    jmp.w _di_loop

_di_pad:
; 0xFC NN: goto cell NN (Y = NN * 2; cells are pre-cleared); the next VWF char starts a fresh tile
    inx
    lda.w 0x0000, x
    inx
    asl
    tay
    lda #0x08
    sta.b battle_render.bits_left_on_tile
    jmp.w _di_loop

_di_baked:
; 0x0B II -> item II's baked name (small_vwf/baked_names.s)
    inx
    lda.w 0x0000, x
    inx
    phx
    copy_baked_name(item_names_vwf, item_names_vwf_tbl, 0)
    plx
    jmp.w _di_loop

draw_monster_name_baked:
"""
TextCmd_0C's monster name ($02:A7D7): A = monster id, Y = cell offset. The slot blanked, then the name's baked tiles
(small_vwf/baked_names.s); Y comes back past the name.
"""
    pha
    phy
    jsr.l initialize_monster_slot
    ply
    pla
    copy_baked_name(monster_names_vwf, monster_names_vwf_tbl, 1)
    rtl

draw_commands_baked:
"""
The command window from the format buffer `_draw_command_list_for_character` built at $EF50 ($0E f: tile flags, $01:
next line, $0F II: command II's baked name, $00: end), with DrawText's row setup ($EF52 rows, $EF54 cells a line).
"""
    php
    sep #0x20
    rep #0x10
    lda.w 0xEF55
    sta.b btlgfx_dp.text_tile_flags
    lda.w 0xEF54
    asl
    sta.w 0xEF54
    rep #0x20
    lda.w 0xEF52
    sta.b btlgfx_dp.dakuten_row_ptr
    lda.w 0xEF54
    and.w #0x00FF
    clc
    adc.b btlgfx_dp.dakuten_row_ptr
    sta.b btlgfx_dp.kana_row_ptr
    sep #0x20
    ldx.w 0xEF50
    ldy.w #0x0000
_dc_loop:
    lda.w 0x0000, x
    bne _dc_code
    jmp.w _dc_done
_dc_code:
    inx
    cmp.b #0x0E
    bne _dc_not_flags
    lda.w 0x0000, x
    inx
    sta.b btlgfx_dp.text_tile_flags
    bra _dc_loop
_dc_not_flags:
    cmp.b #0x01
    bne _dc_not_newline
    rep #0x20
    lda.w 0xEF54
    and.w #0x00FF
    pha
    asl
    clc
    adc.b btlgfx_dp.dakuten_row_ptr
    sta.b btlgfx_dp.dakuten_row_ptr
    pla
    clc
    adc.b btlgfx_dp.dakuten_row_ptr
    sta.b btlgfx_dp.kana_row_ptr
    sep #0x20
    ldy.w #0x0000
    bra _dc_loop
_dc_not_newline:
    cmp.b #0x0F
    bne _dc_loop
    lda.w 0x0000, x
    inx
    phx
    copy_baked_name(command_names_vwf, command_names_vwf_tbl, 0)
    plx
    jmp.w _dc_loop
_dc_done:
    plp
    rtl

_init_glyphs_at:
"""Blank Y16 tiles of CHR from tile id A8, aim the allocator there (clamped to the range) and reset the glyph state."""
    php
    rep #0x30
    and.w #0x00FF
    sta.b 0x02
    tya
    sta.b 0x04
    asl
    asl
    asl
    tay  ; words to blank: 8 a tile
    lda.b 0x02
    asl
    asl
    asl
    asl
    clc
    adc.w #battle_render.buffer_ptr & 0xffff
    tax
_ig_chr_clear:
    lda.w #0x00ff
    sta 0x700000, x
    inx
    inx
    dey
    bne _ig_chr_clear
    sep #0x20
    jsr.l battle_flags.set_vwf_render
    lda.b 0x02
    jsr.w battle_render.render_allocator_init_with_tile_id_thunk
    lda.b 0x02
    clc
    adc.b 0x04
    dec
    sta.l render_allocator.slot_limit_low
    stz.b battle_render.prev_char
    lda.b #0x08
    sta.b battle_render.bits_left_on_tile
    stz.b battle_render.temp
    stz.b battle_render.counter
    plp
    rts

init_inventory_for_current_slot_local:
"""`init_inventory_for_current_slot` for jsr.w callers (returns with rts)."""


    php
    rep #0x10
    rep #0x20
    lda 0x7EEF82
    and.w #0x00FF
    sta.b 0x00
    asl
    asl
    asl
    clc
    adc.b 0x00
    clc
    adc.b 0x00
    clc
    adc.w #ITEM_VWF_TILE_BASE
    sta.b 0x02
    asl
    asl
    asl
    asl
    clc
    adc.w #battle_render.buffer_ptr & 0xffff
    tax
    ldy.w #ITEM_VWF_CHR_WORDS
_dis_chr_clear:
    lda.w #0x00ff
    sta 0x700000, x
    inx
    inx
    dey
    bne _dis_chr_clear
    lda.b 0x02
    sep #0x20
    pha
    jsr.l battle_flags.set_vwf_render
    pla
; A = slot tile base; never into pending_transfer_mask (see init_inventory_for_current_slot).
    jsr.w battle_render.render_allocator_init_with_tile_id_thunk
; Clamp to the slot's last tile, AFTER init_with_tile_id (which resets slot_limit_low).
    lda.b 0x02
    clc
    adc.b #( ITEM_VWF_TILE_BUDGET - 1 )
    sta.l render_allocator.slot_limit_low
    stz.b battle_render.prev_char
    lda.b #0x08
    sta.b battle_render.bits_left_on_tile
    stz.b battle_render.temp
    stz.b battle_render.counter
    plp
    rts
init_monsters_gated:
"""
Gated `init_monsters`: always sets the VWF flag (paired with `deinit_gated`). A clean region skips clear_buffer and
allocator setup and leaves render_skipped = $FF, so the trampoline skips DrawText and deinit_gated the DMA signal.
"""


    jsr.l battle_flags.set_vwf_render
    jsr.w battle_render.init_monsters_gated
    rtl
init_names_gated:
"""Gated counterpart to `init_names`."""
    jsr.l battle_flags.set_vwf_render
    jsr.w battle_render.init_names_gated
    rtl
init_commands_list_gated:
"""Gated counterpart to `init_commands_list`."""
    jsr.l battle_flags.set_vwf_render
    jsr.w battle_render.init_commands_list_gated
    rtl
deinit:
"""Deinit the renderer: battle_flags back to fixed mode, and queue the rendered region's CHR flush for the NMI."""


    jsr.l battle_flags.clear_vwf_render
; The VRAM transfer is the battle NMI's. Flag the region again here: a render spanning frames can lose its region bit
; to an NMI between its init (buffer cleared) and its glyphs, which then never go up.
    lda.l battle_render_state.pending_transfer_mask
    ora.b #battle_render.CHR_PENDING
    ora.l battle_render_state.render_region
    sta.l battle_render_state.pending_transfer_mask
    rtl
deinit_gated:
"""Companion to `init_*_gated`: always clears the flag; queues the CHR flush only if the init rendered."""


    jsr.l battle_flags.clear_vwf_render
    lda.l battle_render_state.render_skipped
    bne _deinit_gated_done
    lda.l battle_render_state.pending_transfer_mask
    ora.b #battle_render.CHR_PENDING
    ora.l battle_render_state.render_region  ; see `deinit`
    sta.l battle_render_state.pending_transfer_mask
_deinit_gated_done:
    rtl
_wait_for_vblank:
    {
    inc 0x1811
_wait:
    lda 0x1811
    bne _wait
    rts
    }
_footer_rows:
""" The border-row scrolls the lists pin below their body: item list, then spell list (7 words each). """
    .dw 0x0193, 0x0193, 0x0193, 0x019B, 0x019B, 0x019B, 0x019B
    .dw 0x01F7, 0x01F7, 0x01F7, 0x0026, 0x0025, 0x0024, 0x0023

_is_footer_row:
"""Carry set if A (16-bit) is one of the item list's pinned rows (spell list rows are vanilla's own values)."""
    cmp.w #0x0193
    beq _ifr_yes
    cmp.w #0x019B
    beq _ifr_yes
    clc
    rts
_ifr_yes:
    sec
    rts

dma_transfer:
"""
Vblank DMA flush for the battle VWF: transfers the regions flagged in `pending_transfer_mask` and clears them.
Forces blank ($2100 = $80) when work is queued; the vanilla INIDISP write at $02:837F restores brightness.
"""


    pha
    phx
    phy
; The DMA below (~40 lines) starts late in the NMI (after OAM DMA + flying-HDMA chain) and spills past the
; ~37-line vblank, tearing VRAM: force blank whenever work is queued. Idle frames skip it (no black strip).
    php
    sep #0x20
    lda.l battle_render_state.pending_transfer_mask
    ora.l battle_render_state.tilemap_pending_mask
    ora.l battle_render_state.dma_dirty_slots
    beq _no_force_blank
    lda #0x80
    sta.l ppu.INIDISP
_no_force_blank:
    plp
; BG3 V-scroll footer pin (ch2 table, shared by cmd / status / inventory). With a list up, vanilla scrolls its
; two rows below the body ($8068..$8081) to black ($02BB) where the bottom border belongs: pin the border rows
; every NMI while the item or spell list has the cursor (vanilla's state-1 swap at $02:A8FE would undo it within
; a frame). Elsewhere vanilla writes its own on every window change. $4A bit 2 stays set through target select.
    php
    sep #0x30
    lda.l battle_cursor_type
    ldx.b #0x00  ; the item list's border rows
    cmp.b #BATTLE_CURSOR_INVENTORY
    bne _inv_footer_not_items
    lda.l (0x7E0000 as BtlGfxDP).menu_windows_open
    and.b #0x04
    bne _inv_footer_list_up
    bra _inv_footer_unpin
_inv_footer_not_items:
    ldx.b #INVENTORY_FOOTER_ENTRIES * 2  ; the spell list's
    cmp.b #BATTLE_CURSOR_SPELLS
    beq _inv_footer_list_up
    cmp.b #BATTLE_CURSOR_MP_COST
    bne _inv_footer_unpin
_inv_footer_list_up:
    phx
    lda.l battle_render_state.inventory_footer_pinned
    bne _inv_footer_pin
; Not while vanilla still swaps the window's rows in (menu_hdma_pending = 1, a row a frame): the pin would show
; the party window's PV header under a window not yet there. Start from the NMI before the last row's swap.
    lda.l menu_hdma_pending
    beq _inv_footer_first_pin
    lda.l menu_hdma_rows
    cmp.b #0x02
    bcc _inv_footer_first_pin
    plx
    bra _inv_footer_done
_inv_footer_first_pin:
    lda.b #0x01
    sta.l battle_render_state.inventory_footer_pinned
; first pinned frame: keep vanilla's values, the active copy's (the unpin puts them in both)
    rep #0x30
    ldx.w #0x0000
_inv_save_loop:
    lda.l btl_bg3_scroll_hdma + 0x356, x
    sta.l inventory_footer_saved, x
    inx
    inx
    inx
    inx
    cpx.w #INVENTORY_FOOTER_ENTRIES * 4
    bne _inv_save_loop
_inv_footer_pin:
    sep #0x20
    pla  ; the 8-bit X pushed above: the list's rows in _footer_rows
    rep #0x30
    and.w #0x00FF
    tay
    ldx.w #0x0000
_inv_pin_loop:
    tya
    phx
    tax
    lda.l _footer_rows, x
    plx
    sta.l btl_bg3_scroll_hdma + 0x356, x
    iny
    iny
    inx
    inx
    inx
    inx
    cpx.w #INVENTORY_FOOTER_ENTRIES * 4
    bne _inv_pin_loop
    bra _inv_footer_done
_inv_footer_unpin:
; The list lost the cursor. Vanilla double-buffers this table (active $7F74.., swap copy +$280): put the saved
; values back in both where ours remain (rewritten entries keep theirs). The swap copy too: closing the list
; swaps them right after ($02:A943), and its stale $02BB values would scroll a party row into the bottom lines.
    lda.l battle_render_state.inventory_footer_pinned
    beq _inv_footer_done
    lda.b #0x00
    sta.l battle_render_state.inventory_footer_pinned
    rep #0x30
    ldx.w #0x0000
_inv_unpin_loop:
    lda.l btl_bg3_scroll_hdma + 0x356, x
    jsr.w _is_footer_row
    bcc _inv_unpin_swap
_inv_unpin_active:
    lda.l inventory_footer_saved, x
    sta.l btl_bg3_scroll_hdma + 0x356, x
_inv_unpin_swap:
    lda.l btl_bg3_scroll_hdma + 0x356 + 0x280, x
    jsr.w _is_footer_row
    bcc _inv_unpin_next
_inv_unpin_swap_write:
    lda.l inventory_footer_saved, x
    sta.l btl_bg3_scroll_hdma + 0x356 + 0x280, x
_inv_unpin_next:
    inx
    inx
    inx
    inx
    cpx.w #INVENTORY_FOOTER_ENTRIES * 4
    bne _inv_unpin_loop
_inv_footer_done:
    plp
; Inventory CHR: DMA one dirty slot's 160-byte slice ($703000 + (0xC0 + N*10)*16 -> VRAM $BC00 + N*$A0).
    php
    sep #0x20
    rep #0x10
    lda.l battle_render_state.dma_dirty_slots
    and.b #0x3F
    bne _inv_dma_have
    jmp.w _no_inv_dma
_inv_dma_have:
    ldx #0xFFFF
_inv_dma_find:
    inx
    lsr
    bcc _inv_dma_find
    cpx.w #0x0006  ; safety: out-of-range index -> no DMA
    bcs _inv_dma_done
; X = slot index 0..5. Clear its bit before DMA so re-entry is safe.
    phx
    lda.l _dma_slot_bit_lut, x
    eor.b #0xFF
    and.l battle_render_state.dma_dirty_slots
    sta.l battle_render_state.dma_dirty_slots
    plx
; Build X = slot*2 with X.hi clean (we're in M=8 X=16, plain tax leaks A.hi).
    rep #0x20
    txa
    and.w #0x000F
    asl
    tax
    sep #0x20
; LUT reads use `.l` (24-bit long) since DBR in NMI isn't bank-20. The addresses go straight to Y and X: the NMI
; lands anywhere in the main loop, whose direct page holds live values (the monster draw's type index at $0A:
; staging these in $0A-$0D would wipe it, the draw taking a zero width and overrunning RAM). Only $0E, vanilla's NMI
; scratch.
    rep #0x20
    lda.l _dma_slot_vram_lut, x
    tay
    lda.l _dma_slot_src_lut, x
    tax
    lda.w #0x00A0
    sta.b 0x0e
    sep #0x20
    lda.b #0x70
    jsr.w _sram_dma_transfer_7
_inv_dma_done:
_no_inv_dma:
    plp

; Per-region CHR: flush the regions flagged this frame, 0x300 bytes each, buffer_ptr + N*0x300 -> VRAM $B000 + N*0x300.
    php
    sep #0x20
    rep #0x10
    lda.l battle_render_state.pending_transfer_mask
    bit.b #battle_render.CHR_PENDING
    bne _chr_dma_go
    jmp.w _chr_dma_skip
_chr_dma_go:
    bit.b #battle_render.CHR_REGION_MESSAGES
    beq _chr_no_msg
    ldy.w #0xb000 >> 1
    ldx.w #battle_render.buffer_ptr
    rep #0x20
    lda #0x300
    sta.b 0x0e
    sep #0x20
    lda.b #0x70
    jsr.w _sram_dma_transfer_7
_chr_no_msg:
    lda.l battle_render_state.pending_transfer_mask
    bit.b #battle_render.CHR_REGION_MONSTERS
    beq _chr_no_mon
    ldy.w #( 0xb000 + 0x300 ) >> 1
    ldx.w #battle_render.buffer_ptr + 0x300
    rep #0x20
    lda #0x300
    sta.b 0x0e
    sep #0x20
    lda.b #0x70
    jsr.w _sram_dma_transfer_7
_chr_no_mon:
    lda.l battle_render_state.pending_transfer_mask
    bit.b #battle_render.CHR_REGION_NAMES
    beq _chr_no_names
    ldy.w #( 0xb000 + 0x600 ) >> 1
    ldx.w #battle_render.buffer_ptr + 0x600
    rep #0x20
    lda #0x300
    sta.b 0x0e
    sep #0x20
    lda.b #0x70
    jsr.w _sram_dma_transfer_7
_chr_no_names:
    lda.l battle_render_state.pending_transfer_mask
    bit.b #battle_render.CHR_REGION_COMMANDS
    beq _chr_no_cmds
    ldy.w #( 0xb000 + 0x900 ) >> 1
    ldx.w #battle_render.buffer_ptr + 0x900
    rep #0x20
    lda #0x300
    sta.b 0x0e
    sep #0x20
    lda.b #0x70
    jsr.w _sram_dma_transfer_7
_chr_no_cmds:
    lda.l battle_render_state.pending_transfer_mask
    bit.b #battle_render.CHR_REGION_SPELLS
    beq _chr_no_spells
    ldy.w #( 0xb000 + battle_render.SPELL_TILE_BASE * 0x10 ) >> 1
    ldx.w #battle_render.buffer_ptr + battle_render.SPELL_TILE_BASE * 0x10
    rep #0x20
    lda.w #battle_render.SPELL_RING_TILES * 0x10
    sta.b 0x0e
    sep #0x20
    lda.b #0x70
    jsr.w _sram_dma_transfer_7
_chr_no_spells:
    lda.l battle_render_state.pending_transfer_mask
    bit.b #ChrTransferBits.status.mask
    beq _chr_no_status
    ldy.w #STATUS_VRAM_WORD
    ldx.w #status_name_tiles & 0xFFFF
    rep #0x20
    lda.w #STATUS_STAGING_BYTES
    sta.b 0x0e
    sep #0x20
    lda.b #status_name_tiles >> 16
    jsr.w _sram_dma_transfer_7
_chr_no_status:
    lda.b #0x00
    sta.l battle_render_state.pending_transfer_mask
_chr_dma_skip:
    plp
_no_transfer:
; Per-region tilemap DMA (WRAM -> BG VRAM) for `tilemap_pending_mask` (gated inits, cmd-window thunk, highlight
; refresh, ATB gauge); replaces vanilla's TfrCmdWindow / TfrMainMenu queue to stay in sync with the CHR DMA above.
    php
    sep #0x20
; M=8, X=16: the NMI caller may leave any M/X
    rep #0x10
    lda.l battle_render_state.tilemap_pending_mask
    beq _no_tilemap_dma
    pha
    bit.b #battle_render.TILEMAP_PENDING_COMMANDS
    beq _no_cmd_tilemap
    ldy #0x71C0
; VRAM word addr (battle cmd window)
    ldx #0xC1E6
; WRAM tilemap src
    rep #0x20
    lda #0x0280
    sta.b 0x0e
    sep #0x20
    lda #0x7E
    jsr.w _sram_dma_transfer_7
_no_cmd_tilemap:
    pla
    bit.b #battle_render.TILEMAP_PENDING_MAIN
    beq _no_main_tilemap
    ldy #0x7020
; VRAM word addr (main window: names/monsters/hp/status)
    ldx #0xBEA6
    rep #0x20
    lda #0x0280
    sta.b 0x0e
    sep #0x20
    lda #0x7E
    jsr.w _sram_dma_transfer_7
_no_main_tilemap:
    lda #0x00
    sta.l battle_render_state.tilemap_pending_mask
_no_tilemap_dma:
    plp
    ply
    plx
    pla
; Flying-monster BG1 V-scroll table, every vblank (bank-02 trampoline: jsr UpdateFlyingHDMA; rtl)
    jsr.l flying_hdma_trampoline
    jsr.l btlgfx_tfr_sprites
    rtl
_sram_dma_transfer_7:
    phb
    pha
    lda #0x00
    pha
    plb
    pla
    sty ppu.VMADDL
    stx dma_ch7.A1TL
    sta dma_ch7.A1B
    lda #0x01
    sta dma_ch7.DMAP
    lda #PPU.VMDATAL
    sta dma_ch7.BBAD
    ldx.b 0x0e
    stx dma_ch7.DASL
    lda #1 << 7
    sta cpu_regs.MDMAEN
    plb
    rts
new_line_escape_code_handler:
"""
Handler for the $01 newline text-stream escape: allocate a fresh tile via `render_allocator.increment`, reset
bits_left_on_tile to 8, and move both row pointers down one line ($EF54 cells).
"""


    pha
    jsr.w render_allocator.increment
    lda #8
    sta.b battle_render.bits_left_on_tile
    pla
    lda 0xef54
    rep #0x20
    pha
    asl
    clc
    adc.b btlgfx_dp.dakuten_row_ptr
    sta.b btlgfx_dp.dakuten_row_ptr
    sta.l render.tilemap_offset
    pla
    clc
    adc.b btlgfx_dp.dakuten_row_ptr
    sta.b btlgfx_dp.kana_row_ptr
    tdc
    tay
    sep #0x20
    rtl

; Per-slot inventory CHR DMA tables: dirty bit 1 << N, VRAM word ($BC00 + N*$A0) >> 1, bank-70 source
; $3C00 + N*$A0 (10 tiles from 0xC0 + N*10 = 160 bytes).
_dma_slot_bit_lut:
    .for k := 0, 6 {
    .db ( 1 << k )
    }
_dma_slot_vram_lut:
    .for k := 0, 6 {
    .dw ( 0xBC00 + k * 0xA0 ) >> 1
    }
_dma_slot_src_lut:
    .for k := 0, 6 {
    .dw 0x3C00 + k * 0xA0
    }
    }
}
