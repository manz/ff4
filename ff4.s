"""
----------------
Final Fantasy IV the new hack.
----------------
"""

; Auto-prepended: imports must precede .include'd patches
.import "assets"
.import "sram_layout"
.import "wram_layout"
.import "battle/render_state"
.import "battle/commands_reloc"
.import "battle/equip_window"
.import "battle/graphics"
.import "battle/inventory_rolling"
.import "battle/items_reloc"
.import "battle/magic_reloc"
.import "battle/math_reloc"
.import "battle/monsters_reloc"
.import "battle/redraw_gates"
.import "battle/sram"
.import "dakuten"
.import "bank20_helpers"
.import "dialog"
.import "preamble"
.import "vanilla"
.import "ingame/init_bg_scroll_hdma"
.import "ingame/items_menu"
.import "ingame/items_menu_vwf"
.import "ingame/places_names"
.import "ingame/new_game"
.import "ingame/namingway"
.import "ingame/fat_chocobo"
.import "ingame/credits"
.import "ingame/places_names_window"
.import "intro"
.import "kerning"
.import "libmz"
.import "menus/in_game_text"
.import "menus/start_screen_text"
.import "menus/system_menus_text"
.import "menus/tools_shop_text"
.import "small_vwf/init"
.import "vwf"

.include "config.i"


.include "src/libmz.i"
.import "items"
.include "src/lib/rolling_buffer.i"
.include "src/menus/system_menus_text.i"
.import "minimal_vwf_patches"
.import "ingame/free_space"
.import "ingame/treasure_rolling_patches"
.import "ingame/inventory_rolling_patches"
.import "ingame/inventory_single_column"
.import "ingame/main"
.import "ingame/shop"
.import "ingame/items"
.import "ingame/magic"
.import "ingame/windows"
.import "ingame/instant_windows"
.import "ingame/options"
.import "ingame/equip"
.import "ingame/status"
.if BATTLE_ENABLED {
    .import "battle/math_patches"
    .import "battle/graphics_patches"
    .if MAGIC_ENABLED {
    .import "battle/magic/patches"
    .import "battle/commands_patches"
    }
    .import "battle/message_patches"
    .import "battle/sram_patches"
    .if BATTLE_MONSTERS_VWF {
    .import "battle/monsters_patches"
    }
    .import "battle/items_patches"
    .import "battle/redraw_writer_patches"
    .if INVENTORY_ROLLING_BUFFER {
    .import "battle/inventory_rolling_patches"
    }
    .if TREASURE_DEBUG_ALWAYS_DROP {
    .import "battle/debug_always_drop"
    }
}


; Relocated init_bg_scroll_hdma (was at $01:EBD2, frees 566 bytes in bank $01).
; Blob with internal absolute references - pinned to offset $EBD2 within an
; expansion bank. Caller patch retargets the single JSL at $02:818A.
.if INVENTORY_ROLLING_BUFFER {
    .import "ingame/init_bg_scroll_hdma_patches"
    .import "ingame/inventory_rolling_trampolines"
}

.if TREASURE_INVENTORY_ROLLING {
    .import "ingame/key_item_picker"
    .import "ingame/drops_rolling"
    .import "ingame/inventory_rolling"
    .import "lib/rolling_inventory_engine"
    .import "ingame/treasure_rolling"
    .import "ingame/shop_sell_rolling"
    .import "ingame/equip_inventory_rolling"
    .import "ingame/key_item_picker_patches"
    .import "ingame/shop_sell_rolling_patches"
    .import "ingame/equip_inventory_rolling_patches"
}


.alloc at 0x00FFC0 {
; patch snes cartridge type
; original PCB: SHVC-1A3B  ;  target PCB: SHVC-1A5B
    .ascii "Final Fantasy IV     "
}

.alloc at 0x00FFD6 {
; FFD5 20H / 30H Map Mode
    .db 0x02  ; Cartridge Type
    .db 0x0B  ; ~ 0BH ROM Size
    .db 0x07  ; RAM Size
}

.if ENABLE_BRK_HANDLER {
; JML trampoline in vector-table padding; native/emu BRK vectors point here.
    .alloc at 0x00FFE0 {
    jmp.l brk_handler
    }


    .alloc at 0x00FFE6 {
    .dw 0xFFE0
    }


    .alloc at 0x00FFFE {
    .dw 0xFFE0
    }
}


; déroutage pour ajouter le splash screen
.alloc at 0x008031 {
    .if ENABLE_INTRO {
    jsr.l start_splash_screen
    } else {
    jsr.l clear_ram
    }
}


; ============================================================================
; Bank-20 relocated region.
;
; Pool spans $20:8000..$20:FFFF (32 KB). `strategy order` keeps symbols in
; declaration order so cross-bank `jsr.l` / `jmp.l` callers resolve to
; stable addresses. Mirrors the bank-01 pool pattern from
; `src/ingame/inventory_rolling_trampolines.s`.
; ============================================================================

.pool bank20_reloc {
    range 0x208000 0x20FFFF
    strategy order
}

.alloc _bank20_main in bank20_reloc {
brk_handler:
"""
BRK trap: mask interrupts, disable NMI, fetch the BRK signature byte
(the imm operand of `brk #$NN`) into A, then STP. Kintsuki halts on
STP  ; tooling reads the signature via `emu.get_state().a` and the
crash site via `emu.callstack()`.

CPU push order on BRK: PB, PC.hi, PC.lo, P (PCH/PCL packed as a
16-bit push by the CPU). Pulled in reverse. Pushed PC = BRK + 2  ;
signature byte sits at PB:(PC - 1).
"""


    sei
    sep #0x20
    lda #0x00  ; disable NMI / auto-joypad
    sta.l cpu_regs.NMITIMEN
    pla  ; A = P (discard)
    rep #0x20
    pla  ; A = pushed PC (= BRK + 2)
    dec  ; A = BRK + 1 (offset of signature byte)
    sta.b 0x00  ; DP $00..$01 = low 16 bits of signature addr
    sep #0x20
    pla  ; A = PB
    sta.b 0x02  ; DP $02 = bank for indirect long
    rep #0x20
    and.w #0x00FF  ; clear high byte of A so signature is the only thing left
    sep #0x20
    lda [0x00]  ; A = signature byte (BRK's #$NN imm)
    stp
}

; end .alloc _bank20_main

.if TRIGGER_ENDING_CUTSCENE {
; all effects are the Ending cutscene
    .alloc at 0xc436 {
    lda #0x39
    nop
    }
}

.if DEBUG_SHOW_ITEM_WINDOW {
; Hijack ExecEvent to always run F7 (select item) with Baron Key
; event_cmd_f7 ($00:ED97) expects: X points to script, $09d5+X+1 = item ID
    .alloc at 0x00E1EB {
    lda #0xD1
    sta.w event_script + 1
    lda #0xFF
    sta.w event_script + 2
    ldx #0x0000
    stx 0xb3
    jmp.w event_cmd_f7
    }
}
