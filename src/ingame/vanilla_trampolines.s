"""
Bank-$01 RTL wrappers around vanilla menu routines, plus the rolling lists' window data.

The rolling list modules, the shared engine and the instance trampolines all call these; they depend on
nothing above them, which keeps the import graph acyclic.
"""
.import "preamble"
.include "config.i"
.include "src/ingame/macros.i"
.include "src/ingame/bank01_trampolines.i"

.if INVENTORY_ROLLING_BUFFER {
    .alloc bank01_vanilla_wrappers in bank01_trampolines {
draw_window_trampoline:
"""Bank-$01 RTL trampoline around original `DrawWindow` ($01:80D9)."""
    jsr 0x80D9
; original DrawWindow at $01:80D9
    rtl

check_can_use_item_trampoline:
"""Bank-$01 RTL trampoline around original `CheckCanUseItem` ($01:A25D)."""
    jsr 0xA25D
; original CheckCanUseItem at $01:A25D (sets $DB)
    rtl

draw_item_slot_inner_trampoline:
"""Bank-$01 RTL trampoline around original `DrawItemSlot` inner ($01:A1ED)."""
    jsr 0xA1ED
; original DrawItemSlot inner at $01:A1ED
    rtl

tfr_sprites_vblank_trampoline:
"""Bank-$01 RTL trampoline around original `TfrSpritesVblank` ($01:824F)."""
    jsr 0x824F
; original @ $01:824F
    rtl

tfr_bg2_tiles_vblank_trampoline:
"""Bank-$01 RTL trampoline around original `TfrBG2TilesVblank` ($01:9420)."""
    jsr 0x9420
; original @ $01:9420
    rtl

tfr_bg3_tiles_vblank_trampoline:
    jsr 0x9447
; original @ $01:9447 - pushes BG3 buffer at $7E:D600 to VRAM $7000
; over a vblank-bounded chunked DMA. Used by the treasure rolling
; buffer: render writes go to the BG3 staging area but original's
; treasure main loop only refreshes BG2/sprites mid-menu, so without
; this call the rolling-buffer slot updates never make it on screen.
    rtl

tfr_bg4_tiles_vblank_trampoline:
    jsr 0x943A
; original @ $01:943A - pushes BG4 buffer at $7E:C600 to VRAM $7800.
; Used by the drops rolling buffer: drops items render into the BG4
; frame that already holds TreasureItemsWindow, but the treasure main
; loop never re-DMAs BG4 mid-menu so swap/scroll updates would stay
; in WRAM without this call.
    rtl

sell_select_bg3_trampoline:
"""
Bank-$01 RTL trampoline around original `SelectBG3` ($01:8470).

Points $29 at the BG3 buffer ($7E:D600) and $35 at its VRAM tilemap
($7000), which is where the sell list renders.
"""


    jsr 0x8470
    rtl

equip_select_bg4_trampoline:
"""
Bank-$01 RTL trampoline around original `SelectBG4` ($01:8488).

Points $29 at the BG4 buffer ($7E:C600), where the equip list renders.
"""


    jsr 0x8488
    rtl

drops_select_bg4_trampoline:
    jsr 0x8485
; original SelectClearBG4 at $01:8485 - wipes BG4 staging to blank
; tiles before falling through to SelectBG4 ($8488). Without the
; clear, $C600..$CDFF holds whatever the previous menu/screen left
; there, which gets DMA'd to BG4 VRAM and bleeds across the screen
; once HDMA enables ch4 for the drops band.
    rtl

draw_item_cursors_trampoline:
"""Bank-$01 RTL trampoline around original `DrawItemCursors` ($01:A105)."""
    jsr 0xA105
; original @ $01:A105
    rtl

update_ctrl_after_scroll_trampoline:
"""Bank-$01 RTL trampoline around original `UpdateCtrlAfterScroll` ($01:82A5)."""
    jsr 0x82A5
; original @ $01:82A5
    rtl

init_item_list_trampoline:
"""Bank-$01 trampoline for original InitItemList @ $01:B2D3 (filters $1440 -> $0712 by key-item ID range)."""
    jsr 0xB2D3
    rtl

reset_sprites_trampoline:
"""Bank-$01 RTL trampoline around original `ResetSprites` ($01:8D6A)."""
    jsr 0x8D6A
; original @ $01:8D6A
    rtl
    }
}

.if TREASURE_INVENTORY_ROLLING {
    .alloc bank01_treasure_windows in bank01_trampolines {
; Custom InventoryWindow data for the treasure inventory list. Built
; via menu_window(left, top, width, height) so the layout matches
; original window blobs (cursor word + width/height byte pair).
; DrawWindowTiles emits 1 + height + 1 BG rows. height = 12 →
; 14 rows total → bottom border at BG row 13, lining up with the
; rolling-buffer footer scanlines (BASE + 16 = -104 with BASE = -120
; → screen 208-223 reads BG line 104-119 = rows 13-14).
treasure_inventory_window:
"""Bank-$01 window data for the treasure inventory list (5 visible rows, BG3)."""
    menu_window(0, 0, 30, 12)

; Drops band window anchored at BG (0, 0). HDMA shifts BG4VOFS by
; -24 so the window appears on screen at y=24 (matching where the
; original TreasureItemsWindow at $01:E275 lived). Anchoring at the
; tilemap origin keeps the per-row HDMA offsets consistent with the
; treasure-inventory layout - same shape, easier math.
treasure_drops_window:
"""
Bank-$01 window data for the treasure drops list (5 visible rows, BG4).

Body height 12 = staging rows 1..12 with bottom border at row 13. Items
render at staging rows 1,3,5,7,9 and the HDMA footer reads -8 to land
the bottom border at screen y=112..120 (just below the 5th item).
"""


    menu_window(0, 0, 30, 12)
    }
}
