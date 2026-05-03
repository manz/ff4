.if 0 {
.scope vwf_tile_ring {
; Ring buffer for VWF tile allocation
; Each entry represents 8 consecutive tiles
; VWF system computes addresses from tile_id

MAX_ENTRIES = 37                    ; Number of 8-tile slots (296 tiles / 8 = 37)
TILES_PER_ENTRY = 8                 ; Fixed 8 tiles per string

; Memory layout
tile_ring_head = 0x703FF0           ; Current allocation position (entry index) - byte
tile_ring_count = 0x703FF1          ; Number of active allocations - byte
tile_ring_next_id = 0x703FF2        ; Next ID to assign - word
tile_ring_base_tile = 0x703FF4      ; Base tile ID for ring buffer area - byte

; A: the base tile id
init:
    ; tile_ring_base_tile should be set to your VWF tile area start
    ; With 0x128 dynamic + 0x128 immortal = 0x250 (592) tiles total
    ; But tile IDs are 1 byte (0-255), so max usable is 0xFF
    ; Let's use dynamic area starting at tile 0x00

    sta.w tile_ring_base_tile

    stz.b tile_ring_head
    stz.b tile_ring_count
    stz.w tile_ring_next_id
    rts

; Allocate next 8-tile slot
; Returns: A = starting tile_id (byte), X = allocation ID (word)
allocate_tiles:
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

; Commit the allocation (call after rendering to tiles)
; X = allocation ID
commit_allocation:
{
    ; Advance head pointer
    lda.w tile_ring_head
    inc
    cmp.b #MAX_ENTRIES
    bne _ok
    lda.b #0        ; Wrap around
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
; Get tile_id of a specific allocation by ID
; A = allocation ID (word)
; Returns: A = starting tile_id (byte), Carry = 0 if found, 1 if expired
get_tiles_by_id:
{
    ; Check if ID is still valid (within current range)
    sec
    lda.w tile_ring_next_id
    sbc.w tile_ring_count
    cmp.b 1,s       ; Compare with requested ID on stack
    bcs _not_found   ; ID too old

    lda.w tile_ring_next_id
    sec
    sbc.b 1,s       ; buffer_next_id - requested_id
    cmp.w tile_ring_count
    bcs _not_found   ; ID too recent

    ; Calculate which entry index this ID maps to
    lda.w tile_ring_head
    sec
    sbc.w tile_ring_count
    clc
    adc.b 1,s       ; Add offset for this ID

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

    clc             ; Found
    rts

_not_found:
    sec             ; Not found
    rts
}
}
}

; Currently works by region
; 0x00 -> 0x40 messages tiles
; 0x40 -> 0x80 monster names
; 0x80 -> 0xB0 char names
; 0xB0 -> 0xF0 commands ? this one is untested.

.scope battle_render {
    buffer_ptr = 0x703000
    buffer_size = 8*(128+32)*2
    region_size = 48
    pending_transfer_mask = 0x703c00
    bits_left_on_tile = 0xA9
    tilemap_offset = bits_left_on_tile + 2
    temp = bits_left_on_tile + 4
    counter = bits_left_on_tile + 6
    prev_char =  bits_left_on_tile + 8
    current_char = prev_char + 1
    ;font_ptr = assets_menu_font_dat ; moved to direct use of assets_menu_font_dat
init_monsters:
"""Initialize the renderer targeting the monsters region."""
    lda.b #region_size
    bra __init
init_names:
"""Initialize the renderer targeting the name region."""
    lda.b #region_size * 2
    bra __init
init_commands_list:
"""Initialize the renderer targeting the commands list region."""
    lda.b #region_size * 3
__init:
    sta.l pending_transfer_mask
    jsr.w render_allocator.init_with_tile_id
    bra _internal_init

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
    cpy.w #region_size*16
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
    adc 1,s
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
    rep #0x20
    lda.w #0x0008
    sta.b counter
    sep #0x20

char_line_loop:
    rep #0x20
    lda.w #0x0000
    sep #0x20

    lda.b bits_left_on_tile

    cmp #0x08
    bne _shift

_read_8x8_char:
    lda.l assets_menu_font_dat, x
    xba
    lda.b #0x00
    xba
    inx
    xba
    bra _store

_shift:
    ; PPU multiplication is being used by the NMI which wrecks char lines once in a while
    phx
    lda.l assets_menu_font_dat, x
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
    asl ; 1
_mul_6:
    asl ; 2
_mul_5:
    asl ; 3
_mul_4:
    asl ; 4
_mul_3:
    asl ; 5
_mul_2:
    asl ; 6
_mul_1:
    asl ; 7
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
    iny
    iny

_next_line:
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
    adc 1,s
    cmp #0x9
    bcs __overflow
    bra _no_overflow
__overflow:
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

_overflow:
    pha
    lda.b current_char
    sta.b prev_char
    pla
    rts
}

get_kerning_adjustment_linear_search:
{
    phx
    phy
    rep #0x20
;    jsr.w _get_kerning_adjustment_binary_search
    jsr.w _get_kerning_adjustment_linear_search
    sep #0x20
    ply
    plx
    rts
}

_get_kerning_adjustment_binary_search:
{
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
    pha                          ; Push high bound (count-1)
    lda.w #0x0000               ; Low bound = 0
    pha                         ; Push low bound
    lda.b prev_char             ; Load target character
    pha                         ; Push target for comparison

_binary_loop:
    ; Check if low > high (search finished)
    lda 0x05, s                 ; Load high bound
    cmp 0x03, s                 ; Compare with low bound
    bcc not_found_cleanup       ; If high < low, not found

    ; Calculate mid = (low + high) / 2
    lda 0x03, s                 ; Load low
    clc
    adc 0x05, s                 ; Add high
    lsr                         ; Divide by 2
    tax                         ; X = mid index

    ; Calculate address: mid * 3 + kerning_table_offset + 2
    ; (each entry is 3 bytes: 2 bytes char pair + 1 byte adjustment)
    pha                         ; Save mid
    asl                         ; mid * 2
    clc
    adc 0x01, s                 ; Add original mid (now mid * 3)
    clc
    adc.w #kerning_table_offset + 2
    tay                         ; Y = address of entry
    pla                         ; Restore mid to A

    ; Load char pair at this position
    pha                         ; Save mid again
    lda.w assets_menu_font_dat, y  ; Load 16-bit char pair

    ; Compare with target
    cmp 0x03, s                 ; Compare with target_char
    beq found_pair_cleanup      ; Found exact match!
    bcc search_upper_half       ; If entry < target, search upper half

    ; Search lower half: high = mid - 1
    pla                         ; Get mid
    sec
    sbc.w #0x0001               ; mid - 1
    bcc not_found_cleanup       ; mid was 0, underflow → not found
    sta 0x05, s                 ; Update high bound
    bra _binary_loop

search_upper_half:
    ; Search upper half: low = mid + 1
    pla                         ; Get mid
    inc                         ; mid + 1
    sta 0x03, s                 ; Update low bound
    bra _binary_loop

found_pair_cleanup:
    pla                         ; Remove mid from stack

    ; Calculate adjustment offset: Y + 2 (skip char pair)
    iny
    iny
    lda.w assets_menu_font_dat, y           ; Load adjustment value (8-bit) - matches original
    and.w #0x00ff              ; Ensure high byte is clear

    ; Clean up stack — use ply so A (adjustment) is preserved.
    ply                         ; Remove target_char
    ply                         ; Remove low bound
    ply                         ; Remove high bound

    clc                         ; Clear carry (success)
    plb
    plb
    rts

not_found_cleanup:
    ; Clean up stack
    pla                         ; Remove target_char
    pla                         ; Remove low bound
    pla                         ; Remove high bound

not_found:
    lda.w #0x0000
    sec                         ; Set carry (not found)
    plb
    plb
    rts

found_pair:
    ; This label kept for compatibility but shouldn't be reached
    ; in binary search version
    clc
    plb
    plb
    rts
}

_get_kerning_adjustment_linear_search:
{
    phb
    pea.w font_table >> 16
    plb

    kerning_table_offset = 256 * 9
    ldy.w #kerning_table_offset
    lda.w assets_menu_font_dat, y
    beq not_found
    dec
    tax
    lda.w #0x0000

_loop:
    txa
    pha
    asl
    clc
    adc 0x01, s
    clc
    adc.w #kerning_table_offset + 2

    tay
    pla

    lda.w assets_menu_font_dat, y ; Load 16-bit char pair
    cmp.b prev_char
    beq found_pair               ; Found exact match!

    txa
    dec
    tax

    bpl _loop

not_found:
    lda.w #0x0000
    sec
    plb
    plb
    rts

found_pair:
    iny
    iny
    lda.w assets_menu_font_dat, y
    and.w #0x00FF
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

BattleMsgKerningLinear_Ext:
    jsr.w get_kerning_adjustment_linear_search
    rtl

BattleMsgKerningBinary_Ext:
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

.scope messages_vwf {
    dakuten_table = 0x16fa40
        ; put char
        ; write to the tilemap if needed
        ; maintain counters
    put_fixed_char:
        cmp #0x42
        bcc put_fixed_char_dakuten

    put_fixed_char_no_dakuten:
        jmp.w battle_render.display_char

    put_fixed_char_dakuten:
        jmp.w battle_render.display_char

    ; far calls for the new implementation
    put_fixed_char_far:
        jsr.w put_fixed_char
        rtl

    put_fixed_char_dakuten_far:
        jsr.w put_fixed_char_dakuten
        rtl

    put_fixed_char_no_dakuten_far:
        jsr.w put_fixed_char_no_dakuten
        rtl

    ; inits the renderer for the messages window
    ; flips the flag for enabling the messages renderer.
    init:
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

    ; deinit the renderer
    ; disables messages renderer falling back to fixed mode.
    deinit:
        jsr.l battle_flags.clear_vwf_render
        ; vram transfer was moved to a trampoline in the battle nmi.
        lda.l battle_render.pending_transfer_mask
        ora #1
        sta.l battle_render.pending_transfer_mask
        rtl

    _wait_for_vblank: {
        inc     0x1811
    _wait:
        lda     0x1811
        bne     _wait
        rts
    }

DMA_TRANSFER:
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
    .if SMART{
    ldx.w #0x400
    } else {
    ldx.w #0xc00
    }
    stx 0x0e
    plx
    lda #0x70
    jsr.w _sram_dma_transfer_7
    lda #0x00
    sta.l battle_render.pending_transfer_mask
_no_transfer:
    ply
    plx
    pla
    jsr.l 0x03fe03
    rtl

_sram_dma_transfer_7:
        phb
        pha
        lda #0x00
        pha
        plb
        pla
        sty     0x2116
        stx     0x4372
        sta     0x4374
        lda     #0x01
        sta     0x4370
        lda     #0x18
        sta     0x4371
        ldx.b   0x0e
        stx     0x4375
        lda     #1 << 7
        sta     0x420b
        plb
        rts

new_line_escape_code_handler:
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



