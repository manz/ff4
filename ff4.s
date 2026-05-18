"""
----------------
Final Fantasy IV the new hack.
----------------
"""

; Forward declaration - conditional_bg1_vofs is at start of relocated region ($208000)
conditional_bg1_vofs := 0x208000

.include "src/libmz.i"
.include "src/items.i"
.include "src/lib/rolling_buffer.s"
.include "src/menus/system_menus_text.i"
.include "src/minimal_vwf_patches.s"
.if BATTLE_ENABLED {
    .include "src/battle/math_patches.s"
    .include "src/battle/graphics_patches.s"
    .if MAGIC_ENABLED {
    .include "src/battle/magic/patches.s"
    .include "src/battle/commands_patches.s"
    }
    .include "src/battle/message_patches.s"
    .include "src/battle/sram_patches.s"
    .if BATTLE_MONSTERS_VWF {
    .include "src/battle/monsters_patches.s"
    }
    .include "src/battle/items_patches.s"
    .include "src/battle/redraw_writer_patches.s"
    .if INVENTORY_ROLLING_BUFFER {
    .include "src/battle/inventory_rolling_patches.s"
    }
    .if TREASURE_DEBUG_ALWAYS_DROP {
    .include "src/battle/debug_always_drop.s"
    }
}

.include "src/ingame/places_names.s"
.include "src/ingame/new_game.s"
.include "src/ingame/credits.s"
.include "src/ingame/menus.i"
; item name expansion patches
.include "src/ingame/items_menu.s"

; Relocated init_bg_scroll_hdma (was at $01:EBD2, frees 566 bytes in bank $01).
; Blob with internal absolute references — pinned to offset $EBD2 within an
; expansion bank. Caller patch retargets the single JSL at $02:818A.
.if INVENTORY_ROLLING_BUFFER {
    .include "src/ingame/init_bg_scroll_hdma_patches.s"
    .include "src/ingame/inventory_rolling_trampolines.s"
}


dialog_bank_ptr_base = 0x218000


*=0xFFC0
    ; patch snes cartridge type
    ; original PCB: SHVC-1A3B
    ; target PCB: SHVC-1A5B
    .ascii "Final Fantasy IV     "

;FFD5 20H / 30H Map Mode

*=0xFFD6
    .db 0x02  ; Cartridge Type
    .db 0x0B  ; ~ 0BH ROM Size
    .db 0x07  ; RAM Size
.if ENABLE_BRK_HANDLER {
    *=0x00FFE0
; JML trampoline in vector-table padding  ; native/emu BRK vectors point here.
    jmp.l brk_handler
    *=0x00FFE6
    .dw 0xFFE0
    *=0x00FFFE
    .dw 0xFFE0
}


*=0x008031
    ; déroutage pour ajouter le splash screen
.if ENABLE_INTRO {
    jsr.l start_splash_screen
} else {
    jsr.l clear_ram
}


*=0x00B463
    ; déroutage pour utiliser la vwf dans les dialogues.
    jsr.l vwfstart
    rts

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

