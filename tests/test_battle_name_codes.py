"""Battle lines show the characters' current names: build.py encodes them as name codes ($04 n), like vanilla's,
so a renamed Caïn reads renamed in "Pourquoi, Caïn !?"."""
from __future__ import annotations

from build import SMALL_VWF_TABLE, battle_text_table


def test_a_name_is_its_name_code() -> None:
    table = battle_text_table(SMALL_VWF_TABLE, "text/ff4fr.tbl")
    assert table.to_bytes("Pourquoi, Caïn !?")[10:12] == bytes([0x04, 0x01])


def test_the_script_spellings_share_a_code() -> None:
    table = battle_text_table(SMALL_VWF_TABLE, "text/ff4fr.tbl")
    assert table.to_bytes("Tellah") == table.to_bytes("Tella") == bytes([0x04, 0x03])
