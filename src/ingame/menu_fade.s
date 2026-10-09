"""
Menu transitions fade with the menu's own FadeOut / FadeIn, as Config always did: the first window change of a
transition (OpenWindow, CloseWindow or TransformWindow, ingame/instant_windows.s) fades the screen out, and the
menu fades back in the next time it polls the pad (UpdateCtrlMenu), once the new screen is built. A screen already
dark (Config and Save fade themselves, the menu opening) is left alone.
"""
.import "sram_layout"
.include "src/ingame/bank01_slack.i"

.label _fade_in_9464 = 0x019464
.label _fade_out_947e = 0x01947E
.label _update_ctrl_far_82b6 = 0x0182B6
.label _play_fanfare_0fc600 = 0x0FC600

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
