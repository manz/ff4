.include "src/battle/sram.i"

.import "dakuten"
.import "small_vwf/init"
.extern render_allocator.init_with_tile_id
.extern render_allocator.init
.extern render_allocator.allocated_tile_id
.extern render_allocator.increment
.extern render.tilemap_offset
.extern battle_render.display_char
.extern battle_render.init
.extern battle_render.init_commands_list
.extern battle_render.init_monsters
.extern battle_render.init_names
.extern battle_render.pending_transfer_mask
.extern battle_render.buffer_ptr
.extern battle_render.bits_left_on_tile
.extern battle_render.clear_buffer
.extern assets_menu_font_dat
.extern font_table

BATTLE_DAKUTEN_TABLE = 0x16FA40

.scope battle_flags {
; NOTE: set_sram_copy and clear_sram_copy removed - SRAM mode no longer used
set_vwf_render:
    battle_flags_set(0x02)
    rtl
clear_vwf_render:
    battle_flags_clear(0x02)
    rtl
}

copy_battle_char:
    lda.l sram_base + 0x2E00, x
    sta (0x00), y
    lda.l sram_base + 0x2E00 + 0x30, x
    sta (0x02), y
    rtl

.scope wram {
put_char:
    phx
    sta (0x34), y
    lda #0xFF
    sta (0x32), y
    iny
    lda 0x36
    sta (0x32), y
    sta (0x34), y
    iny
    plx
    rtl
put_char_with_dakuten:
    phx
    .if 0 {
    sec
    sbc #0xF
    asl
    tax
    lda.l BATTLE_DAKUTEN_TABLE, x
    sta (0x32), y
    lda.l BATTLE_DAKUTEN_TABLE + 1, x
    sta (0x34), y
    } else {
    jsr.l lookup_dakuten
    sta (0x32), y
    xba
    sta (0x34), y
    lda #0x00
    xba
    }
    iny
    lda 0x36
    sta (0x32), y
    sta (0x34), y
    iny
    plx
    rtl
}

; NOTE: sram scope removed - SRAM mode no longer used
; .scope sram { put_char, put_char_with_dakuten }

battle_display_char:
{
    battle_flag_switch(battle_flags_jump_table)
battle_flags_jump_table:
    .dw wram.put_char  ; index 0 (flags = 0)
    .dw wram.put_char  ; index 2 (flags = 1) - fallback to WRAM
    .dw messages_vwf.put_fixed_char_dakuten_far  ; index 4 (flags = 2)
    .dw messages_vwf.put_fixed_char_dakuten_far  ; index 6 (flags = 3) - fallback
}

battle_display_dakuten_char:
{
    battle_flag_switch(battle_flags_jump_table)
battle_flags_jump_table:
    .dw wram.put_char_with_dakuten  ; index 0 (flags = 0)
    .dw wram.put_char_with_dakuten  ; index 2 (flags = 1) - fallback to WRAM
    .dw messages_vwf.put_fixed_char_no_dakuten_far  ; index 4 (flags = 2)
    .dw messages_vwf.put_fixed_char_no_dakuten_far  ; index 6 (flags = 3) - fallback
}

sink:
    rtl

clear_names_window_buffer:
    phx
    phy
    rep #0x20
    ldy.w #0
    ldx.w 0xef52

_clear_name_loop:
    lda.w #0x00ff
    sta.l 0x7e0000, x
    sta.l 0x7e0002, x
    sta.l 0x7e0004, x
    sta.l 0x7e0006, x
    sta.l 0x7e0008, x
    sta.l 0x7e000a, x

    txa
    clc
    adc.w #6 * 2
    tax
    iny
    tya
    cmp.w #5 * 2

    bne _clear_name_loop


    sep #0x20
    ply
    plx
    tdc
    sta 0x74FC, y
    rtl

    .include "src/battle/message.s"
