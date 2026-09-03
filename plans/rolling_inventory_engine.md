# Rolling Inventory Engine — Unified Bank-20 Design

Status: draft. Phase 1 = dynamic VWF render preserved. ROM pre-rendered slots
deferred to a later phase.

## Goal

One engine, many menus. Today `inventory_rolling.s`, `treasure_rolling.s`,
`drops_rolling.s`, `key_item_picker.s`, and `shop.s` each duplicate slot
math, scroll animation, HDMA setup, and VWF render orchestration. Drops +
treasure currently share a single VWF CHR region and clobber each other.

Phase 1 collapses them onto a shared engine living in bank-20, driven by a
per-instance state struct. Each menu owns its own struct instance at a fixed
WRAM base. The engine never holds inventory-specific knowledge — render and
draw-window hooks are supplied per instance via the struct.

## Non-goals (Phase 1)

- Pre-rendering slot tiles into ROM and DMAing them in. Comes later.
- Touching the battle inventories. They reuse leaf helpers at most.
- Changing the visible layout, kerning, or tile budget per menu.

## Architecture

```
bank-01 caller (e.g. items_menu, treasure, drops, key_items, shop)
        |
        | JSL with state struct pointer in (e.g.) X
        v
bank-20 rolling_inventory engine
        |
        | reads state.* fields
        | calls state.render_slot_hook / state.draw_window_hook
        v
per-instance hooks back in bank-01 (small, menu-specific)
```

Engine = scroll state machine + slot index math + VWF region setup +
HDMA bookkeeping. Hooks = "how do I draw the window chrome" and "how do I
render slot N into the active VWF region for this menu". Hooks stay in
caller's bank.

## Extended state struct

`RollingBufferState` today is 12 bytes of engine scratch. Phase 1 extends it
with instance config + VWF region fields so the engine reads everything off
the struct pointer. No globals like `VWF_CONFIG_BASE` floating around.

```
.struct RollingBufferState {
    ; --- engine scratch (12 bytes, unchanged) ---
    byte top_row
    byte buffer_pos
    byte edge_row
    byte slot_index
    word base_scroll
    byte hdma_enable
    byte _pad
    byte scroll_state
    byte scroll_remaining
    byte scroll_direction
    byte transfer_pending
    word scroll_anim_offset
    byte hdma_copy_pending

    ; --- instance config ---
    byte visible_rows           ; e.g. 5 field items, 3 shop
    byte slot_height_tiles      ; rows of CHR per slot (usually 2)
    long item_list_ptr          ; far ptr to inventory array
    byte item_count             ; live count (decremented on use/drop)
    byte hdma_channel           ; statically assigned per instance

    ; --- VWF region (pointer to standalone VwfRegionConfig, see below) ---
    long vwf_cfg_ptr

    ; --- hooks (far ptrs, bank-01 routines) ---
    long fn_draw_window         ; draw frame, headers, static chrome (init only)
    long fn_ensure_hdma         ; install instance HDMA channel
    long fn_render_slot         ; render slot at A=index into vwf_stage_ptr

    ; --- dirty tracking ---
    byte dirty_mask             ; bit per visible row, max 8 rows
}
```

Size: ~31 bytes per instance. Five instances = 155 bytes WRAM. Plus 11
bytes per `VwfConfig` (trimmed existing struct from `src/vwf_state.i:74`,
one per rolling instance + any extras for battle).

### Trim + reuse existing `VwfConfig` struct

`src/vwf_state.i:74` already defines `.struct VwfConfig` (14 bytes) as a
forward-compat reservation. Nobody reads it yet ; `VWF_CONFIG_BASE` is one
SRAM slot at `$70:7080`. That single slot IS the clobber bug: coexisting
instances (drops + treasure) need disjoint configs.

`VwfConfig` also carries dead weight: `font_ptr` / `font_bank` /
`kerning_ptr` / `kerning_bank`. We have one font globally and kerning is
already a `flags` bit. Drop those 6 bytes.

