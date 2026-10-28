"""A colon in dialogue makes the words before it a bold speaker label.

« Il n'a été vaincu qu'une fois: quand la foudre... » was drawn with « Il n'a été vaincu qu'une fois » in bold. A real
label is a name: capitalised, and every word capitalised but the joining ones (« Palom et Porom », "King Eblana",
"Dr. Lugae") unless it is two words ("Old man", "Yang's wife")."""
from __future__ import annotations

from pathlib import Path

import pytest

from utils.dialog_layout import QUOTING, clean, tokenize
from utils.script_xml import pointer_texts

JOINING = {"et", "and", "de", "of", "d'", "du"}
CREDITS = {("bank2", "297"), ("bank2", "298"), ("bank2", "299")}  # the developers' room: "Role - Name: line"
FILES = [path for lang in ("fr", "en") for path in sorted(Path(f"text/{lang}").glob("bank*.xml"))]


def _is_name(label: str) -> bool:
    words = label.split()
    return words[0][0].isupper() and (len(words) <= 2 or all(word[0].isupper() or word in JOINING for word in words))


@pytest.mark.parametrize("path", FILES, ids=lambda p: f"{p.parent.name}/{p.stem}")
def test_every_speaker_label_is_a_name(path: Path) -> None:
    quoting = QUOTING[path.parent.name]
    labels = [
        f"#{pointer}: {token.value}"
        for pointer, text in pointer_texts(path).items()
        if (path.stem, pointer) not in CREDITS
        for token in tokenize(clean(text), quoting)
        if token.kind == "SPEAKER" and not _is_name(token.value)
    ]
    assert labels == []
