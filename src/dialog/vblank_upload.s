"""
The dialogue VWF's VRAM uploads, run by the field NMI at the start of vblank instead of by the main thread after it.

The main thread used to poll for vblank (wait_for_vblank) and DMA right after, racing the field NMI's own transfers
for the same vblank: a long NMI pushed the DMA past vblank, where the PPU drops VRAM writes. Now a caller pushes its
transfers, then waits as before: FieldNMI drains them before its sprite transfer, the wait returns in the same
vblank. When no field NMI drained them (NMI off, another screen's NMI), the wait uploads them itself, as before:
nothing can hang on a missing drain. One vblank per wait, as before.
"""
.import "core/preamble"
.import "core/sram_layout"
.import "core/libmz"
.include "core/bank20.i"

.label _tfr_sprites = 0x15CADC
_ENTRY := 8  ; VRAM word, source, bytes, source bank
_VRAM_INCREMENT := 0x80  ; VMAIN: +1 word after the high byte
_DMA_TO_VRAM := 0x1801  ; DMAP: two registers, VMDATAL/H
_CHANNEL := 7

.alloc at 0x0092C9 {
; FieldNMI, DP and DB set: `jsl TfrSprites`
    jsl vblank_upload.drain
}

.alloc _vblank_upload in bank20_reloc {
    .scope vblank_upload {
    """Push from the dialogue VWF, drain from the field NMI or the wait."""
drain:
"""FieldNMI ($00:92C9, M = 8, X = 16 bits): the queued uploads, then the TfrSprites it replaces."""
        jsr.w _upload_all
        jml _tfr_sprites

push:
"""Queue A bytes at `vblank_uploads.bank`:X for VRAM word Y; a full queue waits a vblank first. M = X = 16 bits."""
        php
        rep #0x30
        pha  ; 3,s bytes
        phx  ; 1,s source
        lda.l vblank_uploads.count
        cmp.w #VBLANK_UPLOAD_SLOTS
        bcc _room
        jsr.w wait
_room:
        lda.l vblank_uploads.count
        asl
        asl
        asl
        tax
        tya
        sta.l vblank_uploads.entries, x
        lda 1, s
        sta.l vblank_uploads.entries + 2, x
        lda 3, s
        sta.l vblank_uploads.entries + 4, x
        lda.l vblank_uploads.bank
        sta.l vblank_uploads.entries + 6, x
        lda.l vblank_uploads.count  ; last: an NMI drains only whole entries
        inc
        sta.l vblank_uploads.count
        plx
        pla
        plp
        rts

wait:
"""Wait for the next vblank; upload what its NMI did not. Any width, registers kept."""
        php
        sep #0x20
        jsr.w wait_for_vblank
        jsr.w _upload_all
        plp
        rts

_upload_all:
"""Upload every queued entry, oldest first, and empty the queue. Any width, registers kept; DB = $00-$3F."""
        php
        rep #0x30
        pha
        phx
        lda.l vblank_uploads.count
        beq _empty
        ldx.w #0x0000
_entry:
        sep #0x20
        lda.b #_VRAM_INCREMENT
        sta.w ppu.VMAIN
        rep #0x20
        lda.l vblank_uploads.entries, x
        sta.w ppu.VMADDL
        lda.l vblank_uploads.entries + 2, x
        sta.w dma_ch7.A1TL
        lda.l vblank_uploads.entries + 4, x
        sta.w dma_ch7.DASL
        lda.w #_DMA_TO_VRAM
        sta.w dma_ch7.DMAP
        sep #0x20
        lda.l vblank_uploads.entries + 6, x
        sta.w dma_ch7.A1B
        lda.b #1 << _CHANNEL
        sta.w cpu_regs.MDMAEN
        rep #0x20
        txa
        clc
        adc.w #_ENTRY
        tax
        lda.l vblank_uploads.count
        dec
        sta.l vblank_uploads.count
        bne _entry
_empty:
        plx
        pla
        plp
        rts
    }
}
