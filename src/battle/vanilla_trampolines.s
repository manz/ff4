"""
Bank-$02 RTL wrappers around vanilla battle routines, plus the text-draw trampoline the battle inventory uses.

`battle/inventory_rolling` and its ROM patches both call these. They depend on nothing above them, which keeps
the import graph acyclic.
"""
.import "preamble"
.import "battle/sram"
.include "config.i"
.include "src/battle/bank02_trampolines.i"

.alloc bank02_vanilla_wrappers in bank02_trampolines {
draw_text_rolling_trampoline:
"""
Bank-$02 trampoline around draw_text for inventory rendering. With
BATTLE_ITEMS_VWF on, sets battle_flags = 0x02 so battle_display_char
routes the put_char dispatch through messages_vwf.put_fixed_char_*
for proportional rendering. Wraps the call with init_names / deinit
so the VWF tile allocator and pending-DMA mask stay in sync.
"""


    .if BATTLE_ITEMS_VWF {
; Custom draw_inventory_text owns the format walk end-to-end (escape
; codes 0x00 / 0x03 / 0x0E plus VWF blits for raw chars). No need to
; toggle battle_flags here ; it manages its own VWF state.
    jsr.l messages_vwf.draw_inventory_text
    rtl
    } else {
    lda.l 0x704F00
    pha
    lda.b #0x00
    sta.l 0x704F00
    xba
    lda.b #0x00
    xba
    jsr 0xA455
    pla
    sta.l 0x704F00
    rtl
    }

mult8_trampoline:
"""Bank-$02 RTL trampoline around original Mult8 ($028560)."""
    jsr 0x8560  ; Mult8 at $028560
    rtl

hex_to_dec_trampoline:
"""Bank-$02 RTL trampoline around original hex_to_dec ($0286BF)."""
    jsr 0x86BF  ; hex_to_dec at $0286BF
    rtl

normalize_num_trampoline:
"""Bank-$02 RTL trampoline around original normalize_num ($028716)."""
    jsr 0x8716  ; normalize_num at $028716
    rtl

load_menu_tfr_data_trampoline:
"""Bank-$02 RTL trampoline around original LoadMenuTfrData ($029738)."""
    jsr 0x9738  ; LoadMenuTfrData at $029738
    rtl

return_to_bank02:
"""Trailing RTS used as a JML target by bank-$20 hooks to return to bank-$02."""
    rts
}
