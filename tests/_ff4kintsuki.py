"""Helpers for kintsuki-driven ff4 tests.

Centralises the boilerplate that loads the patched ROM + a kintsuki
savestate, walks the input through the treasure menu, and captures
WRAM / VRAM snapshots so individual tests stay focused on assertions.
"""
from __future__ import annotations

import ctypes
from pathlib import Path

import pytest

from kintsuki import Button, Emu

REPO = Path(__file__).resolve().parents[1]
ROM = REPO / "build/ff4.sfc"

# WRAM landmarks mirroring src/ingame/treasure_rolling*.s.
INVENTORY = 0x7E1440
DROPS     = 0x7EFF28
SCROLL_POS = 0x7E1BB7
TREASURE_BUFFER_POS = 0x7E1BD1
TREASURE_EDGE_ROW = 0x7E1BD2
TREASURE_SLOT_INDEX = 0x7E1BD3
TREASURE_BASE_SCROLL = 0x7E1BD4

BG1_TILEMAP_VRAM_BASE = 0x6000  # drops list
BG3_TILEMAP_VRAM_BASE = 0x7000  # rolling-buffer inventory


SAVESTATES = Path(__file__).parent / "savestates"


def kss_path(name: str = "ff4-before-battle-inventory.kss") -> Path:
    return SAVESTATES / name


def load_emu_from_kss(kss: Path | None = None) -> Emu:
    """Load the patched ROM + a kintsuki savestate, settle for ~1 game-second.

    Skips the test if either artifact is missing — keeps CI happy when
    the kss isn't around (gitignored).
    """
    if not ROM.exists():
        pytest.skip(f"ff4.sfc not built at {ROM}")
    kss = kss or kss_path()
    if not kss.exists():
        pytest.skip(f"{kss.name} missing — drop one at tests/savestates/")
    # Tests want deterministic state — skip the .srm sidecar that
    # `kintsuki_load_rom` would otherwise seed cart SRAM with.
    e = Emu(load_srm_sidecar=False)
    e.load_rom(str(ROM))
    blob = kss.read_bytes()
    from kintsuki._native import lib
    buf = (ctypes.c_uint8 * len(blob))(*blob)
    assert lib.kintsuki_load_state(e._handle, buf, len(blob)) == 1
    e.run_frames(60)
    return e


def tap(emu: Emu, button: int, *, hold: int = 6, gap: int = 8) -> None:
    """Press + release a single button with edge-detection-friendly gaps."""
    emu.press(0, button)
    emu.run_frames(hold)
    emu.release(0, button)
    emu.run_frames(gap)


def enter_treasure_picker(emu: Emu, *, settle_frames: int = 300) -> None:
    """From the treasure menu's top-level "Tout prendre / Quitter" choice,
    drive into the bottom-inventory exchange picker. Cursor lands on
    inventory row 0 ready for DOWN/UP navigation.
    """
    emu.run_frames(settle_frames)
    tap(emu, Button.DOWN)        # leave Tout prendre, cursor on drops
    tap(emu, Button.A, gap=20)   # confirm drop, enter Echange picker


def vram_byte(emu: Emu, word_addr: int, hi: bool = False) -> int:
    from kintsuki._native import lib
    return lib.kintsuki_vram_read(emu._handle, word_addr * 2 + (1 if hi else 0))


def capture_bg3_tilemap(emu: Emu, *, rows: int = 14) -> bytes:
    """Read BG3 tilemap rows 0..rows as char bytes (low half of each tile).
    Strips palette/attr so the snapshot is stable across palette swaps."""
    out = bytearray()
    for r in range(rows):
        for tile in range(32):
            out.append(vram_byte(emu, BG3_TILEMAP_VRAM_BASE + r * 32 + tile))
    return bytes(out)


def capture_treasure_state(emu: Emu) -> bytes:
    """Snapshot rolling-buffer state bytes + BG3 tilemap, suitable for
    golden-file regression tests."""
    head = bytes([
        emu.read(SCROLL_POS),
        emu.read(TREASURE_BUFFER_POS),
        emu.read(TREASURE_EDGE_ROW),
        emu.read(TREASURE_SLOT_INDEX),
        emu.read(TREASURE_BASE_SCROLL),
        emu.read(TREASURE_BASE_SCROLL + 1),
    ])
    return head + capture_bg3_tilemap(emu)


