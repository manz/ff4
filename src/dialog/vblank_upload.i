"""Pushing a dialogue VRAM upload for the field NMI (dialog/vblank_upload.s)."""

.macro vblank_upload_push(source, vramptr, count) {
    """Queue `count` bytes at `source` for VRAM word `vramptr`; registers and widths kept."""
    php
    rep #0x30
    pha
    phx
    phy
    lda.w #0x00FF & ( source >> 16 )
    sta.l vblank_uploads.bank
    lda.w #count
    ldx.w #source & 0xFFFF
    ldy.w #vramptr
    jsr.w vblank_upload.push
    ply
    plx
    pla
    plp
}
