"""
Bank-$02 RTL wrappers around vanilla battle routines, plus the text-draw trampoline the battle inventory uses.

`battle/inventory_rolling` and its ROM patches both call these. They depend on nothing above them, which keeps
the import graph acyclic.
"""
.import "preamble"
.import "battle/sram"
.include "config.i"
.include "src/battle/bank02_trampolines.i"
.import "vanilla"

.alloc _bank02_vanilla_wrappers in bank02_trampolines {
draw_text_rolling_trampoline:
"""
Bank-$02 trampoline around draw_text for inventory rendering: the custom draw_inventory_text walks the format
string itself, VWF blits included.
"""


; Custom draw_inventory_text owns the format walk end-to-end (escape
; codes 0x00 / 0x03 / 0x0E plus VWF blits for raw chars). No need to
; toggle battle_flags here ; it manages its own VWF state.
    jsr.l messages_vwf.draw_inventory_text
    rtl


mult8_trampoline:
"""Bank-$02 RTL trampoline around original Mult8 ($028560)."""
    jsr.w mult8
    rtl

hex_to_dec_trampoline:
"""Bank-$02 RTL trampoline around original hex_to_dec ($0286BF)."""
    jsr.w btlgfx_hex_to_dec
    rtl

normalize_num_trampoline:
"""Bank-$02 RTL trampoline around original normalize_num ($028716)."""
    jsr.w normalize_num
    rtl

load_menu_tfr_data_trampoline:
"""Bank-$02 RTL trampoline around original LoadMenuTfrData ($029738)."""
    jsr.w load_menu_tfr_data
    rtl

return_to_bank02:
"""Trailing RTS used as a JML target by bank-$20 hooks to return to bank-$02."""
    rts
}
