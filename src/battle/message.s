"""
Battle-message tile renderer + VWF parser scopes (`battle_render` low-level blitter, `messages_vwf` high-level
dialog-stream consumer).
"""
.if 0 {
    .scope _vwf_tile_ring {
; Ring buffer for VWF tile allocation
; Each entry represents 8 consecutive tiles
; VWF system computes addresses from tile_id
    MAX_ENTRIES = 37
; Number of 8-tile slots (296 tiles / 8 = 37)
    TILES_PER_ENTRY = 8
; Fixed 8 tiles per string
; Memory layout
    tile_ring_head = 0x703FF0
; Current allocation position (entry index) - byte
    tile_ring_count = 0x703FF1
; Number of active allocations - byte
    tile_ring_next_id = 0x703FF2
; Next ID to assign - word
    tile_ring_base_tile = 0x703FF4
init:
"""
Base tile ID for ring buffer area - byte
A: the base tile id
"""


; tile_ring_base_tile should be set to your VWF tile area start
; With 0x128 dynamic + 0x128 immortal = 0x250 (592) tiles total
; But tile IDs are 1 byte (0-255), so max usable is 0xFF
; Let's use dynamic area starting at tile 0x00
    sta.w tile_ring_base_tile
    stz.b tile_ring_head
    stz.b tile_ring_count
    stz.w tile_ring_next_id
    rts
allocate_tiles:
"""
Allocate next 8-tile slot
Returns: A = starting tile_id (byte), X = allocation ID (word)
"""


; Calculate tile_id: base_tile + (head * TILES_PER_ENTRY)
    lda.w tile_ring_head
; Multiply by 8 (shift left 3 times)
    asl
    asl
    asl
; Add to base
    clc
    adc.w tile_ring_base_tile
; Get current ID for tracking
    ldx.w tile_ring_next_id
    rts
commit_allocation:
"""
Commit the allocation (call after rendering to tiles)
X = allocation ID
"""


    {
; Advance head pointer
    lda.w tile_ring_head
    inc
    cmp.b #MAX_ENTRIES
    bne _ok
    lda.b #0  ; Wrap around
_ok:
    sta.w tile_ring_head

; Increment count (max at MAX_ENTRIES)
    lda.w tile_ring_count
    cmp.b #MAX_ENTRIES
    beq _next
    inc
    sta.w tile_ring_count
_next:
; Increment next ID
    inc.w tile_ring_next_id

    rts
    }
get_tiles_by_id:
"""
Get tile_id of a specific allocation by ID
A = allocation ID (word)
Returns: A = starting tile_id (byte), Carry = 0 if found, 1 if expired
"""


    {
; Check if ID is still valid (within current range)
    sec
    lda.w tile_ring_next_id
    sbc.w tile_ring_count
    cmp.b 1, s  ; Compare with requested ID on stack
    bcs _not_found  ; ID too old

    lda.w tile_ring_next_id
    sec
    sbc.b 1, s  ; buffer_next_id - requested_id
    cmp.w tile_ring_count
    bcs _not_found  ; ID too recent

; Calculate which entry index this ID maps to
    lda.w tile_ring_head
    sec
    sbc.w tile_ring_count
    clc
    adc.b 1, s  ; Add offset for this ID

; Handle wrap-around
_loop:
    cmp.b #MAX_ENTRIES
    bcc _ok
    sec
    sbc.b #MAX_ENTRIES
    bra _loop
_ok:
; Calculate tile_id
; Multiply by 8
    asl
    asl
    asl
; Add to base
    clc
    adc.w tile_ring_base_tile

    clc  ; Found
    rts

_not_found:
    sec  ; Not found
    rts
    }
    }
}


