"""Snapshot the battle inventory rolling-buffer tilemap + allocator
state across consecutive frames. Diffs each frame's snapshot against
the prior frame so we can pin down whether the tile_id refs in the
tilemap drift (allocator races), whether the WRAM CHR buffer drifts
(buffer reuse race), or both stay stable while VRAM stays correct.

Usage:
    python3 tests/_profile/dump_inv_tilemap.py
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, "tests")
from kintsuki import Button
from _ff4kintsuki import kss_path, load_emu_from_kss, tap

REPO = Path(__file__).resolve().parents[2]
SYM_PATH = REPO / "build" / "ff4.sym"

# Inventory rolling-buffer tilemap entries live in WRAM around the
# vanilla DrawInventoryItemText slot. The rolling layout stores 6
# slots * 60 bytes starting at $97A6.
SLOT_BASE = 0x7E97A6
SLOT_STRIDE = 60
SLOT_COUNT = 6

# Inventory CHR region in the shared VWF buffer (16 bytes per tile,
# tile_id 0xC0..0xEF -> buffer + $C00..$EF0).
BUFFER_CHR_BASE = 0x703C00
BUFFER_CHR_LEN = 0x300  # 48 tiles * 16

# Allocator state (cross-bank).
ALLOCATED_TILE_ID = 0x702F00

# Gate state (recently moved past inventory tiles).
PENDING_TRANSFER_MASK = 0x703F00
REGION_DIRTY_BITS = 0x703F01
RENDER_SKIPPED = 0x703F02
TILEMAP_PENDING_MASK = 0x703F03

# Rolling-buffer state.
ROLLING_TOP_ROW = 0x7EEF84
ROLLING_BUFFER_POS = 0x7EEF80
ROLLING_SLOT_INDEX = 0x7EEF82


def snapshot(emu) -> dict:
    snap = {
        "tile_id": emu.read(ALLOCATED_TILE_ID),
        "pending": emu.read(PENDING_TRANSFER_MASK),
        "region_dirty": emu.read(REGION_DIRTY_BITS),
        "render_skipped": emu.read(RENDER_SKIPPED),
        "tilemap_pending": emu.read(TILEMAP_PENDING_MASK),
        "rolling_top": emu.read(ROLLING_TOP_ROW),
        "rolling_pos": emu.read(ROLLING_BUFFER_POS),
        "rolling_slot": emu.read(ROLLING_SLOT_INDEX),
        "slots": [
            bytes(emu.read(SLOT_BASE + i * SLOT_STRIDE + j) for j in range(SLOT_STRIDE))
            for i in range(SLOT_COUNT)
        ],
        "buffer_chr": bytes(emu.read(BUFFER_CHR_BASE + i) for i in range(BUFFER_CHR_LEN)),
    }
    return snap


def diff(prev: dict, cur: dict, frame: int) -> None:
    scalars = [
        "tile_id", "pending", "region_dirty", "render_skipped",
        "tilemap_pending", "rolling_top", "rolling_pos", "rolling_slot",
    ]
    changes = []
    for k in scalars:
        if prev[k] != cur[k]:
            changes.append(f"{k}: {prev[k]:02X} -> {cur[k]:02X}")
    for i in range(SLOT_COUNT):
        if prev["slots"][i] != cur["slots"][i]:
            differing = sum(1 for a, b in zip(prev["slots"][i], cur["slots"][i]) if a != b)
            changes.append(f"slot{i}: {differing} bytes differ")
    if prev["buffer_chr"] != cur["buffer_chr"]:
        differing = sum(1 for a, b in zip(prev["buffer_chr"], cur["buffer_chr"]) if a != b)
        changes.append(f"buffer_chr: {differing} / {BUFFER_CHR_LEN} bytes differ")
    print(f"[frame {frame}] " + (", ".join(changes) if changes else "no change"))


def main() -> None:
    emu = load_emu_from_kss(kss_path("ff4-battle.kss"), settle_frames=600)
    # Settle until Cecil's ATB fills + cmd menu opens, then drive the
    # input sequence the user mapped out: DOWN, DOWN, A -> item menu.
    tap(emu, Button.DOWN, gap=20)
    tap(emu, Button.DOWN, gap=20)
    tap(emu, Button.A, gap=60)
    print(f"Initial state after settle + nav:")
    s0 = snapshot(emu)
    print(f"  tile_id={s0['tile_id']:02X} pending={s0['pending']:02X} "
          f"region_dirty={s0['region_dirty']:02X} rolling_slot={s0['rolling_slot']:02X}")
    for i, slot in enumerate(s0["slots"]):
        first16 = slot[:16].hex(" ")
        print(f"  slot{i}[:16]: {first16}")
    print()

    prev = s0
    for f in range(1, 11):
        emu.run_frames(1)
        cur = snapshot(emu)
        diff(prev, cur, f)
        prev = cur

    # Capture the visible framebuffer so we can eyeball the "scrolling"
    # symptom alongside the byte deltas.
    from kintsuki.visual import golden
    out = REPO / "tests" / "goldens" / "battle_init" / "inv_open.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    if out.exists():
        out.unlink()
    golden(emu, out, threshold=0.1, max_diff_pixels=0)
    print(f"\nframebuffer saved to {out}")


if __name__ == "__main__":
    main()
