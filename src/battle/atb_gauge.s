"""
The battle ATB gauge, FF6 style: in the party window each character's action timer fills up to their next turn,
where vanilla showed the max HP ("4079/4079" becomes "4079 [gauge]").

HP text ($7E:B9DE): per character two rows of 9 cells, the bottom one the current HP (4), "/" and the max HP (4).
When vanilla redraws a bottom row with its "/" back, the gauge goes over "/max": a left cap and 4 fill cells
(32 px); the right cap goes in the main view's free cell after the row, every pass. The tiles live in the 8x8
font's blank kana slots (utils/atb_gauge.py).

The action timer ($2A07, 21 bytes a fighter) counts battle-main passes down to the turn (4-6 a turn late game); its
full value is what it was last reset to. The fill is the share run out: grey (palette 1) while filling, white once
at 0. Between ticks (all timers at once, ~10 frames apart, none during animations) it moves on with the frames
since the last tick at the last ticks' pace, up to one tick: 32 one-pixel steps a turn instead of 4-6 jumps.
"""
.import "battle/tasks"
.import "core/vanilla"
.import "battle/render_state"
.import "core/wram_layout"
.include "core/bank20.i"
.include "battle/bank02_trampolines.i"

_PARTY := 5
_SETTING := 0x7E16B3  ; ingame/options.s ATB_GAUGE_SETTING: bit 0 shows the gauges (saved, 0 by default)
_SETTING_ON := 0x01
_TIMERS := 0x7E2A07  ; the action timer, a word, per fighter
_DISPLAY_ORDER := 0x02A1F3  ; vanilla: the party window's rows list the slots in this order, present ones only
_RECORDS := 0x7E2000  ; a character per $80, +0 0 for nobody
_HIDDEN := 0x7EF2C1  ; per slot: non-zero hides its name and HP
_TIMER_STRIDE := 21
_TIMER_FLAGS := 0x7E2A09  ; the action timer's flags: $08 = act when it expires (a command was chosen)
_COMMAND_DELAY := 0x08
_HP_TEXT := 0x7EB9DE  ; vanilla's HP text: a row per character
_BOTTOM := 9 * 2  ; the bottom row: the current HP (4 cells), "/", the max HP (4)
_SLASH := _BOTTOM + 4 * 2
_LAST_DIGIT := _BOTTOM + 3 * 2  ; a digit when the row shows a character
_GAUGE := _SLASH
_MAIN_VIEW_HP := 0x7EBED0  ; the HP rows' place in the main view (vanilla's text update): a character per 2 rows of 64
_CAP_CELL := 64 + 9 * 2  ; the cell after the bottom row
_GAUGE_CELL := 64 + 4 * 2  ; the gauge's first cell in the main view
_NMI_WAIT := 0x7E1811  ; vanilla: the frame wait's flag
_MIRROR := 0xC1A5 - 0xBE65  ; the command window's copy of the main view (messages_vwf.mirror_main_to_cmd)
_SLASH_TILE := 0xC7
_DIGIT_0 := 0x80
_FILL_0 := 0xE1  ; utils/atb_gauge.py: fill 0-8 px, then the caps
_CAP_LEFT := 0xEB
_CAP_RIGHT := 0xEC
_FILL_CELLS := 4
_MAX_PERIOD := 40  ; frames: a longer gap between ticks (an animation) paces as this
_MAX_PACED_TIME := 40  ; ticks: longer timers (sleep, paralysis) fill without pacing
_GAUGE_PX := _FILL_CELLS * 8
_PALETTE_MASK := 0x1C
_FILLING_PALETTE := 0x04  ; palette 1, the greyed text's: a full gauge goes back to the text's white (palette 0)

.struct AtbGauge {
    word[_PARTY] timer  ; the action timer last seen
    word[_PARTY] full_time  ; what it was last reset to
    byte[_PARTY] drawn_px  ; per row: the fill drawn, $FF for none
    byte[_PARTY] row_slot  ; per row: its character's slot, as vanilla packs them (scratch)
    byte rows  ; rows showing a character (scratch)
    word row  ; its HP row (scratch)
    byte changed  ; a row was redrawn this pass
    word frames  ; the NMI's frame count (battle_frame_counter) as this update saw it: the pace's clock
    word[_PARTY] last_tick  ; per slot: `frames` at its timer's last tick
    byte[_PARTY] period  ; per slot: frames between its last two ticks, 0 before the second
    byte[_PARTY] pending  ; per slot: a command waits for its timer (the gauge stays full until it acts)
}

.reserve atb_gauge_state as AtbGauge in battle_text_ram