# ---- Field-menu (Items submenu) primitives ---------------------------------

FIELD_SCROLL_POS = 0x7E1B1A
FIELD_BUFFER_POS = 0x7E1BA9
FIELD_HDMA_ENABLE = 0x7E1BAE
MENU_VISIBLE_ITEMS = 10
MENU_BUFFER_SLOTS = 11
TRASH_ITEM_ID = 0xFF


def capture_bg1_tilemap(emu: Emu, *, rows: int = 24) -> bytes:
    """Read BG1 tilemap rows 0..rows as char bytes. Field-menu inventory
    lives on BG1 at VRAM word $6000."""
    out = bytearray()
    for r in range(rows):
        for tile in range(32):
            out.append(vram_byte(emu, BG1_TILEMAP_VRAM_BASE + r * 32 + tile))
    return bytes(out)


def capture_field_state(emu: Emu) -> bytes:
    """Snapshot field rolling-buffer state + BG1 tilemap."""
    head = bytes([
        emu.read(FIELD_SCROLL_POS),
        emu.read(FIELD_BUFFER_POS),
        emu.read(FIELD_HDMA_ENABLE),
    ])
    return head + capture_bg1_tilemap(emu)


def screenshot_png(emu: Emu, path: Path) -> None:
    """Write the live framebuffer to `path` as a PNG via the C ABI."""
    path.parent.mkdir(parents=True, exist_ok=True)
    emu.screenshot(str(path))


def assert_screenshot_matches_golden(emu: Emu, golden_path: Path,
                                     *, update: bool = False,
                                     threshold: float = 0.1,
                                     max_diff_pixels: int = 0) -> None:
    """Snapshot the framebuffer via the C-side `screenshot` (which goes
    through `correctedFrame`, so dimensions match the on-disk PNG even
    when ares' raw fb is doubled-x), then run kintsuki's numba-jitted
    pixelmatch against `golden_path`. On first run / `UPDATE_GOLDENS=1`
    records the golden and xfails so it gets committed. On mismatch
    drops `<name>.actual.png` + `<name>.diff.png` next to the golden."""
    import os
    if update or os.environ.get("UPDATE_GOLDENS") == "1" or not golden_path.exists():
        golden_path.parent.mkdir(parents=True, exist_ok=True)
        screenshot_png(emu, golden_path)
        pytest.xfail(f"recorded {golden_path.name} — verify visually + commit")
    actual_path = golden_path.with_suffix(".actual.png")
    screenshot_png(emu, actual_path)
    try:
        from kintsuki._vendor.pixelmatch_numba import pixelmatch
    except ImportError as e:
        pytest.skip(f"kintsuki[pixelmatch] extras not installed: {e}")
    from PIL import Image
    golden_img = Image.open(golden_path).convert("RGBA")
    actual_img = Image.open(actual_path).convert("RGBA")
    if golden_img.size != actual_img.size:
        raise AssertionError(
            f"size mismatch: golden {golden_img.size} vs actual "
            f"{actual_img.size}"
        )
    n, diff = pixelmatch(golden_img, actual_img, threshold=threshold)
    if n > max_diff_pixels:
        diff_path = golden_path.with_suffix(".diff.png")
        diff.save(diff_path, format="PNG")
        raise AssertionError(
            f"{n} diff pixels (threshold={threshold}); "
            f"actual={actual_path} diff={diff_path}"
        )
    actual_path.unlink(missing_ok=True)


def assert_bytes_match_golden(snapshot: bytes, golden_path: Path) -> None:
    """Generic byte-blob golden compare. Records on first run."""
    import os
    if not golden_path.exists() or os.environ.get("UPDATE_GOLDENS") == "1":
        golden_path.parent.mkdir(parents=True, exist_ok=True)
        golden_path.write_bytes(snapshot)
        pytest.xfail(f"recorded {golden_path.name} — verify + commit")
    expected = golden_path.read_bytes()
    assert snapshot == expected, (
        f"snapshot mismatch vs {golden_path.name} "
        f"({len(snapshot)} vs {len(expected)} bytes). "
        f"Re-record with UPDATE_GOLDENS=1 if intended."
    )
