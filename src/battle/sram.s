"""
Battle put-char dispatch: `battle_display_char` / `battle_display_dakuten_char` jump tables over `battle_flags`
(WRAM put_char from battle/put_char or messages_vwf), and the `clear_names_window_buffer` helper.
"""
.import "core/preamble"
.include "battle/sram.i"
.include "core/bank20.i"

.import "core/assets"
.import "dialog/dakuten"
.import "small_vwf/init"
.import "battle/render_state"
.import "battle/message"
.import "battle/put_char"

.alloc _battle_sram_block in bank20_reloc {
battle_display_char:
"""
    Dispatch a fixed-mode char draw to either the WRAM put_char or the messages_vwf renderer based on the active
    battle_flags.
"""


    {
    battle_flag_switch(battle_flags_jump_table)
battle_flags_jump_table:
    .dw wram.put_char  ; index 0 (flags = 0)
    .dw wram.put_char  ; index 2 (flags = 1) - fallback to WRAM
    .dw messages_vwf.put_fixed_char_dakuten_far  ; index 4 (flags = 2)
    .dw messages_vwf.put_fixed_char_dakuten_far  ; index 6 (flags = 3) - fallback
    }

battle_display_dakuten_char:
"""
    Dakuten-aware variant of `battle_display_char`: routes to the dakuten put_char or to messages_vwf depending on
    battle_flags.
"""


    {
    battle_flag_switch(battle_flags_jump_table)
battle_flags_jump_table:
    .dw wram.put_char_with_dakuten  ; index 0 (flags = 0)
    .dw wram.put_char_with_dakuten  ; index 2 (flags = 1) - fallback to WRAM
    .dw messages_vwf.put_fixed_char_no_dakuten_far  ; index 4 (flags = 2)
    .dw messages_vwf.put_fixed_char_no_dakuten_far  ; index 6 (flags = 3) - fallback
    }

_sink:
    rtl

clear_names_window_buffer:
"""
    Fill the names-window WRAM tilemap buffer with $FF (transparent / blank tile) starting at the address held in
    $EF52.
"""


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
}
