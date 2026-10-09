"""Namingway's letters: every one draws as the same letter in a dialog (names are stored in menu codes)."""
from __future__ import annotations

from pathlib import Path

import pytest

from _ff4kintsuki import kss_path, load_emu_from_kss
from script import Table
from utils.name_codes import drawable_in_dialog, name_codes

MENU_TABLE = Path("text/ff4_menus.tbl")
DIALOG_TABLE = Path("text/ff4fr.tbl")
NAME_LETTERS = 0x01DBBA  # NameAlphaTbl: 3 grids of 80 cells
GRID_CELLS = 240


def test_a_lowercase_accent_maps_to_the_dialog_code_of_the_same_letter():
    codes = name_codes(MENU_TABLE, DIALOG_TABLE)
    menu, dialog = Table(str(MENU_TABLE)), Table(str(DIALOG_TABLE))
    assert codes[menu.to_bytes("é")[0]] == dialog.to_bytes("é")[0]


def test_a_letter_both_tables_share_keeps_its_code():
    codes = name_codes(MENU_TABLE, DIALOG_TABLE)
    a = Table(str(MENU_TABLE)).to_bytes("A")[0]
    assert codes[a] == a


@pytest.fixture(scope="module")
def grid() -> bytes:
    e = load_emu_from_kss(kss_path("ff4-namingway.kss"), settle_frames=1)
    yield bytes(e.read(NAME_LETTERS + i) for i in range(GRID_CELLS))
    e.close()


def test_every_grid_letter_draws_in_dialog(grid: bytes):
    assert drawable_in_dialog(MENU_TABLE, DIALOG_TABLE, grid) == []


def test_the_grids_offer_the_whole_alphabet_both_cases(grid: bytes):
    letters = Table(str(MENU_TABLE)).to_text(bytes(c for c in grid if c))
    assert set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzéèàêù") <= set(letters)
