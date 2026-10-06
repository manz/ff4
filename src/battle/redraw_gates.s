"""
Battle redraw-gate state + writer helpers.

FF6-style dirty-bit gating for the battle redraw chain. One byte at
`$7E:EF9A` tracks which per-frame renderables (cmd window, char menus,
status strip, main-menu chrome) actually need rebuilding. A sibling
byte `$EF9B` does the same per-monster-slot for `DrawMonsterNames`.

Render-side code reads the byte and short-circuits when its bit is
clear. Writer-side code (state changes: ATB pick, cursor move,
submenu enter, status flip, …) sets the matching bit via the
`mark_*` helpers below.

See `todo/battle-text-redraw.md` for the architecture rationale and
`tests/_profile/baseline_battle_idle.py` for the cycle measurement
that prompted the work.
"""


.import "battle/render_state"


battle_menu_dirty := 0x7EEF9A  ; bit 5 = cmd window, bit 6 = status strip,
; bits 0-4 = per-char menu (HP/MP/name),
; bit 7 = main-menu chrome
battle_monster_dirty := 0x7EEF9B  ; bits 0-7 = per-monster-slot name redraw

; Cross-module LABEL: extern at root scope (`.extern` only registers in its own
; scope, and an `.alloc` body opens its own).
.import "battle/sram"
.import "vanilla"

.scope battle_render {
    """
    Render constants shared with message.s.

    Cross-module constants are compile-time, not link symbols, so both
    modules pull the same definitions in under the same scope name
    rather than one importing them from the other.
    """
    .include "render_defs.i"
}

.include "../bank20.i"

