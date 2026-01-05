.include 'src/ingame/macros.i'

; during scroll
*=0x01A814
    load_system_menu_text_pointer(items_menu.item)

; when scroll done
*=0x019F56
    load_system_menu_text_pointer(items_menu.item)

*=0x1a750
    load_system_menu_text_pointer(items_menu.item)

; patching find description setup bank and offset
*=0x01a7f6
    ldx.w #assets_item_descriptions_dat & 0xffff

*=0x01a7fc
    addr = (assets_item_descriptions_dat & 0xff0000)
    lda.l addr, x


*=0x01a7da
    ; In the original code the item description is rendered multiple times (once per tick ?)
    ; rendering the variable width font that often cause noticeable slowdowns, we are trying to render the text only
    ; when the description should change. Because the draw window clears the tilemap the check must happen before it.
    jmp.w check_if_description_was_rendered
    nop
    _back:


; Hook in the display_item_description function, draw the window and render the string
*=0x01a808
    lda.b #assets_item_descriptions_dat>>16
    ldx.w #0x0054
    jsr.w draw_vwf_message


*=0x1a439
    ldy.w #messages.use_on_whom
    jsr.w draw_vwf_message_pos_with_bank

*=0x1a36f
    ldy.w #messages.cantuse
    jsr.w draw_vwf_message_pos_with_bank


; inventory window (22 rows tall for 10 visible items + borders)
*=0x01dcce
    menu_window(0,0,30,24)

;
*=0x01dcd6
    menu_window(9,0,21,3)

; item select character on the left side (selected item in the right column)
*=0x01dd38
  menu_window(0,5,16,21)

; item select character on the right side (selected item in the left column)
*=0x01dd3c
 menu_window(14,5,16,21)

; moves the right item column one tile to the right
*=0x01a227
    adc.w #0x001c + 2
*=0x01a1c4
    adc.w #0x0002

*=0x1efd7d
__delta_l = 0
__delta_r = 2

  .dw   0x039e- __delta_l,0x019e- __delta_l,0x059e- __delta_l,0x029e- __delta_l,0x049e- __delta_l
  .dw   0x0384- __delta_r,0x0184- __delta_r,0x0584- __delta_r,0x0284- __delta_r,0x0484- __delta_r

*=0x01a4f4
    adc.w #0x0082

*=0x01a51a
    draw_hp_mp = 0x018a2a
    lda.w #0x0046 + 0x40
    ldy.w #0x0007
    jsr.w draw_hp_mp
    lda.w #0x0050 + 0x40
    ldy.w #0x0009
    jsr.w draw_hp_mp
    lda.w #0x0086 + 0x40
    ldy.w #0x000b
    jsr.w draw_hp_mp
    lda.w #0x0090 + 0x40
    ldy.w #0x000d
    jsr.w draw_hp_mp

*=0x01aed6
        ldy.w #messages.cant_use_magic - 0x8000
        jsr.w draw_window_and_vwf_message

; choice window
*=0x01db40
    load_system_menu_text_pointer(treasure.choice_window)

; label window
*=0x01db46
    load_system_menu_text_pointer(treasure.header_window)

*=0x01d83d
    load_system_menu_text_pointer(treasure.take_all)


*=0x01db2e
    load_system_menu_text_pointer(treasure.key_items_left_warning)

*=0x01d95b
    load_system_menu_text_pointer(treasure.exchange)

*=0x1d88b
    lda.b #0x48 - 8
*=0x1d88f
    lda.b #0xb8 - 8

;01D887  A5 60          LDA $60
;01D889  D0 04          BNE $01D88F
;01D88B  A9 48          LDA #$48
;01D88D  80 02          BRA $01D891
;01D88F  A9 B8          LDA #$B8
;01D891  85 45          STA $45
;01D893  A9 0E          LDA #$0E
;01D895  85 46          STA $46
;01D897  4C 81 82       JMP $8281

*=0x01D814
  load_system_menu_text_pointer(treasure.items_window)

*=0x1d792
treasure_menu_entry:

; Test Overrides:
; would be nice to automate that
; open menu, set PC to 01d792
; starts the menu
; set 0xee to 0x1804 (Key item baron key.)

; ============================================================================
; Single-column patches (moved here to test if they apply)
; ============================================================================
; Scroll limit: 48 items - 10 visible = 38 max scroll position
; CMP opcode at $A076, operand at $A077
*=0x01A077
    .db     38                      ; 38 = new scroll limit

; Visible items count - handled in inventory_single_column.s

; Disable left button (AND #$00 instead of AND #$02)
*=0x019FF4
    and     #0x00

; Disable right button (AND #$00 instead of AND #$01)
*=0x01A005
    and     #0x00
