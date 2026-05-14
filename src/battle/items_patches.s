"""
Patches for 12-byte (instead of 9-byte) item names in battle: rewrites every `cpx`/`cmp` boundary check and
every $0F8000 item-data reference to land on `assets_items_dat`.
"""
; Item name expansion patches for battle graphics
; Changes 9-byte items to 12-byte items
; Redirects 0x0F8000 references to assets_items_dat

; ===== BTLGFX/MENU: LOCATION 1 =====

; --- multiplier ---
; Original: 02/9E1A: A9 09  LDA #0x09

*=0x029E1A
    lda #ITEM_NAME_RECORD_SIZE

; --- item symbol ---
; Original: 02/9E44: BF 00 80 0F  LDA 0x0F8000,X

*=0x029E44
    lda.l assets_items_dat, x

; --- loop counter ---
; Original: 02/9E58: A9 08  LDA #0x08

*=0x029E58
    lda #ITEM_NAME_TEXT_SIZE

; --- item name (+1 skip symbol) ---
; Original: 02/9E5C: BF 01 80 0F  LDA 0x0F8001,X

*=0x029E5C
    lda.l assets_items_dat + 1, x

; ===== BTLGFX/MENU: LOCATION 2 =====

; --- multiplier ---
; Original: 02/9FEF: A9 09  LDA #0x09

*=0x029FEF
    lda #ITEM_NAME_RECORD_SIZE

; --- item symbol ---
; Original: 02/A00C: BF 00 80 0F  LDA 0x0F8000,X

*=0x02A00C
    lda.l assets_items_dat, x

; --- loop counter ---
; Original: 02/A020: A9 08  LDA #0x08

*=0x02A020
    lda #ITEM_NAME_TEXT_SIZE

; --- item name (+1 skip symbol) ---
; Original: 02/A024: BF 01 80 0F  LDA 0x0F8001,X

*=0x02A024
    lda.l assets_items_dat + 1, x

; ===== TEXTVAR_03: BATTLE MESSAGE ITEM NAME =====

; --- multiplier ---
; Original: 02/A594: A9 09  LDA #0x09

*=0x02A594
    lda #ITEM_NAME_RECORD_SIZE

; --- loop counter ---
; Original: 02/A5A1: A9 08  LDA #0x08

*=0x02A5A1
    lda #ITEM_NAME_TEXT_SIZE

; --- item name ---
; Original: 02/A5A5: BF 00 80 0F  LDA 0x0F8000,X

*=0x02A5A5
    lda.l assets_items_dat, x

; ===== BTLGFX/BTLGFX: ITEM DISPLAY =====

; --- multiplier ---
; Original: 02/CB77: A9 09  LDA #0x09

*=0x02CB77
    lda #ITEM_NAME_RECORD_SIZE

; --- item name ---
; Original: 02/CB83: BF 00 80 0F  LDA 0x0F8000,X

*=0x02CB83
    lda.l assets_items_dat, x

; --- loop counter ---
; Original: 02/CB8C: C0 08 00  CPY #0x0008

*=0x02CB8C
    cpy #0x000b

; ===== EQUIPPED ITEMS DISPLAY WIDTH =====

; --- equipped items width 1 ---
; Original: 02/AB47: A9 09  LDA #0x09

*=0x02AB47
    lda #ITEM_NAME_RECORD_SIZE

; --- equipped items width 2 ---
; Original: 02/B442: A9 09  LDA #0x09

*=0x02B442
    lda #ITEM_NAME_RECORD_SIZE

; --- equipped items width 3 ---
; Original: 02/B698: A9 09  LDA #0x09

*=0x02B698
    lda #ITEM_NAME_RECORD_SIZE

; ===== INVENTORY BUFFER STRIDE EXPANSION =====
; Expand from 48 bytes/item (12 tiles/row) to 60 bytes/item (15 tiles/row)
; This extends into freed magic buffer space at 0x97A6+

; --- DrawInventoryItemText: buffer stride ---
; Original: 02/9FAF: A9 30  LDA #0x30

*=0x029FAF
    lda #0x3c  ; 60 bytes per item instead of 48

; --- DrawInventoryItemText: line length ---
; Original: 02/9FC4: A9 0C  LDA #0x0C

*=0x029FC4
    lda #0x0f  ; 15 tiles per line instead of 12

