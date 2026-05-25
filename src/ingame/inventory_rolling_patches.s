"""
ROM patches wiring the field-menu inventory rolling-buffer engine in (FF6-style non-blocking scroll state
machine, scroll up/down hooks, redraw and exit-cleanup hooks).
"""
; ============================================================================
; Inventory Rolling Buffer Patches for Main Menu
; ============================================================================
;
; FF6-style non-blocking scroll with state machine.
; Replaces FF4's blocking 8-frame scroll loops with per-frame updates.
;
; ROM hooks only - implementations are in free_space.s and inventory_rolling.s
;
; ============================================================================

.include "config.i"
.if INVENTORY_ROLLING_BUFFER {
; ============================================================================
; MAIN LOOP HOOK - Process scroll animation frames
; ============================================================================
; Hook at $019FF2 - the start of the input processing loop in SelectItem.
.alloc at 0x019FF2 {
        jmp.w main_loop_scroll_check
    ; 3 bytes - replaces LDA $01
}
.alloc at 0x019FF5 {
        nop
        nop
        nop
    ; ============================================================================
    ; SCROLL DOWN - Replace blocking loop with state machine
    ; ============================================================================
}
.alloc at 0x01A076 {
        jsr.w scroll_down_trigger
        jmp.w 0xA0BC
    ; Skip to after scroll block (A button check)
    ; ============================================================================
    ; SCROLL UP - Replace blocking loop with state machine
    ; ============================================================================
}
.alloc at 0x01A01F {
        jsr.w scroll_up_trigger
        jmp.w 0xA066
    ; Skip to after scroll block (down button check)
    ; ============================================================================
    ; Menu Entry/Exit Hooks
    ; ============================================================================
}
.alloc at 0x019F27 {
        jsr.w menu_entry_hook
}
.alloc at 0x019F87 {
        jsr.w menu_exit_hook
    ; ============================================================================
    ; NMI HDMA Hook
    ; ============================================================================
}
.alloc at 0x018081 {
        jsr.w hdma_enable_hook
        nop
    ; ============================================================================
    ; UpdateScrollRegs BG1VOFS Hook - Skip when menu HDMA is active
    ; ============================================================================
}
.alloc at 0x14FF2D {
        jsr.l conditional_bg1_vofs
        nop
        nop
        nop
        nop
        nop
        nop
    ; ============================================================================
    ; Refresh inventory after SelectItem2 (swap OR use)
    ; ============================================================================
    ; After SelectItem2 completes (swap or use item), we need to refresh the
    ; display. For swaps, swap_redraw_hook_impl already handled it. For item use,
    ; we need to refresh the current slot to show updated quantity.
    ; Call our refresh hook instead of the original DrawInventoryList.
}
.alloc at 0x01A0D2 {
        jsr.w item_use_refresh_hook
    ; ============================================================================
    ; DrawItemSlot Column Check Patch - Force single column mode
    ; ============================================================================
}
.alloc at 0x01A1F0 {
        .db 0x00
    ; Change operand from $01 to $00
    ; ============================================================================
    ; Replace DrawInventoryList with our rolling buffer init
    ; ============================================================================
}
.alloc at 0x019F7B {
        jsr.w init_menu_rolling_buffer
    ; Replace JSR DrawInventoryList
    ; ============================================================================
    ; DrawItemSlot - Clear count display for item ID 0 (empty slot)
    ; ============================================================================
    ; Original code at $A202: lda ($5a); cmp #$fe; beq @a222
    ; We replace with JSR that handles clearing for empty slots
    ; Original bytes: B2 5A C9 FE F0 1A (6 bytes at $A202-$A207)
}
.alloc at 0x01A202 {
        jsr.w check_and_clear_count
    ; 3 bytes - checks item, clears if empty
        nop
    ; 1 byte - padding
        nop
    ; 1 byte - padding
        nop
    ; 1 byte - padding
    ; ============================================================================
    ; Patch $A1BA: Replace sequential Y calculation with circular buffer version
    ; ============================================================================

    ; Original code at $A1BA-$A1C7 (14 bytes):
    ;   LDA $5D / LSR / ASL×7 / ADC #$0004 / TAY
    ; Replace with JSL to CircularSlotCalc_ext trampoline + NOPs
    ;
}
.alloc at 0x01A1BA {
        jsr.l circular_slot_calc_ext
    ; 4 bytes
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
}