.alloc bank20_main in bank20_reloc {
; --- Inline reloc helpers ------------------------------------------------

; Conditional BG1VOFS write for HDMA inventory scrolling.
; Called from UpdateScrollRegs at $14FF2D via JSL.
; Skips BG1VOFS write when menu HDMA is active.
; Address is pinned by `conditional_bg1_vofs := 0x208000` at the top of
; this file ; `strategy order` keeps it first in the pool.
    .if INVENTORY_ROLLING_BUFFER {
    lda.l 0x7E0000 + menu_hdma_enable
    bne _cond_skip_bg1vofs
; HDMA not active - do original BG1VOFS writes
; Menu context: D=$0100, so $93 reads from $0193
    lda.b 0x93
    sta.w 0x210E
    lda.b 0x94
    sta.w 0x210E

_cond_skip_bg1vofs:
    rtl
    }


clear_ram:
"""
Clear the dialog VWF tile buffer at $702000-$706FFF (16-bit zeroes) after letting the boot ROM init at
$15C9AA.
"""


    jsr.l 0x15C9AA
    {
    lda.b #0x00
    ldx.w #0x0000

_loop:
    sta.l 0x702000, x
    inx
    cpx.w #0x5000
    bne _loop
    }
    rtl


multiply_item_index_12:
"""
Relocated multiply-by-12 for item name offset.
Called from $019023 via JSL.
Input: $43 = item ID (16-bit mode active).
Output: X = offset into ItemName table.
"""


    lda 0x43
    clc
    adc 0x43  ; x2
    adc 0x43  ; x3
    asl
    asl  ; x12
    tax
    rtl


multiply_item_index_17:
"""
Relocated multiply-by-ITEM_UNLEASHED_RECORD_SIZE for the items_unleashed
name offset. Called from $019023 via JSL when the field menu is
wired to the 17-byte assets_items_unleashed_dat table.
Input: $43 = item ID (16-bit mode active).
Output: X = offset into ItemName table.
"""


; ITEM_UNLEASHED_RECORD_SIZE = 17 = (id << 4) + id.
    lda 0x43
    pha
    asl
    asl
    asl
    asl  ; * 16
    clc
    adc 0x01, s  ; * 16 + id = * 17
    tax
    pla  ; balance stack
    rtl


multiply_by_12:
"""A: value to multiply  ; returns A*12 in A."""
    php
    rep #0x20
    and.w #0x00FF
    pha
    asl
    clc
    adc 0x01, s
    asl
    asl
    sta 0x01, s
    pla
    plp
    rtl


multiply_by_17:
"""
A: value to multiply  ; returns A*17 in A. Mirror of multiply_by_12
sized for the 17-byte assets_items_unleashed_dat stride.
"""


    php
    rep #0x20
    and.w #0x00FF
    pha
    asl
    asl
    asl
    asl
    clc
    adc 0x01, s  ; * 16 + value = * 17
    sta 0x01, s
    pla
    plp
    rtl


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
    sta.l 0x004200
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

; end .alloc bank20_main

; Resume implicit org for imported modules. The .alloc above consumes
; $20:8000..$20:8048 (5 inline routines); $20:8100 gives safe margin
; and matches the legacy `*=0x208000` chain so .import modules without
; their own `*=` directive land in bank-20 as expected.

*=0x208100
    ; --- Imported modules ---------------------------------------------------

.import "libmz"
.import "dialog"
.import "kerning"
.if ENABLE_INTRO {
    .import "intro"
}
.import "vwf"
.import "small_vwf/init"

.if BATTLE_ENABLED {
    .import "battle/sram"
    .import "battle/graphics"
    .import "battle/monsters_reloc"
    .if MAGIC_ENABLED {
    .import "battle/magic_reloc"
    }
    .import "battle/redraw_gates"
    .import "battle/commands_reloc"
    .import "battle/items_reloc"
    .import "battle/equip_window"
    .import "battle/math_reloc"
    .if INVENTORY_ROLLING_BUFFER {
    .import "battle/inventory_rolling"
    }
}

.import "ingame/places_names_window"
.import "menus/system_menus_text"
.import "dakuten"
.import "menus/start_screen_text"
.import "menus/tools_shop_text"
.import "menus/in_game_text"
.import "assets"

; --- Includes (gated by build flags) ------------------------------------

.if INVENTORY_ROLLING_BUFFER {
    .import "ingame/init_bg_scroll_hdma"
    .include "src/ingame/inventory_rolling.s"
}

.if TREASURE_INVENTORY_ROLLING {
    .include "src/ingame/treasure_rolling.s"
    .include "src/ingame/drops_rolling.s"
    .include "src/ingame/key_item_picker.s"
}

; --- Binary text assets -------------------------------------------------

.incbin "assets/attack_names.ptr"
.incbin "assets/attack_names.dat"
.incbin "assets/monsters_long.ptr"
.incbin "assets/monsters_long.dat"
.incbin "assets/battle_commands_nul.ptr"

.incbin "assets/battle_commands_nul.dat"
.incbin "assets/magic.dat"
.incbin "assets/places_names.dat"
.incbin "assets/classes.ptr"
.incbin "assets/classes.dat"
.incbin "assets/items.dat"
.incbin "assets/item_descriptions.dat"
.if TREASURE_INVENTORY_ROLLING {
    .include "src/ingame/key_item_picker_patches.s"
}

.if TRIGGER_ENDING_CUTSCENE {
; all effects are the Ending cutscene
    *=0xc436
    lda #0x39
    nop
}

.if DEBUG_SHOW_ITEM_WINDOW {
; Hijack ExecEvent to always run F7 (select item) with Baron Key
; EventCmd_f7 at $00ED96 expects: X points to script, $09d5+X+1 = item ID
    *=0x00E1EB
    lda #0xD1
    sta 0x09d6
    lda #0xFF
    sta 0x09d7
    ldx #0x0000
    stx 0xb3
    jmp.w 0xED96
}

; Park the 17-byte-stride items_unleashed.dat in an empty bank so the
; full 4352-byte table fits without crossing a LoROM bank boundary
; (which would otherwise leave the upper half of the table at
; $21:0xxx, an address LoROM does not map back to ROM data).

*=0x238000
.incbin "assets/items_unleashed.dat"  ; end
