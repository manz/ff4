"""
ROM patches that wire the battle magic system to the relocated `draw_magic_list_direct` renderer + the
long-form attack-name copier.
"""
.import "assets"
.import "battle/magic_reloc"
.import "vanilla"


; $02:9A69 (vanilla JSR $A070, InitMagicListTextBuf) is replaced by the walker hook in
; redraw_writer_patches.s; the two-column display drives its own buffer.
.alloc at 0x029834 {
    ldx.w #24 * 4
}
.alloc at 0x02982F {
    ldx.w #24 * 4 * 2
}
.alloc at 0x16fe1c {
; Spell-list tilemap upload length (vanilla 0x400): rows 1-24 of spells
; plus the bottom-edge row 25 `draw_magic_list_direct` draws.
    .dw 0x640
}
.alloc at 0x029839 {
_transfer_white_magic:
    ldx.w #0x0000  ; white magic
    phx
    stx 0x06
    lda.w battle_selected_char
    sta 0x00
    jsr.l draw_magic_list_direct
    lda #0x02  ; spell list
    ldy.w #0x0002
    jsr.w load_menu_tfr_data
    lda #0x01
    sta.w menu_tilemap_tfr_count  ; 1 transfer
    sta.w menu_tilemap_tfr_enable  ; enable menu tilemap vram transfer
    plx
    rts
}
.alloc at 0x029ead {
_draw_magic_list:
    lda 0x00  ; character slot
    asl
    tax
    rep #0x20
    lda.l magic_list_ptrs, x  ; pointers to spell lists
    clc
    adc 0x06  ; add magic type offset
    sta 0x00
    tdc
    sep #0x20
    rts

_draw_letter_far:
"""Far-callable wrapper around original draw_letter ($02A497)."""
    pha
    tdc
    sta.l 0x7FFFFF
    pla
    jsr.w draw_letter  ; Original draw_letter
    rtl

; attack name window
}
.alloc at 0x02cbcc {
    lda.b #battle_magic_length
}
.alloc at 0x02cbdd {
    lda.l magic_names, x
}
.alloc at 0x02cbe6 {
    cpy.w #battle_magic_length + 1
}
.alloc at 0x02cba2 {
    sec
    sbc #0x48

    rep #0x20
    and.w #0x00ff
    asl
    tax
; force the longest one.
; ldx.w #51* 2
    lda.l attack_name_pointers, x
    tax
    sep #0x20

    tdc
    tay

loop:
"""Inner loop of the attack-name copier: stream attack-name bytes into the format buffer."""
    lda.l attack_name_text, x
    sta 0x74fd, y
    beq exit
    iny
    inx
    bra loop

exit:
"""Tail of `loop`: jump to original attack-name window display."""
    jmp.w draw_attack_name_window  ; display monster? attack name window

; attack window position
}
.alloc at 0x029369 {
    ldx.w #0x0009

; attack window size
}
.alloc at 0x02936f {
    ldx.w #0x040e
}
.alloc at 0x029382 {
    ldx.w #0xdb50 - 4 - 2 - 16


; cursor and scrolling
}
.alloc at 0x02B72B {
    cmp #11
}
.alloc at 0x02B781 {
    cmp #1
}
.alloc at 0x02B712 {
    nop
    nop
}
.alloc at 0x02B71C {
    nop
    nop
}
.alloc at 0x02B751 {
;    INC     D,$63
    nop
    nop
}
.alloc at 0x02B742 {
    nop
    nop
}
; Battle list hand Y per visible row ($16:FC5B), read by both the item
; cursor ($02:B594) and the spell cursor ($02:B7B9). Both lists now draw
; VWF names on each 16-px row's bottom tile line, lower in the cell than
; the 8x8 font's glyphs, so the hand comes down _LIST_CURSOR_Y_NUDGE
; pixels to point at the middle of the name.
_LIST_CURSOR_Y_FIRST := 0x9C  ; vanilla row 0
_LIST_CURSOR_Y_PITCH := 12  ; vanilla row step
_LIST_CURSOR_Y_NUDGE := 2
.alloc at 0x16FC5B {
    .for row := 0, 5 {
    .db _LIST_CURSOR_Y_FIRST + _LIST_CURSOR_Y_NUDGE + row * _LIST_CURSOR_Y_PITCH
    }
}
.alloc at 0x16FC56 {
    .db 8 - 8
    .db 0x3C + 8 * 3 + 4 - 8
}
.alloc at 0x02B764 {
    inc 0x5F
;inc 0x5F
    nop
    nop
    inc 0x63
;inc 0x63
    nop
    nop
}
.alloc at 0x02B785 {
    dec 0x5F
;dec 0x5F
    nop
    nop
    dec 0x63
;dec 0x63
    nop
    nop
}
.alloc at 0x02A567 {
    lda #9
}
.alloc at 0x02A573 {
    lda.l magic_names, x
}
.alloc at 0x02A57E {
    lda.l magic_names + 1, x
}
.alloc at 0x02A57A {
    lda #9 - 1
}
