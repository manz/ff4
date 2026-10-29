"""
Bank-$01 RTL wrappers around vanilla menu routines, plus the rolling lists' window data. Imports nothing above
it, keeping the import graph acyclic.
"""
.import "core/preamble"
.include "ingame/macros.i"
.include "ingame/bank01_trampolines.i"
.import "core/vanilla"

.alloc _bank01_vanilla_wrappers in bank01_trampolines {
draw_window_trampoline:
"""Bank-$01 RTL trampoline around original `DrawWindow` ($01:80D9)."""
    jsr.w draw_window
    rtl

check_can_use_item_trampoline:
"""Bank-$01 RTL trampoline around original `CheckCanUseItem` ($01:A25D, sets $DB)."""
    jsr.w check_can_use_item
    rtl

draw_item_slot_inner_trampoline:
"""Bank-$01 RTL trampoline around original `DrawItemSlot` inner ($01:A1ED)."""
    jsr.w draw_item_slot_inner
    rtl

tfr_sprites_vblank_trampoline:
"""Bank-$01 RTL trampoline around original `TfrSpritesVblank` ($01:824C): waits for vblank, then sends OAM."""
    jsr.w tfr_sprites_vblank
    rtl

tfr_bg3_tiles_vblank_trampoline:
"""
Bank-$01 RTL trampoline around `TfrBG3TilesVblank` ($01:9447): BG3 buffer $7E:D600 to VRAM $7000. The treasure
loop never pushes BG3 itself.
"""
    jsr.w tfr_bg3_tiles_vblank
    rtl

tfr_bg4_tiles_vblank_trampoline:
"""
Bank-$01 RTL trampoline around `TfrBG4TilesVblank` ($01:943A): BG4 buffer $7E:C600 to VRAM $7800. The treasure
loop never pushes BG4 itself.
"""
    jsr.w tfr_bg4_tiles_vblank
    rtl

sell_select_bg3_trampoline:
"""
Bank-$01 RTL trampoline around `SelectBG3` ($01:8470): $29 = BG3 buffer $7E:D600, $35 = VRAM $7000.
"""


    jsr.w select_bg3
    rtl

equip_select_bg4_trampoline:
"""
Bank-$01 RTL trampoline around `SelectBG4` ($01:8488): $29 = BG4 buffer $7E:C600.
"""


    jsr.w select_bg4
    rtl

drops_select_bg4_trampoline:
"""
Bank-$01 RTL trampoline around `SelectClearBG4` ($01:8485). The clear matters: stale BG4 staging bleeds across the
screen once ch4 drives the drops band.
"""
    jsr.w select_clear_bg4
    rtl

draw_item_cursors_trampoline:
"""Bank-$01 RTL trampoline around original `DrawItemCursors` ($01:A105)."""
    jsr.w draw_item_cursors
    rtl

update_ctrl_after_scroll_trampoline:
"""Bank-$01 RTL trampoline around original `UpdateCtrlAfterScroll` ($01:82A5)."""
    jsr.w update_ctrl_after_scroll
    rtl

_init_item_list_trampoline:
"""Bank-$01 trampoline for original InitItemList @ $01:B2D3 (filters $1440 -> $0712 by key-item ID range)."""
    jsr.w init_item_list
    rtl

reset_sprites_trampoline:
"""Bank-$01 RTL trampoline around original `ResetSprites` ($01:8D6A)."""
    jsr.w reset_sprites
    rtl
}

.alloc _bank01_treasure_windows in bank01_trampolines {
; Height 12: bottom border at BG row 13, where the rolling-buffer footer (BASE + 16) reads it.
treasure_inventory_window:
"""Bank-$01 window data for the treasure inventory list (5 visible rows, BG3)."""
    menu_window(0, 0, 30, 12)

treasure_drops_window:
"""
Bank-$01 window data for the treasure drops list (5 visible rows, BG4), anchored at BG (0, 0); HDMA shows it at
screen y=24. Bottom border at row 13.
"""


    menu_window(0, 0, 30, 12)
}
