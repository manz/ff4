"""
Deferred VRAM uploads for the menu's small VWF, drained at the end of the menu's vblank wait.

Menu code does its transfers on the main thread right after WaitVblank ($01:818A) returns, and every menu screen
paces itself through that wait. A string's tiles are copied into a staging area when pushed (the render buffer is
reused by the next string) and uploaded after the next wait, before the caller's own tilemap transfer, oldest
first, at most _DRAIN_BUDGET bytes a vblank. The oldest entry always goes, so a large one can't starve. A full
queue falls back to waiting for a vblank and uploading everything. Baked tiles (push_rom) go straight from ROM.
"""
.import "preamble"
.import "sram_layout"
.import "libmz"
.include "src/vwf_state.i"
.include "../bank20.i"

_ENTRY := 8  ; VRAM word, source address, bytes, source bank
_STAGING_BYTES := 0x1000
_DRAIN_BUDGET := 0x0400  ; bytes a vblank, beside the menu's own tilemap transfers
.assert sizeof(VramQueue.entries) == VRAM_QUEUE_SLOTS * _ENTRY, "one entry per queue slot"
.assert sizeof(vram_queue_staging) == _STAGING_BYTES, "staging size"

.alloc at 0x0181B5 {
; WaitVblank's tail: its brightness store, then the queue, in the vblank it waited for
    jsl vram_queue.wait_tail
    pla
    rts
}

.alloc _vram_queue in bank20_reloc {
    .scope vram_queue {
    """Push from the renderer, drain from the vblank wait."""
wait_tail:
"""WaitVblank's end ($01:81B5, D = $0100): the brightness store it replaces, then up to _DRAIN_BUDGET bytes."""
    lda.b 0x88
    sta.l ppu.INIDISP
    php
    rep #0x30
    pha
    phx
    phy
    lda.w #_DRAIN_BUDGET
    jsr.w _drain
    ply
    plx
    pla
    plp
    rtl

push:
"""Queue A bytes from VWF_CHR_BUFFER's bank, offset X, for VRAM word Y. M = X = 16 bits."""
    php
    rep #0x30
    pha  ; 5,s bytes
    phx  ; 3,s source
    phy  ; 1,s VRAM word
    lda.l vram_queue_state.count
    cmp.w #VRAM_QUEUE_SLOTS
    bcs _full
    lda.l vram_queue_state.staging_used
    clc
    adc 5, s
    cmp.w #_STAGING_BYTES + 1
    bcc _room
_full:
    jsr.w flush
_room:
    jsr.w _entry_offset
    lda 1, s
    sta.l vram_queue_state.entries, x
    lda.l vram_queue_state.staging_used
    clc
    adc.w #vram_queue_staging & 0xFFFF
    sta.l vram_queue_state.entries + 2, x
    lda 5, s
    sta.l vram_queue_state.entries + 4, x
    lda.w #vram_queue_staging >> 16
    sta.l vram_queue_state.entries + 6, x
    lda.l vram_queue_state.staging_used
    tay
    lda 3, s
    tax
    lda 5, s
    lsr
    pha  ; words left; the frame moves down by 2
_copy_word:
    lda.l VWF_CHR_BUFFER & 0xFF0000, x
    phx
    tyx
    sta.l vram_queue_staging, x
    plx
    inx
    inx
    iny
    iny
    lda 1, s
    dec
    sta 1, s
    bne _copy_word
    pla
    lda.l vram_queue_state.staging_used
    clc
    adc 5, s
    sta.l vram_queue_state.staging_used
    lda.l vram_queue_state.count
    inc
    sta.l vram_queue_state.count
    ply
    plx
    pla
    plp
    rts

push_rom:
"""Queue A bytes from ROM at X, bank vram_queue_state.source_bank, for VRAM word Y. M = X = 16 bits."""
    php
    rep #0x30
    pha  ; 5,s bytes
    phx  ; 3,s source
    phy  ; 1,s VRAM word
    lda.l vram_queue_state.count
    cmp.w #VRAM_QUEUE_SLOTS
    bcc _rom_room
    jsr.w flush
_rom_room:
    jsr.w _entry_offset
    lda 1, s
    sta.l vram_queue_state.entries, x
    lda 3, s
    sta.l vram_queue_state.entries + 2, x
    lda 5, s
    sta.l vram_queue_state.entries + 4, x
    lda.l vram_queue_state.source_bank
    sta.l vram_queue_state.entries + 6, x
    lda.l vram_queue_state.count
    inc
    sta.l vram_queue_state.count
    ply
    plx
    pla
    plp
    rts

_entry_offset:
"""X = the next free entry's offset. M = X = 16 bits."""
    lda.l vram_queue_state.count
    asl
    asl
    asl  ; * _ENTRY
    tax
    rts

flush:
"""Wait for a vblank and upload everything queued. M = X = 16 bits."""
    sep #0x20
    jsr.w wait_for_vblank
    rep #0x20
    lda.w #0xFFFF

_drain:
"""Upload queued entries while A bytes of budget last (the first one regardless). M = X = 16 bits."""
    pha  ; 1,s budget left
_drain_next:
    lda.l vram_queue_state.next
    cmp.l vram_queue_state.count
    bcs _drained
    asl
    asl
    asl  ; * _ENTRY
    tax
    lda 1, s
    cmp.l vram_queue_state.entries + 4, x
    bcs _fits
    cmp.w #_DRAIN_BUDGET
    bne _budget_spent  ; something went this vblank: the rest waits
_fits:
    sec
    sbc.l vram_queue_state.entries + 4, x
    bcs _budget_kept
    lda.w #0x0000
_budget_kept:
    sta 1, s
    jsr.w _dma_entry
    lda.l vram_queue_state.next
    inc
    sta.l vram_queue_state.next
    bra _drain_next
_drained:
    jsr.w clear
_budget_spent:
    pla
    rts

clear:
"""Drop everything queued: the menu's VRAM changes hands (menu_vram.s save / restore)."""
    php
    rep #0x20
    lda.w #0x0000
    sta.l vram_queue_state.count
    sta.l vram_queue_state.next
    sta.l vram_queue_state.staging_used
    plp
    rts

_dma_entry:
"""Channel 7: the entry at X to VRAM. M = X = 16 bits."""
    sep #0x20
    lda.b #0x80
    sta.l ppu.VMAIN
    lda.b #0x01  ; two registers, VMDATAL / VMDATAH
    sta.l dma_ch7.DMAP
    lda.b #PPU.VMDATAL
    sta.l dma_ch7.BBAD
    lda.l vram_queue_state.entries + 6, x
    sta.l dma_ch7.A1B
    rep #0x20
    lda.l vram_queue_state.entries, x
    sta.l ppu.VMADDL
    lda.l vram_queue_state.entries + 2, x
    sta.l dma_ch7.A1TL
    lda.l vram_queue_state.entries + 4, x
    sta.l dma_ch7.DASL
    sep #0x20
    lda.b #0x80
    sta.l cpu_regs.MDMAEN
    rep #0x20
    rts
    }
}
