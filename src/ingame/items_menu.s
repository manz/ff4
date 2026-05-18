"""
Item-name expansion for the field-menu (mirror of `battle/items_patches.s`): mul-by-9 -> mul-by-17 stride
changes, $0F8000 -> `assets_items_unleashed_dat` pointer remaps.
Field / drops / treasure rolling inventory all defer to vanilla
DrawItemSlot at $01:9000, so patching here switches them in one
go.
"""
; Item name expansion for menu system
; Patches the multiply-by-9 to multiply-by-17
; Also redirects $0F8000 references to assets_items_unleashed_dat

; --- Patch loop counter ---
; Original: 01/903F: A9 08  LDA #$08
; Name field is ITEM_UNLEASHED_TEXT_SIZE chars in items_unleashed
; (records are ITEM_UNLEASHED_RECORD_SIZE bytes = symbol + name).

*=0x01903F
    lda #ITEM_UNLEASHED_TEXT_SIZE

; --- Patch multiply logic ---

; Original at $019023-902A (7 bytes):
;   LDA $43, ASL, ASL, ASL, ADC $43, TAX
; New: JSL to relocated routine (4 bytes) + 3 NOPs

*=0x019023
    jsr.l multiply_item_index_17
    nop
    nop
    nop
    nop

; ===== ITEM TABLE ADDRESS REDIRECTS =====

; --- menu: item symbol ---
; Original: 01/902E: BF 00 80 0F  LDA $0F8000,X

*=0x01902E
    lda.l assets_items_unleashed_dat, x

; --- menu: item name (in loop) ---
; Original: 01/9043: BF 00 80 0F  LDA $0F8000,X

*=0x019043
    lda.l assets_items_unleashed_dat, x

; ===== COLON/QUANTITY POSITION PATCHES =====
; Item names expanded from 9 to 16 bytes (+7 chars = +14 VRAM bytes)
; Change offset from $0052 to $0060

; --- DrawItemSlot: left column colon/qty position ---
; Original: 01/A1FC: 69 52 00  ADC #$0052

*=0x01A1FC
    adc #0x0060

; --- DrawItemSlot: right column colon/qty position ---
; Original: 01/A236: 69 52 00  ADC #$0052

*=0x01A236
    adc #0x0060
