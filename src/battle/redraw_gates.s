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


battle_menu_dirty := 0x7EEF9A  ; bit 5 = cmd window, bit 6 = status strip,
; bits 0-4 = per-char menu (HP/MP/name),
; bit 7 = main-menu chrome
battle_monster_dirty := 0x7EEF9B  ; bits 0-7 = per-monster-slot name redraw
scp_active_slot := 0x7EEF9C  ; scratch for set_active_char_palette
scp_pal_byte := 0x7EEF9D  ; current palette byte being applied
status_hash := 0x7EEF9E  ; hash of char-status bytes; gates DrawStatusText
obj_names_hash := 0x7EEF9F  ; hash of monster slots + $1822; gates DrawObjNames
char_hp_hash := 0x7EEFA0  ; hash of char HP bytes; gates DrawCharHP

CMD_DIRTY_BIT := 0x20  ; bit 5 of battle_menu_dirty
NAMES_DIRTY_BIT := 0x10  ; bit 4 of battle_menu_dirty (char names region)
MONSTER_DIRTY_BIT := 0x01  ; bit 0 of battle_monster_dirty (any monster name)

mark_cmd_dirty:
"""
Set the cmd-window dirty bit. Callable from any bank via JSL/RTL.
65816 `tsb` has no long-addressing form  ; emulate via lda/ora/sta.
"""
    lda.l battle_menu_dirty
    ora.b #CMD_DIRTY_BIT
    sta.l battle_menu_dirty
    rtl

gate_obj_names_check:
"""
Bank-20 body for the DrawObjNames hash gate. XOR of monster slot
type bytes ($29B5..$29B8) + active-char index ($1822). Sets
carry on dirty (re-render needed), clears carry on clean.
Caller (bank-02 trampoline at $02:97C2) tail-jumps to $99D3 on
dirty, rts on clean.
"""
    lda.l 0x7E29B5
    eor.l 0x7E29B6
    eor.l 0x7E29B7
    eor.l 0x7E29B8
    eor.l 0x7E1822
    cmp.l obj_names_hash
    beq _goc_clean
    sta.l obj_names_hash
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
    lda.l battle_render.region_dirty_bits
    ora.b #battle_render.REGION_DIRTY_MONSTERS
    sta.l battle_render.region_dirty_bits
    tdc
    tax
    stx.b 0xa9
    rtl

mark_all_dirty:
"""
Reset both dirty bytes to $FF so the next frame renders everything.
Called once at battle init.
"""
    lda.b #0xFF
    sta.l battle_menu_dirty
    sta.l battle_monster_dirty
    rtl

    .extern clear_names_window_buffer
    .extern battle_render.REGION_DIRTY_MONSTERS
    .extern battle_render.REGION_DIRTY_NAMES
    .extern battle_render.region_dirty_bits
    .extern battle_render.render_skipped
    .extern battle_render.tilemap_pending_mask
    .extern battle_render.TILEMAP_PENDING_MAIN

reset_queue_dirty_bits:
"""
Seed all redraw-gate state for a fresh battle. Called once per
battle from the InitMenuWindows hook ($02:9A63). Normal sense
everywhere: 1 = dirty, 0 = clean. Seed all bytes to $FF so the
first frame renders everything  ; the per-region gates clear their
own bits after rendering, and writer sites re-arm on state change.
"""
    lda.b #0x00
    sta.l battle_render.render_skipped
    lda.b #0xFF
    sta.l battle_render.region_dirty_bits
    sta.l battle_menu_dirty
    sta.l battle_monster_dirty
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
    lda.l battle_render.region_dirty_bits
    bit.b #battle_render.REGION_DIRTY_NAMES
    beq _gcnwb_skip
    jsr.l clear_names_window_buffer

_gcnwb_skip:
    rtl

set_active_char_palette:
"""
Walk all 5 char-name slots in the `$7E:B966` tilemap. Active slot
gets palette $04 (bit 2 of tilemap-entry hi byte = palette 1)  ;
others get $00 (palette 0).

Each char-name slot occupies row at `$B966 + slot * $40`. Names
are max 6 tiles wide in the FR translation. Each tilemap entry
is 2 bytes (low = tile id, hi = flags+palette). Two pointer
mirrors get written by the VWF dispatcher (`tilemap_write`
in message.s) at offsets +0 and +$0C of the row base, so 12 hi
bytes total per slot (6 on each mirror).

A = active slot index (0..4) on entry. M=8, X=8.
"""


    php
    sep #0x20
    rep #0x10
    phb
    pha
    lda.b #0x7E  ; force DBR = $7E so `(0x32),y` writes to WRAM
    pha
    plb
    pla
    sta.l scp_active_slot
    ldx.w #0

_scp_slot_loop:
    cpx.w #5
    bcs _scp_done
    txa
    cmp.l scp_active_slot
    beq _scp_is_active
    lda #0x00
    bra _scp_have_pal

_scp_is_active:
    lda #0x08  ; palette 2 (vanilla `lda #$08` in UpdateCharNames @a24c)

_scp_have_pal:
    sta.l scp_pal_byte
    ; base = $B966 + slot * $40
    rep #0x20
    txa
    and.w #0x000F
    asl
    asl
    asl
    asl
    asl
    asl
    clc
    adc.w #0xB966
    sta.b 0x32  ; reuse $32 as scratch ptr for indirect writes
    sep #0x20
    ; Patch 6 entries on the ($32) mirror at offsets +1, +3, +5, +7, +9, +B
    ldy.w #1
    jsr.w _scp_patch_six
    ; Now patch the ($34) mirror at base + $0C
    rep #0x20
    lda.b 0x32
    clc
    adc.w #0x000C
    sta.b 0x32
    sep #0x20
    ldy.w #1
    jsr.w _scp_patch_six
    inx
    bra _scp_slot_loop

_scp_done:
    plb
    plp
    rts

_scp_patch_six:
    ; ($32) = row base in bank $7E. Y = first hi-byte offset.
    ; Walks Y, Y+2, ..., Y+10. Masks `$E3`, ORs in `scp_pal_byte`.
    phx
    ldx.w #6

_scp_loop_six:
    lda (0x32), y
    and #0xE3
    ora.l scp_pal_byte
    sta (0x32), y
    iny
    iny
    dex
    bne _scp_loop_six
    plx
    rts

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
    sta.l 0x7E1822
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
    pla
    pha
    jsr.w set_active_char_palette
    lda.l battle_render.tilemap_pending_mask
    ora.b #battle_render.TILEMAP_PENDING_MAIN
    sta.l battle_render.tilemap_pending_mask
    pla
    rtl
