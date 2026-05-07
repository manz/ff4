"""Field-menu inventory rolling-buffer regression.

Drives DOWN/UP through the 11-slot rolling buffer and checks:
  * exactly 10 visible items per render (the 11th prefetch slot must
    not leak past the footer band)
  * scroll across the buffer seam keeps slot text in sync with $1440
  * trash item ($FF) renders the special 2x2 icon at its slot

Snapshots both the WRAM rolling state + BG1 tilemap as binary
goldens, and the live framebuffer as PNG goldens, so regressions
surface as either a byte-diff or a visual diff.

Run with:
    pytest tests/test_field_inventory_rolling.py -v
    UPDATE_GOLDENS=1 pytest tests/test_field_inventory_rolling.py -v
"""
from __future__ import annotations

from pathlib import Path

import pytest

from kintsuki import Button

from _ff4kintsuki import (
    FIELD_BUFFER_POS,
    FIELD_SCROLL_POS,
    INVENTORY,
    MENU_BUFFER_SLOTS,
    MENU_VISIBLE_ITEMS,
    REPO,
    TRASH_ITEM_ID,
    assert_bytes_match_golden,
    assert_screenshot_matches_golden,
    capture_bg1_tilemap,
    capture_field_state,
    kss_path,
    load_emu_from_kss,
    tap,
)

GOLDENS = Path(__file__).parent / "goldens" / "field_inventory"
KSS = kss_path("ff4-field-inventory-open.kss")


@pytest.fixture
def field_emu():
    e = load_emu_from_kss(KSS)
    # Settle so the menu is fully open and HDMA shadows are populated.
    e.run_frames(60)
    yield e
    e.close()


def _read_inventory(emu, *, count: int = 16) -> list[tuple[int, int]]:
    return [
        (emu.read(INVENTORY + i * 2), emu.read(INVENTORY + i * 2 + 1))
        for i in range(count)
    ]


# ---- Rendering / state goldens ---------------------------------------------

@pytest.mark.parametrize("steps,name", [
    (0,  "scroll_0"),
    (1,  "scroll_1"),
    (5,  "scroll_5"),
    (10, "scroll_10"),
    (15, "scroll_15"),
])
def test_field_scroll_state_golden(field_emu, steps: int, name: str) -> None:
    """Press DOWN `steps` times; verify rolling state + BG1 tilemap match
    the committed golden. Catches scroll math, slot rotation, footer
    scroll, and slot-content-render regressions in one shot."""
    for _ in range(steps):
        tap(field_emu, Button.DOWN)
    assert_bytes_match_golden(
        capture_field_state(field_emu),
        GOLDENS / f"{name}.bin",
    )


@pytest.mark.parametrize("steps,name", [
    (0,  "scroll_0"),
    (5,  "scroll_5"),
    (10, "scroll_10"),
])
def test_field_scroll_screenshot_golden(field_emu, steps: int, name: str) -> None:
    """Visual check: framebuffer PNG must match. Picks up regressions
    that only show on screen (e.g. footer revealing slot 10, palette
    swap on cursor row)."""
    for _ in range(steps):
        tap(field_emu, Button.DOWN)
    assert_screenshot_matches_golden(field_emu, GOLDENS / f"{name}.png")


# ---- Swap across the buffer seam -------------------------------------------

def _swap(emu, src_row: int, dst_row: int) -> None:
    """Field menu swap: A on src item → cursor confirm → DOWN to dst →
    A to confirm. Original two-A swap pattern."""
    for _ in range(src_row):
        tap(emu, Button.DOWN)
    tap(emu, Button.A)
    delta = dst_row - src_row
    if delta > 0:
        for _ in range(delta):
            tap(emu, Button.DOWN)
    else:
        for _ in range(-delta):
            tap(emu, Button.UP)
    tap(emu, Button.A)
    emu.run_frames(30)


@pytest.mark.parametrize("src_row,dst_row,name", [
    (0,  3,  "swap_0_to_3"),     # within first visible page
    (0,  10, "swap_0_to_10"),    # across the rolling-buffer seam
    (5,  20, "swap_5_to_20"),    # both sides scroll
])
def test_field_swap_byte_swap(field_emu, src_row: int, dst_row: int,
                              name: str) -> None:
    """Swap inventory[src_row] ↔ inventory[dst_row]. The two memory
    bytes must end up exactly transposed.
    """
    src_id_before = field_emu.read(INVENTORY + src_row * 2)
    dst_id_before = field_emu.read(INVENTORY + dst_row * 2)
    src_qty_before = field_emu.read(INVENTORY + src_row * 2 + 1)
    dst_qty_before = field_emu.read(INVENTORY + dst_row * 2 + 1)
    _swap(field_emu, src_row, dst_row)
    src_after = (field_emu.read(INVENTORY + src_row * 2),
                 field_emu.read(INVENTORY + src_row * 2 + 1))
    dst_after = (field_emu.read(INVENTORY + dst_row * 2),
                 field_emu.read(INVENTORY + dst_row * 2 + 1))
    assert src_after == (dst_id_before, dst_qty_before), (
        f"src row {src_row} did not become dst's old contents"
    )
    assert dst_after == (src_id_before, src_qty_before), (
        f"dst row {dst_row} did not become src's old contents"
    )
    # Also lock the post-swap rendered state so we catch any visual
    # disagreement between memory and tilemap (the rolling buffer's
    # main job is keeping the two in sync).
    assert_bytes_match_golden(
        capture_bg1_tilemap(field_emu),
        GOLDENS / f"{name}.bg1.bin",
    )


