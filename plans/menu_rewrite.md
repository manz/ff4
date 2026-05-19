# Menu system rewrite

## Why

FF4's menu/UI layer accumulated technical debt that costs disproportionate
effort on every new feature:

- 4 BG3 CHR bases that flip per context (menu `$4000`, town `$4000`-small,
  dialog `$C000`, battle `$5000`).
- 4 staging buffers (`$0774` text, `$7E:D600` BG3, `$7E:B600` BG1,
  `$7E:C600` BG4).
- Tilemap bases shift per BG mode.
- Vanilla `$EB=1` NMI dispatch interleaved with custom rolling-engine hooks.
- Tile-id semantics flip 8-bit / 9-bit by mode.
- Per-menu HDMA channels (5, 6, 4) each with their own header/footer/signal
  hook trio just to anchor the window border while items scroll.
- Save/restore range depends on caller (`$1300` widened to `$2000` then
  bumped again for the VWF leak).

Every new menu feature is an archaeology dig. The current rolling engine
landed in 18 commits and still doesn't cover the key-item picker because
that runs as an overlay on the active map and the existing engine's
assumptions don't hold there.

## Target architecture (FF6-derived)

Both FF5 and FF6 simplify in two key ways FF4 didn't pursue:

1. **Window borders and item text live on different BG layers.** FF6 puts
   the item list on BG1 (HDMA-scrollable), window frames on BG2 (static),
   cursor sprites on BG3. The "anchor the bottom border while items
   scroll" gymnastics dissolve — borders don't move.
2. **HDMA scroll uses a mostly-static ROM table** with one runtime patch
   for the scroll bias. FF6's `LoadItemBG1VScrollHDMATbl`
   (`ff6decomp/src/menu/item.asm:270`) copies a ROM-resident table into
   WRAM and `ADC`s the current scroll position into the variable slice.
   No per-frame buffer_pos / buffer_slots modular math.

### Proposed VRAM map

```
$0000-$2FFF  BG1 + BG2 CHR (mode-1 4bpp, shared map tileset)
$3000-$3FFF  BG1 tilemap (item text — HDMA-scrollable layer)
$4000-$4FFF  ??? (consider relocating sprite CHR here once layout settles)
$5000-$5FFF  BG2 tilemap (window borders — static)
$6000-$7FFF  reserved
$8000-$BFFF  sprite CHR
$C000-$DFFF  BG3 CHR (dialog VWF + description font — shared by all
             BG3-text contexts incl. picker)
$E000-$EFFF  BG3 tilemap (description / overlay text)
```

Single CHR window for BG3-text across menu, dialog, picker. No flipping
BG34NBA per context.

### HDMA strategy (FF6-mirrored)

Per menu:
- Static ROM table `<menu>_HdmaTable` with pre-computed `count + scroll`
  entries for every row of the list. Hand-tuned per menu's vertical layout.
- One runtime subroutine `LoadHdmaTable<menu>` copies ROM table → WRAM
  shadow (e.g. `$7E:9800`), `ADC`s the variable slice with current
  scroll_pos. ~10 instructions.
- HDMA channel 5 hardcoded to scroll BG1VOFS. Only one channel needed;
  no `header_hook` / `footer_hook` / `signal_hook` dispatch.

### Window draw

Single `DrawWindow` writes border tiles to whichever BG staging buffer
is selected. Caller selects BG2 for window frames, BG1 for body content.
No animation, no HDMA window-position channels. Window appears
instantly on tilemap blit.

## Function replacement list

Replace wholesale (vanilla site becomes `JSR thunk; RTS` in bank-01,
thunk JSL's bank-20 reimpl). Old vanilla code becomes unreachable.

| Vanilla | Address | Replaces | Blocks |
|---|---|---|---|
| `DrawWindow` | `$01:80D9` | Custom window-frame blitter writing to selected BG | BG layer split |
| `UpdateItemText` | `$00:B229` | Custom VWF render of N visible rows into BG1 tilemap | Picker integration |
| `DrawItemSlot` inner | `$01:A1ED` | Custom row writer matching new tilemap layout | Per-menu render hooks |
| `ShowItemWindow` | `$00:AF4D` | Custom picker driver routed through rolling engine | Standalone picker |
| `TfrBG1/2/3/4TilesVblank` | `$01:9420-9447` | Unified NMI DMA driver (one entry, dirty-mask dispatch) | 4-trampoline spaghetti |
| Main field-menu loop | `$01:9F7B+` | Custom dispatcher running rolling engine + new draw stack | Vanilla input FSM |

Routines that stay (layer-agnostic, no need to touch):
- `InitItemList` (`$01:B2D3`) — list filter
- `DrawItemCursors` (`$01:A105`) — sprite hand
- `CheckCanUseItem` (`$01:A25D`) — palette decision

## Migration order

Each step is one commit, parking-lot tested via screenshot goldens.

1. **`DrawWindow` reimpl in bank-20** (mirrors vanilla output exactly).
   No call-site changes. Verify byte-for-byte identical render via test.
2. **Switch own trampolines** (`draw_window_trampoline`,
   `_treasure_draw_inventory_window`, `_menu_draw_inventory_window`,
   `_drops_draw_window`) to the new entry. Vanilla `$01:80D9` still alive
   for vanilla callers (event dialogs, etc).
3. **Hijack `$01:80D9`** with `JSR _drawwindow_thunk; RTS`. Vanilla code
   becomes dead.
4. **Per menu: redirect window draw to BG2 staging.** Wrap each menu's
   draw-window call with `SelectBG2 → DrawWindow → SelectBG1`. Border
   moves from BG1 to BG2.
5. **Per menu: delete HDMA header/footer hooks.** Now that border is on
   BG2 (static), BG1 HDMA only needs per-row scroll entries. Collapse
   `update_X_scroll_hdma` to FF6-style static-table + scroll-bias patch.
6. **`UpdateItemText` reimpl.** Replaces vanilla item-list rendering.
   Routes through small-VWF directly.
7. **`DrawItemSlot` reimpl.** Same pattern; replaces per-slot vanilla
   render.
8. **Picker wire-up.** Now trivial — picker is just `DrawWindow` (border
   on BG2) + `UpdateItemText` (VWF on BG1 region) + rolling engine for
   scroll. No more "town context vs menu context" branches.
9. **`TfrBG*TilesVblank` unification.** One vblank DMA driver dispatched
   by a dirty mask. Replaces the 4 vanilla trampolines + each menu's
   per-BG transfer-pending shadow.
10. **Main field-menu loop reimpl.** Last large vanilla function to
    delete. Drives rolling engine + new draw stack from a single
    dispatcher.

## Acceptance gates

- Every commit keeps the 143/19/1 baseline (no new fails).
- Screenshot goldens flag any pixel diff for review — re-record only
  when the diff is intentional.
- After step 5, expect to record new field-menu screenshot goldens
  (border-on-BG2 visual is identical but tilemap snapshot will differ).
- After step 10, delete `src/lib/rolling_buffer.s` macro stubs +
  bank01_trampolines entries that point at unreachable vanilla addresses.

## Out of scope

- World map / airship / battle inventory (different BG modes; pattern
  port-able later once the field-menu pipeline is proven).
- Mode-7 transitions.
- HDMA-driven palette/scroll effects outside the inventory list.
