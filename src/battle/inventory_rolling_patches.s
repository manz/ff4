; ============================================================================
; Rolling Inventory Buffer - ROM Patches (Single Column)
; ============================================================================
;
; Patches for single-column rolling inventory buffer.
; Key change: Hook scroll START (not completion) to pre-render edge rows.
;
; IMPORTANT: Bank $02 free space is limited ($98FF-$9982 = 131 bytes)
; Only small trampolines go here. Large functions go in bank $20.
;
; See docs/ff6_rolling_inventory_analysis.md for design rationale.
;
; ============================================================================

; ============================================================================
; PATCH: InitInventoryTextBuf ($029E9C)
; ============================================================================
*=0x029E9C
    jsr.l   InitInventoryTextBuf_Rolling
    .db     0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4
    .db     0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4
    .db     0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4
    rts

; ============================================================================
; PATCH: TfrInventoryList ($0298FA)
; ============================================================================
; Original function is $98FA-$9982 (136 bytes). We replace with JSL+RTS (5 bytes)
; This frees $98FF-$9982 (131 bytes) for our trampolines.

*=0x0298FA
    jsr.l   TfrInventoryList_Rolling
    rts

; ============================================================================
; TRAMPOLINES (Bank $02 free space: $98FF-$9982)
; ============================================================================
; These are called via JSL from bank $20, return via RTL

DrawText_Rolling_Trampoline:
    ; Save current battle flags to prevent VWF mode interference
    lda.l   0x704F00
    pha
    ; Clear battle flags (force WRAM mode for inventory)
    lda     #0x00
    sta.l   0x704F00

    ; Original DrawText call
    xba
    lda     #0x00
    xba
    jsr     0xA455                      ; DrawText at $02A455

    ; Restore battle flags
    pla
    sta.l   0x704F00
    rtl

Mult8_Trampoline:
    jsr     0x8560                      ; Mult8 at $028560
    rtl

HexToDec_Trampoline:
    jsr     0x86BF                      ; HexToDec at $0286BF
    rtl

NormalizeNum_Trampoline:
    jsr     0x8716                      ; NormalizeNum at $028716
    rtl

LoadMenuTfrData_Trampoline:
    jsr     0x9738                      ; LoadMenuTfrData at $029738
    rtl

UpdateEnabledItems_Trampoline:
    jsr     0x9F0E                      ; UpdateEnabledItems at $029F0E
    rtl

; ============================================================================
; RELOCATED: Draw Battle Command Window (originally at $9989)
; ============================================================================
; Original function was overwritten. This must fit in bank $02 free space.

DrawBattleCommandWindow_Relocated:
    jsr.w   draw_window_render_hook     ; Draw command list + sets LDX #$0340
_dbcw_loop:
    lda.w   0xBE65,x                    ; Copy main menu window tilemap
    sta.w   0xC1A5,x
    dex
    bne     _dbcw_loop
    lda     #0x02
    jsr     0x9B59                      ; Load menu window data
    jsr     0x9BC7                      ; Draw window
    lda     #0x03
    ldx.w   #0x0064
    jmp     0x99F1                      ; Continue original flow

; ============================================================================
; WRAP/CLEAR TRAMPOLINE (small, stays in bank $02)
; ============================================================================
; After scroll animation completes, we need to post-render for scroll DOWN.
; For scroll down: the slot that just scrolled off-screen needs to be updated
; with the NEXT item for future scrolls.
; For scroll up: pre-rendering was already done before animation.

WrapAndClear_Trampoline:
    ; FF6-style circular scroll - no reset needed!
    ; The wrap function in UpdateListScrollHDMA_Wrapped handles coordinate conversion.
    ;
    ; After scroll down, we need to post-render the next item to prepare for
    ; future scrolls. The off-screen slot that just scrolled off should be
    ; updated with the next item in the list.
    jsr.l   PostScrollDown_Render   ; Post-render if scroll down

    ; Clear animation state
    stz.w   0x1820
    rts