; ===== TfrInventoryList PATCHES =====
; Skip when rolling buffer enabled - it has its own transfer routine
.if INVENTORY_ROLLING_BUFFER == 0 {
; --- right column buffer offset ---
; Original: 02/9923: BD D6 8E  LDA 0x8ED6,X
    *=0x029923
    lda.w 0x8EE2, x  ; 0x8EA6 + 0x3C = 0x8EE2

; --- loop 1 end (first tilemap row) ---
; Original: 02/992A: C0 1A 00  CPY #0x001A
    *=0x02992A
    cpy #0x0020  ; copy 30 bytes (Y: 2 to 32) instead of 24

; --- right column buffer offset (line 2) ---
; Original: 02/9937: BD D6 8E  LDA 0x8ED6,X
    *=0x029937
    lda.w 0x8EE2, x

; --- loop 2 end (second tilemap row) ---
; Original: 02/993E: C0 5A 00  CPY #0x005A
    *=0x02993E
    cpy #0x0060  ; copy 30 bytes (Y: 0x42 to 0x60) instead of 24

; --- X stride after each row ---
; Original: 02/9947: 69 30 00  ADC #0x0030
    *=0x029947
    adc #0x003c  ; advance 60 bytes instead of 48
}

; end !INVENTORY_ROLLING_BUFFER

; ===== UpdateEnabledItems PATCHES (using item mode) =====

; --- tile count (using item) ---
; Original: 02/9F2B: A9 0C  LDA #0x0C

*=0x029F2B
    lda #0x0f  ; 15 tiles instead of 12

; --- row 2 attribute offset (using item) ---
; Original: 02/9F47: 99 BF 8E  STA 0x8EBF,Y

*=0x029F47
    sta.w 0x8EC5, y  ; 0x8EA7 + 0x1E = 0x8EC5

; --- Y stride (using item) ---
; Original: 02/9F54: 69 18 00  ADC #0x0018

*=0x029F54
    adc #0x001e  ; advance 30 bytes instead of 24

; ===== UpdateEnabledItems PATCHES (throw mode) =====

; --- tile count (throw) ---
; Original: 02/9F68: A9 0C  LDA #0x0C

*=0x029F68
    lda #0x0f  ; 15 tiles instead of 12

; --- row 2 attribute offset (throw) ---
; Original: 02/9F86: 99 BF 8E  STA 0x8EBF,Y

*=0x029F86
    sta.w 0x8EC5, y

; --- Y stride (throw) ---
; Original: 02/9F93: 69 18 00  ADC #0x0018

*=0x029F93
    adc #0x001e  ; advance 30 bytes instead of 24

; ===== INVENTORY WINDOW SIZE =====
; MenuWindowTbl entry 5 (inventory) at 0x16FE5A + 5*6 = 0x16FE78
; Format: x, y, width, height
; Original: 0x01, 0x00, 0x1E, 0x33
.if INVENTORY_ROLLING_BUFFER {
    *=0x16FE78
    .db 0x00, 0x00, 0x20, 0x0F  ; x=0, y=0, width=32, height=15 (6 items × 2 + 3 border)
} else {
    *=0x16FE78
    .db 0x00, 0x00, 0x20, 0x33  ; x=0 (edge), y=0, width=32, height=51
}

; ===== TILEMAP BASE POINTERS =====
; Skip when rolling buffer enabled - these addresses are used for hooks/trampoline
.if INVENTORY_ROLLING_BUFFER == 0 {
; Shift item drawing 1 tile left by adjusting base pointers
; Y offsets stay at 2/0x42 to preserve loop mechanics

; --- TfrInventoryList: left column base pointer ---
; Original: 02/98FD: A2 2A C5  LDX #0xC52A
    *=0x0298FD
    ldx #0xC526  ; 2 tiles left

; --- NOP out 0xFF border writes that now overwrite content ---
; Original: 02/9910: 91 00  STA ($00),Y  (left col Y=0)
    *=0x029910
    nop
    nop

; Original: 02/9917: 91 00  STA ($00),Y  (left col Y=$40)
    *=0x029917
    nop
    nop

; --- TfrInventoryList: right column base pointer ---
; Original: 02/9902: A2 46 C5  LDX #0xC546
    *=0x029902
    ldx #0xC544  ; 1 tile left
}
; end !INVENTORY_ROLLING_BUFFER

; ===== CURSOR SPRITE POSITIONS =====

; --- Hand cursor X positions ---
; Original: 16/FC59: 0x0C, 0x7C (left=12px, right=124px)

*=0x16FC59
    .db 0x0C, 0x7C  ; Keep original positions (left=12px, right=124px)

; --- Arrow sprite positions (X, Y, tile, attr) ---
; Original: 16/FC3C

