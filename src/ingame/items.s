"""
Field-menu item screen patches: windows, text pointers, VWF descriptions and messages (the list itself is
`inventory_rolling.s`).
"""
.import "core/preamble"
.import "core/assets"
.import "menus/in_game_text"
.import "menus/system_menus_text"
.import "ingame/free_space"
.import "small_vwf/init"
.include "menus/system_menus_macros.i"

.include "ingame/bank01_slack.i"
.include "core/bank20.i"
.include "ingame/macros.i"

.label _draw_item_description = 0x01A808

; Item label: during scroll, after scroll, and on redraw
.alloc at 0x01A814 {
    load_system_menu_text_pointer(items_menu.item)
}
.alloc at 0x019F56 {
    load_system_menu_text_pointer(items_menu.item)
}
.alloc at 0x1a750 {
    load_system_menu_text_pointer(items_menu.item)
}
.alloc at 0x01a7da {
; Vanilla redraws the description every frame, too slow for the VWF: render only when it changes. The check
; must come before DrawWindow, which clears the tilemap.
    jmp.w check_if_description_was_rendered
    nop

item_desc_back:
}
; Vanilla's string search ($01:A7F6), $45 = the description number
.alloc at 0x01A7F6 {
    jsr.l find_item_description
    bra _draw_item_description
}
; display_item_description: draw the window and render the string
.alloc at 0x01a808 {
    lda.b #item_descriptions >> 16
    ldx.w #0x0054
    jsr.w draw_vwf_message
}
.alloc at 0x1a439 {
    ldy.w #messages.use_on_whom
    jsr.w draw_vwf_message_pos_with_bank
}
.alloc at 0x1a36f {
    ldy.w #messages.cantuse
    jsr.w draw_vwf_message_pos_with_bank
}
; Inventory window: 10 visible items + borders
.alloc at 0x01dcce {
    menu_window(0, 0, 30, 23)
}
; Description window
.alloc at 0x01dcd6 {
    menu_window(9, 0, 21, 3)
}
; Character select on the left (item in the right column)
.alloc at 0x01dd38 {
    menu_window(0, 5, 16, 21)
}
; Character select on the right (item in the left column)
.alloc at 0x01dd3c {
    menu_window(14, 5, 16, 21)
}
; Right item column one tile right
.alloc at 0x01a227 {
    adc.w #0x001c + 2
}
; $01:A1C4 sits inside the slot hook at $01:A1BA when the rolling buffer is on.
.alloc at 0x1efd7d {
    _delta_l = 0
    _delta_r = 2

    .dw 0x039e - _delta_l, 0x019e - _delta_l, 0x059e - _delta_l, 0x029e - _delta_l, 0x049e - _delta_l
    .dw 0x0384 - _delta_r, 0x0184 - _delta_r, 0x0584 - _delta_r, 0x0284 - _delta_r, 0x0484 - _delta_r
}
.alloc at 0x01a4f4 {
    adc.w #0x0082
}
.alloc at 0x01a51a {
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
}
.alloc at 0x01aed6 {
    ldy.w #messages.cant_use_magic - 0x8000
    jsr.w draw_window_and_vwf_message
}
; Treasure choice window
.alloc at 0x01db40 {
    load_system_menu_text_pointer(treasure.choice_window)
}
; Treasure label window
.alloc at 0x01db46 {
    load_system_menu_text_pointer(treasure.header_window)
}
.alloc at 0x01d83d {
    load_system_menu_text_pointer(treasure.take_all)
}
.alloc at 0x01db2e {
    load_system_menu_text_pointer(treasure.key_items_left_warning)
}
.alloc at 0x01d95b {
    load_system_menu_text_pointer(treasure.exchange)
}
.alloc at 0x1d88b {
    lda.b #0x48 - 8
}
.alloc at 0x1d88f {
    lda.b #0xb8 - 8
}
; The rolling treasure screen NOPs $01:D811-$01:D819 (treasure_rolling_patches.s).
.alloc at 0x1d792 {
_treasure_menu_entry:
}

; Swap redraw resets the rolling buffer.
.alloc at 0x01A401 {
    jmp.w swap_redraw_trampoline  ; was `jsr $A172`
}

.alloc _item_description_skip_check in bank01_slack {
check_if_description_was_rendered:
"""
Skips the description redraw while a pad button is held or when A matches `render.last_drawn_text_ptr`.
"""


    pha
    lda.l cpu_regs.PAD1L
    ora.l cpu_regs.PAD1H
    bne _not_still
    pla
    pha

    cmp.l render.last_drawn_text_ptr
    bne _continue

_not_still:
    pla
    rts

_continue:
    sta.l render.last_drawn_text_ptr

    pla

    pha
    ldy.w #0xdcd6
    jmp item_desc_back
}

.alloc _find_item_description in bank20_reloc {
find_item_description:
"""
$45 = a description number: Y = that string's offset in `item_descriptions`. Vanilla's search counted every zero
byte, the line break's position word too. M = 8 bits, X = 16 bits.
"""
    ldx.w #item_descriptions & 0xFFFF
_skip_string:
    lda.l item_descriptions & 0xFF0000, x
    inx
    cmp #0x01
    bne _not_line_break
    inx  ; its position word
    inx
    bra _skip_string
_not_line_break:
    cmp #0x00
    bne _skip_string
    dec.b 0x45
    bne _skip_string
    txy
    rtl
}

; なにもありません and the label redrawn after an item message, in the small VWF
.alloc at 0x01A300 {
    load_system_menu_text_pointer(items_menu.nothing_here)
}
.alloc at 0x01A387 {
    load_system_menu_text_pointer(items_menu.item + 4)  ; DrawPosText: the label after the window
}
; the item refusals' window ($01:A5E0 is its only reader) and texts, in the small VWF
.alloc at 0x01DCDA {
    menu_window(5, 10, 20, 2)
}
.alloc at 0x01A5D6 {
    load_system_menu_text_pointer(items_menu.no_effect)
}
.alloc at 0x01A6F2 {
    load_system_menu_text_pointer(items_menu.no_effect)
}
.alloc at 0x01A6BF {
    load_system_menu_text_pointer(items_menu.not_needed)
}
.alloc at 0x01A7BF {
    load_system_menu_text_pointer(items_menu.not_needed)
}
.alloc at 0x01A8E4 {
; a summon learned from its item
    load_system_menu_text_pointer(items_menu.summon_learned)
}
.alloc at 0x01A8F6 {
; the summon's name, after "a appris"
    ldx.w #18 * 2 + 12 * 64
}
