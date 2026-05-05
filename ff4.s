; ----------------
; Final Fantasy IV the new hack.
; ----------------

; Forward declaration - ConditionalBG1VOFS is at start of relocated region ($208000)
ConditionalBG1VOFS := 0x208000

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
    """
    patch snes cartrdige type
    original PCB: SHVC-1A3B
    target PCB: SHVC-1A5B
    """
    .ascii "Final Fantasy IV     "

    ;FFD5 20H / 30H Map Mode

*=0xFFD6
    .db 0x02                                  ; Cartridge Type
    .db 0x0B                                  ; ~ 0BH ROM Size
    .db 0x07                                  ; RAM Size
.if ENABLE_BRK_HANDLER {
    *=0x00FFE0
    """JML trampoline in vector-table padding ; native/emu BRK vectors point here."""
    jmp.l brk_handler
    *=0x00FFE6
    .dw 0xFFE0
    *=0x00FFFE
    .dw 0xFFE0
}


*=0x008031
    """déroutage pour ajouter le splash screen"""

.if ENABLE_INTRO {
    jsr.l start_splash_screen
} else {
    jsr.l clear_ram
}


*=0x00B463
    """déroutage pour utiliser la vwf dans les dialogues."""
    jsr.l vwfstart
    rts

*=0x208000
    """Relocated Region"""

    ; Conditional BG1VOFS write for HDMA inventory scrolling
    ; Called from UpdateScrollRegs at $14FF2D via JSL
    ; Skips BG1VOFS write when menu HDMA is active
    ; Address is defined as constant ConditionalBG1VOFS := $208000
.if INVENTORY_ROLLING_BUFFER {
    ; Check if menu HDMA is enabled (use long addressing, DB may be $00)
    .db 0xAF
    ; LDA.L opcode
    .dw menu_hdma_enable
    ; $1BAE
    .db 0x7E
    ; Bank $7E
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
    .import "battle/commands_reloc"
    .import "battle/items_reloc"
    .import "battle/math_reloc"
    .if INVENTORY_ROLLING_BUFFER {
    .import "battle/inventory_rolling"
    }
}
; dialog.s is now imported as a module (see .import "dialog" above)
.import "ingame/places_names_window"
; system menu text routines
.import "menus/system_menus_text"
.import "dakuten"

; menu text scopes
.import "menus/start_screen_text"
.import "menus/tools_shop_text"
.import "menus/in_game_text"
.import "assets"

; Relocated multiply-by-12 for item name offset
; Called from $019023 via JSL
; Input: $43 = item ID (16-bit mode active)
; Output: X = offset into ItemName table

MultiplyItemIndex12:
    lda 0x43
    clc
    adc 0x43                                  ; x2
    adc 0x43                                  ; x3
    asl
    asl                                       ; x12
    tax
    rtl

brk_handler:
    """
    BRK trap: mask interrupts, disable NMI, capture P/PC/PB into
    $710100-$710103 (extended SRAM, persists across reset) then STP
    so kintsuki halts. CPU pushes (low->high addr): P, PC.lo, PC.hi,
    PB. Pulled in reverse. Pushed PC = BRK+2.
    """
    sei
    sep #0x20
    lda #0x00
    sta.l 0x004200
    pla
    sta.l 0x710100
    rep #0x20
    pla
    sta.l 0x710101
    sep #0x20
    pla
    sta.l 0x710103
    stp
.if INVENTORY_ROLLING_BUFFER {
    .import "ingame/init_bg_scroll_hdma"
    .include "src/ingame/inventory_rolling.s"

}
.if TREASURE_INVENTORY_ROLLING {
    .include "src/ingame/treasure_rolling.s"
}
; binary text assets
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
;end
