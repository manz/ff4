"""
Cooperative tasks for battle graphics, woken by signals.

After cacheguard's src/task.s (itself after Bahamut Lagoon's scheduler): a task is bank-$20 code on its own stack
that gives the CPU back with `task_yield` (next frame), `task_sleep` (N frames) or `task_wait` (until a signal).
`run_tasks` runs once per battle-graphics pass, from WaitFrameMain, and resumes every task that can run.

Signals are what FF4 lacks: vanilla redraws its windows on every pass (RedrawMainMenu) and keeps a single update
request ($181F). Here the code that changes what a window shows raises a bit with `task_signal`; a task waiting on
that bit wakes, draws once, and waits again. FF6's battle menu does a poor man's version with a 16-deep queue of
window states ($7E7BF0), one step a frame.

Slot state: 0 stopped, 1 runnable, 2..$FE asleep (one frame closer each pass), $FF waiting for a signal in its mask.
A suspended task's registers sit on its own stack, top down: return address, P, A, X, Y, DB, D. Tasks share the
battle direct page (D = 0): keep values across a yield on the task's stack, not in DP. Each stack also absorbs the
NMI when vblank lands mid-task (about 29 bytes measured).

The kernel state is SRAM (`battle_tasks`); the stacks must be bank-0 WRAM, in `$1847-$18FF`, unused by vanilla.
"""
.include "../bank20.i"
.import "sram_layout"

TASK_COUNT := 2
TASK_STACK_SIZE := 0x5C
TASK_WAITING := 0xFF

SIG_STATUS := 0x01  ; a character's status bytes changed (UpdateObjBuf's copy)
SIG_MAIN_MENU := 0x02  ; DrawText wrote into the main menu's text buffers (names, HP)

.struct BattleTasks {
    byte[TASK_COUNT] state
    byte[TASK_COUNT] wait_mask
    byte[TASK_COUNT] woken  ; the signal bits that woke each task
    word[TASK_COUNT] sp
    word kernel_sp
    word cur
    byte pending  ; signals raised and not yet taken
    word tmp_slot
    word tmp_entry
    word tmp_arg
    word tmp_caller_sp
}

.reserve battle_tasks as BattleTasks in sram_bank71

.pool battle_task_stack_ram {
    bss
    range 0x7E1847 0x7E18FF
    strategy order
}
.reserve battle_task_stacks TASK_COUNT * TASK_STACK_SIZE in battle_task_stack_ram

