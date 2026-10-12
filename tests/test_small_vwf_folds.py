"""The small VWF draws one glyph per code and has none for the accented capitals: each must fold to its bare letter
(build.py SMALL_VWF_FOLDS), or the menu text drops it ("me de Bombe" for "Âme de Bombe", "a ne marche pas")."""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from build import SMALL_VWF_FOLDS  # noqa: E402

FONT = ROOT / "build" / "gen" / "menu_font.dat"
TABLE = ROOT / "text" / "ff4_menus.tbl"


def test_every_capital_without_a_glyph_folds() -> None:
    if not FONT.exists():
        pytest.skip(f"{FONT} not built")
    from katsuji import VwfFont

    font = VwfFont.decode(FONT.read_bytes())
    missing = []
    for line in TABLE.read_text(encoding="utf-8").splitlines():
        code, _, text = line.partition("=")
        if len(text) == 1 and text.isupper() and ord(text) > 127 and font.widths[int(code, 16)] == 0:
            if text not in SMALL_VWF_FOLDS:
                missing.append(text)
    assert missing == []
