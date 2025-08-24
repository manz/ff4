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


; inventory window
*=0x01dcce
    menu_window(0,0,30,48)

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
    adc.w #0x001c + 4

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

; free space at the end of the bank

*=0x01ff40
draw_window = 0x0180d9
check_if_description_was_rendered:
    pha

    cmp.l render.last_drawn_text_ptr
    bne _continue
    pla
    rts
    _continue:
    sta.l render.last_drawn_text_ptr

    pla

    pha
    ldy.w #0xdcd6
    jmp _back

draw_vwf_message:
    jsr.l items_description.draw_trampoline
    rts
draw_window_and_vwf_message:
    jsr.w draw_window
    ; NOTE: quirks from the hardcore bank switching can be solved by loading the bank in A before the call.
    pha
    rep #0x20
    tya
    adc.w #0x8000
    tay
    sep #0x20
    pla

    iny
    iny
    iny
    iny
draw_vwf_message_pos_with_bank:
    lda.b #messages.use_on_whom >> 16

draw_vwf_message_pos:
    jsr.l items_description.draw_trampoline_pos
    rts