.alloc _battle_tasks in bank20_reloc {
    .scope battle_task {
reset:
"""Stop every task and drop pending signals (battle start). Callable with JSL. Keeps A/X/Y."""
    php
    sep #0x20
    pha
    lda.b #0x00
    sta.l battle_tasks.pending
    sta.l battle_tasks.state
    sta.l battle_tasks.state + 1
    pla
    plp
    rtl

start:
"""
Start (or restart) slot A8 at entry X16 (bank $20) with Y16 in its A; it runs from the next run_tasks pass.
Callable with JSL. Clobbers A/X/Y.
"""
    php
    rep #0x30
    and.w #0x00FF
    sta.l battle_tasks.tmp_slot
    txa
    dec  ; the resume rts lands on the entry
    sta.l battle_tasks.tmp_entry
    tya
    sta.l battle_tasks.tmp_arg
    tsc
    sta.l battle_tasks.tmp_caller_sp
; the slot's resume frame, on its own stack: S = base + (slot + 1) * size - 1
    lda.l battle_tasks.tmp_slot
    inc
    tax
    lda.w #( battle_task_stacks & 0xFFFF ) - 1
_top:
    clc
    adc.w #TASK_STACK_SIZE
    dex
    bne _top
    tcs
    lda.w #exit - 1
    pha  ; the entry routine's rts exits the task
    lda.l battle_tasks.tmp_entry
    pha  ; resume address
    sep #0x20
    lda.b #0x20
    pha  ; P: A8 I16
    rep #0x20
    lda.l battle_tasks.tmp_arg
    pha  ; A
    lda.w #0x0000
    pha  ; X
    pha  ; Y
    sep #0x20
    lda.b #0x7E
    pha  ; DB: battle graphics work on bank $7E
    rep #0x20
    lda.w #0x0000
    pha  ; D
    tsc
    tay
    lda.l battle_tasks.tmp_caller_sp
    tcs  ; back on the caller's stack
    lda.l battle_tasks.tmp_slot
    asl
    tax
    tya
    sta.l battle_tasks.sp, x
    lda.l battle_tasks.tmp_slot
    tax
    sep #0x20
    lda.b #0x01
    sta.l battle_tasks.state, x
    plp
    rtl

signal:
"""Raise signal bits A8: every task waiting on one of them runs on the next pass. Callable with JSL. Keeps A."""
    php
    sep #0x20
    pha
    ora.l battle_tasks.pending
    sta.l battle_tasks.pending
    pla
    plp
    rtl

run_far:
"""run_tasks for bank-$02 callers (WaitFrameMain). Keeps A/X/Y and P."""
    php
    rep #0x30
    pha
    phx
    phy
    phb
    phd
    pea.w 0x0000
    pld
    sep #0x20
    lda.b #0x7E
    pha
    plb
    jsr.w run
    rep #0x30
    pld
    plb
    ply
    plx
    pla
    plp
    rtl

run:
"""Run every task that can, once, in slot order; a waiting task runs when a signal in its mask is pending."""
    rep #0x30
    tsc
    sta.l battle_tasks.kernel_sp
    lda.w #0x0000
    sta.l battle_tasks.cur
_loop:
    rep #0x30
    lda.l battle_tasks.cur
    cmp.w #TASK_COUNT
    bcs _done
    tax
    sep #0x20
    lda.l battle_tasks.state, x
    beq _next
    cmp.b #TASK_WAITING
    bne _not_waiting
    lda.l battle_tasks.wait_mask, x
    and.l battle_tasks.pending
    beq _next
    sta.l battle_tasks.woken, x
    eor.b #0xFF
    and.l battle_tasks.pending
    sta.l battle_tasks.pending  ; taken: a later signal wakes it again
    bra _run
_not_waiting:
    dec
    beq _run
    sta.l battle_tasks.state, x  ; asleep: one frame closer
    bra _next
_run:
    lda.b #0x01
    sta.l battle_tasks.state, x
    rep #0x20
    txa
    asl
    tax
    lda.l battle_tasks.sp, x
    tcs
    pld
    plb
    ply
    plx
    pla
    plp
    rts  ; into the task

yield:
"""Suspend the current task until the next pass."""
    php
    rep #0x30
    pha
    phx
    phy
    phb
    phd
    tsc
    tay
    lda.l battle_tasks.cur
    asl
    tax
    tya
    sta.l battle_tasks.sp, x
    lda.l battle_tasks.kernel_sp
    tcs
_next:
    rep #0x20
    lda.l battle_tasks.cur
    inc
    sta.l battle_tasks.cur
    bra _loop
_done:
    sep #0x20
    rts

sleep:
"""Suspend the current task for A8 passes (1..253)."""
    php
    sep #0x20
    inc
    pha
    rep #0x20
    lda.l battle_tasks.cur
    tax
    sep #0x20
    pla
    sta.l battle_tasks.state, x
    plp
    bra yield

wait:
"""Suspend the current task until a signal in mask A8 is raised; it resumes with the bits that woke it in A8."""
    php
    sep #0x20
    pha
    rep #0x20
    lda.l battle_tasks.cur
    tax
    sep #0x20
    pla
    sta.l battle_tasks.wait_mask, x
    lda.b #TASK_WAITING
    sta.l battle_tasks.state, x
    plp
    jsr.w yield
    rep #0x20
    lda.l battle_tasks.cur
    tax
    sep #0x20
    lda.l battle_tasks.woken, x
    rts

exit:
"""End the current task; it never resumes. Also where an entry routine's rts lands."""
    rep #0x30
    lda.l battle_tasks.cur
    tax
    sep #0x20
    lda.b #0x00
    sta.l battle_tasks.state, x
    rep #0x20
    lda.l battle_tasks.kernel_sp
    tcs
    bra _next
    }
}