*=0x16FC3C
    .db 0xec + 10, 0x90, 0x4f, 0xb1  ; up arrow 1 (X was 0xec)
    .db 0xec + 10, 0x98, 0x4e, 0xb1  ; up arrow 2
    .db 0xec + 10, 0xcc, 0x4e, 0x31  ; down arrow 1
    .db 0xec + 10, 0xd4, 0x4f, 0x31  ; down arrow 2

; ===== 1D CURSOR NAVIGATION (ROLLING BUFFER ONLY) =====
.if INVENTORY_ROLLING_BUFFER {
; Disable left/right button handling for single-column scrolling mode
; Original at $02B541: CMP #$02 / BNE $B55A (left button check)
; Replace with BRA to common exit at $B579
; BRA opcode=$80, offset=$36 ($B579-$B543=54)
    *=0x02B541
    .db 0x80, 0x36  ; bra $B579 (skip left/right handlers)
    nop  ; Fill remaining bytes
    nop

; Single-column item index: change $63 by 1 per row instead of 2
; In 2-column mode, each row has 2 items, so up/down changes $63 by 2.
; In single-column mode, each row has 1 item, so change by 1.
; NOP the second INC/DEC $63 in each up/down handler.

; UP button - scroll case: $02B500-B503 has DEC $63 / DEC $63
    *=0x02B502
    nop  ; NOP second DEC $63
    nop

; UP button - non-scroll case: $02B508-B50B has DEC $63 / DEC $63
    *=0x02B50A
    nop  ; NOP second DEC $63
    nop

; DOWN button - scroll case: $02B530-B533 has INC $63 / INC $63
    *=0x02B532
    nop  ; NOP second INC $63
    nop

; DOWN button - non-scroll case: $02B538-B53B has INC $63 / INC $63
    *=0x02B53A
    nop  ; NOP second INC $63
    nop
}

; ===== REMOVE 8PX SPRITE CLIPPING BANDS =====
; Original window masks sprites in 8px bands on left (0-7) and right (249-255)

; --- Window 1 left edge: 8 → 0 ---
; Original: 02/8A1D: A9 08  LDA #$08

*=0x028A1D
    lda #0x00  ; left edge at pixel 0

; --- Window 1 right edge: 248 → 255 ---
; Original: 02/8A22: A9 F8  LDA #$F8

*=0x028A22
    lda #0xff  ; right edge at pixel 255

; ===== EQUIPPED ITEMS BUFFER EXPANSION =====
; Expand from 12 tiles to 15 tiles per item (same as inventory)
; Needed because 11-char names + symbol + 3 formatting tiles = 15 tiles

; --- DrawEquipItemText: tile count ---
; Original: 02/9DD3: A9 0C  LDA #$0C

*=0x029DD3
    lda #0x0f  ; 15 tiles instead of 12

; --- TfrEquipWindow: replace entire body with JSL to relocated routine ---
; Vanilla body $0297A6..$029824 (126 bytes) hard-coded a side-by-side dual-write
; pattern. New routine in bank $20 walks label/item per hand row-by-row.
; Trampoline overwrites the entry; obsolete in-body patches removed.
    .extern tfr_equip_window_new

*=0x0297A6
    jsr.l tfr_equip_window_new
    rts

; --- EquipHandPtrs: item offset within buffer ---
; Original: 02/9D67: 00 30 (item 1 at 0, item 2 at 48)

*=0x029D67
    .db 0x00, 0x3c  ; item 1 at 0, item 2 at 60

; --- EquipTextBufPtrs: relocate to freed magic buffer space ---
; Original buffer at $BC86 is too small (96 bytes per char)
; New: 120 bytes per char (2 items × 60 bytes) at $9A00
; Original: 16/FEC1: BC86, BCE6, BD46, BDA6, BE06 (stride $60)

*=0x16FEC1
    .dw 0x9A00  ; char 0
    .dw 0x9A00 + 0x78  ; char 1 ($9A78)
    .dw 0x9A00 + 0x78 * 2  ; char 2 ($9AF0)
    .dw 0x9A00 + 0x78 * 3  ; char 3 ($9B68)
    .dw 0x9A00 + 0x78 * 4  ; char 4 ($9BE0)

; ===== EQUIPPED ITEMS WINDOW SIZE =====
; Move window to screen edge (x: 1→0) and make 2 tiles wider (width: 30→32)

; MenuWindowTbl entry 6 (equipped items) at 0x16FE5A + 6*6 = 0x16FE7E
; Format: x, y, width, height
; Original: 0x01, 0x00, 0x1E, 0x07

*=0x16FE7E
    .db 0x00, 0x00, 0x20, 0x07  ; x=0 (edge), y=0, width=32, height=7