.alloc _battle_redraw_gates_block in bank20_reloc {
    _status_copy := 0x7EF015  ; vanilla DrawStatusText source: 4 status bytes per char slot
    _STATUS_COPY_BYTES = 5 * 4
    _obj_names_hash := 0x7EEF9F  ; hash of monster slots + $1822; gates DrawObjNames
    _char_hp_hash := 0x7EEFA0  ; hash of char HP bytes; gates DrawCharHP

    CMD_DIRTY_BIT := 0x20  ; bit 5 of battle_menu_dirty
    _NAMES_DIRTY_BIT := 0x10  ; bit 4 of battle_menu_dirty (char names region)
    _MONSTER_DIRTY_BIT := 0x01  ; bit 0 of battle_monster_dirty (any monster name)

_mark_cmd_dirty:
"""
    Set the cmd-window dirty bit. Callable from any bank via JSL/RTL.
    65816 `tsb` has no long-addressing form  ; emulate via lda/ora/sta.
"""


    lda.l battle_menu_dirty
    ora.b #CMD_DIRTY_BIT
    sta.l battle_menu_dirty
    rtl

walker_rtl:
"""
    RTL wrapper around `set_active_char_palette` so bank-02 callers
    can JSL into it with matching pop. Reads $1822 into A first so
    caller doesn't have to set it up.
"""


    lda.l battle_selected_char
    jsr.w set_active_char_palette
    rtl

gate_status_check:
"""
    Bank-20 body for the DrawStatusText gate. Compares the 20 status
    bytes vanilla DrawStatusText draws ($7E:F015, 4 per char slot)
    with the shadow copy from the last draw. Sets carry and refreshes
    the shadow when any byte changed, clears carry when none did.
    Caller (bank-02 trampoline at $02:97F8) tail-jumps to $A2A1 on
    dirty, rts on clean. Runs with 8-bit A and 16-bit X/Y (btlgfx).
"""


    phx
    phy
    ldy.w #0  ; 0: clean, 1: a status byte changed
    ldx.w #_STATUS_COPY_BYTES - 1

_gsc_loop:
    lda.l _status_copy, x
    cmp.l battle_render_state.status_shadow, x
    beq _gsc_next
    sta.l battle_render_state.status_shadow, x
    ldy.w #1

_gsc_next:
    dex
    bpl _gsc_loop
    cpy.w #1  ; carry = changed
    ply
    plx
    rtl

gate_obj_names_check:
"""
    Bank-20 body for the DrawObjNames hash gate. XOR of monster slot
    type bytes ($29B5..$29B8) + active-char index ($1822). Sets
    carry on dirty (re-render needed), clears carry on clean.
    Caller (bank-02 trampoline at $02:97C2) tail-jumps to $99D3 on
    dirty, rts on clean.
"""


    lda.l btl_monster_types
    eor.l btl_monster_types + 1
    eor.l btl_monster_types + 2
    eor.l btl_monster_types + 3
    eor.l battle_selected_char
    cmp.l _obj_names_hash
    beq _goc_clean
    sta.l _obj_names_hash
    sec
    rtl

_goc_clean:
    clc
    rtl

mark_monsters_dirty_and_init:
"""
    Hook shim for `UpdateDead` entry at $03:B1A0. The original 4 bytes
    (`tdc  ; tax; stx $a9`) get replaced by a JSL here  ; this helper
    sets the monsters-region dirty bit, then replicates the clobbered
    prelude so execution can fall through to the original loop at
    $03:B1A4. UpdateDead is the engine path that marks a monster
    dead (`sta $29b5,x` with $FF after status apply)  ; flagging
    monsters dirty here lets the gated monster-name trampoline
    re-render once the dead slot is wiped.
"""


    lda.l battle_render_state.region_dirty_bits
    ora.b #battle_render.REGION_DIRTY_MONSTERS
    sta.l battle_render_state.region_dirty_bits
; Propagate to cmd-window region: the cmd-window tilemap at $C1A5+ is
; a mirror of the main view ($BE65+) overlaid with cmd tiles. If we
; refresh monsters in the main view, the cmd mirror is stale, so set
; CMD_DIRTY_BIT here too. The relocated DrawCmdWindow path picks this
; up next frame and re-runs the WRAM mirror via `mirror_main_to_cmd`.
    lda.l battle_menu_dirty
    ora.b #CMD_DIRTY_BIT
    sta.l battle_menu_dirty
    tdc
    tax
    stx.b 0xa9
    rtl

_mark_all_dirty:
"""
    Reset both dirty bytes to $FF so the next frame renders everything.
    Called once at battle init.
"""


    lda.b #0xFF
    sta.l battle_menu_dirty
    sta.l battle_monster_dirty
    php
    sep #0x20
    rep #0x10
    ldx.w #_STATUS_COPY_BYTES - 1

_seed_status_shadow:
    sta.l battle_render_state.status_shadow, x
    dex
    bpl _seed_status_shadow
    plp
    rtl

reset_queue_dirty_bits:
"""
    Seed all redraw-gate state for a fresh battle. Called once per
    battle from the InitMenuWindows hook ($02:9A63). Normal sense
    everywhere: 1 = dirty, 0 = clean. Seed all bytes to $FF so the
    first frame renders everything  ; the per-region gates clear their
    own bits after rendering, and writer sites re-arm on state change.
"""


    lda.b #0x00
    sta.l battle_render_state.render_skipped
    lda.b #0xFF
    sta.l battle_render_state.region_dirty_bits
    sta.l battle_menu_dirty
    sta.l battle_monster_dirty
    php
    sep #0x20
    rep #0x10
    ldx.w #_STATUS_COPY_BYTES - 1

_seed_status_shadow:
    sta.l battle_render_state.status_shadow, x
    dex
    bpl _seed_status_shadow
    plp
    rtl

gated_clear_names_window_buffer:
"""
    Wrap `clear_names_window_buffer` ($02:A299 call site) with the
    names-region dirty-bit check. When names is clean (bit clear),
    skip the tilemap wipe so the gated `init_names_gated` + skipped
    DrawText leaves the VRAM tilemap untouched. Without this the
    tilemap wipe still fires every frame and the gated render skip
    leaves blank tiles on screen.
"""


    lda.l battle_render_state.region_dirty_bits
    bit.b #battle_render.REGION_DIRTY_NAMES
    beq _gcnwb_skip
    jsr.l clear_names_window_buffer

_gcnwb_skip:
    rtl

set_active_char_palette:
"""
    Stamp the active-character highlight palette into the char-name
    tilemaps: the VWF staging buffer at `$7E:B966` and the live
    main-view tilemap the NMI DMA uploads (`$7E:BEA6` -> VRAM $7020).
    Active row gets palette $08 (vanilla `lda #$08` in UpdateCharNames
    @a24c)  ; every other row gets $00.

    Names are max 6 tiles wide in the FR translation. Each tilemap
    entry is 2 bytes (low = tile id, hi = flags+palette). In the
    staging buffer a row spans 24 bytes: the dakuten line at +0 and
    the name line at +$0C. In the main view the same pair sits at
    `$BEC2 + row * $80` and `$40` further on.

    A = active character SLOT on entry (vanilla `$1822` semantics).

    Rows are display-ordered AND compacted, exactly like vanilla
    `UpdateCharNames` (@a20c): it walks display index 0..4, maps it to
    a slot through `CharOrderTbl` (`$02:A1C8` = .byte 1,3,0,4,2) and
    emits NOTHING for a char that is absent (`CharPropPtrs` entry
    reads $00) or name-hidden (`$F2C1,slot` non-zero, e.g. Kain
    mid-jump). A 3-char party therefore fills rows 0..2, not the rows
    its slots would occupy in a full party. The loop below mirrors
    that: display index in X, output row counted separately in
    `battle_render_state.highlight_row`.

    M=8, X=8. Preserves the caller's full 16-bit C: vanilla callers
    run `tax` with X=16 and rely on the hidden B byte (e.g. the
    `asl  ; tax` dispatch at $02:800E), so leaking the high byte of
    our `$32` restore sent that dispatch through a garbage jump table
    entry into `brk #$21`.
"""


    php
    rep #0x30
    pha
    sep #0x20
    phb
    pha
    lda.b #0x7E  ; force DBR = $7E so `(0x32),y` writes to WRAM
    pha
    plb
    pla
    sta.l battle_render_state.highlight_active_slot
; Vanilla only highlights while the battle menu is open (`lda $d7 ;
; beq` at UpdateCharNames @a250, $D7 set by OpenMenu @abdd). Match it:
; with the menu closed, park the active slot at $FF so no display row
; can match and every row clears.
    lda.l 0x7E00D7
    bne _scp_menu_open
    lda.b #0xFF
    sta.l battle_render_state.highlight_active_slot

_scp_menu_open:
; Save $32/$33 ; walker reuses as scratch indirect-ptr ; NMI
; caller's BG / DMA state needs them preserved.
    rep #0x20
    lda.b btlgfx_dp.dakuten_row_ptr
    pha
    sep #0x20
    lda #0x00
    sta.l battle_render_state.highlight_row
    ldx.w #0

_scp_slot_loop:
    cpx.w #5
    bcc _scp_in_range
    brl _scp_done

_scp_in_range:
; Skip display slots vanilla would not emit a row for; they shift
; every following name up one row.
    jsr.w _scp_row_visible
    bcc _scp_next_slot
; CharOrderTbl[display index] = char slot shown on this row. Compare
; to the active slot; match -> highlight palette, miss -> palette 0.
    lda.l 0x02A1C8, x
    cmp.l battle_render_state.highlight_active_slot
    beq _scp_is_active
    lda #0x00
    bra _scp_have_pal

_scp_is_active:
    lda #0x08  ; palette 2 (vanilla `lda #$08` in UpdateCharNames @a24c)

_scp_have_pal:
    sta.l battle_render_state.highlight_pal_byte

; Staging buffer: base = $B966 + row * 24.
    lda.l battle_render_state.highlight_row
    rep #0x20
    and.w #0x00FF
    asl
    asl
    asl  ; *8
    pha
    asl  ; *16
    clc
    adc 1, s  ; *16 + *8 = *24
    clc
    adc.w #0xB966
    sta.b btlgfx_dp.dakuten_row_ptr
    pla  ; balance stack
    sep #0x20
; Patch 6 entries on the dakuten line at offsets +1, +3, +5, +7, +9, +B
    ldy.w #1
    jsr.w _scp_patch_six
; Now the name line at base + $0C
    rep #0x20
    lda.b btlgfx_dp.dakuten_row_ptr
    clc
    adc.w #0x000C
    sta.b btlgfx_dp.dakuten_row_ptr
    sep #0x20
    ldy.w #1
    jsr.w _scp_patch_six
; The staging buffer only reaches VRAM when the names region
; re-renders, which the slice-2 gate skips on an ATB rotation. Stamp
; the live main-view tilemap as well so the TILEMAP_PENDING_MAIN DMA
; carries the highlight on the next NMI: dakuten line at
; $BEC2 + row * $80, name line $40 further on.
    lda.l battle_render_state.highlight_row
    rep #0x20
    and.w #0x00FF
    xba  ; *256
    lsr  ; *128
    clc
    adc.w #0xBEC2
    sta.b btlgfx_dp.dakuten_row_ptr
    sep #0x20
    ldy.w #1
    jsr.w _scp_patch_six
    rep #0x20
    lda.b btlgfx_dp.dakuten_row_ptr
    clc
    adc.w #0x0040
    sta.b btlgfx_dp.dakuten_row_ptr
    sep #0x20
    ldy.w #1
    jsr.w _scp_patch_six
    lda.l battle_render_state.highlight_row
    inc
    sta.l battle_render_state.highlight_row

_scp_next_slot:
    inx
    brl _scp_slot_loop

_scp_done:
    rep #0x20
    pla
    sta.b btlgfx_dp.dakuten_row_ptr
    sep #0x20
    plb
    rep #0x20
    pla
    plp
    rts

_scp_row_visible:
"""
    Carry set when display index X owns a name row. Mirrors vanilla
    `CheckShowCharName` ($02:A1F8) plus the `lda ($00)  ; beq` char-
    present test in UpdateCharNames. Clobbers $32/$33 (the caller
    recomputes them per row) and A  ; X survives.
"""


    phx
    lda.l 0x02A1F3, x  ; CharOrderTbl2[display index] = char slot
    rep #0x20
    and.w #0x00FF
    sep #0x20
    tax
    lda.l btl_name_hp_hidden, x  ; name-hidden flag (Kain mid-jump, ...)
    plx
    cmp #0x00  ; `plx` re-set Z from the index ; re-test the flag
    bne _scp_row_absent
    phx
    txa
    asl  ; CharPropPtrs is a word table
    rep #0x20
    and.w #0x00FF
    sep #0x20
    tax
    rep #0x20
    lda.l 0x02A1CD, x
    sta.b btlgfx_dp.dakuten_row_ptr
    sep #0x20
    plx
    lda.b (btlgfx_dp.dakuten_row_ptr)  ; first byte of the char's battle data ; $00 = no char
    beq _scp_row_absent
    sec
    rts

_scp_row_absent:
    clc
    rts

_scp_patch_six:
; ($32) = row base in bank $7E. Y = first hi-byte offset.
; Walks Y, Y+2, ..., Y+10. Masks `$E3`, ORs in the palette byte.
    phx
    ldx.w #6

_scp_loop_six:
    lda.b (btlgfx_dp.dakuten_row_ptr), y
    and #0xE3
    ora.l battle_render_state.highlight_pal_byte
    sta.b (btlgfx_dp.dakuten_row_ptr), y
    iny
    iny
    dex
    bne _scp_loop_six
    plx
    rts

refresh_active_char_palette:
"""
    Per-frame re-stamp, called from the tail of the gated DrawCharNames
    trampoline. Two jobs:

    - A names re-render rebuilds `$B966` through vanilla
      `UpdateCharNames`, which writes palette 0 for every row whenever
      `$D7` is clear. That wipes the walker's stamp mid-turn, which is
      what made the highlight look erratic. `battle_render_state.render_skipped` is $00
      exactly when DrawText ran, so re-stamp on that edge.
    - `$1822` / `$D7` can also move without a render (ATB rotation is
      covered by the writer shim, but the menu open/close edge is not),
      so compare both against the cached pair.

    Costs ~600 cycles on the frames it fires and nothing on the rest.
"""


    php
    sep #0x20
    lda.l battle_render_state.render_skipped
    beq _rap_stamp
    lda.l battle_selected_char
    cmp.l battle_render_state.highlight_cache_slot
    bne _rap_stamp
    lda.l 0x7E00D7
    cmp.l battle_render_state.highlight_cache_menu
    beq _rap_done

_rap_stamp:
    lda.l 0x7E00D7
    sta.l battle_render_state.highlight_cache_menu
    lda.l battle_selected_char
    sta.l battle_render_state.highlight_cache_slot
    jsr.w set_active_char_palette
    lda.l battle_render_state.tilemap_pending_mask
    ora.b #battle_render.TILEMAP_PENDING_MAIN
    sta.l battle_render_state.tilemap_pending_mask

_rap_done:
    plp
    rtl

set_active_char_and_dirty:
"""
    Writer-site shim for the active-char store (`sta $1822` at $03:A482,
    followed by `sta $d0`). Original 5 bytes replaced by JSL + NOP. Shim
    performs both stores then unconditionally marks cmd + names +
    monsters dirty. The vanilla site fires only when the battle-menu
    queue pops a new char (`check if menu needs to open` path in
    `battle/char.asm:464`), so re-arming on every call is correct  ;
    a compare-against-current would mis-skip when the popped char
    matches a stale value in $1822, leaving the prior cmd-window
    tilemap on screen.
    Caller has M=8, A holds the char index, DBR may differ from $7E.
"""


    sep #0x20
    sta.l battle_selected_char
    sta.l 0x7E00D0
    pha
    lda.l battle_menu_dirty
    ora.b #CMD_DIRTY_BIT
    sta.l battle_menu_dirty
; Char-name palette patch (replaces the full names VWF re-render
; that used to fire via REGION_DIRTY_NAMES on every rotation).
; Walks the `$7E:B966` tilemap, rewrites the palette field of
; each char's 6 max tiles on both pointer mirrors ; ~300 cycles
; vs ~3M for the VWF re-render. Also flip names tilemap dirty
; so the unified-DMA path uploads the patched tilemap to VRAM.
; Invalidate the highlight cache rather than walking here: this runs
; at the $1822 store, before the engine has populated the hidden-name
; flags the walker reads. `refresh_active_char_palette` re-stamps on
; the next frame, when that state is good.
    lda.b #0xFF
    sta.l battle_render_state.highlight_cache_slot
    pla
    rtl
}
