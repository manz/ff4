; ----------------
; Final Fantasy IV the new hack.
; ----------------

; Forward declaration - ConditionalBG1VOFS is at start of relocated region ($208000)
ConditionalBG1VOFS := 0x208000

.include "src/libmz.i"
.include "src/system_menus_text.i"

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
}


.include "src/places_names.s"
.include "src/new_game.s"
.include "src/credits.s"
.include "src/ingame/menus.i"
; item name expansion patches
.include "src/ingame/items_menu.s"


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
    .db 0x02                            ; Cartridge Type
    .db 0x0B                            ; ~ 0BH ROM Size
    .db 0x07                            ; RAM Size


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

*=0x0AF000
.incbin "fonts/8x8.bin"                 ; *=0x0AFF00-0x10 * 10

;*=0x0AF900
;	.incbin 'assets/vwf_precomp.bin'


*=0x0FA710
    """Patch des noms des personages"""
.incbin "assets/characters_names.dat"   ; *=0x0F8AB0
;	.incbin 'assets/attack-names.dat'

;*=0x0f8000

;.incbin "assets/items.dat"

*=0x0E9800

.incbin "assets/monsters.dat"

*=0x208000
"""Relocated Region"""

; Conditional BG1VOFS write for HDMA inventory scrolling
; Called from UpdateScrollRegs at $14FF2D via JSL
; Skips BG1VOFS write when menu HDMA is active
; Address is defined as constant ConditionalBG1VOFS := $208000
.if INVENTORY_ROLLING_BUFFER {
    ; Check if menu HDMA is enabled (use long addressing, DB may be $00)
    .db 0xAF                        ; LDA.L opcode
    .dw menu_hdma_enable            ; $1BAE
    .db 0x7E                        ; Bank $7E
    bne     _cond_skip_bg1vofs
    ; HDMA not active - do original BG1VOFS writes
    ; Menu context: D=$0100, so $93 reads from $0193
    lda.b   0x93
    sta.w   0x210E
    lda.b   0x94
    sta.w   0x210E
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
.import "places_names_window"
; system menu text routines
.import "system_menus_text"
.import "dakuten"

; menu text scopes
.import "menus/start_screen_text"
.import "menus/tools_shop_text"
.import "menus/in_game_text"

; Relocated multiply-by-12 for item name offset
; Called from $019023 via JSL
; Input: $43 = item ID (16-bit mode active)
; Output: X = offset into ItemName table
MultiplyItemIndex12:
    lda     0x43
    clc
    adc     0x43         ; x2
    adc     0x43         ; x3
    asl
    asl                 ; x12
    tax
    rtl

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

*=0x218000
.incbin "assets/bank1_1.ptr"
.incbin "assets/bank1_2.ptr"

.incbin "assets/bank2.ptr"

*=0x228000

.incbin "assets/bank1_1.dat"

*=0x24A000

.incbin "assets/bank1_2.dat"

*=0x25A000

.incbin "assets/bank2.dat"

*=0x27B000

.incbin "assets/battle_statuses.dat"

*=0x288000
.incbin "assets/menu_font.dat"
.incbin "assets/font.dat"
.incbin "assets/wicked_font.dat"

.incbin "assets/book_font.dat"

.incbin "assets/bold_font.dat"

.incbin "assets/battle_commands.dat"

font_table:
    .pointer assets_font_dat
    .pointer assets_wicked_font_dat
    .pointer assets_book_font_dat
    .pointer assets_bold_font_dat


.incbin "assets/credits_text.bin"

*=0x298000
.incbin "assets/battle_messages.ptr"

.incbin "assets/battle_messages.dat"

*=0x299900
.incbin "assets/battle_text.ptr"

.incbin "assets/battle_text.dat"

*=0x318000
    """Splash screen assets"""
.if ENABLE_INTRO {
    .incbin "assets/intro.map"
    .incbin "assets/intro.col"
    .incbin "assets/intro.set"
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
;end

