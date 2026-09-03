"""Shop item-list rendering regression.

The shop draws its list through vanilla `DrawItemName` ($01:9060), which
we hijack into `items_menu_vwf.draw_field_item_name`. That helper treats
DP `$5D` as the slot index and hands each slot its own tile-id window,
but the shop's list loop ($01:C4A0) uses `$5D` as the item-id scratch:
row 4 of a weapon shop put id $4E there, so the renderer asked for tile
base $100 + 78 * 10 = $40C, past both the 9-bit tilemap id and the CHR
buffer. Rows collided on the same tiles, one landed as a black bar, and
the writes ran off the end of VWF_CHR_BUFFER.
"""
from __future__ import annotations

import pytest
from kintsuki import Button

from _ff4kintsuki import kss_path, load_emu_from_kss, tap

KSS = "ff4-buggy-item-shop-press-a.kss"
BG4_STAGING = 0x7EC600
# Tilemap offsets the shop's list loop feeds DrawItemName, from the
# table at $01:C58E. Names render one row below each.
ROW_OFFSETS = (0x0246, 0x02C6, 0x0346, 0x03C6, 0x0446)
NAME_WIDTH = 16
VWF_TILE_BASE = 0x100
VWF_TILE_BUDGET = 0x0A


@pytest.fixture
def shop_emu():
    e = load_emu_from_kss(kss_path(KSS), settle_frames=60)
    tap(e, Button.A, gap=40)      # "Achat" -> item list
    e.run_frames(60)
    yield e
    e.close()


def _row_tiles(emu, offset: int) -> list[int]:
    """Tile ids the name cells of one list row point at."""
    base = BG4_STAGING + offset + 0x40   # names sit on the row below
    ids = []
    for i in range(NAME_WIDTH):
        low = emu.read(base + i * 2)
        attr = emu.read(base + i * 2 + 1)
        ids.append(low | ((attr & 0x01) << 8))
    return ids


def _row_tiles_wide(emu, offset: int, width: int = 20) -> list[int]:
    """Raw tile ids across a whole list row, name and price alike."""
    base = BG4_STAGING + offset + 0x40
    return [emu.read(base + i * 2) for i in range(width)]


def test_rows_render_within_the_vwf_window(shop_emu) -> None:
    """Every glyph cell must point inside the field VWF tile window."""
    limit = VWF_TILE_BASE + len(ROW_OFFSETS) * VWF_TILE_BUDGET
    for row, offset in enumerate(ROW_OFFSETS):
        for tile in _row_tiles(shop_emu, offset):
            if tile == 0xFF or tile < VWF_TILE_BASE:
                continue          # blank filler or fixed-font cell
            assert tile < limit, (
                f"row {row} points at tile ${tile:03x}, past the window "
                f"ending at ${limit:03x}")


def test_rows_own_disjoint_tiles(shop_emu) -> None:
    """Each row owns its own slot, so no two rows share a glyph tile."""
    seen: dict[int, int] = {}
    for row, offset in enumerate(ROW_OFFSETS):
        for tile in _row_tiles(shop_emu, offset):
            if tile == 0xFF or tile < VWF_TILE_BASE:
                continue
            if tile in seen and seen[tile] != row:
                pytest.fail(f"tile ${tile:03x} used by rows "
                            f"{seen[tile]} and {row}")
            seen[tile] = row


# Vanilla draws each row's price digits and the "Gils" suffix before the
# name, at these cells of the name row.
PRICE_DIGIT_COLS = (13, 14, 15)
PRICE_SUFFIX_COL = 16
DIGIT_TILES = range(0x80, 0x8A)
GLYPH_G = 0x48


def test_price_survives_the_name_render(shop_emu) -> None:
    """The name render must not blank the price the shop already drew.

    The list loop draws digits and "Gils" into the name row, then calls
    DrawItemName for the same row. Our bottom-row pre-fill blanked
    1 + ITEM_UNLEASHED_TEXT_SIZE cells, which reached columns 13..16 and
    erased the digits plus the "G", leaving every row reading " ils".
    """
    for row, offset in enumerate(ROW_OFFSETS):
        cells = _row_tiles_wide(shop_emu, offset)
        digits = [cells[c] for c in PRICE_DIGIT_COLS]
        assert any(d in DIGIT_TILES for d in digits), (
            f"row {row} has no price digits, got "
            + " ".join(f"${d:02x}" for d in digits))
        assert cells[PRICE_SUFFIX_COL] == GLYPH_G, (
            f"row {row} lost the 'G' of Gils, got ${cells[PRICE_SUFFIX_COL]:02x}")
