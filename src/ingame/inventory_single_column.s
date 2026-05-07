"""
Phase-1 single-column inventory layout patches: collapse the original 2-column items list to one column so the
rolling buffer can take over rendering.
"""
; ============================================================================
; Single Column Inventory Patches for Main Menu
; ============================================================================
;
; Phase 1: Convert 2-column inventory to single column
; - Changes visible items from 20 (10 per column) to 10 (single column)
; - Removes left/right cursor handling
; - Updates scroll limits for 48 items
;
; ============================================================================

; ============================================================================
; CONSTANTS
; ============================================================================
VISIBLE_ITEMS := 10  ; Items visible at once
;TOTAL_ITEMS             := 48       ; Total inventory items
SCROLL_LIMIT := 38  ; 48 - 10 = 38 (max scroll position)

; File is being processed - patches below should apply

; ============================================================================
; DrawInventoryList Patch
; ============================================================================
; Original at $01A172 draws 48 items (all items)
; New version draws only 10 visible items based on scroll position
;

; Original code:

;   DrawInventoryList:
;   @a172:  ldy     #.loword(InventoryWindow)
;           jsr     DrawWindow
;           ldx     #$1440
;           stx     $5a
;           lda     #$30                    ; 48 items
;           sta     $e1
;   _a181:  stz     $5d
;           stz     $5e
;
; Hook at the item count setup

; Original: lda #$30 at A17D-A17E (a9 30)
; Just patch the operand byte at A17E, not the full instruction

*=0x01A17E
    .db VISIBLE_ITEMS + 1  ; Draw 11 items (10 visible + 1 pre-render slot)

; ============================================================================
; DrawItemSlot - Single Column Version
; ============================================================================
; Original checks odd/even item index for left/right column
; Single column always uses left column position
;

; Original at $01A1ED:
;   @a1ed:  lda     $5d
;           and     #$01
;           bne     @a223           ; Branch if right column
;
; Patch: Always use left column code path (never branch)

*=0x01A1EF
    ; Change BNE to BRA skip (effectively disable right-column branch)
    ; Original: AND #$01 / BNE @a223
    ; New: AND #$00 / BNE @a223 (always zero, never branches)
    and #0x00

; ============================================================================
; Tilemap Y Position - Single Column Fix
; ============================================================================

; Original code at $01A1B9 calculates tilemap Y position:
;   LDA $5D    ; item index (0-47)
;   LSR        ; divide by 2 (for 2-column: items 0,1→row 0, items 2,3→row 1)
;   ASL x7     ; multiply by 128 (tilemap row offset)
;   ADC #$0002 ; base offset
;
; For single column, each item needs its own row, so remove the LSR.
; This makes Y = item_index * 128 + 2 instead of (item_index/2) * 128 + 2

*=0x01A1BC
    nop  ; Replace LSR with NOP

; ============================================================================
; Scroll Limit Patch
; ============================================================================

; Original scroll down limit check at $01A076:
;   @a076:  cmp     #$0e            ; 14 = 24 items - 10 visible
;           beq     @a0bc           ; Don't scroll if at limit
;
; The CMP opcode is at $A076, operand at $A077
; New limit for single column: 48 - 10 = 38

*=0x01A077
    .db SCROLL_LIMIT  ; 38 instead of 14

; Also patch the cursor Y limit check

; Original at $01A071:
;   @a06c:  lda     $1b23           ; cursor Y
;           cmp     #$09            ; max Y = 9 (for 10 visible rows)
;
; This stays the same for 10 visible items, so no change needed

; ============================================================================
; Cursor Drawing - Fixed X Position
; ============================================================================
; Original at $01A105 checks $1b22 (X position) for left/right column
; Single column: always use left position
;

; Original:
;   @a105:  ...
;   @a116:  lda     $1b22                   ; cursor 1 x position
;           beq     @a11b
;           lda     #$6c                    ; right column X
;   @a11b:  clc
;           adc     #$04
;
; Patch: Skip the X position check, always use left column

*=0x01A114
    lda #0x00  ; Always 0 (left column) - replaces LDA $1B22 (3 bytes)
    nop  ; Was high byte of $1B22 address
    nop  ; Skip BEQ opcode
    nop  ; Skip BEQ offset
    nop  ; Skip LDA #$6c opcode
    nop  ; Skip LDA #$6c operand

; ============================================================================
; Input Handling - Disable Left/Right Toggle
; ============================================================================
; Original at $01A003 and $01A014 handle left/right button presses
; to switch columns. We disable this for single column.
;

; Left button handler at @9ff2:
;   @9ff2:  lda     $01
;           and     #JOY_LEFT
;           beq     @a003
;           lda     $1b22           ; toggle x position
;           inc
;           and     #$01
;           sta     $1b22
;           bne     @a01a           ; move up
;
; Right button handler similar at @a003
;
; Patch: Make left/right do nothing (skip to down button check)

*=0x019FF4
    ; Change AND #JOY_LEFT to AND #0x00 (never matches)
    and #0x00

