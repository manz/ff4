; ============================================================================
; Inventory Rolling Buffer Patches for Main Menu
; ============================================================================
;
; FF6-style non-blocking scroll with state machine.
; Replaces FF4's blocking 8-frame scroll loops with per-frame updates.
;
; Key patch points:
;   $019FF2 - Main input loop entry (check scroll state)
;   $01A024 - Scroll up trigger (start non-blocking scroll)
;   $01A07A - Scroll down trigger (start non-blocking scroll)
;   $019F27 - Menu entry (init state machine)
;   $019F87 - Menu exit (cleanup HDMA)
;
; ============================================================================

.if INVENTORY_ROLLING_BUFFER {



; ============================================================================
; MAIN LOOP HOOK - Process scroll animation frames
; ============================================================================
; Hook at $019FF2 - the start of the input processing loop in SelectItem.
; If scrolling is active, process one animation frame and skip ALL input.
;
; Original code at $019FF2 (6 bytes total):
;   @9ff2: LDA $01       ; A5 01 (2 bytes)
;          AND #$80      ; 29 80 (2 bytes) - check JOY_LEFT
;          BEQ @a003     ; F0 0D (2 bytes)
;
; Replace with JMP to handler. Handler either:
; - Does original code and returns inline, OR
; - Processes scroll frame and jumps to @a0ff to skip all input

*=0x019FF2
    jmp.w   MainLoopScrollCheck     ; 3 bytes - replaces LDA $01

; The remaining 3 bytes at $9FF5-$9FF7 become dead code.
; MainLoopScrollCheck will either return to $9FF5 (input mode) or JMP away (scroll mode)
; Bytes at $9FF5-$9FF7 become dead code (JMP $FE00 never returns here)
; $9FF8 is the start of the left button handler (LDA $1B22) - do NOT overwrite!
*=0x019FF5
    nop
    nop
    nop

; Handler at free space - does full input check logic
*=0x01FE00
MainLoopScrollCheck:
    ; Check if we're scrolling
    lda.w   menu_scroll_state
    beq     _main_loop_do_input

    ; We're scrolling - process one animation frame
    jsr.w   UpdateScrollFrame

    ; Check if scroll finished
    lda.w   menu_scroll_remaining
    bne     _main_loop_skip_input

    ; Scroll finished - clean up
    jsr.w   FinishScroll
    ; Fall through to do input

_main_loop_do_input:
    ; Do original: LDA $01, AND #$80, then branch appropriately
    lda.b   0x01
    and     #0x80                   ; Check JOY_LEFT
    beq     _left_not_pressed
    jmp.w   0x9FF8                  ; Left pressed - continue to left button handling at $9FF8

_left_not_pressed:
    jmp.w   0xA003                  ; Left not pressed - skip to @a003 (right column check)

_main_loop_skip_input:
    ; Still scrolling - skip ALL input, jump to @a0ff
    ; @a0ff does DrawItemCursors then jumps to @9fcd (which does vblank)
    jmp.w   0xA0FF

; ============================================================================
; SCROLL DOWN - Replace blocking loop with state machine
; ============================================================================
; Original at $01A076-$01A0B7:
;   @a076: inc; sta $1b1a      (4 bytes)
;   @a07a: rep #$20; ldy #8    (5 bytes)
;   @a07f: [blocking loop]     (~56 bytes)
;   @a0b1: shorta; jsr DrawItemCursors; jsr UpdateCtrlAfterScroll; bcs; jmp @9ff2
;
; We replace the trigger at $A076 to call StartScrollDown and skip the loop.
; Jump to $A0BC (after scroll down block) to continue with A button check.

*=0x01A076
    jsr.w   ScrollDownTrigger
    jmp.w   0xA0BC                  ; Skip to after scroll block (A button check)

*=0x01FE30
ScrollDownTrigger:
    ; A already has $1B1A from LDA at $A073
    ; Check bounds (original: cmp #$0e; beq @a0bc)
    cmp     #0x0E
    beq     _scroll_down_at_max

    ; Do original: inc; sta $1b1a
    inc
    sta.w   0x1B1A

    ; Initialize non-blocking scroll
    jsr.w   StartScrollDown

_scroll_down_at_max:
    rts

; ============================================================================
; SCROLL UP - Replace blocking loop with state machine
; ============================================================================
; Original at $01A01F-$01A065:
;   @a01f: lda $1b1a             (3 bytes) - load scroll position
;   @a022: beq @a066             (2 bytes) - if at top, skip
;   @a024: dec; sta $1b1a        (4 bytes) - decrement scroll position
;   @a028: rep #$20; ldy #8      (5 bytes)
;   @a02d: [blocking loop]       (~46 bytes)
;   @a05b: shorta; jsr DrawItemCursors; jsr UpdateCtrlAfterScroll; bcs; jmp @9ff2
;
; Hook at $A01F to handle the entire scroll up logic.
; 6 bytes replaces 5 bytes of original (LDA + BEQ), overwrites DEC at $A024.

*=0x01A01F
    jsr.w   ScrollUpTrigger
    jmp.w   0xA066                  ; Skip to after scroll block (down button check)

*=0x01FE50
ScrollUpTrigger:
    ; Check if at top (original: lda $1b1a; beq @a066)
    lda.w   0x1B1A
    beq     _scroll_up_at_top

    ; Do original: dec; sta $1b1a
    dec
    sta.w   0x1B1A

    ; Initialize non-blocking scroll
    jsr.w   StartScrollUp

_scroll_up_at_top:
    rts

; ============================================================================
; Menu Entry/Exit Hooks
; ============================================================================

; --- Hook ItemMenu Entry ---
; Original at $019F27: stz $1b1f (3 bytes)
; Replace with: jsr.w MenuEntryHook
*=0x019F27
    jsr.w   MenuEntryHook

*=0x01FE70
MenuEntryHook:
    jsr.l   MenuEntryHook_Impl
    rts

; --- Hook ItemMenu Exit ---
; Original at $019F87: jsr ResetSprites ($8D6A) (3 bytes)
*=0x019F87
    jsr.w   MenuExitHook

*=0x01FE90
MenuExitHook:
    jsr.l   MenuExitHook_Impl
    rts

; ============================================================================
; NMI HDMA Hook
; ============================================================================
; The menu vblank routine at $8081-8084 does: TDC; STA $420C (disables all HDMA)
; We hook this to use our shadow variable instead.

*=0x018081
    jsr.w   HdmaEnableHook
    nop

*=0x01FEB0
HdmaEnableHook:
    ; Load HDMA enable shadow (long addressing for WRAM)
    .db 0xAF                        ; LDA.L opcode
    .dw menu_hdma_enable            ; $1BAE
    .db 0x7E                        ; Bank $7E
    sta.w   0x420C                  ; Write to HDMAEN
    rts

; ============================================================================
; NMI DMA Transfer Handler
; ============================================================================
; Hook into NMI to transfer WRAM buffer to VRAM when flag is set.
; This happens during vblank to avoid visual glitches.
;
; We hook the WaitVblank routine at $0181A5 which is called frequently.
; After vblank is detected, we check the transfer flag.

*=0x01FE98
NmiDmaTransferCheck:
    jsr.l   NmiDmaTransferCheck_Impl
    rts

; ============================================================================
; UpdateScrollRegs BG1VOFS Hook - Skip when menu HDMA is active
; ============================================================================
; UpdateScrollRegs at $14FF0A writes scroll registers to hardware.
; At offset +35 ($14FF2D), it writes $93/$94 to BG1VOFS ($210E).
; When our menu HDMA is active, we skip these writes so HDMA has full control.

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
; Original DrawItemSlot at $A1ED checks $5D AND #$01 to determine left/right column.
; If odd (right column), it branches to $A223 which adds $001C offset.
; For our single-column rolling buffer, $5D contains slot_index (0-11).
; Odd slot indices (1,3,5,7,9,11) would incorrectly trigger right-column offset.
;
; Patch: Change AND #$01 to AND #$00 at $01A1EF so branch is never taken.
; Original: 29 01 (AND #$01)
; Patched:  29 00 (AND #$00)

*=0x01A1F0
    .db 0x00                            ; Change operand from $01 to $00

}
