"""
Writer-site patches that mark the cmd-window dirty bit when battle state
changes. Counterpart to the reader gate in `commands_reloc.s` and the
shim helpers in `redraw_gates.s`.

Slice 1 of the redraw-gate work: patches the ATB "pick new active char"
site that writes `$1822`. Battle init and any per-turn rotation flow
through this site, so this single patch is enough to keep the cmd
window rendering correctly while gating idle frames. Additional writer
sites (cursor scroll, submenu enter/exit, status flips, …) land in
follow-up patches.
"""


.extern set_active_char_and_dirty
.extern messages_vwf
.extern messages_vwf.init_monsters_gated
.extern messages_vwf.init_names_gated
.extern messages_vwf.deinit_gated
.extern reset_queue_dirty_bits
.extern mark_monsters_dirty_and_init
.extern status_hash
.extern obj_names_hash
.extern gate_obj_names_check
.extern gate_status_check
.extern walker_rtl
.extern battle_render.render_skipped

; --- ATB active-char update (slice 1 cmd-gate writer) ---

; Original `battle/char.asm:UpdateMenu` at @a472..@a488 contains:
;   $03:A481  68             pla
;   $03:A482  8D 22 18       sta $1822   ; selected character slot
;   $03:A485  85 D0          sta $d0
;   $03:A487  20 1B A8       jsr ValidateArrows
;
; We replace the 5 bytes at $03:A482..$03:A486 with `jsr.l ... ; nop`.
; The shim performs the two original stores then sets the cmd-window
; dirty bit AND clears the slice-2 region-clean bits for names +
; monsters at $703C01 so the queue-gated init paths re-render after
; an ATB rotation.

*=0x03A482
    jsr.l set_active_char_and_dirty
    .db 0xEA  ; nop padding so $03:A487 still aligns to `jsr ValidateArrows`

; --- Names + monster gated trampolines (slice 2, queue-side bits) ---
; Live in the freed $02:97AB..$02:9824 hole (old TfrEquipWindow body).
; The init→DrawText→deinit pipeline still fires every frame so
; battle_flags symmetry is preserved (other VWF callers like HP/MP
; digits keep seeing a consistent dispatcher state). The gating is
; INSIDE `init_*_gated`: it reads the region's clean bit from
; `region_dirty_bits` at $703C01. If clean, it sets `render_skipped`
; ($703C02) to $FF; the trampoline reads that and skips DrawText, and
; `deinit_gated` skips the DMA-signal. The WRAM tile buffer is left
; untouched, no DMA fires from this region's deinit, and the VRAM
; tilemap persists from the previous render.

*=0x0297B0
_msg_monster_window_gated:
    jsr.l messages_vwf.init_monsters_gated
    lda.l battle_render.render_skipped
    bne _mmwg_after_draw
    jsr 0xA455  ; DrawText

_mmwg_after_draw:
    jsr.l messages_vwf.deinit_gated
    rts

; --- Battle-init seed: zero/seed all redraw-gate state at the
; `Battle_ext` root entry ($03:8000). Runs exactly once per battle
; (from field.asm:1005 `jsl Battle_ext` and menu.asm:163
; `jml Battle_ext`  ; no other callers per ff4decomp). Earlier we
; tried `InitMenuWindows` ($02:9A63) but that ran INSIDE the
; UpdateCharNames per-char loop entry, and a 2nd-battle kss restore
; mid-state could skip it entirely. The root entry is the only
; correct seed point.
;
; Original `Battle_ext` was `jmp ExecBattle` (3 bytes). JML is 4
; bytes so we clobber 1 byte of `Battle_ext2` at $03:8003. Decomp
; grep confirms zero callers of Battle_ext2 anywhere.

; --- Bank-02 trampoline for NMI-side UpdateFlyingHDMA ---
; `dma_transfer` (bank-20) calls this via JSL ; trampoline JSR's
; into UpdateFlyingHDMA ($02:82E1, vanilla now with phase-2 spin-
; wait nopped) and RTLs back. Matches the JSL push/pop convention.
; Sits in the 8-byte gap between `_msg_names_window_gated` body
; (ends ~$97E8) and `_battle_ext_seed` at $97F0.

*=0x0297EA
flying_hdma_trampoline:
"""
Bank-02 wrapper around vanilla `UpdateFlyingHDMA` ($02:82E1)
so `dma_transfer` (bank-20) can JSL into it with matching RTL pop  ;
the vanilla function ends in rts, our trampoline rtl's instead.
"""
    jsr 0x82E1
    rtl

*=0x0297F0
_battle_ext_seed:
    jsr.l reset_queue_dirty_bits
    jmp.l 0x038009  ; ExecBattle

*=0x038000
    jmp.l 0x0297F0

