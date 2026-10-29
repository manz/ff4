"""
Menu transitions fade with the menu's own FadeOut / FadeIn, as Config always did: the first window change of a
transition (OpenWindow, CloseWindow or TransformWindow, ingame/instant_windows.s) fades the screen out, and the
menu fades back in the next time it polls the pad (UpdateCtrlMenu), once the new screen is built. A screen already
dark (Config and Save fade themselves, the menu opening) is left alone.
"""
.import "core/sram_layout"
.include "ingame/bank01_slack.i"

.label _fade_in_9464 = 0x019464
.label _fade_out_947e = 0x01947E
.label _update_ctrl_far_82b6 = 0x0182B6
.label _play_fanfare_0fc600 = 0x0FC600
.label _play_sfx_038006 = 0x038006
.label _tfr_bg2_tiles_9423 = 0x019423
.label _tfr_bg4_tiles_943d = 0x01943D

.alloc at 0x0182C0 {
; UpdateCtrlMenu's pad read: the menu is ready for input, so the screen it built can come back
    jsr.w menu_fade_ready
}

.alloc _menu_fade in bank01_slack {
menu_fade_out:
"""Fade out for a window change unless this transition already did, or the screen is dark ($88 bit 7 or 0)."""
    lda.l menu_faded_out
    bne _faded
    lda 0x88
    bmi _faded
    beq _faded
    jsr.w _fade_out_947e
    lda.b #0x01
    sta.l menu_faded_out
_faded:
    rts
menu_fade_ready:
"""UpdateCtrlMenu's pad read, after fading back in the screen a transition built."""
    jsr.w menu_fade_in
    jmp.w _update_ctrl_far_82b6
menu_fade_in:
"""Fade back in the screen a transition built, if it faded out."""
    lda.l menu_faded_out
    beq _lit
    lda.b #0x00
    sta.l menu_faded_out
    jsr.w _fade_in_9464
_lit:
    rts
menu_fanfare_lit:
"""PlayFanfare after fading in: the summon-learned window waits through the fanfare without reading the pad."""
    jsr.w menu_fade_in
    jml.l _play_fanfare_0fc600
}

.alloc at 0x01A902 {
; the summon-learned fanfare ($0F:C600, ends in RTL): fade in first; its RTL returns here
    jsl.l menu_fanfare_lit
}

.alloc _menu_fade_exits in bank01_slack {
menu_equip_exit:
"""Equip's exit: fade out before it rebuilds the main menu, then the sound it replaces ($01:BC76)."""
    jsr.w menu_fade_out
    lda 0xE8
    jsl.l _play_sfx_038006
    rts
menu_magic_exit:
"""Magic's exit: fade out before it drops its sprites, then the store it replaces ($01:B041)."""
    jsr.w menu_fade_out
    lda.b #0x30
    sta 0x3F
    rts
}

; Equip and Magic redraw the main menu's cell lit before TransformWindow fades: fade first, and upload the restored
; screens without waiting for vblank (the screen is blanked, and no window animates from them any more).
.alloc at 0x01BC76 {
    jsr.w menu_equip_exit
    nop
    nop
    nop
}

.alloc at 0x01BC82 {
    jsr.w _tfr_bg4_tiles_943d
}

.alloc at 0x01BCAD {
    jsr.w _tfr_bg4_tiles_943d
}

.alloc at 0x01BCB8 {
    jsr.w _tfr_bg2_tiles_9423
}

.alloc at 0x01B041 {
    jsr.w menu_magic_exit
    nop
}

.alloc at 0x01B054 {
    jsr.w _tfr_bg4_tiles_943d
}
