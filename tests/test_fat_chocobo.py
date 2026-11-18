"""Fat Chocobo's lists (ingame/fat_chocobo_rolling.s): one item per row, every bag or stored item, rolling."""
from __future__ import annotations

from pathlib import Path

from _ff4kintsuki import (
    FIELD_HDMA_ENABLE,
    FULL_PICTURE,
    INVENTORY,
    assert_screenshot_matches_golden,
    kss_path,
    load_emu_from_kss,
    tap,
)
from kintsuki import Button, Emu

GOLDENS = Path(__file__).parent / "goldens" / "fat_chocobo"
STORED = 0x7E1340  # the Fat Chocobo's 126 stored items, id then count
HAND_ROW = 0x7E1BB0
TOP_ROW = 0x7E1BB2
BAG_ITEMS = 48
STORED_ITEMS = 126
FAT_HDMA_BIT = 0x20  # field_menu_rolling.hdma_enable bit that arms ch5 for his lists
HDMAEN = 0x00420C


def _open_deposit() -> Emu:
    emu = load_emu_from_kss(kss_path("ff4-fat-chocobo.kss"), settle_frames=30)
    tap(emu, Button.A, gap=60)  # talk to him
    tap(emu, Button.A, gap=60)  # Déposer
    return emu


def _items(emu: Emu, base: int, count: int) -> list[tuple[int, int]]:
    return [(emu.read(base + 2 * k), emu.read(base + 2 * k + 1)) for k in range(count)]


def _changed_by_a(emu: Emu, base: int, count: int) -> tuple[int, list[int]]:
    before = _items(emu, base, count)
    under_hand = emu.read(TOP_ROW) + emu.read(HAND_ROW)
    tap(emu, Button.A, gap=60)
    after = _items(emu, base, count)
    return under_hand, [k for k in range(count) if before[k] != after[k]]


def _open_withdraw(emu: Emu) -> None:
    for _ in range(4):
        tap(emu, Button.A, gap=40)
        tap(emu, Button.DOWN, gap=16)
    tap(emu, Button.B, gap=40)
    tap(emu, Button.RIGHT, gap=30)  # Retirer
    tap(emu, Button.A, gap=60)


def test_the_deposit_list_golden() -> None:
    emu = _open_deposit()
    try:
        assert_screenshot_matches_golden(emu, GOLDENS / "deposit.png", region=FULL_PICTURE)
    finally:
        emu.close()


def test_the_list_scrolled_golden() -> None:
    emu = _open_deposit()
    try:
        for _ in range(9):
            tap(emu, Button.DOWN, gap=16)
        assert_screenshot_matches_golden(emu, GOLDENS / "scrolled.png", region=FULL_PICTURE)
    finally:
        emu.close()


def test_a_deposits_the_item_under_the_hand() -> None:
    emu = _open_deposit()
    try:
        for _ in range(9):
            tap(emu, Button.DOWN, gap=16)
        under_hand, changed = _changed_by_a(emu, INVENTORY, BAG_ITEMS)
        assert changed == [under_hand]
    finally:
        emu.close()


def test_a_withdraws_the_stored_item_under_the_hand() -> None:
    emu = _open_deposit()
    try:
        _open_withdraw(emu)
        tap(emu, Button.DOWN, gap=16)
        tap(emu, Button.DOWN, gap=16)
        under_hand, changed = _changed_by_a(emu, STORED, STORED_ITEMS)
        assert changed == [under_hand]
    finally:
        emu.close()


def test_the_withdraw_list_golden() -> None:
    emu = _open_deposit()
    try:
        _open_withdraw(emu)
        assert_screenshot_matches_golden(emu, GOLDENS / "withdraw.png", region=FULL_PICTURE)
    finally:
        emu.close()


def test_leaving_him_disarms_the_list_s_hdma() -> None:
    emu = _open_deposit()
    try:
        tap(emu, Button.B, gap=40)
        tap(emu, Button.B, gap=90)
        enables: list[int] = []
        emu.add_write_callback(HDMAEN, HDMAEN, lambda _a, v: enables.append(v))
        emu.run_frames(30)
        assert (emu.read(FIELD_HDMA_ENABLE) & FAT_HDMA_BIT, any(v & FAT_HDMA_BIT for v in enables)) == (0, False)
    finally:
        emu.close()