Trimmed struct (11 bytes):

```
.struct VwfConfig {
    word tile_id_base    ; first tile_id this renderer owns
    byte slot_budget     ; tile-budget clamp ; $FF = none
    word tilemap_base    ; WRAM dest base (bank-$7E implied)
    byte palette_byte    ; default palette / attr
    byte flags           ; bit 0 = kerning, bit 1 = priority OR ; rest reserved
    word chr_vram_word   ; VRAM word addr for DMA dest
    word chr_byte_count  ; DMA byte count
}
```

Plan: stop inventing a parallel struct. Trim + consume `VwfConfig`:

1. Trim dead font/kerning ptr fields out of `src/vwf_state.i`.
2. Allocate per-instance `VwfConfig` slots at fixed SRAM bases (`$70:7080`,
   `$70:708C`, `$70:7098`, ...). One per rolling instance + any battle
   consumer.
3. Migrate `src/vwf.s` / `src/small_vwf/render.s` to read `VwfConfig` fields
   instead of hardcoded tile_id base + tilemap dest. Font ptr stays the
   single global it always was.

`RollingBufferState.vwf_cfg_ptr` (`long`) points at the instance's
`VwfConfig`. Battle reuses the same struct.

Resolved design points:

- **No `fn_format_qty`.** Render hook owns layout. Key items hook writes name
  only; field items hook writes name + qty. Engine never branches on it.
- **No bank fields.** `item_list_ptr` and `vwf_stage_ptr` are `long`. Removes
  "did you set the bank" footgun.
- **HDMA channel = static struct field, not free-list.** Coexistence map is
  known at design time (only drops + treasure overlap), so allocation is a
  static table: drops gets ch 3, everyone else ch 2. Verify against current
  `src/ingame/init_bg_scroll_hdma.s` before locking numbers.
- **Shop qty overlay = caller's problem.** Shop calls
  `rolling_engine_invalidate_slot` on qty change; its render hook draws the
  overlay. Engine stays slot-agnostic.
- **`fn_draw_window` lives in struct** even though only called at init. Keeps
  init signature clean (just `X = state ptr, Y = top_row`); 3 bytes / instance
  is noise.
- **`dirty_mask` capped at 8 rows.** No current menu needs more. Locked.

## WRAM instance bases (proposal)

| Instance      | Base       | Notes                                    |
|---------------|------------|------------------------------------------|
| field items   | `$7E:1BA8` | already there                            |
| treasure inv  | `$7E:1BD0` | already there                            |
| drops         | `$7E:1C00` | new; owns disjoint VWF region            |
| key items     | `$7E:1C30` | already at 1BF0, may relocate            |
| shop          | `$7E:1C60` | new                                      |

Field menu + shop never coexist with treasure/drops, but drops + treasure DO
coexist on the same screen, so their `vwf_chr_base` MUST differ. That is the
bug we fix.

## Engine entry points (bank-20)

All entry points take `X = instance struct ptr` (16-bit, in WRAM, bank fixed
to `$7E`). JSL from bank-01 callers.

```
; Cold init. Zero engine scratch, latch instance config from caller-prefilled
; fields, draw window, render initial visible slots.
;   in : X = state ptr
;        Y = initial top_row (usually 0)
;   out: VWF region populated, HDMA armed
rolling_engine_init:

; Per-frame tick. Read pad, advance scroll state machine, schedule VWF
; renders for newly-revealed rows, update HDMA scratch.
;   in : X = state ptr
;        A.b = pad-down bits this frame
;   out: state.dirty_mask reflects rows needing redraw
rolling_engine_tick:

; NMI-time flush. Walk dirty_mask, DMA VWF stage -> VRAM, write tilemap.
; MUST be called inside force-blank or HDMA gap window.
;   in : X = state ptr
rolling_engine_vblank_flush:

; Cursor / selection helpers — thin wrappers over slot_index math.
rolling_engine_cursor_up:
rolling_engine_cursor_down:

; Mutation API for callers that add / remove items mid-menu.
;   in : X = state ptr
;        A = slot index being mutated
; Marks affected rows dirty; engine re-renders next tick.
rolling_engine_invalidate_slot:
rolling_engine_invalidate_all:

; Teardown. Tear down HDMA channel, leave state struct intact for re-entry.
rolling_engine_shutdown:
```

