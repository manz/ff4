"""
Battle redraw-gate state + writer helpers (FF6-style dirty bits). `battle_menu_dirty` tracks which per-frame
renderables need rebuilding, `battle_monster_dirty` the per-monster-slot names. Renderers skip when their bit is
clear; writers (ATB pick, cursor move, status flip, ...) set it via the helpers below.
"""


.import "battle/render_state"
.import "core/wram_layout"


.import "battle/sram"
.import "core/vanilla"

; bit 5 = cmd window, bit 6 = status strip, bits 0-4 = per-char menu (HP/MP/name), bit 7 = main-menu chrome.
; Reserved, not vanilla's $EF9A: the item menu reads $EF9A (the equip popup's A: non-zero picks "use" over
; "swap"), so a dirty command list there would turn the popup's A into an item use.
.reserve battle_menu_dirty 1 in battle_text_ram
.reserve battle_monster_dirty 1 in battle_text_ram  ; bits 0-7 = per-monster-slot name redraw
; root-scope extern: battle/tasks_patches imports this module through inventory_rolling_patches
.extern signal_commands


.include "core/bank20.i"

.alloc _battle_redraw_gates_block in bank20_reloc {
    CMD_DIRTY_BIT := 0x20  ; bit 5 of battle_menu_dirty
    _NAMES_DIRTY_BIT := 0x10  ; bit 4 of battle_menu_dirty (char names region)
    _MONSTER_DIRTY_BIT := 0x01  ; bit 0 of battle_monster_dirty (any monster name)

_mark_cmd_dirty:
"""
    Set the cmd-window dirty bit (JSL). `tsb` has no long form, hence lda/ora/sta.
"""


    lda.l battle_menu_dirty
    ora.b #CMD_DIRTY_BIT
    sta.l battle_menu_dirty
    jsr.l signal_commands  ; battle/tasks_patches.s: the command window task redraws
    rtl

walker_rtl:
"""
    RTL wrapper around `set_active_char_palette` for bank-02 callers; loads A from $1822.
"""


    lda.l battle_selected_char
    jsr.w set_active_char_palette
    rtl

mark_monsters_dirty_and_init:
"""
    UpdateDead hook ($03:B1A0, the monster-death path): set the monsters-region dirty bit, then replay the
    replaced prelude (tdc; tax; stx $a9) and fall through to $03:B1A4.
"""


    lda.l battle_render_state.region_dirty_bits
    ora.b #battle_render.REGION_DIRTY_MONSTERS
    sta.l battle_render_state.region_dirty_bits
; The cmd window mirrors the main view, so it is stale too: re-arm CMD_DIRTY_BIT.
    lda.l battle_menu_dirty
    ora.b #CMD_DIRTY_BIT
    sta.l battle_menu_dirty
    jsr.l signal_commands  ; battle/tasks_patches.s: the command window task redraws
    tdc
    tax
    stx.b 0xa9
    rtl

_mark_all_dirty:
"""
    Reset both dirty bytes to $FF so the next frame renders everything.
"""


    lda.b #0xFF
    sta.l battle_menu_dirty
    sta.l battle_monster_dirty
    rtl

reset_queue_dirty_bits:
"""
    Seed all redraw-gate state for a fresh battle (`battle_ext_seed`, once per battle): every byte $FF (1 = dirty)
    so the first frame renders everything; gates clear their bits, writers re-arm them.
"""


    lda.b #0x00
    sta.l battle_render_state.render_skipped
    lda.b #0xFF
    sta.l battle_render_state.region_dirty_bits
    sta.l battle_menu_dirty
    sta.l battle_monster_dirty
    rtl

gated_clear_names_window_buffer:
"""
    `clear_names_window_buffer` ($02:A299 call site) only when the names region is dirty: a wipe on a skipped
    render leaves blank tiles on screen.
"""


    lda.l battle_render_state.region_dirty_bits
    bit.b #battle_render.REGION_DIRTY_NAMES
    beq _gcnwb_skip
    jsr.l clear_names_window_buffer

_gcnwb_skip:
    rtl

set_active_char_palette:
"""
    Stamp the active-char highlight palette into the char-name tilemaps: the VWF staging buffer `$7E:B966` (rows
    of 24 bytes, dakuten line +0, name line +$0C) and the live main view `$7E:BEA6` (-> VRAM $7020; row pair at
    `$BEC2 + row * $80` and +$40). Active row gets palette $08 (vanilla UpdateCharNames @a24c), others $00.
    Rows are display-ordered and compacted like UpdateCharNames: display index 0..4 maps to a slot via CharOrderTbl
    ($02:A1C8); absent or name-hidden chars (Kain mid-jump) emit no row, so a 3-char party fills rows 0..2.
    In: A = active slot ($1822), M=8, X=8. Preserves the full 16-bit C: vanilla callers `tax` with X=16 using the
    hidden B (dispatch at $02:800E), and a leaked high byte jumps into `brk #$21`.
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
; Vanilla highlights only while the menu is open ($D7, OpenMenu @abdd): closed, park the slot at $FF.
    lda.l 0x7E00D7
    bne _scp_menu_open
    lda.b #0xFF
    sta.l battle_render_state.highlight_active_slot

_scp_menu_open:
; The walker uses $32/$33 as scratch; the NMI caller needs them.
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
; Rows vanilla doesn't emit shift every following name up one row.
    jsr.w _scp_row_visible
    bcc _scp_next_slot
; CharOrderTbl[display index] = slot on this row
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
; dakuten line: hi bytes +1, +3, ..., +B
    ldy.w #1
    jsr.w _scp_patch_six
; name line at base + $0C
    rep #0x20
    lda.b btlgfx_dp.dakuten_row_ptr
    clc
    adc.w #0x000C
    sta.b btlgfx_dp.dakuten_row_ptr
    sep #0x20
    ldy.w #1
    jsr.w _scp_patch_six
; The staging buffer reaches VRAM only on a names re-render, which the gate skips on ATB rotation: stamp the
; live main view too, for the TILEMAP_PENDING_MAIN DMA.
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
    Carry set when display index X owns a name row (vanilla CheckShowCharName $02:A1F8 + the char-present
    test in UpdateCharNames). Clobbers $32/$33 and A; X survives.
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
    Per-frame re-stamp from the gated DrawCharNames trampoline. A names re-render (render_skipped = $00) rebuilds
    $B966 with palette 0 whenever $D7 is clear, and $1822 / $D7 can move without one (menu open/close). ~600
    cycles when it fires.
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
    jsr.l signal_commands  ; the menu opened, closed or changed hands

_rap_done:
    plp
    rtl

set_active_char_and_dirty:
"""
    Writer shim for `sta $1822 / sta $d0` at $03:A482 (JSL + NOP): both stores, then cmd dirty and highlight
    cache invalidated. The site fires only when the menu queue pops a char, so always re-arm: comparing with $1822
    misses a pop matching a stale value. In: M=8, A = char index, any DBR.
"""


    sep #0x20
    sta.l battle_selected_char
    sta.l 0x7E00D0
    pha
    lda.l battle_menu_dirty
    ora.b #CMD_DIRTY_BIT
    sta.l battle_menu_dirty
    jsr.l signal_commands  ; battle/tasks_patches.s: the command window task redraws
; No names re-render on rotation (~3M cycles): the walker rewrites the palette. Invalidate the cache rather than
; walk here, before the engine sets the hidden-name flags; refresh_active_char_palette re-stamps next frame.
    lda.b #0xFF
    sta.l battle_render_state.highlight_cache_slot
    pla
    rtl
}
