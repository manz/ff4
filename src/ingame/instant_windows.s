"""
Instant menu windows: OpenWindow, CloseWindow and TransformWindow (bank $01) reach their last frame at once.

The window art and its scroll offsets end exactly as before: TransformWindow still steps every window edge and
every scroll rate (the fractional scroll positions and the edge fills come out identical), only the per-frame
vblank wait, BG transfer and scroll-register write move after the loop. Open and Close transfer the 25 rows they
wiped in one DMA. Shop windows open instantly too: they share these routines.
"""
.label _wait_vblank_818a = 0x01818A
.label _tfr_vram_8078 = 0x018078
.label _exec_jump_tbl_834b = 0x01834B
.label _update_scroll_regs_far_94a4 = 0x0194A4
.label _tfr_bg_tiles_tbl_85b8 = 0x0185B8
.label _transform_loop_8526 = 0x018526
.label _transform_rts_858c = 0x01858C

_WINDOW_ROWS_BYTES := 25 * 0x80  ; the 25 two-row steps of the vanilla wipe

.alloc at 0x0183E3 {
; OpenWindow: rows 0-49 of the selected BG's buffer ($29) to its VRAM tilemap ($35), in one vblank
    ldx 0x35
    stx 0x1D
    ldx 0x29
    stx 0x1F
    lda.b #0x7E
    sta 0x21
    ldx.w #_WINDOW_ROWS_BYTES
    stx 0x22
    jsr.w _wait_vblank_818a
    jsr.w _tfr_vram_8078
    stz 0x45
    rts
}

.alloc at 0x018417 {
; CloseWindow: the same rows end in VRAM; "close" is the caller having cleared the buffer
    jmp.w 0x0183E3
}

.alloc at 0x01855E {
; TransformWindow after one edge / scroll step: loop without waiting, then show the final frame once
    jsr.w 0x01CF  ; the portrait mover, still one step per loop
    ldx 0x63
    cpx 0x67
    bne _transform_loop_8526
    ldx 0x65
    cpx 0x69
    bne _transform_loop_8526
    lda.w 0x01C2
    bne _transform_loop_8526
    jsr.w _wait_vblank_818a
    lda 0xC3
    ldx.w #_tfr_bg_tiles_tbl_85b8 & 0xFFFF
    jsr.w _exec_jump_tbl_834b
    jsr.w 0x01CC
    jsr.w _update_scroll_regs_far_94a4
    ldx.w #_transform_rts_858c & 0xFFFF
    stx.w 0x01CD
    stx.w 0x01D0
    rts
}
.assert 0x01855E + 46 == 0x01858C, "TransformWindow's rts must stay at $01:858C, where its hooks point"
