"""VWF asset width budget tests.

Item names are baked into small-VWF tiles (utils/bake_names.py): kerned pair by pair on the menu font's glyphs, set
ITEM_NAME_LEAD columns off their icon. Every list that shows them (field, battle inventory, shops, equip) gives a name
10 tiles after its fixed-width symbol; an 11+ tile name would be cut.
"""
from __future__ import annotations
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from katsuji import VwfFont  # noqa: E402
from katsuji import config as katsuji_config  # noqa: E402
from katsuji.script import Table  # noqa: E402
from build import ITEM_NAME_LEAD, read_fixed_from_xml  # noqa: E402
from utils.bake_names import Glyphs, auto_kern, name_tiles  # noqa: E402

NAME_TILES = 10


def _names(asset_xml: Path, table: Table) -> list[bytes]:
    """Each item's name: its symbol byte and [end] off."""
    items = read_fixed_from_xml(str(asset_xml), table, formatter=lambda t: (t or "").strip() + "[end]")
    return [item.value[1:].rstrip(b"\x00") for item in items]


@pytest.mark.parametrize("lang", ["fr", "en"])
def test_every_item_name_fits_its_tiles(lang: str) -> None:
    table = Table(str(ROOT / "text" / "ff4_menus.tbl"))
    names = _names(ROOT / "text" / lang / "items_unleashed.xml", table)
    font = VwfFont.decode((ROOT / "build" / "gen" / "menu_font.dat").read_bytes())
    font = auto_kern(font, Glyphs.of(katsuji_config.load(ROOT / "katsuji.toml").fonts["menu"]), names)
    tiles = {i: len(name_tiles(font, codes, ITEM_NAME_LEAD)) // 16 for i, codes in enumerate(names)}
    too_wide = [f"{i} {table.to_text(names[i])!r}: {n} tiles" for i, n in tiles.items() if n > NAME_TILES]
    assert too_wide == []
