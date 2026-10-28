"""Every battle message and battle text fits the message window: 32 cells wide ($EF58 = $0420), 30 inside.

Several lines ran past it (up to 289 px) and were cut off on screen."""
from __future__ import annotations

import re
from pathlib import Path

import pytest
from katsuji import VwfFont, render
from katsuji.script import Table

from utils.script_xml import pointer_texts

INSIDE = 30 * 8 - 4  # the window's inside, a glyph's spacing short of the border
ARGUMENT = "XXXXXXXX"  # [0x6]N, an item or a number: stands in at a wide 8 characters
FILES = tuple(f"text/{lang}/{name}.xml" for lang in ("fr", "en") for name in ("battle_messages", "battle_text"))
FONT = Path("build/gen/menu_font.dat")


def _lines(path: str) -> list[tuple[str, str]]:
    return list(pointer_texts(Path(path)).items())


@pytest.mark.parametrize("path", FILES)
def test_every_line_fits_the_window(path: str) -> None:
    if not FONT.exists():
        pytest.skip("menu_font.dat not built")
    font = VwfFont.decode(FONT.read_bytes())
    table = Table("text/ff4_menus.tbl")
    over = []
    for pointer, line in _lines(path):
        plain = re.sub(r"\[0x6\]\d", ARGUMENT, line.replace("[end]", ""))
        width = render(font, list(table.to_bytes(plain))).shape[1]
        if width > INSIDE:
            over.append((pointer, width))
    assert over == []