; --- Monster-death dirty hook: `UpdateDead` entry at $03:B1A0 ---
; Replaces the 4-byte prelude (`tdc; tax; stx $a9`) with a JSL to
; the bank-20 shim that ORs in REGION_DIRTY_MONSTERS, replays the
; prelude, and RTLs. Engine reaches B1A4 with identical state to
; vanilla. Fires every time the engine applies dead-status to a
; battle slot (post-attack, regen tick, etc.)  ; the gated monster-
; name trampoline picks up the dirty bit on the next frame.

*=0x03B1A0
    jsr.l mark_monsters_dirty_and_init

; --- DrawStatusText gate (hash-based) ---
; RedrawMainMenu @96C8 = `jsr DrawStatusText` ; 9.33M cycles per 60f
; (top remaining hitter after the cmd-window gate). Skip when char
; status state is unchanged. Hash = XOR of `$2003+slot*$40` for the
; 5 char slots (status 1 byte). Cached at `status_hash` ; first call
; per battle always renders (cache initialized to 0 by Battle_ext
; seed but state hash != 0 in normal play). Status flicker pulse
; freezes when no status changes ; acceptable trade for ~9M cycles.

*=0x0297F8
gate_draw_status_text:
"""
Bank-02 trampoline  ; JSL's bank-20 hash check, tail-jumps to
$A2A1 on carry-set (dirty), rts on carry-clear (clean). Lives
in the slot after `_battle_ext_seed` (ends $97F8).
"""
    jsr.l gate_status_check
    bcc _gdst_skip
    jmp 0xA2A1

_gdst_skip:
    rts

; Redirect RedrawMainMenu's `jsr DrawStatusText` to our gate. Same
; size (3 bytes) so no byte-shift.

*=0x0296C8
    jsr.w gate_draw_status_text

; --- DrawObjNames gate (hash of monster slots + $1822) ---
; Bank-20 body returns carry-set when re-render needed ; bank-02
; trampoline tail-jumps to vanilla DrawObjNames on dirty, rts on
; clean. Earlier we noop'd UpdateMagicList ($02:96D4) to reclaim
; 36 bytes for this gate's body, but that broke Rydia's summon
; menu display (vanilla UpdateMagicList still needed for periodic
; magic list refresh ; ImmediateMenuUpdate alone doesn't cover
; all dispatch paths). Restored.
; Trampoline lives in the 8-byte slot at $97C2 (after
; `_msg_monster_window_gated` body).

*=0x0297C2
gate_draw_obj_names:
"""
Bank-02 trampoline  ; JSL's bank-20 hash check, tail-jumps to
$99D3 on carry-set (dirty), rts on carry-clear (clean).
"""
    jsr.l gate_obj_names_check
    bcc _gdon_skip
    jmp 0x99D3

_gdon_skip:
    rts

*=0x0296CE
    jsr.w gate_draw_obj_names

; --- Phase 2: NMI-safe UpdateFlyingHDMA ---
; Vanilla `UpdateFlyingHDMA` ($02:82E1) spin-waits on the IRQ flag
; `$f353` at $02:82E8 (5 bytes: `lda $f353; beq -5`) to avoid HDMA
; mid-fetch tearing in main-loop context. In NMI/vblank the HDMA
; engine is idle, so the wait is safe to skip and required to
; avoid hanging when called from NMI (the IRQ won't fire while we're
; in vblank). NOP out the 5 bytes ; main-loop callers still work
; (just take the wait-loop hit one less time per frame).

*=0x0282E8
    nop
    nop
    nop
    nop
    nop

; --- Battle-init highlight stamp ---
; Reclaim the 3-nop slot at $02:9A69 (previously vanilla `jsr
; InitMagicListTextBuf` ; we noop'd that in magic/patches.s since
; our two-column magic display drives its own buffer). Insert
; `jsr walker_helper` so the active-char palette gets stamped
; right after UpdateCharNames built $B966 ; subsequent init steps
; (DrawHPText, DrawMonsterNames, etc.) target different WRAM
; regions ($B9DE, $BB1E) so the stamp survives.

*=0x029802
walker_helper:
"""5-byte bank-02 trampoline: JSL bank-20 walker, RTS to caller."""
    jsr.l walker_rtl
    rts

*=0x029A69
    jsr.w walker_helper

; --- Phase 5: deduplicate UpdateFlyingHDMA ---
; Main-loop `UpdateObjPos` ($02:82B9) calls UpdateFlyingHDMA at
; $02:82BC ; our NMI hook in `messages_vwf.dma_transfer` already
; fires it every vblank, so the main-loop call is redundant.
; NOP the 3-byte JSR to reclaim ~5K cycles/NMI.

*=0x0282BC
    nop
    nop
    nop

*=0x0297D0
_msg_names_window_gated:
    lda.b 0x4A
    and.b #0x04
    bne _mnwg_done  ; inventory open -> skip whole pipeline
    jsr.l messages_vwf.init_names_gated
    lda.l battle_render.render_skipped
    bne _mnwg_after_draw
    jsr 0xA455

_mnwg_after_draw:
    jsr.l messages_vwf.deinit_gated

_mnwg_done:
    rts
