"""The game picks a pointer's messages by index: each French pointer keeps the Japanese's count of `[end]`s."""
from __future__ import annotations

from pathlib import Path

import pytest

from utils.script_xml import pointer_texts

BANKS = ("bank1-1.xml", "bank1-2.xml", "bank2.xml")


def _ends(text: str) -> int:
    return text.count("[end]")


@pytest.mark.parametrize("bank", BANKS)
def test_each_pointer_keeps_the_japanese_message_count(bank: str) -> None:
    japanese, french = pointer_texts(Path("text/jp") / bank), pointer_texts(Path("text/fr") / bank)
    last = max(japanese, key=int)  # the dump's last pointer runs to the bank's end, unterminated
    mismatches = [(pointer, _ends(text), _ends(french.get(pointer, "")))
                  for pointer, text in japanese.items() if pointer != last and _ends(text) != _ends(french.get(pointer, ""))]
    assert mismatches == []
