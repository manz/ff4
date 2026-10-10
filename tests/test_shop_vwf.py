"""The shop's labels in the small VWF, beside the owner's line and the item names.

The shop strings (menus/tools_shop_text.s) are a small-VWF menu block drawing tiles $200-$2FF, while the owner's
line goes through the item description ($180-$1FF, re-flushed from the CHR buffer's $800-$FFF at the next NMI).
A menu string used to clear the buffer to its block's end, wiping the description's tiles before that flush: the
owner's line went blank once the buy list drew its prices. ConfirmSell draws the item name with the item id in $5D,
which the VWF renderer reads as a slot: the name took another slot's tiles.

The savestate opened the shop under an older build, so each test leaves it and talks to the owner again.
"""
from __future__ import annotations

import pytest
from kintsuki import Button

from _ff4kintsuki import kss_path, load_emu_from_kss, tap

KSS = "ff4-buggy-item-shop-press-a.kss"
DESCRIPTION_VRAM = 0x5800  # tiles $180-$1FF: the owner's line
DESCRIPTION_BYTES = 0x200  # its first 32 tiles
BG2_TILEMAP = 0x6800 * 2  # byte address, BG2SC $6A
SELL_NAME_CELL = 12 * 32 + 11  # ConfirmSell's name, row 12, column 11
SELL_NAME_TILE = 0x100 + 9 * 10  # field-item slot 9


@pytest.fixture
def shop():
    e = load_emu_from_kss(kss_path(KSS), settle_frames=30)
    for _ in range(4):
        tap(e, Button.B, gap=60)
    e.run_frames(120)
    tap(e, Button.A, gap=150)  # talk to the owner: a shop opened by this build
    yield e
    e.close()


def _ink(vram: bytes, start: int, size: int) -> bool:
    """A glyph pixel in 2bpp tiles cleared to colour 1 ($FF, $00 per row)."""
    return any((vram[i], vram[i + 1]) != (0xFF, 0x00) for i in range(start, start + size, 2))


def test_the_owner_line_survives_the_buy_list(shop) -> None:
    tap(shop, Button.A, gap=90)  # Achat: list, prices and "Que désirez vous ?"
    shop.run_frames(10)
    assert _ink(bytes(shop.vram_read_range(0)), DESCRIPTION_VRAM, DESCRIPTION_BYTES)


def test_the_sell_confirmation_names_from_its_own_slot(shop) -> None:
    tap(shop, Button.RIGHT, gap=20)
    tap(shop, Button.A, gap=90)  # Vente: the inventory
    tap(shop, Button.A, gap=60)  # an item: quantity
    tap(shop, Button.A, gap=60)  # the confirmation window
    vram = bytes(shop.vram_read_range(0))
    cell = BG2_TILEMAP + SELL_NAME_CELL * 2
    assert (vram[cell] | vram[cell + 1] << 8) & 0x3FF == SELL_NAME_TILE
