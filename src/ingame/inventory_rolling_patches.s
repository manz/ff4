"""
Field-menu inventory hooks: the blocking 8-frame scroll loops become a per-frame scroll state machine over the
rolling buffer (free_space.s, inventory_rolling.s).
"""
.import "core/preamble"
.import "ingame/free_space"
.import "ingame/inventory_rolling"
.import "ingame/inventory_rolling_trampolines"
.import "core/bank20_helpers"

.label _select_item_a066 = 0x01A066
.label _select_item_a0bc = 0x01A0BC

; SelectItem's per-frame BG1 upload: the first screen only.
.alloc at 0x019FEC {
    jsr.w tfr_item_list_screen
}


; SelectItem input loop start: run the scroll animation frame.
.alloc at 0x019FF2 {
    jmp.w main_loop_scroll_check
}


.alloc at 0x019FF5 {
    nop
    nop
    nop
}


; Scroll down, then skip to the A button check.
.alloc at 0x01A076 {
    jsr.w scroll_down_trigger
    jmp.w _select_item_a0bc
}


; Scroll up, then skip to the down button check.
.alloc at 0x01A01F {
    jsr.w scroll_up_trigger
    jmp.w _select_item_a066
}


; Menu entry / exit
.alloc at 0x019F27 {
    jsr.w menu_entry_hook
}


.alloc at 0x019F87 {
    jsr.w menu_exit_hook
}


; NMI HDMAEN write
.alloc at 0x018081 {
    jsr.w hdma_enable_hook
    nop
}


; UpdateScrollRegs: skip BG1VOFS while the menu HDMA drives it.
.alloc at 0x14FF2D {
    jsr.l conditional_bg1_vofs
    nop
    nop
    nop
    nop
    nop
    nop
}


; After SelectItem2 (swap or use): refresh the used slot's quantity instead of DrawInventoryList.
.alloc at 0x01A0D2 {
    jsr.w item_use_refresh_hook
}


; $01:A1F0 (the DrawItemSlot column mask) is zeroed by inventory_single_column.s.


; DrawInventoryList -> rolling buffer init
.alloc at 0x019F7B {
    jsr.w init_menu_rolling_buffer
}


; DrawItemSlot $A202 (`lda ($5a) / cmp #$fe / beq`, 6 bytes): clear the count of an empty slot.
.alloc at 0x01A202 {
    jsr.w check_and_clear_count
    nop
    nop
    nop
}


; DrawItemSlot $A1BA-$A1C7: tilemap Y from the circular slot instead of `$5D * 128 + 4`.
.alloc at 0x01A1BA {
    jsr.l circular_slot_calc_ext
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
}