; Return point for bank $20 functions that need to RTS to bank $02 callers
Return_To_Bank02:
    rts

; ============================================================================
; ROM PATCHES
; ============================================================================

; Redirect callers of $9989 to relocated function
; Must use JSR (not JSL) since function ends with JMP, not RTL
*=0x0296CB
    jsr.w   DrawBattleCommandWindow_Relocated

*=0x029983
    jsr.w   DrawBattleCommandWindow_Relocated

; ============================================================================
; PATCHES in ascending address order (assembler requires this)
; ============================================================================

; Scroll animation end - wrap $EF65 (4 bytes each)
; Must use JMP (not JMP.L) - 3 bytes + 1 NOP = 4 bytes
*=0x02A86E
    jmp.w   WrapAndClear_Trampoline
    nop

; Animation loop DECrement path ($02A872-$02A87B) - 10 bytes
; Original: LDX $EF71 / DEX / STX $EF71 / JMP CheckListCursorVisible
; NOP the LDX/DEX/STX, replace JMP with RTS (skips CheckListCursorVisible)
; CheckListCursorVisible can incorrectly hide cursor 2 with our circular buffer scroll values
*=0x02A872
_nop_patch_dec:
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    rts             ; Skip CheckListCursorVisible (was JMP $A82D)
    nop             ; Fill remaining 2 bytes of JMP
    nop

*=0x02A8AA
    jmp.w   WrapAndClear_Trampoline
    nop

; Animation loop INCrement path ($02A8AE-$02A8B7) - 10 bytes
; Original: LDX $EF71 / INX / STX $EF71 / JMP CheckListCursorVisible
; NOP the LDX/INX/STX, replace JMP with RTS (skips CheckListCursorVisible)
; CheckListCursorVisible can incorrectly hide cursor 2 with our circular buffer scroll values
*=0x02A8AE
_nop_patch_inc:
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    rts             ; Skip CheckListCursorVisible (was JMP $A82D)
    nop             ; Fill remaining 2 bytes of JMP
    nop

; Scroll hooks - use JMP.L to bank $20 functions
*=0x02A8B8
    jmp.l   ScrollListDown_Hook

*=0x02A8CA
    jmp.l   ScrollListUp_Hook

; ============================================================================
; PATCH: UpdateListScrollHDMA ($02A7F1)
; ============================================================================
; This is the KEY patch for true FF6-style circular buffer.
; Original code builds HDMA table with unbounded scroll values.
; Our replacement wraps scroll values at 96 pixels (6 rows).
;
; Original function is 32 bytes ($02A7F1-$02A810).
; We replace with JMP.L (4 bytes) + NOPs.

*=0x02A7F1
    jmp.l   UpdateListScrollHDMA_Wrapped
    ; Fill remaining bytes with NOPs (32 - 4 = 28 bytes)
    .db     0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4
    .db     0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4
    .db     0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4
    .db     0xEA, 0xEA, 0xEA, 0xEA  ; nop x 4

; ============================================================================
; PATCH: Cursor scroll limit for single-column mode
; ============================================================================
; Original code at $02B517 checks if at end of list:
;   lda $ef85 / cmp #$17 / bne @b521
; The #$17 (23) is for 2-column mode (24 items per column).
; For single-column (48 items), change to #$2B (43 = 48-5).

*=0x02B519
    .db     0x2B            ; CMP #$2B instead of CMP #$17

; ============================================================================
; PATCH: ResetListScrollHDMA ($02AAB8)
; ============================================================================
; Fill BOTH $7F74 (active table) AND $81F4 (swap table) with our converted
; scroll values. This prevents the menu animation from swapping in bad values.
;
; Original fills only $81F4 with 371-based values.
; We fill both with our 132-based values so animation swap is a no-op.

*=0x02AAB8
    jsr.l   ResetListScrollHDMA_Rolling
    rts
