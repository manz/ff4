"""
Battle tasks wired into the battle graphics loop: run_tasks after RedrawMainMenu in WaitFrameMain, and the first
task, the status text, drawn when UpdateObjBuf's copy of the status bytes sees a change instead of on every pass.
"""
.import "vanilla"
.import "battle/tasks"
.include "../bank20.i"
.include "src/battle/bank02_trampolines.i"

.label _redraw_main_menu_96c8 = 0x0296C8

.alloc _battle_tasks_bank02 in bank02_trampolines {
battle_frame_tasks:
"""WaitFrameMain's RedrawMainMenu, then this pass's tasks."""
    jsr.w _redraw_main_menu_96c8
    jsr.l battle_task.run_far
    rts

draw_status_text_far:
"""DrawStatusText ($02:A2A1) for the status task."""
    jsr.w draw_status_text
    rtl
}

.alloc at 0x0282A1 {
; WaitFrameMain: `jsr RedrawMainMenu`
    jsr.w battle_frame_tasks
}

.alloc at 0x02893D size 12 {
; UpdateObjBuf: the 4 status bytes of a character slot, copied with a change check that raises SIG_STATUS
    jsr.l status_copy_signal
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
}

.alloc _battle_status_task in bank20_reloc {
status_copy_signal:
"""
UpdateObjBuf's status copy ($02:893D, M = X = 16 bits): $7E:2003,X and $2005,X into $F015,Y and $F017,Y, raising
SIG_STATUS when either word changes. DB = $7E as in vanilla. Keeps X and Y.
"""
    lda.w 0x2003, x
    cmp.w 0xF015, y
    beq _first_same
    sta.w 0xF015, y
    jsr.w _raise_status
_first_same:
    lda.w 0x2005, x
    cmp.w 0xF017, y
    beq _second_same
    sta.w 0xF017, y
    jsr.w _raise_status
_second_same:
    rtl

_raise_status:
    php
    sep #0x20
    lda.b #SIG_STATUS
    jsr.l battle_task.signal
    plp
    rts

status_text_task:
"""Draw the status text whenever a character's status bytes change."""
    lda.b #SIG_STATUS
    jsr.w battle_task.wait
    jsr.l draw_status_text_far
    bra status_text_task

battle_tasks_seed:
"""Battle start: stop leftover tasks, start the status task and draw the status text once. Callable with JSL."""
    php
    sep #0x20
    rep #0x10
    jsr.l battle_task.reset
    lda.b #0x00
    ldx.w #status_text_task
    ldy.w #0x0000
    jsr.l battle_task.start
    lda.b #SIG_STATUS
    jsr.l battle_task.signal
    plp
    rtl
}