.scope battle_render {
    """
    Currently works by region
    0x00 -> 0x40 messages tiles
    0x40 -> 0x80 monster names
    0x80 -> 0xB0 char names
    0xB0 -> 0xF0 commands ? this one is untested.
    """
    buffer_ptr = 0x703000
    buffer_size = 8 * ( 128 + 32 ) * 2
    region_size = 48
    pending_transfer_mask = 0x703c00
; --- Per-region dirty bits (normal sense: 1 = dirty, 0 = clean) ---
; Sits next to the DMA queue byte; writers SET bits on state change.
    region_dirty_bits = 0x703c01
    REGION_DIRTY_MESSAGES = 0x01
    REGION_DIRTY_MONSTERS = 0x02
    REGION_DIRTY_NAMES = 0x04
    REGION_DIRTY_COMMANDS = 0x08
; Transient marker: $FF if `init_*_with_gate` short-circuited
; because the region was clean; $00 if it ran the full init.
; Used by deinit_with_gate to decide whether to signal DMA, and
; by the gated trampoline to decide whether to skip DrawText.
    render_skipped = 0x703c02
; Per-region tilemap-DMA pending bitmask. Set by `init_*_gated`
; on the render path  ; consumed by `dma_transfer` in NMI to fire
; a per-region tilemap DMA (WRAM tilemap -> BG VRAM). Decouples
; tilemap upload from the vanilla `TfrCmdWindow` / `TfrMainMenu`
; periodic queue so the tile-data + tilemap transfers stay in
; sync on the same NMI as the render.
    tilemap_pending_mask = 0x703c03
    TILEMAP_PENDING_COMMANDS = 0x01
    TILEMAP_PENDING_MAIN = 0x02
    bits_left_on_tile = 0xA9
    tilemap_offset = bits_left_on_tile + 2
    temp = bits_left_on_tile + 4
    counter = bits_left_on_tile + 6
    prev_char = bits_left_on_tile + 8
    current_char = prev_char + 1
;font_ptr = assets_menu_font_dat ; moved to direct use of assets_menu_font_dat
init_monsters:
"""Initialize the renderer targeting the monsters region."""
    lda.b #region_size
    bra _init
init_names:
"""Initialize the renderer targeting the name region."""
    lda.b #region_size * 2
    bra _init
init_commands_list:
"""Initialize the renderer targeting the commands list region."""
    lda.b #region_size * 3
    bra _init
init_inventory_region:
"""
Initialize the renderer targeting the inventory region (tile_id 0xC0+).
Skips clear_buffer — clearing from tile_id 0xC0 would overrun the shared
buffer into the state words at $703C00+. The rolling-buffer overwrites
tile bytes fully each render so the no-clear path is safe.
"""


    lda.b #region_size * 4
    sta.l pending_transfer_mask
    jsr.w render_allocator.init_with_tile_id
    .if ENABLE_KERNING_MENU {
    stz.b prev_char
    }
    lda.b #0x08
    sta.b bits_left_on_tile
    stz.b temp
    stz.b counter
    rts
_init:
    sta.l pending_transfer_mask
    jsr.w render_allocator.init_with_tile_id
    bra _internal_init
; --- Region-gated init variants ---
; Mirror the public init_X paths but check the matching region-dirty
; bit in `region_dirty_bits` first. When the bit is CLEAR (= clean), set
; `render_skipped = $FF` and short-circuit (no clear_buffer, no
; allocator init, no `_internal_init` setup). The caller (gated
; trampoline) reads `render_skipped` after the init returns to decide
; whether to call DrawText. On the dirty path: do the full work and
; CLEAR the region's bit to mark clean for next frame; `render_skipped`
; stays at $00 so DrawText runs.
init_monsters_gated:
"""Gated init for the monsters region."""
    lda.l region_dirty_bits
    bit.b #REGION_DIRTY_MONSTERS
    beq _gated_skip
    and.b #( ~ REGION_DIRTY_MONSTERS ) & 0xFF
    sta.l region_dirty_bits
    lda.l tilemap_pending_mask
    ora.b #TILEMAP_PENDING_MAIN
    sta.l tilemap_pending_mask
    lda.b #region_size
    bra _init_continue
init_names_gated:
"""Gated init for the names region."""
    lda.l region_dirty_bits
    bit.b #REGION_DIRTY_NAMES
    beq _gated_skip
    and.b #( ~ REGION_DIRTY_NAMES ) & 0xFF
    sta.l region_dirty_bits
    lda.l tilemap_pending_mask
    ora.b #TILEMAP_PENDING_MAIN
    sta.l tilemap_pending_mask
    lda.b #region_size * 2
    bra _init_continue
init_commands_list_gated:
"""Gated init for the commands region."""
    lda.l region_dirty_bits
    bit.b #REGION_DIRTY_COMMANDS
    beq _gated_skip
    and.b #( ~ REGION_DIRTY_COMMANDS ) & 0xFF
    sta.l region_dirty_bits
    lda.l tilemap_pending_mask
    ora.b #TILEMAP_PENDING_COMMANDS
    sta.l tilemap_pending_mask
    lda.b #region_size * 3
_init_continue:
    pha
    lda.b #0x00
    sta.l render_skipped
    pla
    sta.l pending_transfer_mask
    jsr.w render_allocator.init_with_tile_id
    bra _internal_init
_gated_skip:
    lda.b #0xFF
    sta.l render_skipped
    rts
init:
    pha
    lda #0
    sta.l pending_transfer_mask
    pla
    jsr.w render_allocator.init
_internal_init:
    .if ENABLE_KERNING_MENU {
    stz.b prev_char
    }
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
Wipe the 16×region_size 4bpp tile buffer for the currently-allocated VWF tile id (sets each plane row to
$FF/$00).
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
;lda.w #0x0000
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
"""
Render `A` (char) at tilemap offset `Y` into the message VWF buffer  ; preserves A/X/Y, returns Y =
`tilemap_offset`.
"""


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

; vwf8_lookup_kerning there:
    .if ENABLE_KERNING_MENU {
    pha
    jsr.w _adjust_bits_left_for_kerning
    pla
    }

; Space ($FF) renders blank ; the 8-row loop only OR-stores zeros (no
; visible effect) and reads 8 glyph bytes plus 8 inx ops we can skip.
; Bump X past the glyph rows so `brk_bits_left` reads the width byte
; from the right offset, then jump straight to the width-update tail.
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

; Tier-2 hoist: classify bits_left_on_tile once per glyph, dispatch to
; one of 8 specialized 8-iteration loops (aligned + shift_0..shift_7).
; Each loop bakes the asl count into its body so the per-row
; cmp/jmp-table/mul-ladder dance disappears. Loops jump to brk_bits_left
; on completion.
;
; X holds the font pointer at entry. The shift dispatch clobbers X for
; the indirect jump, so the font pointer is stashed in `temp` first and
; each shift loop restores X from there on entry. The aligned path
; keeps X untouched so it bypasses the save / restore.
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
    lda.l assets_menu_font_dat, x
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
    lda.l assets_menu_font_dat, x
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
    .if ENABLE_KERNING_MENU {
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
; Space ($FF) never appears in any font's kerning pair table; bail out
; before the bank push so external callers (battle_msg_kerning_binary_ext
; and Python tooling) skip the search too. Caller is in 16-bit M.
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
    dec

; Setup binary search bounds on stack
; Stack layout (from top): [high] [low] [target_char]
    pha  ; Push high bound (count-1)
    lda.w #0x0000  ; Low bound = 0
    pha  ; Push low bound
    lda.b prev_char  ; Load target character
    pha  ; Push target for comparison

_binary_loop:
; Check if low > high (search finished)
    lda 0x05, s  ; Load high bound
    cmp 0x03, s  ; Compare with low bound
    bcc not_found_cleanup  ; If high < low, not found

; Calculate mid = (low + high) / 2
    lda 0x03, s  ; Load low
    clc
    adc 0x05, s  ; Add high
    lsr  ; Divide by 2
    tax  ; X = mid index

; Calculate address: mid * 3 + kerning_table_offset + 2
; (each entry is 3 bytes: 2 bytes char pair + 1 byte adjustment)
    pha  ; Save mid
    asl  ; mid * 2
    clc
    adc 0x01, s  ; Add original mid (now mid * 3)
    clc
    adc.w #kerning_table_offset + 2
    tay  ; Y = address of entry
    pla  ; Restore mid to A

; Load char pair at this position
    pha  ; Save mid again
    lda.w assets_menu_font_dat, y  ; Load 16-bit char pair

; Compare with target
    cmp 0x03, s  ; Compare with target_char
    beq found_pair_cleanup  ; Found exact match!
    bcc search_upper_half  ; If entry < target, search upper half

; Search lower half: high = mid - 1
    pla  ; Get mid
    sec
    sbc.w #0x0001  ; mid - 1
    bcc not_found_cleanup  ; mid was 0, underflow → not found
    sta 0x05, s  ; Update high bound
    bra _binary_loop

search_upper_half:
; Search upper half: low = mid + 1
    pla  ; Get mid
    inc  ; mid + 1
    sta 0x03, s  ; Update low bound
    bra _binary_loop

found_pair_cleanup:
    pla  ; Remove mid from stack

; Calculate adjustment offset: Y + 2 (skip char pair)
    iny
    iny
    lda.w assets_menu_font_dat, y  ; Load adjustment value (8-bit) - matches original
    and.w #0x00ff  ; Ensure high byte is clear

; Clean up stack — use ply so A (adjustment) is preserved.
    ply  ; Remove target_char
    ply  ; Remove low bound
    ply  ; Remove high bound

    clc  ; Clear carry (success)
    plb
    plb
    rts

not_found_cleanup:
; Clean up stack
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
; Space-pair early-out: 8-bit M from the entry check, no bank push or
; search bounds were pushed yet. Just signal "not found" and return.
    rep #0x20
    lda.w #0x0000
    sec
    rts

found_pair:
; This label kept for compatibility but shouldn't be reached
; in binary search version
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
    }
tilemap_write_no_inc:
    lda.l render_allocator.allocated_tile_id
    phy
    ldy.b tilemap_offset
    sta (0x34), y
    lda #0xff
    sta (0x32), y
    iny
    lda 0x36
    sta (0x32), y
    ora.b #0x01
    sta (0x34), y
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

.extern flying_hdma_trampoline

.scope messages_vwf {
    """High-level battle-message VWF parser: consumes the dialog stream and feeds glyphs into battle_render."""
    dakuten_table = 0x16fa40
put_fixed_char:
"""
put char
write to the tilemap if needed
maintain counters
"""


    cmp #0x42
    bcc put_fixed_char_dakuten
put_fixed_char_no_dakuten:
    jmp.w battle_render.display_char
put_fixed_char_dakuten:
    jmp.w battle_render.display_char
put_fixed_char_far:
"""far calls for the new implementation"""
    jsr.w put_fixed_char
    rtl
put_fixed_char_dakuten_far:
    jsr.w put_fixed_char_dakuten
    rtl
put_fixed_char_no_dakuten_far:
    jsr.w put_fixed_char_no_dakuten
    rtl
init:
"""
inits the renderer for the messages window
flips the flag for enabling the messages renderer.
"""


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
init_inventory:
"""
Wrap battle_render.init_inventory_region with set_vwf_render so the
message renderer routes char dispatch through the VWF put_char path.
"""


    jsr.l battle_flags.set_vwf_render
    jsr.w battle_render.init_inventory_region
    rtl
init_monsters_gated:
"""
Gated counterpart to `init_monsters`. Always flips the VWF flag
(symmetry preserved with `deinit_gated`)  ; skips clear_buffer +
allocator setup when the monsters region's clean bit is already
set. Writes `$FF` to `render_skipped` so the gated trampoline can
short-circuit DrawText and the matching `deinit_gated` skips the
DMA signal.
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
"""
the renderer
disables messages renderer falling back to fixed mode.
"""


    jsr.l battle_flags.clear_vwf_render
; vram transfer was moved to a trampoline in the battle nmi.
    lda.l battle_render.pending_transfer_mask
    ora #1
    sta.l battle_render.pending_transfer_mask
    rtl
deinit_gated:
"""
Companion to `init_*_gated`: always flips the flag back, only
signals DMA (sets bit 0 of pending_transfer_mask) if the matching
init actually rendered. Reads `render_skipped` to decide.
"""


    jsr.l battle_flags.clear_vwf_render
    lda.l battle_render.render_skipped
    bne _deinit_gated_done
    lda.l battle_render.pending_transfer_mask
    ora #1
    sta.l battle_render.pending_transfer_mask
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
dma_transfer:
"""
Vblank-time DMA flush for the battle-message VWF tile buffer  ; reads `battle_render.pending_transfer_mask`,
transfers the dirty regions to VRAM, and clears the mask bits.

Sets forced-blank (`$2100 = $80`) when any DMA work is queued so
the DMA window extends past actual vblank into the first ~5 lines
of normal scan  ; restored to `$6cc1` brightness by the vanilla
INIDISP write at `$02:837F` after the NMI DMA chain. On idle
frames (nothing queued) forced-blank is NOT set  ; vblank stays
normal length, no visible black strip.
"""


    pha
    phx
    phy
    lda.l battle_render.pending_transfer_mask
    bit #1
    beq _no_transfer
    and #0xfe
    .if SMART {
    rep #0x20
    asl
    asl
    asl
    asl
    pha
    clc
    adc.w #0xb000
    lsr
    tay
    pla
    clc
    adc.w #battle_render.buffer_ptr
    tax
    sep #0x20
    }
    ldy.w #0xb000 >> 1
    ldx.w #battle_render.buffer_ptr
    phx
    .if SMART {
    ldx.w #0x400
    } else {
    .if BATTLE_ITEMS_VWF {
; Inventory region (tile_id 0xC0..0xEF) extends past the legacy 0xC00
; window. Buffer stores 16 bytes per tile, so tile_id 0xEF ends at
; buffer_ptr + 0xF00. Dest stays at VRAM $B000 ; tail lands at $BF00,
; inside the BG3 CHR window ($A000..$BFFF).
    ldx.w #0xf00
    } else {
    ldx.w #0xc00
    }
    }
    stx 0x0e
    plx
    lda #0x70
    jsr.w _sram_dma_transfer_7
    lda #0x00
    sta.l battle_render.pending_transfer_mask
_no_transfer:
; --- Per-region tilemap DMA pass ---
; Reads `tilemap_pending_mask` (set by `init_*_gated` on render paths
; and by the cmd-window thunk on its dirty render) and fires a WRAM
; tilemap -> BG VRAM DMA for each pending region. Replaces the
; vanilla `TfrCmdWindow` / `TfrMainMenu` queue so cmd-window tilemap
; stays in sync with the tile-data DMA above.
; Save+restore P and X/Y around the DMA pass: NMI caller may leave
; M/X flags in any state, and `ldy.w` / `ldx.w` need X-flag = 16
; to load full word operands.
    php
    sep #0x20
; M = 8-bit (bit instructions use 8-bit immediates)
    rep #0x10
; X = 16-bit (ldy.w / ldx.w load full word)
    lda.l battle_render.tilemap_pending_mask
    beq _no_tilemap_dma
    pha
    bit.b #battle_render.TILEMAP_PENDING_COMMANDS
    beq _no_cmd_tilemap
    ldy.w #0x71C0
; VRAM word addr (battle cmd window)
    ldx.w #0xC1E6
; WRAM tilemap src
    rep #0x20
    lda.w #0x0280
    sta.b 0x0e
    sep #0x20
    lda #0x7E
    jsr.w _sram_dma_transfer_7
_no_cmd_tilemap:
    pla
    bit.b #battle_render.TILEMAP_PENDING_MAIN
    beq _no_main_tilemap
    ldy.w #0x7020
; VRAM word addr (main window: names/monsters/hp/status)
    ldx.w #0xBEA6
    rep #0x20
    lda.w #0x0280
    sta.b 0x0e
    sep #0x20
    lda #0x7E
    jsr.w _sram_dma_transfer_7
_no_main_tilemap:
    lda #0x00
    sta.l battle_render.tilemap_pending_mask
_no_tilemap_dma:
    plp
    ply
    plx
    pla
; Phase-1: NMI-side anim. Bank-02 trampoline does
; `jsr UpdateFlyingHDMA; rtl` so the bank-02 routine ends in rts
; while our cross-bank JSL gets a matching RTL pop. Float-monster
; BG1 vscroll table now updates every vblank.
    jsr.l flying_hdma_trampoline
    jsr.l 0x03fe03
    rtl
_sram_dma_transfer_7:
    phb
    pha
    lda #0x00
    pha
    plb
    pla
    sty 0x2116
    stx 0x4372
    sta 0x4374
    lda #0x01
    sta 0x4370
    lda #0x18
    sta 0x4371
    ldx.b 0x0e
    stx 0x4375
    lda #1 << 7
    sta 0x420b
    plb
    rts
new_line_escape_code_handler:
"""
Handler for the ` ` text-stream escape: allocate a fresh tile via `render_allocator.increment`, reset
bits_left_on_tile to 8, and advance the tilemap offset by one row (16 tiles).
"""


; we might have something of interest in Y we might know where we are in the previous iteration ?
    pha
;jsr.w battle_render.tilemap_write
    jsr.w render_allocator.increment
    lda #8
    sta.b battle_render.bits_left_on_tile
    pla
    lda.w 0xef54
    rep #0x20
    pha
    asl
    clc
    adc 0x32
    sta 0x32
    sta.b render.tilemap_offset
    pla
    clc
    adc 0x32
    sta 0x34
    tdc
    tay
    sep #0x20
    rtl
; escape code $01: newline
;02/A637: AD 54 EF     LDA $EF54
;02/A63A: C2 20        REP #$20
;02/A63C: 48           PHA
;02/A63D: 0A           ASL
;02/A63E: 18           CLC
;02/A63F: 65 32        ADC $32
;02/A641: 85 32        STA $32
;02/A643: 68           PLA
;02/A644: 18           CLC
;02/A645: 65 32        ADC $32
;02/A647: 85 34        STA $34
;02/A649: 7B           TDC
;02/A64A: A8           TAY
;02/A64B: E2 20        SEP #$20
;02/A64D: 60           RTS
}
