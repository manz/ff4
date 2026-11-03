"""Battle messages' speaker labels get the dialog's 1px spacer before the colon: « Tella°: », not « Tella: » (b3
playtest). Battle messages are not laid out like dialog, so the build adds it on its own."""
from __future__ import annotations

from pathlib import Path

import pytest

from utils.dialog_layout import SPEAKER_SPACE, battle_speaker_spaced
from utils.script_xml import pointer_texts


@pytest.mark.parametrize(
    ("text", "spaced"),
    [
        ("Tella: Bon sang...[end]", "Tella°: Bon sang...[end]"),
        ("Les trois sœurs Magus: Attaque Delta !![end]", "Les trois sœurs Magus°: Attaque Delta !![end]"),
        ("????: Ça va ![end]", "????°: Ça va ![end]"),
        ("Tella°: Bon sang...[end]", "Tella°: Bon sang...[end]"),
        ("Pas de nom ici.[end]", "Pas de nom ici.[end]"),
    ],
)
def test_the_label_gets_the_spacer(text: str, spaced: str) -> None:
    assert battle_speaker_spaced(text) == spaced


def test_every_french_battle_colon_gets_the_spacer() -> None:
    texts = pointer_texts(Path("text/fr/battle_messages.xml")).values()
    bare = [text for text in map(battle_speaker_spaced, texts) if ":" in text.replace(f"{SPEAKER_SPACE}:", "")]
    assert bare == []
