"""ff4's fonts as katsuji builds them: kerning the French text relies on."""

from pathlib import Path

import pytest
from katsuji import config as katsuji_config
from katsuji.atlas import Atlas
from katsuji.build import font_atlas
from katsuji.formats import VwfFont
from katsuji.kerning import pair_kerning
from katsuji.script import Table

ROOT = Path(__file__).parent.parent


@pytest.fixture(scope="module")
def dialog() -> tuple[Atlas, Table]:
    atlas = font_atlas(katsuji_config.load(ROOT / "katsuji.toml").fonts["dialog"])
    return atlas, Table(str(ROOT / "text" / "ff4fr.tbl"))


def _kerning(dialog: tuple[Atlas, Table], text: str) -> int:
    atlas, table = dialog
    left, right = table.to_bytes(text)
    return pair_kerning(atlas, left, right, default=1)


@pytest.mark.parametrize(("pair", "expected"), [("ïe", -1), ("re", -1), ("ce", 0)])
def test_dialog_pair_kerning(dialog: tuple[Atlas, Table], pair: str, expected: int) -> None:
    assert _kerning(dialog, pair) == expected


def test_fo_is_kerned(dialog: tuple[Atlas, Table]) -> None:
    assert _kerning(dialog, "fo") != 0


def test_dialog_font_keeps_the_hand_tuned_tt_pair() -> None:
    font = VwfFont.decode((ROOT / "build" / "gen" / "font.dat").read_bytes())
    t, _ = Table(str(ROOT / "text" / "ff4fr.tbl")).to_bytes("tt")
    assert font.kerning[(t, t)] == 2
