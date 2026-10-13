"""
Pinned-address overlay rewiring original battle-message pointer loads ($02C909, $02CC07, ...) to the relocated
translated-string tables.
"""

.import "core/preamble"
.import "battle/sram_patches"
.import "core/assets"
.import "battle/sram"


.scope message_patches {
    """Pinned-address overlay scope rewriting original battle-message pointer loads to relocated tables."""
; pointers to battle dialog
    .alloc at 0x02c909 {
    lda.l battle_messages, x
    sta 0x00
    lda.l battle_messages + 1, x
    sta 0x01
    lda.w #battle_messages >> 16
    sta 0x02
    }


; pointers to battle messages
    .alloc at 0x02cc07 {
    lda.l battle_texts, x
    sta 0x00
    tdc
    sep #0x20
    lda.b #battle_texts >> 16
    sta 0x02
    }


; Vanilla VRAM: BG3 tiles $B000-$BFFF, BG2 map 64x32 at $B000 ($1000), BG1 map 64x64 at $C000 ($2000),
; BG3 map 64x64 at $E000 ($2000). BG1 shrinks to 32x64 and moves to $D000.
    .alloc at 0x0382f5 {
    lda.b #( 0xd000 >> 9 | 0b01 )
    sta ppu.BG1SC
    lda.b #( 0xc000 >> 9 | 0b01 )
    sta ppu.BG2SC
    }


; teleport resized BG1 & 2 back to their original addresses
    .alloc at 0x02f11a {
    lda.b #( 0xd000 >> 9 | 0b01 )
    sta.l ppu.BG1SC
    lda.b #( 0xc000 >> 9 | 0b01 )
    sta.l ppu.BG2SC
    }


; BG1 move
    .alloc at 0x028B3B {
    ldy.w #0x6000 + 0x800
    }


    .alloc at 0x02bcad {
    ldy.w #0x6000 + 0x800
    }


    .alloc at 0x02BCB2 {
    ldy.w #0x6400 + 0x800
    }


; MP cost transfer destination, was ldy #$5F39
    .alloc at 0x029429 {
    ldy.w #0x5f39 + 0x800
    }


; kick animation, was ldy #$6140
    .alloc at 0x02c6a8 {
    ldy.w #0x6140 + 0x800
    }


; BG1 move, was ldy #$5800
    .alloc at 0x0291FE {
    ldy.w #0x6000
    }


; was ldy #$5C00
    .alloc at 0x02921F {
    ldy.w #0x6400
    }


; Menu defend / row / MP cost init: wram, vram, size
    .alloc at 0x16fdd6 + 6 * 6 {
    .dw 0xd366, 0x6400 + 0x260, 0x0340
    }


    .alloc at 0x16fe0c + 6 * 6 {
    .dw 0xd366, 0x6400 + 0x260, 0x0140
    }


    .alloc at 0x0292F8 {
; move the text buffer pointer back 3 entries
    ldx.w #0xDB2E - 3 * 2
    stx 0xEF52
    jsr.w msg_window_draw_text_trampoline
    }
}


; Battle NMI: transfer the battle render buffer
.alloc at 0x02836e {
    jsr.l messages_vwf.dma_transfer
}
; Bigger message window
.alloc at 0x0292DF {
; (0, 3) (26, 4)
    ldx.w #0x0000
    stx.w 0xEF56
    ldx.w #0x041A + 6
    stx.w 0xEF58
}