.alloc _battle_atb_gauge in bank20_reloc {
    .scope atb_gauge {
reset:
"""Battle start: forget every timer, draw every gauge on its first pass. Callable with JSL."""
    php
    sep #0x20
    rep #0x10
    ldx.w #sizeof(AtbGauge) - 1
    lda.b #0x00
_reset_byte:
    sta.l atb_gauge_state, x
    dex
    bpl _reset_byte
    ldx.w #_PARTY - 1
    lda.b #0xFF
_reset_drawn:
    sta.l atb_gauge_state.drawn_px, x
    dex
    bpl _reset_drawn
    plp
    rtl

frame:
"""
Vanilla's wait for vblank ($02:851E), its `inc $1811` moved here after the gauges: once a frame, whatever
battle-graphics loop is waiting (its spin on $1811 stays vanilla's, where savestates catch the CPU). Keeps A, X, Y, D
and the data bank as vanilla's did (its callers rely on them: $02:9472 indexes a jump table with A's high byte left
over); the update runs on direct page 0. Callable with JSL.
"""
    php
    rep #0x30
    pha
    phx
    phy
    phd
    lda.w #0x0000
    tcd
    jsr.l update
    rep #0x30
    pld
    ply
    plx
    pla
    plp
    php
    sep #0x20
    lda.l _NMI_WAIT
    inc
    sta.l _NMI_WAIT
    plp
    rtl

update:
"""
Every gauge whose fill changed, redrawn in the HP text, the main view and its copy: once a frame (`frame`), and on each
battle-graphics pass before the menu task copies the HP text (vanilla redraws it with "/max", the menu shows it next).
Callable with JSL.
"""
    php
    phb
    rep #0x30
    lda.b 0x00  ; scratch: kept for WaitFrameMain's callers
    pha
    lda.b 0x02
    pha
    lda.b 0x04
    pha
    lda.b 0x06
    pha
    lda.b 0x08
    pha
    lda.b 0x0A
    pha
    sep #0x20
    lda.b #0x7E
    pha
    plb
    lda.l _SETTING  ; Options, "Jauge ATB": off leaves vanilla's "/max HP"
    and.b #_SETTING_ON
    bne _on
    jmp.w _done
_on:
    stz.w atb_gauge_state.changed & 0xFFFF
    rep #0x20
    lda.l battle_frame_counter  ; real time: the updates come every frame or every other one, the NMI every frame
    sta.w atb_gauge_state.frames & 0xFFFF
    sep #0x20
    ldx.w #0x0000
_watch:
    phx
    jsr.w _watch_timer
    plx
    inx
    cpx.w #_PARTY
    bne _watch
_paced:
    jsr.w _map_rows
    ldx.w #0x0000
_row:
    txa
    cmp.w atb_gauge_state.rows & 0xFFFF
    beq _rows_drawn
    phx
    jsr.w _draw_row
    plx
    inx
    bra _row
_rows_drawn:
    txa
    cmp.b #_PARTY
    beq _caps_done
    stx.b 0x0A
    phx
    jsr.w _clear_cap
    plx
    inx
    bra _rows_drawn
_caps_done:
    lda.w atb_gauge_state.changed & 0xFFFF
    beq _done
    lda.l battle_render_state.tilemap_pending_mask  ; the NMI uploads both views this frame
    ora.b #TilemapPendingBits.main.mask | TilemapPendingBits.commands.mask
    sta.l battle_render_state.tilemap_pending_mask
_done:
    rep #0x20
    pla
    sta.b 0x0A
    pla
    sta.b 0x08
    pla
    sta.b 0x06
    pla
    sta.b 0x04
    pla
    sta.b 0x02
    pla
    sta.b 0x00
    plb
    plp
    rtl

_slot_index:
"""$00 = slot X, $02 = slot * 2, $04 = slot * 4, X = slot * 21 (leaves A16)."""
    rep #0x20
    txa
    sta.b 0x00
    asl
    sta.b 0x02
    asl
    sta.b 0x04
    asl
    asl
    clc
    adc.b 0x04
    adc.b 0x00
    tax
    rts

_watch_timer:
"""
Character X's action timer: a rise is a new turn (its full length), a drop is a tick (its pace: the updates since its
last one); its flags say whether a chosen command waits on it (A8 X16, DB $7E).
"""
    jsr.w _slot_index
    sep #0x20
    lda.l _TIMER_FLAGS, x
    and.b #_COMMAND_DELAY
    ldy.b 0x00
    sta.w atb_gauge_state.pending & 0xFFFF, y
    rep #0x20
    lda.l _TIMERS, x
    ldx.b 0x02
    cmp.w atb_gauge_state.timer & 0xFFFF, x
    sta.w atb_gauge_state.timer & 0xFFFF, x
    beq _watched
    bcc _dropped
    sta.w atb_gauge_state.full_time & 0xFFFF, x
    lda.w atb_gauge_state.frames & 0xFFFF  ; a new turn: its pace counts from now
    sta.w atb_gauge_state.last_tick & 0xFFFF, x
    bra _watched
_dropped:
    lda.w atb_gauge_state.frames & 0xFFFF
    sec
    sbc.w atb_gauge_state.last_tick & 0xFFFF, x
    cmp.w #_MAX_PERIOD
    bcc _period
    lda.w #_MAX_PERIOD
_period:
    pha
    lda.w atb_gauge_state.frames & 0xFFFF
    sta.w atb_gauge_state.last_tick & 0xFFFF, x
    pla
    sep #0x20
    ldx.b 0x00
    sta.w atb_gauge_state.period & 0xFFFF, x
_watched:
    sep #0x20
    rts

_map_rows:
"""Which slot each row of the party window shows: vanilla's display order, present characters only (A8 X16)."""
    ldx.w #0x0000
    txy  ; rows
_mr_next:
    phx
    lda.l _DISPLAY_ORDER, x
    rep #0x20
    and.w #0x00FF
    tax
    sep #0x20
    lda.l _HIDDEN, x
    bne _mr_skip
    phx
    rep #0x20
    txa
    xba
    lsr  ; slot * $80
    tax
    sep #0x20
    lda.l _RECORDS, x
    plx
    cmp.b #0x00
    beq _mr_skip
    txa
    sta.w atb_gauge_state.row_slot & 0xFFFF, y
    iny
_mr_skip:
    plx
    inx
    cpx.w #_PARTY
    bne _mr_next
    tya
    sta.w atb_gauge_state.rows & 0xFFFF
    rts

_draw_row:
"""The gauge on row X of the party window (A8 X16, DB $7E): $00-$04 its slot's indices, $0A the row."""
    stx.b 0x0A
    lda.w atb_gauge_state.row_slot & 0xFFFF, x
    rep #0x20
    and.w #0x00FF
    tax
    jsr.w _slot_index
    lda.b 0x0A
    asl
    asl
    sta.b 0x04  ; row * 4
    asl
    asl
    asl  ; row * 32
    clc
    adc.b 0x04  ; row * 36
    adc.w #_HP_TEXT & 0xFFFF
    sta.w atb_gauge_state.row & 0xFFFF
    tay
    sep #0x20
    lda.w _SLASH, y
    cmp.b #_SLASH_TILE
    bne _row_ready
    ldx.b 0x0A
    lda.b #0xFF
    sta.w atb_gauge_state.drawn_px & 0xFFFF, x  ; vanilla drew "/max" again: draw the gauge over it
_row_ready:
    lda.w _LAST_DIGIT, y
    sec
    sbc.b #_DIGIT_0
    cmp.b #10
    bcs _no_character  ; a blank row: nobody in this slot
    jsr.w _fill_px
    ldx.b 0x0A
    cmp.w atb_gauge_state.drawn_px & 0xFFFF, x
    beq _unchanged
    sta.w atb_gauge_state.drawn_px & 0xFFFF, x
    jsr.w _draw_gauge
    jsr.w _publish_gauge
    lda.b #0x01
    sta.w atb_gauge_state.changed & 0xFFFF
_unchanged:
    jmp.w _draw_cap
_no_character:
    jmp.w _clear_cap

_fill_px:
"""
A8 = the fill in pixels (0-24) of character $00: the share of its turn's timer run out, plus the frames since the last
tick at the ticks' pace (up to one tick); full once the timer is 0.
"""
    sep #0x20
    ldx.b 0x00
    lda.w atb_gauge_state.pending & 0xFFFF, x
    bne _fill_full  ; a command waits: the turn is still on
    rep #0x20
    ldx.b 0x02
    lda.w atb_gauge_state.full_time & 0xFFFF, x
    beq _fill_full  ; not seen reset yet
    sta.b 0x06
    lda.w atb_gauge_state.timer & 0xFFFF, x
    beq _fill_full
    cmp.b 0x06
    bcc _running
    beq _running
    bra _fill_empty
_running:
    eor.w #0xFFFF
    sec
    adc.b 0x06  ; run out = full - timer
    sta.b 0x08
; the pace: frames since the tick (at most a period) over the period; none before two ticks or on a long timer
    ldx.b 0x00
    lda.w atb_gauge_state.period & 0xFFFF, x
    and.w #0x00FF
    beq _no_pace
    ldy.b 0x06
    cpy.w #_MAX_PACED_TIME
    bcs _no_pace
    sta.b 0x04  ; period
    ldx.b 0x02
    lda.w atb_gauge_state.frames & 0xFFFF
    sec
    sbc.w atb_gauge_state.last_tick & 0xFFFF, x
    cmp.b 0x04
    bcc _elapsed
    lda.b 0x04
_elapsed:
    pha  ; elapsed
    lda.b 0x08
    jsr.w _times_period
    clc
    adc 1, s
    sta.b 0x08  ; run out * period + elapsed
    pla
    lda.b 0x06
    jsr.w _times_period
    sta.b 0x06  ; full * period
_no_pace:
    lda.b 0x08
    asl
    clc
    adc.b 0x08  ; * 3
    asl
    asl
    asl  ; * 24
    ldx.w #0x0000
_divide:
    cmp.b 0x06
    bcc _divided
    sbc.b 0x06
    inx
    bra _divide
_divided:
    txa
    sep #0x20
    cmp.b #_GAUGE_PX
    bcc _fill_done
    lda.b #_GAUGE_PX - 1  ; full only once the timer is 0
_fill_done:
    rts
_fill_empty:
    sep #0x20
    lda.b #0x00
    rts
_fill_full:
    sep #0x20
    lda.b #_GAUGE_PX
    rts

_times_period:
"""A16 *= the period in $04 (small: repeated addition)."""
    pha
    lda.w #0x0000
    ldy.b 0x04
_tp_add:
    clc
    adc 1, s
    dey
    bne _tp_add
    ply
    rts

_draw_gauge:
"""Fill A8 into the gauge cells of row `atb_gauge_state.row`: grey while it fills, the HP digits' white when full."""
    sta.b 0x06
    ldy.w atb_gauge_state.row & 0xFFFF
    lda.w _LAST_DIGIT + 1, y
    and.b #( ~_PALETTE_MASK ) & 0xFF
    sta.b 0x07
    lda.b 0x06
    cmp.b #_GAUGE_PX
    beq _attr_set
    lda.b 0x07
    ora.b #_FILLING_PALETTE
    sta.b 0x07
_attr_set:
    lda.b #_CAP_LEFT
    sta.w _GAUGE, y
    lda.b 0x07
    sta.w _GAUGE + 1, y
    ldx.w #_FILL_CELLS
_cell:
    iny
    iny
    lda.b 0x06  ; what is left to fill
    cmp.b #8
    bcc _partial
    lda.b #8
_partial:
    pha
    clc
    adc.b #_FILL_0
    sta.w _GAUGE, y
    lda.b 0x07
    sta.w _GAUGE + 1, y
    pla
    eor.b #0xFF
    sec
    adc.b 0x06
    sta.b 0x06
    dex
    bne _cell
    rts

_publish_gauge:
"""Row $0A's gauge cells (its HP text's cells 4-8) into the main view and the command window's copy (A8 X16)."""
    jsr.w _cap_cell  ; Y = the cap cell: the gauge starts 5 cells before
    rep #0x20
    tya
    sec
    sbc.w #_CAP_CELL - _GAUGE_CELL
    tay
    ldx.w atb_gauge_state.row & 0xFFFF
    lda.w #5
    sta.b 0x08
_pg_cell:
    lda.w _GAUGE, x
    sta.w 0x0000, y
    sta.w _MIRROR, y
    inx
    inx
    iny
    iny
    dec.b 0x08
    bne _pg_cell
    sep #0x20
    rts

_cap_cell:
"""Y = the main view's cell after row $0A's bottom row (A16 on return)."""
    rep #0x20
    lda.b 0x0A
    and.w #0x00FF
    xba
    lsr  ; row * 128
    clc
    adc.w #( _MAIN_VIEW_HP & 0xFFFF ) + _CAP_CELL
    tay
    rts

_draw_cap:
"""The right cap of row $0A, in its gauge's palette (A8 X16, DB $7E)."""
    jsr.w _cap_cell
    sep #0x20
    ldx.w atb_gauge_state.row & 0xFFFF
    lda.w _GAUGE + 1, x  ; the left cap's attribute: the gauge's palette
    xba
    lda.b #_CAP_RIGHT
    rep #0x20
    sta.w 0x0000, y
    sta.w _MIRROR, y
    sep #0x20
    rts

_clear_cap:
"""No character on row $0A: a blank where its right cap goes (A8 X16, DB $7E)."""
    jsr.w _cap_cell
    lda.w #0x00FF
    sta.w 0x0000, y
    sta.w _MIRROR, y
    sep #0x20
    rts
    }
}

.alloc _battle_atb_gauge_bank02 in bank02_trampolines {
atb_gauge_frame:
"""Vanilla's wait for vblank calls in here instead of its `inc $1811` (atb_gauge.frame does it)."""
    jsr.l atb_gauge.frame
    rts
}

.alloc at 0x02851E size 3 {
; vanilla's wait for vblank: `inc $1811`, then its own spin (left as it is)
    jsr.w atb_gauge_frame
}
