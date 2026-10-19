"""The game picks a pointer's messages by index: each French and English pointer keeps the Japanese's count of `[end]`s."""
from __future__ import annotations

from pathlib import Path

import pytest

from utils.script_xml import pointer_texts

BANKS = ("bank1-1.xml", "bank1-2.xml", "bank2.xml")


def _ends(text: str) -> int:
    return text.count("[end]")


@pytest.mark.parametrize("lang", ["fr", "en"])
@pytest.mark.parametrize("bank", BANKS)
def test_each_pointer_keeps_the_japanese_message_count(bank: str, lang: str) -> None:
    japanese, translated = pointer_texts(Path("text/jp") / bank), pointer_texts(Path("text") / lang / bank)
    last = max(japanese, key=int)  # the dump's last pointer runs to the bank's end, unterminated
    mismatches = [(pointer, _ends(text), _ends(translated.get(pointer, "")))
                  for pointer, text in japanese.items() if pointer != last and _ends(text) != _ends(translated.get(pointer, ""))]
    assert mismatches == []