Internally the engine reuses the existing `engine_*` macros from
`src/lib/rolling_buffer.s` (scroll prepare / start / update / finish). Those
macros become the engine's private kernel; bank-01 callers stop including
them directly.

## Caller skeleton (bank-01)

Each menu shrinks to: declare instance, fill config fields, JSL init,
JSL tick from main loop, JSL flush from NMI, supply 3-4 hook routines.

```
items_menu_open:
    ldx.w #field_items_state
    lda.w #visible_rows_5 : sta.w 0,X RollingBufferState.visible_rows
    ; ... fill remaining config + hooks once ...
    ldy.w #0
    jsl rolling_engine_init
    rts

items_menu_render_slot:        ; A = slot index, X = state ptr
    ; existing VWF render code, writes to state.vwf_stage_ptr
    rtl
```

Hooks are `.long` because engine lives in bank-20 and hooks in bank-01.
Engine does `jsl [state + fn_render_slot]` style indirection (via a small
trampoline since 65816 has no JSL-indirect).

## Migration plan — single branch, multi-commit, squash at merge

Single feature branch. Each commit green at HEAD. TDD per commit (failing
test first, commit when green). Squash to one commit at merge time per
`feedback_no_rebase_published_branches`.

0. **Consume existing `VwfConfig`.** Wire `src/vwf.s` and
   `src/small_vwf/render.s` to read from a `VwfConfig*` instead of
   hardcoded font ptr + tile_id base. Allocate one `VwfConfig` slot per
   coexisting instance (drops + treasure get distinct slots). Legacy
   callers point at the original `$70:7080` slot ; un-migrated paths
   unchanged. Clobber bug fixed at VWF layer.
1. **Engine skeleton in bank-20** + extended struct + smoke harness driving
   a fake inventory. No callers migrated. Existing `engine_*` macros become
   engine's private kernel. Engine reads `state.vwf_cfg_ptr` and passes it
   straight through to VWF entry points.
2. **Port field items.** Drop duplicated scroll state machine from
   `inventory_rolling.s`. Goldens: `tests/goldens/field_items/*` unchanged.
3. **Port shop.** Second consumer flushes single-instance assumptions.
4. **Port key items**, enable actual rolling (today it doesn't). New
   goldens for rolling behaviour.
5. **Split drops + treasure VWF regions.** Each gets own `vwf_chr_base` and
   `vwf_dst_tile_id`. New combined golden verifies no clobber.
6. **Delete duplication.** Remove dead code from `inventory_rolling.s` /
   `drops_rolling.s` / `treasure_rolling.s` once all callers are on engine.

## Battle (out of scope, future note)

Battle inventory menus have a different tile budget, OAM-driven cursor, and
tighter NMI window. They can reuse:

- the slot math helpers (which row is visible, where does it map in CHR),
- the VWF stage -> VRAM DMA helper,
- the dirty-mask flush.

They cannot reuse the field scroll-animation state machine as-is. Punt to a
later design once the field side stabilises.

## Verification gates before phase 6

- xdds disassembly of patched ROM at each engine entry point: confirm
  bank-20 location, MX flags, JSL targets resolve.
- Goldens green for field items, shop, key items, drops+treasure combined.
- Mesen-S smoke run: open each menu, scroll past wrap on both directions,
  add/remove items mid-menu, verify dirty_mask handling.
- WRAM check: instance bases do not overlap and stay inside the existing
  `$7E:1Bxx` rolling region (extend allocation if needed; document in
  `sram_management.s`).
