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

.if INVENTORY_ROLLING_BUFFER {

; ============================================================================
; MAIN LOOP HOOK - Process scroll animation frames
; ============================================================================
; Hook at $019FF2 - the start of the input processing loop in SelectItem.
*=0x019FF2
    jmp.w   MainLoopScrollCheck     ; 3 bytes - replaces LDA $01
*=0x019FF5
    nop
    nop
    nop

; ============================================================================
; SCROLL DOWN - Replace blocking loop with state machine
; ============================================================================
*=0x01A076
    jsr.w   ScrollDownTrigger
    jmp.w   0xA0BC                  ; Skip to after scroll block (A button check)

; ============================================================================
; SCROLL UP - Replace blocking loop with state machine
; ============================================================================
*=0x01A01F
    jsr.w   ScrollUpTrigger
    jmp.w   0xA066                  ; Skip to after scroll block (down button check)

; ============================================================================
; Menu Entry/Exit Hooks
; ============================================================================
*=0x019F27
    jsr.w   MenuEntryHook

*=0x019F87
    jsr.w   MenuExitHook

; ============================================================================
; NMI HDMA Hook
; ============================================================================
*=0x018081
    jsr.w   HdmaEnableHook
    nop

; ============================================================================
; UpdateScrollRegs BG1VOFS Hook - Skip when menu HDMA is active
; ============================================================================
*=0x14FF2D
    jsr.l   ConditionalBG1VOFS
    nop
    nop
    nop
    nop
    nop
    nop

; ============================================================================
; DrawItemSlot Column Check Patch - Force single column mode
; ============================================================================
*=0x01A1F0
    .db 0x00                            ; Change operand from $01 to $00

; ============================================================================
; Replace DrawInventoryList with our rolling buffer init
; ============================================================================
*=0x019F7B
    jsr.w   InitMenuRollingBuffer       ; Replace JSR DrawInventoryList

; ============================================================================
; DrawItemSlot - Clear count display for item ID 0 (empty slot)
; ============================================================================
; Original code at $A202: lda ($5a); cmp #$fe; beq @a222
; We replace with JSR that handles clearing for empty slots
; Original bytes: B2 5A C9 FE F0 1A (6 bytes at $A202-$A207)
*=0x01A202
    jsr.w   CheckAndClearCount          ; 3 bytes - checks item, clears if empty
    nop                                  ; 1 byte - padding
    nop                                  ; 1 byte - padding
    nop                                  ; 1 byte - padding

}
