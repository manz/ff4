"""The 8x8 font's dakuten table (get_dakuten, $01:8E32): an accented letter draws as its accent over the bare letter.

It comes from the 8x8 menu table: built from the small VWF's (accented capitals folded onto the bare letters' codes),
the bare A E I O U drew with accents and the real accented codes fell outside the table, so Namingway's grids broke.
"""
from __future__ import annotations

import struct
from pathlib import Path

import pytest
from script import Table

from utils.dakutens import generate_dakutens

MENU_TABLE = Table("text/ff4_menus.tbl")
DAKUTENS = Path("build/gen/dakuten.bin")


def _pairs() -> dict[int, bytes]:
    if not DAKUTENS.exists():
        pytest.skip("build/gen/dakuten.bin not built")
    data = DAKUTENS.read_bytes()
    lowest, end = struct.unpack("<HH", data[:4])
    return {code: data[4 + (code - lowest) * 2: 6 + (code - lowest) * 2] for code in range(lowest, end)}


def test_the_build_uses_the_8x8_table() -> None:
    assert DAKUTENS.exists() and DAKUTENS.read_bytes() == generate_dakutens(MENU_TABLE)


@pytest.mark.parametrize("letter", "AEIOU")
def test_a_bare_capital_has_no_accent(letter: str) -> None:
    assert _pairs().get(MENU_TABLE.to_bytes(letter)[0], b"\x00\x00") == b"\x00\x00"


def test_an_accented_letter_is_its_accent_over_the_bare_letter() -> None:
    assert _pairs()[MENU_TABLE.to_bytes("é")[0]][1:] == MENU_TABLE.to_bytes("e")