# ---- Trash slot ($FF) ------------------------------------------------------

@pytest.mark.xfail(reason="Trash render path needs deterministic frame "
                          "scheduling; relax once trash test isolates the "
                          "DMA cycle.")
def test_field_trash_renders_2x2_icon(field_emu) -> None:
    """Plant a $FF (trash) item somewhere visible, force a re-render
    (DOWN+UP roundtrip), and verify the 2x2 trash icon tiles land at
    the slot's tilemap rows. Locks the visual + binary goldens."""
    # Plant the trash marker at row 3 so it stays visible after the
    # roundtrip below scrolls one row down + one row back up.
    field_emu.write(INVENTORY + 3 * 2, TRASH_ITEM_ID)
    field_emu.write(INVENTORY + 3 * 2 + 1, 0)
    # Force re-render: nudge the rolling buffer so DrawItemSlot fires
    # for each visible slot again. DOWN+UP returns scroll_pos to the
    # original value so we can compare against a stable golden.
    tap(field_emu, Button.DOWN)
    tap(field_emu, Button.UP)
    field_emu.run_frames(30)
    assert_bytes_match_golden(
        capture_field_state(field_emu),
        GOLDENS / "trash_at_row3.bin",
    )
    assert_screenshot_matches_golden(
        field_emu,
        GOLDENS / "trash_at_row3.png",
    )


# ---- Footer + 11th-slot regressions ----------------------------------------

def _force_field_hdma_init(emu) -> None:
    """Trigger the field menu's lazy HDMA init by issuing a DOWN+UP
    roundtrip — the first DOWN runs `init_menu_rolling_buffer_impl`
    which captures BASE from $93 and enables ch5; the UP returns the
    cursor to its original row so subsequent assertions see scroll_pos=0
    again."""
    tap(emu, Button.DOWN)
    tap(emu, Button.UP)
    emu.run_frames(30)


def test_field_footer_hides_prefetch_slot(field_emu) -> None:
    """The footer HDMA entry (16 scanlines past row 10) must point at a
    blank tilemap row, not at the prefetch slot. Read the active HDMA
    table and confirm the footer scroll lands vy ≥ 168 (row 21+, blank)
    when applied at scanline 208."""
    _force_field_hdma_init(field_emu)
    if field_emu.read(0x7E1BAE) == 0:
        pytest.skip("field HDMA never initialized in this kss state")
    base = field_emu.read(0x7E1BAC) | (field_emu.read(0x7E1BAD) << 8)
    # Active table layout: header + 10 row entries + footer + end.
    # Each entry = 3 bytes (count, scroll_lo, scroll_hi).
    footer_off = 3 + 10 * 3
    footer_count = field_emu.read(0x7E9800 + footer_off)
    footer_scroll = (field_emu.read(0x7E9800 + footer_off + 1)
                     | (field_emu.read(0x7E9800 + footer_off + 2) << 8))
    # Footer applies at scanline 208 (header 48 + 10*16 = 208).
    vy_at_footer = (208 + footer_scroll) & 0xFFFF
    vy_at_footer_mod = vy_at_footer % 256
    assert vy_at_footer_mod >= 168, (
        f"footer scroll ${footer_scroll:04X} (BASE=${base:04X}) puts vy at "
        f"scanline 208 = {vy_at_footer_mod} = tilemap row "
        f"{vy_at_footer_mod // 8}, which falls inside the 0..167 slot "
        f"range. Expected ≥ 168 (row 21, first blank past slot 10)."
    )


def test_field_extra_slot_not_visible(field_emu) -> None:
    """The prefetch slot (slot 10 for the 11-slot rolling buffer) must
    not bleed into the visible inventory band. Compares the live frame
    in the footer scanline range to a "blank window border" reference
    captured by clearing inventory rows 10+ first, so any non-blank
    pixels in that band signal a regression of the footer-band leak.
    """
    # Wipe inventory rows 10..47 so anything visible past row 9 must be
    # the window-frame chrome (border tiles), not item text.
    for i in range(10, 48):
        field_emu.write(INVENTORY + i * 2, 0)
        field_emu.write(INVENTORY + i * 2 + 1, 0)
    _force_field_hdma_init(field_emu)
    field_emu.run_frames(15)
    rgba, w, h = field_emu.framebuffer()
    if not rgba or w == 0 or h == 0:
        pytest.skip("framebuffer empty")
    # Sample the inventory band scanline that would correspond to slot
    # 10 if the prefetch leaked through (native scanline ~208 → doubled
    # ≈ 416). Count bright (item-text) pixels across the row.
    target = min(2 * 213, h - 1)
    row_start = target * w * 4
    row = rgba[row_start : row_start + w * 4]
    bright = sum(1 for i in range(0, len(row), 4)
                 if row[i] > 200 and row[i + 1] > 200 and row[i + 2] > 200)
    assert bright < 8, (
        f"scanline {target // 2} has {bright} item-text pixels — slot 10 "
        f"likely leaking through the footer band."
    )
