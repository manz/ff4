"""VWF asset width budget tests.

For each fixed-list XML asset that gets rendered through the 8x8 menu
VWF blitter, measure every entry's rendered tile-width with the same
font + kerning tables the runtime uses, and assert it fits the slot
budget the rendering code reserves.

Battle inventory uses 10 VWF tile_ids per slot (the symbol byte +
colon + 2 digits are fixed-width tiles outside the budget). The
allocator clamp freezes at slot_base+9 ; an 11+ tile name would
truncate at render time.
"""
from __future__ import annotations
import math
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from script import Table  # noqa: E402
from metrics import TextMetrics  # noqa: E402
from build import read_fixed_from_xml  # noqa: E402


def _load(asset_xml: Path) -> tuple[list, TextMetrics, Table]:
    table = Table(str(ROOT / "text" / "ff4_menus.tbl"))
    metrics = TextMetrics(table, [str(ROOT / "assets" / "menu_font.dat")], char_height=8)
    items = read_fixed_from_xml(
        str(asset_xml),
        table,
        formatter=lambda t: (t or "").strip() + "[end]",
    )
    return items, metrics, table


@pytest.mark.parametrize(
    "asset_xml, vwf_tile_budget, kind",
    [
        ("text/fr/items.xml",            10, "battle inventory items"),
        ("text/fr/items_unleashed.xml",  10, "battle inventory items_unleashed"),
    ],
)
def test_vwf_asset_within_budget(asset_xml: str, vwf_tile_budget: int, kind: str) -> None:
    items, metrics, table = _load(ROOT / asset_xml)
    offenders = []
    for i, ptr in enumerate(items):
        body = ptr.value
        # First byte is the fixed-width symbol icon ; VWF starts at byte 1.
        vwf_bytes = body[1:] if body else b""
        # Strip trailing [end] sentinel before measurement.
        if vwf_bytes and vwf_bytes[-1] == 0:
            vwf_bytes = vwf_bytes[:-1]
        width_px = metrics.measure_bytes(vwf_bytes)
        tiles = math.ceil(width_px / 8)
        if tiles > vwf_tile_budget:
            text = table.to_text(body).replace("[end]", "")
            offenders.append((i, tiles, width_px, text))
    assert not offenders, (
        f"{kind}: {len(offenders)} entries exceed {vwf_tile_budget}-tile VWF budget:\n  "
        + "\n  ".join(
            f"id={i:>3} {tiles:>2} tiles {px:>3}px  {text!r}"
            for i, tiles, px, text in offenders
        )
    )
