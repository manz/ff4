"""
Battle tasks wired into the battle graphics loop: run_tasks after RedrawMainMenu in WaitFrameMain, and the first
task, the status text: drawn and transferred when UpdateObjBuf's copy of the status bytes sees a change, instead of
on every pass and every eighth frame.
"""
.import "vanilla"
.import "battle/tasks"
; root-scope extern: inventory_rolling_patches reaches this module back through redraw_gates
.extern draw_battle_command_window_relocated
.include "../bank20.i"
.include "src/battle/bank02_trampolines.i"

.label _redraw_main_menu_96c8 = 0x0296C8
.label _tfr_status_tiles_99b9 = 0x0299B9
.label _draw_main_menu_99ca = 0x0299CA
_MAIN_MENU_TEXT_START := 0xB966  ; character names, then HP ($B9DE), then monster names ($BB1E, 8 x $14 x 2)
_MAIN_MENU_TEXT_END := 0xBB1E + 8 * 0x14 * 2
_MENU_TFR_PENDING := 0x7E1824  ; vanilla: a menu tilemap transfer is queued

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

draw_command_window_far:
"""The command window (draw_battle_command_window_relocated): list, mirror of the main view, frame, text, upload."""
    jsr.w draw_battle_command_window_relocated
    rtl

draw_main_menu_far:
"""DrawMainMenu ($02:99CA): copy the monster names, character names and HP into the main view, queue its transfer."""
    jsr.w _draw_main_menu_99ca
    rtl

draw_text_entry:
"""DrawText's first instruction (`lda $EF55`), after raising SIG_MAIN_MENU if it draws into the main menu's text."""
    jsr.l text_destination_signal
    lda.w 0xEF55
    rts

tfr_status_tiles_far:
"""TfrStatusTiles ($02:99B9): queue the status tilemap's transfer (one pending transfer at a time, $1824)."""
    jsr.w _tfr_status_tiles_99b9
    rtl
}

.alloc at 0x02A455 {
; DrawText: `lda $EF55`
    jsr.w draw_text_entry
}

.alloc at 0x0296CE {
; RedrawMainMenu: `jsr DrawObjNames` (gated) and `jmp DrawCharHP` every pass; the main menu task copies them on
; SIG_MAIN_MENU
    nop
    nop
    nop
    rts
    nop
    nop
}

.alloc at 0x0296B0 {
; PeriodicMenuUpdate's two DrawMainMenu slots (every fourth frame)
    .dw 0x949A  ; rts
}

.alloc at 0x0296B0 + 6 * 2 {
    .dw 0x949A  ; rts
}

.alloc at 0x0296B0 + 5 * 2 {
; PeriodicMenuUpdate's UpdateStatusTiles slot: the status task draws and transfers on SIG_STATUS instead of every
; eighth frame
    .dw 0x949A  ; rts
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

text_destination_signal:
"""SIG_MAIN_MENU when DrawText's destination ($EF52) lies in the main menu's text buffers. Keeps A/X/Y and P."""
    php
    rep #0x20
    pha
    lda.l 0x7EEF52
    cmp.w #_MAIN_MENU_TEXT_START
    bcc _not_main_menu
    cmp.w #_MAIN_MENU_TEXT_END
    bcs _not_main_menu
    sep #0x20
    lda.b #SIG_MAIN_MENU
    jsr.l battle_task.signal
_not_main_menu:
    rep #0x20
    pla
    plp
    rtl

menu_task:
"""
The battle menu windows, redrawn only when something they show changed: the status text (SIG_STATUS), the names and
HP of the main view (SIG_MAIN_MENU), the command window (SIG_COMMANDS, and after the main view under it changed).
The status and main view go through vanilla's single menu transfer slot ($1824): wait for it to be free.
"""
    lda.b #SIG_STATUS | SIG_MAIN_MENU | SIG_COMMANDS
    jsr.w battle_task.wait
    pha  ; the bits that woke the task, kept on its stack across the yields below
    and.b #SIG_STATUS
    beq _menu_main
    jsr.l draw_status_text_far
    jsr.w _menu_wait_transfer_slot
    jsr.l tfr_status_tiles_far
_menu_main:
    lda 1, s
    and.b #SIG_MAIN_MENU
    beq _menu_commands
    jsr.w _menu_wait_transfer_slot
    jsr.l draw_main_menu_far
    lda 1, s
    ora.b #SIG_COMMANDS  ; the command window mirrors the main view under it
    sta 1, s
_menu_commands:
    pla
    and.b #SIG_COMMANDS
    beq menu_task
    jsr.l draw_command_window_far
    bra menu_task

_menu_wait_transfer_slot:
"""Yield until no menu tilemap transfer is queued."""
    lda.l _MENU_TFR_PENDING
    beq _menu_slot_free
    jsr.w battle_task.yield
    bra _menu_wait_transfer_slot
_menu_slot_free:
    rts

signal_commands:
"""SIG_COMMANDS for the command-dirty writers (battle/redraw_gates.s). Keeps A and P."""
    php
    sep #0x20
    pha
    lda.b #SIG_COMMANDS
    jsr.l battle_task.signal
    pla
    plp
    rtl

battle_tasks_seed:
"""Battle start: stop leftover tasks, start the menu task and draw every window once. Callable with JSL."""
    php
    sep #0x20
    rep #0x10
    jsr.l battle_task.reset
    lda.b #0x00
    ldx.w #menu_task
    ldy.w #0x0000
    jsr.l battle_task.start
    lda.b #SIG_STATUS | SIG_MAIN_MENU | SIG_COMMANDS
    jsr.l battle_task.signal
    plp
    rtl
}
