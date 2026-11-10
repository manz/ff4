"""The save screen's confirmation (ingame/new_game.s): the slot preview and its messages in the small VWF.

Vanilla points Y at bank $01 for "EMPTY" ($01:9801) and the cancel message ($01:CC33); the menu text thunks draw
any Y of $8000 and up from bank $01 as is, kana through the French table.
"""
from __future__ import annotations

from pathlib import Path

import pytest
from _ff4kintsuki import (
    FULL_PICTURE,
    assert_screenshot_matches_golden,
    kss_path,
    load_emu_from_kss,
    tap,
)
from kintsuki import Button

GOLDENS = Path(__file__).parent / "goldens" / "save_confirm"
SAVE_ENABLED = 0x7E1A02  # set on save points
FIXED_VALUE = 0x7E17FE  # $1BE4 once a game runs: anything else previews the slot as empty
SAVE_ROW = 7


def _confirm(*, empty: bool):
    emu = load_emu_from_kss(kss_path("ff4-late-field.kss"), settle_frames=10)
    tap(emu, Button.X, gap=60)
    emu.write(SAVE_ENABLED, 1)
    for _ in range(SAVE_ROW):
        tap(emu, Button.DOWN, gap=16)
    tap(emu, Button.A, gap=90)
    if empty:
        emu.write(FIXED_VALUE, 0)
    tap(emu, Button.A, gap=90)  # the first slot
    return emu


@pytest.fixture
def empty_slot():
    emu = _confirm(empty=True)
    try:
        yield emu
    finally:
        emu.close()


def test_an_empty_preview_says_vide(empty_slot) -> None:
    assert_screenshot_matches_golden(empty_slot, GOLDENS / "empty.png", region=FULL_PICTURE)


def test_oui_says_the_save_is_done() -> None:
    emu = _confirm(empty=False)
    try:
        tap(emu, Button.A, hold=4, gap=30)
        assert_screenshot_matches_golden(emu, GOLDENS / "saved.png", region=FULL_PICTURE)
    finally:
        emu.close()


INVENTORY = 0x7E1440  # item id, count: 2 bytes a slot
TENT = 0xE2
FIELD_MENU_HDMA_ENABLE = 0x7E9C96  # field_menu_rolling.hdma_enable: the field menus' NMI writes it to HDMAEN


def test_the_save_screen_has_no_hdma_after_a_tent() -> None:
    """A Tente used from Objets closes the whole menu (InitMainMenu's saved stack): Objets' exit hook never ran, so
    its HDMA channel 5 stayed in the byte every field menu's NMI writes to HDMAEN. The next save screen lost its second
    block (Analogue Pocket, Super NT), and every submenu was off until Objets opened again."""
    emu = load_emu_from_kss(kss_path("ff4-late-field.kss"), settle_frames=10)
    try:
        emu.write(INVENTORY, TENT)
        emu.write(INVENTORY + 1, 1)
        emu.write(SAVE_ENABLED, 1)
        tap(emu, Button.X, gap=60)
        tap(emu, Button.A, gap=60)  # Objets
        for _ in range(3):
            tap(emu, Button.A, gap=60)  # the Tente, used: the party rests on the field
        emu.run_frames(900)  # the rest scene, back to the field
        tap(emu, Button.X, gap=60)
        emu.write(SAVE_ENABLED, 1)
        for _ in range(SAVE_ROW):
            tap(emu, Button.DOWN, gap=16)
        tap(emu, Button.A, gap=90)
        assert emu.read(FIELD_MENU_HDMA_ENABLE) == 0
    finally:
        emu.close()
