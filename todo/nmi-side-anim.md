# NMI-side anim writes (FF5/FF6 architecture)

## What

Move per-frame animation WRITES from main-loop (WaitFrameMain chain)
to NMI body. NMI fires every vblank guaranteed ; anim stays smooth
even when main-loop overruns and skips an iteration. FF5/FF6 already
do this ; FF4 doesn't.

## Why

Profile shows engine completes ~40 frames per 60 NMI vblanks
(post-gating). Other 20 vblanks fire while main-loop is mid-
iteration. Anim writes that live in main-loop only happen on those
40 frames ; the other 20 keep stale state. Visually = stutter.

FF4's `$1813` frame counter is NMI-driven (accurate), but the
consumers (UpdateFlyingHDMA, sprite-pos calc, etc.) run from main-
loop so they only sample $1813 every 1+ frame.

## Scope of audit (`WaitFrameMain` @$02:8295 chain)

Each child evaluated for NMI-safety + benefit:

| Function | Address | NMI-safe? | Notes |
|---|---|---|---|
| ImmediateMenuUpdate | $02:966D | maybe | one-shot dispatch via $1823 ; idempotent if $1823 cleared after |
| PeriodicMenuUpdate | $02:96FA | NO | spin-waits on IRQ ; rotates Tfr* ; most periodic entries we noop'd |
| UpdateObjPos | $02:82B9 | partial | calls UpdateCharAnimPos + UpdateFlyingHDMA + UpdateMonsterPos |
| `UpdateCharAnimPos` | ? | yes | reads NMI counter, writes char pos |
| `UpdateFlyingHDMA` | $02:82E1 | NO (spin-waits on $f353 IRQ) | needs no-wait variant |
| `UpdateMonsterPos` | ? | yes | sprite pos calc |
| RedrawMainMenu | $02:96C8 | NO | calls DrawCmdWindow which renders text via WRAM staging then DMA queue ; should stay main-loop, gated by our dirty bits |
| CheckAutoCloseMenu / CloseMenu | $02:F741 / $02:ABD2 | NO | input + state machine, main-loop only |
| UpdateObjBuf | $02:892E | yes | sprite OAM build |

Move candidates: `UpdateCharAnimPos`, `UpdateFlyingHDMA`,
`UpdateMonsterPos`, `UpdateObjBuf`. These produce sprite OAM Y-pos
+ HDMA table updates ; visible state.

## Approach

### Phase 1: shim entry in dma_transfer

Already have a tail call to TfrSprites at end of
`messages_vwf.dma_transfer`. Insert a per-NMI anim pass BEFORE the
TfrSprites tail call so anim writes update WRAM/HDMA tables, then
TfrSprites DMA's the fresh OAM to PPU.

```asm
dma_transfer:
    ...existing tile/tilemap DMAs...
    jsr.l 0x028302   ; SetFlyingHDMA hook (no-wait variant)
    jsr.l 0x03fe03   ; existing TfrSprites tail
    rtl
```

### Phase 2: no-wait UpdateFlyingHDMA

Patch `$02:82E8` to skip the `lda $f353; beq _self` spin-wait
(5 bytes -> 5 NOPs). The wait existed to avoid mid-fetch HDMA
tearing in main-loop context ; in NMI/vblank, HDMA is idle, write
is safe. Main-loop call site still uses the function (harmless,
just slightly less optimal cadence).

### Phase 3: move sprite-pos calc into NMI

`UpdateCharSprites` (sprite.asm @e24c) ALREADY runs in
BattleNMI body @8365 line 592. The `$efc8,x` Y-offset feeds OAM.
But the CHAR float status read at @df90 only fires if `$0f` has
bit $40 set ; otherwise sprite Y stays at $efc8's last value.

Verify the float path runs every NMI for floating chars
(Float spell on party). Likely already smooth.

For monsters: monster Y comes from a different path ; need to
trace. Look at `UpdateMonsterPos` and the BG1 vscroll register
write that uses $efc8 or monster equivalent.

### Phase 4: HDMA table update from NMI directly

Currently `SetFlyingHDMA` writes 560 bytes to $7614/$76A0/$772C/
$77B8 each call. Done in main-loop. If we move to NMI, that's
~3K cycles per vblank ; eats into our DMA budget.

Optimize: use a single DMA to fill the HDMA table from a pre-
computed source instead of unrolled per-byte stores. Or only
update the first 8 bytes (HDMA tables often repeat).

## Files

- `src/battle/redraw_writer_patches.s` : add no-wait patch at
  $02:82E8 + hook in dma_transfer tail
- `src/battle/message.s` : `dma_transfer` body - add jsr.l hooks
  for anim updates before TfrSprites tail
- `todo/nmi-side-anim.md` : this doc, update as phases land

## Tests

- `tests/_profile/profile_bank20.py` : measure dma_transfer
  inclusive cycle delta after each phase
- Visual smoke on `ff4-battle-ext.kss` : Zu wing flap, char float
  state if any party member has Float

## Crack / risk

- **HDMA mid-fetch tearing**: skipping spin-wait might cause
  occasional torn HDMA. Vblank writes should be safe but verify
  with actual hardware test eventually.
- **NMI budget**: vblank is ~1900 cycles. Our DMA pass uses ~5K
  already (assumes forced-blank extending the window). Adding
  3K SetFlyingHDMA pushes deeper into visible scanlines. Forced-
  blank toggle still on the table (todo earlier).
- **Double-fire**: main-loop UpdateFlyingHDMA still runs ; NMI
  version duplicates the write each frame. Mostly harmless but
  wastes ~3K cycles. Phase 5 could noop the main-loop call site.
- **$3a58-style flag**: instead of always firing the anim update,
  gate on a "anim dirty" bit set only when phase advances enough
  to change visible output. FF6 pattern at battle_main.asm:2675
  shows the throttle-by-frame-counter technique.
