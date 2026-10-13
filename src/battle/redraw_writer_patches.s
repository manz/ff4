"""
Writer-site patches that mark the cmd-window dirty bit when battle state changes (counterpart to the reader gate in
`commands_reloc.s` and the shims in `redraw_gates.s`). Main writer: the ATB "pick new active char" site writing
`$1822`, which battle init and every turn rotation go through. Also: the monster-death hook, the NMI-safe
UpdateFlyingHDMA patches and the bank-02 helper pool for the gated trampolines.
"""


.import "battle/render_state"


.import "battle/redraw_gates"
.import "battle/tasks_patches"
.import "battle/sram"
.import "core/vanilla"

; UpdateMenu $03:A481: pla / sta $1822 / sta $d0 / jsr ValidateArrows. The 5 bytes at $03:A482 become a JSL to a shim
; that does both stores, sets the cmd dirty bit and invalidates the active-char highlight cache.
.alloc at 0x03A482 {
    jsr.l set_active_char_and_dirty
    .db 0xEA  ; nop padding so $03:A487 still aligns to `jsr ValidateArrows`
}

; UpdateDead $03:B1A0: the 4-byte prelude (tdc; tax; stx $a9) becomes a JSL that ORs in REGION_DIRTY_MONSTERS and
; replays it. Fires on every dead-status apply; the gated monster-name trampoline redraws next frame.
.alloc at 0x03B1A0 {
    jsr.l mark_monsters_dirty_and_init
}

; UpdateFlyingHDMA ($02:82E1) spin-waits on the IRQ flag $f353 at $02:82E8. Called from the NMI the IRQ never fires
; and it hangs; HDMA is idle in vblank anyway. Main-loop callers still work.
.alloc at 0x0282E8 {
    nop
    nop
    nop
    nop
    nop
}

; UpdateObjPos's jsr UpdateFlyingHDMA at $02:82BC: dma_transfer already runs it every vblank (~5K cycles/NMI saved).
.alloc at 0x0282BC {
    nop
    nop
    nop

; Free space left by TfrEquipWindow's relocation (items_patches.s). `strategy order` keeps the helpers at stable
; addresses for the bank-02 jsr.w callers.
    .pool bank02_battle_redraw_helpers {
    range 0x0297AB 0x029824
    strategy order
    }
}
.alloc _battle_redraw_helpers in bank02_battle_redraw_helpers {
; Gated trampolines: init -> DrawText -> deinit still runs every frame so battle_flags stay symmetric for other VWF
; callers. A clean region makes init_*_gated set render_skipped = $FF: DrawText and the DMA signal are skipped and
; the VRAM tilemap from the last render stays.
msg_monster_window_gated:
"""Gated DrawMonsterNames trampoline (monsters region dirty bit)."""
    jsr.l messages_vwf.init_monsters_gated
    lda.l battle_render_state.render_skipped
    bne _mmwg_after_draw
    jsr.w draw_text
_mmwg_after_draw:
    jsr.l messages_vwf.deinit_gated
    rts
flying_hdma_trampoline:
"""
Bank-02 RTL wrapper around vanilla `UpdateFlyingHDMA` ($02:82E1), JSL'd from `dma_transfer`. The NMI leaves M=X=16;
vanilla needs M=8, or the BG V-scroll entries all get 0 and the flying animation freezes.
"""


    php
    rep #0x30
    lda.w #0x0000
    sep #0x20
    jsr.w update_flying_hdma
    plp
    rtl
; Battle_ext ($03:8000) runs exactly once per battle (field jsl, menu jml); InitMenuWindows ($02:9A63) is no seed
; point, a kss restore can skip it. JML is 4 bytes over the 3-byte `jmp ExecBattle`: it clobbers 1 byte of
; Battle_ext2, which has no callers.
battle_ext_seed:
"""Battle_ext root tail: seed redraw-gate state then jump ExecBattle."""
    jsr.l reset_queue_dirty_bits
    jsr.l battle_tasks_seed  ; battle/tasks_patches.s
    jmp.l exec_battle
gate_draw_status_text:
"""RedrawMainMenu's DrawStatusText slot: the active-char highlight refresh; the menu task draws the text."""
; RedrawMainMenu's first call, every frame. DrawCharNames runs only a few frames per battle, so it can't host this.
    jsr.l refresh_active_char_palette
    rts
; Takes the $02:9A69 slot (jsr InitMagicListTextBuf, unneeded): stamps the palette right after UpdateCharNames built
; $B966; later init steps write other regions ($B9DE, $BB1E).
walker_helper:
"""5-byte bank-02 trampoline: JSL bank-20 walker, RTS to caller."""
    jsr.l walker_rtl
    rts
msg_names_window_gated:
"""Gated DrawCharNames trampoline (names region dirty bit)."""
    lda.b btlgfx_dp.menu_windows_open
; bit 2 = inventory open: skip the whole pipeline
    and.b #0x04
    bne _mnwg_done
    jsr.l messages_vwf.init_names_gated
    lda.l battle_render_state.render_skipped
    bne _mnwg_after_draw
    jsr.w draw_text
_mnwg_after_draw:
    jsr.l messages_vwf.deinit_gated
; A render rebuilt the names tilemap without the highlight, and menu open/close has no writer site: re-stamp.
    jsr.l refresh_active_char_palette
_mnwg_done:
    rts
}

; Battle_ext entry -> seed helper
.alloc at 0x038000 {
    jmp.l battle_ext_seed
}
; RedrawMainMenu's jsr DrawStatusText -> gate
.alloc at 0x0296C8 {
    jsr.w gate_draw_status_text
}

; Battle-init palette stamp (replaces the InitMagicListTextBuf jsr).
.alloc at 0x029A69 {
    jsr.w walker_helper
}
