"""Treasure / drops exchange picker: the hand cursor tracks the rows.

The hand sprite sits flush left of the item icon and one pixel above
the row's glyphs, on both the drops band and the inventory list.

The screen also has to keep the hand's sprite CHR: a VWF flush armed
against cart RAM a build never initialised (savestates carry $FF there)
used to DMA 64K over VRAM and blank it.
"""
from __future__ import annotations

import pytest
from kintsuki import Button
from PIL import Image

from _ff4kintsuki import kss_path, load_emu_from_kss, tap

KSS = kss_path("ff4-before-battle-inventory.kss")
PICTURE = (13, 9, 13 + 256, 9 + 224)
HAND_TILE_VRAM = 0x6000 + 0x0A * 32
DROPS_BAND = (32, 120)
INVENTORY_BAND = (128, 224)


def _treasure(steps):
    e = load_emu_from_kss(KSS, settle_frames=600)
    for button in steps:
        tap(e, getattr(Button, button), gap=20)
    return e


def _hand(emu, band) -> tuple[int, int]:
    oam = bytes(emu.oam_read_range(0, 512))
    return next(
        (oam[4 * i], oam[4 * i + 1])
        for i in range(128)
        if band[0] <= oam[4 * i + 1] < band[1] and oam[4 * i] < 32
    )


def _picture(emu, path) -> Image.Image:
    emu.screenshot(str(path))
    return Image.open(path).convert("RGB").crop(PICTURE)


def _lit(im, x, y) -> bool:
    return im.getpixel((x, y))[0] > 200


def _glyph_tops(im, band) -> list[int]:
    lit = [y for y in range(*band) if any(_lit(im, x, y) for x in range(30, 140))]
    return [y for i, y in enumerate(lit) if i == 0 or y - lit[i - 1] > 2]


ROWS = [
    (["DOWN"], DROPS_BAND, 0),
    (["DOWN", "DOWN", "DOWN"], DROPS_BAND, 2),
    (["DOWN", "A"], INVENTORY_BAND, 0),
    (["DOWN", "A", "DOWN", "DOWN", "DOWN"], INVENTORY_BAND, 3),
]


@pytest.mark.parametrize("steps, band, row", ROWS)
def test_hand_sits_on_its_row(steps, band, row, tmp_path):
    e = _treasure(steps)
    try:
        top = _glyph_tops(_picture(e, tmp_path / "s.png"), band)[row]
        assert abs(_hand(e, band)[1] - (top - 1)) <= 1
    finally:
        e.close()


@pytest.mark.parametrize("steps, band, row", ROWS)
def test_hand_stays_left_of_the_row(steps, band, row, tmp_path):
    e = _treasure(steps)
    try:
        im = _picture(e, tmp_path / "s.png")
        top = _glyph_tops(im, band)[row]
        first_lit = min(x for x in range(16, 140) for y in range(top, top + 7) if _lit(im, x, y))
        assert _hand(e, band)[0] + 16 <= first_lit
    finally:
        e.close()


def test_hand_sprite_chr_survives():
    e = _treasure(["DOWN"])
    try:
        assert any(bytes(e.vram_read_range(HAND_TILE_VRAM, 32)))
    finally:
        e.close()