*=0x01A005
    ; Change AND #JOY_RIGHT to AND #0x00 (never matches)
    and #0x00

; ============================================================================
; Scroll Position Adjustment for Drawing
; ============================================================================
; When drawing, need to start from scroll position, not always item 0
; This requires adding $1B1A (scroll position) to the item pointer
;

; Original _a181 loop at $01A181:
;   _a181:  stz     $5d             ; item counter = 0
;           stz     $5e
;
; We need to initialize $5d to scroll_pos * 2 (since items are 2 bytes each)
; But actually, the loop uses $5a as a pointer, and $5d as a counter
; The pointer $5a = $1440 + (scroll_pos * 2)
;
; Add patch to adjust $5a before the loop

*=0x01A181
    jsr.w adjust_inventory_pointer
    nop

; ============================================================================
; Cursor Y Limit for Scroll Down
; ============================================================================
; Original at $01A071: cmp #$09 for 10 visible rows
; This is correct for single column with 10 visible items
; No change needed

; ============================================================================
; Second Cursor (for item swap)
; ============================================================================
; The second cursor also uses $1b24 (X position) and $1b25 (Y position)
; For single column, $1b24 should always be 0
;

; When storing first item selection at $01A2C3:
;   @a2c3:  lda     $1b1a
;           clc
;           adc     $1b23
;           sta     $1b25
;           lda     $1b22
;           sta     $1b24           ; Store X position
;
; Patch: Always store 0 for X position

; $1B25 stores absolute position (scroll + cursor) - keep original storage
; Just patch $A2CD to store 0 for X position

*=0x01A2CD
    lda #0x00  ; Always 0 for single column X (was LDA $1B22)
    nop  ; Pad to 3 bytes

; ============================================================================
; Item Index Calculation for Selection
; ============================================================================
; Original two-column: ((Y + scroll) * 2 + X) * 2 = item_index * 2
; Single column: (Y + scroll) * 2
; Need to remove one ASL at each calculation

; First item (current cursor) at $A398
; Original: ASL / ADC $1B22 / ASL -> ((val*2)+col)*2
; New: CLC / ADC $1B22 / ASL -> (val+col)*2
; MUST use CLC because the previous CMP leaves carry set!

*=0x01A398
    clc  ; Clear carry (was ASL which also clears carry)

; Second item (swap target) at $A3A6
; $1B25 already has absolute position
; Original: ASL / ADC $1B24 / ASL -> ((val*2)+col)*2
; New: CLC / ADC $1B24 / ASL -> (val+col)*2

*=0x01A3A6
    clc  ; Clear carry (was ASL which also clears carry)

; Another second item calculation at $A320
; Used when selecting same item twice to use it
; CRITICAL: CMP $1B24 at $A318 sets carry if $1B22 >= $1B24 (always true when both are 0)
; Original ASL would clear carry, but NOP leaves carry SET, causing ADC to add +1!

*=0x01A320
    clc  ; Clear carry (was ASL which also clears carry)
    ; Original calculates: (scroll_pos + cursor_y) * 2 + cursor_x * 2
    ; For single column: (scroll_pos + cursor_y) * 2
    ;

; At $01A309 (SelectItem2):
;   @a309:  lda     $1b23
;           clc
;           adc     $1b1a
;           cmp     $1b25
;           bne     _a38e           ; items don't match
;           lda     $1b22
;           cmp     $1b24
;           bne     _a38e
;
; The X position compare should always match for single column
; Already handled by setting both to 0

; At $01A320 to calculate item offset:
;   @a320:  lda     $1b25
;           asl
;           adc     $1b24           ; +0 or +1 for column
;           asl                     ; x2 for 2 bytes per slot
;
; For single column, $1b24=0, so this simplifies to: $1b25 * 2
; No patch needed if $1b24 is always 0

; ============================================================================
; DrawItemDesc - Single Column Fix
; ============================================================================

; Original at $01A7C8 uses two-column calculation (ABSOLUTE addressing):
;   $A7C8: LDA.W $1B23   (AD 23 1B) - cursor_y
;   $A7CB: CLC           (18)
;   $A7CC: ADC.W $1B1A   (6D 1A 1B) - + scroll_pos
;   $A7CF: ASL           (0A)       - * 2 (for two columns per row) <-- PATCH HERE
;   $A7D0: ADC.W $1B22   (6D 22 1B) - + column
;   $A7D3: ASL           (0A)       - * 2 (for 2 bytes per item)
;
; For single column: remove first ASL at $A7CF
; This matches the patches at $A398, $A3A6, $A320

*=0x01A7CF
    nop  ; Remove first ASL for single column

; ============================================================================
; Initialize $1B22 (cursor column) to 0 on menu entry
; ============================================================================
; Ensure $1b22 starts at 0 even if it had a value from a previous menu.
; Patch at $01A181 which runs after SelectClearBG1 and before DrawInventoryList.
; We already have adjust_inventory_pointer at $A181, so add $1b22 init there.
; Actually, we'll add it to the menu_entry_hook_impl in inventory_rolling.s
